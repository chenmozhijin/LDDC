import 'dart:async';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'app_config.dart';
import 'config_defaults.dart';
import 'config_keys.dart';
import 'config_migration.dart';

typedef DefaultSavePathResolver = Future<String> Function();
typedef ConfigDiagnosticSink =
    void Function(String message, Map<String, Object?> fields);

/// 配置存储端口：负责底层读写，不关心配置结构。
///
/// `read` 返回的 Map 由调用方独占；`write` 在 Future 完成后不得继续持有或
/// 修改传入 Map。这个快照约定让仓储可以安全保留原始配置，避免为未知嵌套值
/// 反复制作副本。需要在内存中保存数据的实现必须在读写边界自行深复制。
abstract interface class ConfigStorage {
  Future<Map<String, Object?>?> read();

  Future<void> write(Map<String, Object?> values);
}

/// 仅用于启动期与测试的内存存储实现。
class InMemoryConfigStorage implements ConfigStorage {
  InMemoryConfigStorage([Map<String, Object?>? seed])
    : _values = seed == null ? null : _ConfigCodec.copyValues(seed);

  Map<String, Object?>? _values;

  @override
  Future<Map<String, Object?>?> read() async {
    final Map<String, Object?>? values = _values;
    if (values == null) {
      return null;
    }
    return _ConfigCodec.copyValues(values);
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    _values = _ConfigCodec.copyValues(values);
  }
}

/// 强类型配置仓储接口。
abstract interface class ConfigRepository {
  AppConfig get current;

  Future<AppConfig> load();

  Future<AppConfig> refreshFromStorage();

  Future<AppConfig> update(Map<String, Object?> patch);

  Stream<AppConfig> watch({bool emitCurrent = true});
}

/// 默认配置仓储：
/// - `load` 读取并解析配置快照
/// - `update` 支持 key 级 patch
/// - `watch` 提供配置变更流
class DefaultConfigRepository implements ConfigRepository {
  DefaultConfigRepository({
    ConfigStorage? storage,
    DefaultSavePathResolver? defaultSavePathResolver,
    ConfigDiagnosticSink? diagnosticSink,
  }) : _storage = storage ?? InMemoryConfigStorage(),
       _defaultSavePathResolver = defaultSavePathResolver ?? (() async => ''),
       _diagnosticSink = diagnosticSink;

  final ConfigStorage _storage;
  final DefaultSavePathResolver _defaultSavePathResolver;
  final ConfigDiagnosticSink? _diagnosticSink;
  final StreamController<AppConfig> _changes =
      StreamController<AppConfig>.broadcast();

  AppConfig _current = ConfigDefaults.current;
  Map<String, Object?>? _persistedValues;
  bool _loaded = false;
  bool _disposed = false;
  Future<void> _operationBarrier = Future<void>.value();

  @override
  AppConfig get current => _current;

  @override
  Future<AppConfig> load() {
    return _enqueue(_loadIfNeeded);
  }

  Future<AppConfig> _loadIfNeeded() async {
    if (_loaded) {
      return _current;
    }
    return _loadFromStorage();
  }

  @override
  Future<AppConfig> refreshFromStorage() {
    return _enqueue(_loadFromStorage);
  }

  Future<AppConfig> _loadFromStorage() async {
    final Map<String, Object?>? raw = await _storage.read();
    final String defaultSavePath = await _defaultSavePathResolver();
    final ConfigMigrationResult migration = ConfigMigrator.migrate(raw);
    final bool isFutureSchema =
        migration.sourceVersion > ConfigDefaults.currentSchemaVersion;
    late final AppConfig next;
    late final Map<String, Object?> persistedValues;
    if (migration.values == null) {
      next = ConfigDefaults.currentWithDefaultSavePath(defaultSavePath);
      persistedValues = _ConfigCodec.encode(next);
      await _storage.write(persistedValues);
    } else {
      _reportInvalidAppLanguage(migration.values!);
      next = _ConfigCodec.decode(
        migration.values,
        defaultSavePath: defaultSavePath,
      );
      if (!isFutureSchema &&
          (migration.changed ||
              !ConfigDefaults.hasAllRequiredKeys(migration.values!))) {
        persistedValues = _ConfigCodec.encode(next);
        await _storage.write(persistedValues);
      } else {
        // 高版本配置不能在加载阶段被旧程序自动规范化。这里保存原始快照，
        // 后续显式更新只覆盖用户实际修改的键，未识别的新字段和值会原样保留。
        persistedValues = migration.values!;
      }
    }
    _current = next;
    _persistedValues = persistedValues;
    _loaded = true;
    _changes.add(_current);
    return _current;
  }

  void _reportInvalidAppLanguage(Map<String, Object?> values) {
    final Object? raw = values[ConfigKey.appLanguage];
    if (raw == null ||
        AppLanguage.values.any((AppLanguage item) => item.value == raw)) {
      return;
    }
    _diagnosticSink?.call('非法应用语言配置已回退为 auto', <String, Object?>{
      'key': ConfigKey.appLanguage,
      'value': raw.toString(),
    });
  }

  @override
  Future<AppConfig> update(Map<String, Object?> patch) {
    final Map<String, Object?> patchSnapshot = _ConfigCodec.copyValues(patch);
    return _enqueue(() => _update(patchSnapshot));
  }

  Future<AppConfig> _update(Map<String, Object?> patch) async {
    await _loadIfNeeded();
    if (patch.isEmpty) {
      return _current;
    }
    _validatePatchKeys(patch);
    final Map<String, Object?> baseValues =
        _persistedValues ?? _ConfigCodec.encode(_current);
    final Map<String, Object?> nextPersistedValues = _ConfigCodec.copyValues(
      baseValues,
    )..addAll(patch);
    final AppConfig next = _ConfigCodec.decode(
      nextPersistedValues,
      fallback: _current,
    );
    final Map<String, Object?> normalizedValues =
        ConfigDefaults.flattenRequired(next);
    for (final String key in patch.keys) {
      nextPersistedValues[key] = normalizedValues[key];
    }

    // 先完成持久化再发布新快照。写入失败时，current、watch 事件和原始快照
    // 都保持在上一次成功状态，调用方可以安全重试而不会读到未落盘的数据。
    await _storage.write(nextPersistedValues);
    _current = next;
    _persistedValues = nextPersistedValues;
    _changes.add(next);
    return next;
  }

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (!_loaded) {
      await load();
    }
    if (emitCurrent) {
      yield _current;
    }
    yield* _changes.stream;
  }

  /// 测试场景下释放资源。
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _operationBarrier;
    await _changes.close();
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_disposed) {
      return Future<T>.error(StateError('DefaultConfigRepository 已释放'));
    }
    final Future<T> result = _operationBarrier.then((_) {
      if (_disposed) {
        throw StateError('DefaultConfigRepository 已释放');
      }
      return operation();
    });
    _operationBarrier = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _validatePatchKeys(Map<String, Object?> patch) {
    for (final String key in patch.keys) {
      if (!ConfigKey.requiredKeys.contains(key)) {
        throw ArgumentError.value(key, 'patch', '配置更新只能写入受控 ConfigKey');
      }
    }
  }
}

/// `Map<String, Object?>` 与强类型配置之间的编解码器。
class _ConfigCodec {
  _ConfigCodec._();

  static Map<String, Object?> copyValues(Map<String, Object?> values) {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in values.entries)
        entry.key: _deepCopy(entry.value),
    };
  }

  static AppConfig decode(
    Map<String, Object?>? raw, {
    AppConfig? fallback,
    String? defaultSavePath,
  }) {
    final Map<String, Object?> source = raw == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(raw);
    final Map<String, Object?> fallbackValues = fallback == null
        ? ConfigDefaults.requiredKeyDefaultsWithDefaultSavePath(
            defaultSavePath ?? ConfigDefaults.defaultSavePath,
          )
        : ConfigDefaults.flattenRequired(fallback);
    final int fallbackSchemaVersion =
        fallback?.schemaVersion ?? ConfigDefaults.currentSchemaVersion;

    final List<String> searchSources = _readStringList(
      source[ConfigKey.searchSources],
      fallbackValues[ConfigKey.searchSources] as List<String>,
    );
    final List<String> lyricLangOrder = _readStringList(
      source[ConfigKey.lyricsLangOrder],
      fallbackValues[ConfigKey.lyricsLangOrder] as List<String>,
      dedupe: true,
      normalizer: LyricsLanguageRegistry.normalizeKey,
    );
    final List<String> desktopDefaultLangs = _readStringList(
      source[ConfigKey.desktopDefaultLangs],
      fallbackValues[ConfigKey.desktopDefaultLangs] as List<String>,
      dedupe: true,
      normalizer: LyricsLanguageRegistry.normalizeKey,
    );
    final List<String> desktopLangOrder = _readStringList(
      source[ConfigKey.desktopLangOrder],
      fallbackValues[ConfigKey.desktopLangOrder] as List<String>,
      dedupe: true,
      normalizer: LyricsLanguageRegistry.normalizeKey,
    );
    final List<String> desktopSources = _readStringList(
      source[ConfigKey.desktopSources],
      fallbackValues[ConfigKey.desktopSources] as List<String>,
    );
    final List<RgbColor> playedColors = _readColorList(
      source[ConfigKey.desktopPlayedColors],
      fallbackValues[ConfigKey.desktopPlayedColors] as List<List<int>>,
    );
    final List<RgbColor> unplayedColors = _readColorList(
      source[ConfigKey.desktopUnplayedColors],
      fallbackValues[ConfigKey.desktopUnplayedColors] as List<List<int>>,
    );

    // 未知键需要进入 legacyExtras，而不是直接丢弃。
    //
    // Python 版配置可能比 Flutter 版本多出一些键；Flutter 不读取这些未知键，
    // 但用户可能会在两个版本之间切换。保留它们可以避免一次 Flutter 写配置
    // 就破坏 Python 版配置。业务代码不要从 legacyExtras 读取新功能配置，
    // 真正属于 Flutter 的配置必须先进入 ConfigKey 和 AppConfig 强类型字段。
    final Map<String, Object?> legacyExtras = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in source.entries) {
      if (entry.key == configSchemaVersionKey) {
        continue;
      }
      if (!ConfigKey.requiredKeys.contains(entry.key)) {
        legacyExtras[entry.key] = _deepCopy(entry.value);
      }
    }

    return AppConfig(
      schemaVersion: _readInt(
        source[configSchemaVersionKey],
        fallbackSchemaVersion,
      ),
      search: SearchConfig(sources: searchSources),
      lyrics: LyricsConfig(
        fileNameFormat: _readString(
          source[ConfigKey.lyricsFileNameFormat],
          fallbackValues[ConfigKey.lyricsFileNameFormat] as String,
        ),
        id3Version: _readEnum(
          source[ConfigKey.lyricsId3Version],
          Id3Version.values,
          (Id3Version v) => v.value,
          _parseId3Version(
            fallbackValues[ConfigKey.lyricsId3Version] as String,
            Id3Version.v23,
          ),
        ),
        langOrder: lyricLangOrder,
        addEndTimestamp: _readBool(
          source[ConfigKey.lyricsAddEndTimestamp],
          fallbackValues[ConfigKey.lyricsAddEndTimestamp] as bool,
        ),
        msDigits: _readInt(
          source[ConfigKey.lyricsMsDigits],
          fallbackValues[ConfigKey.lyricsMsDigits] as int,
        ),
        lastRefStyle: _readInt(
          source[ConfigKey.lyricsLastRefStyle],
          fallbackValues[ConfigKey.lyricsLastRefStyle] as int,
        ),
        tagInfoSource: _readInt(
          source[ConfigKey.lyricsTagInfoSource],
          fallbackValues[ConfigKey.lyricsTagInfoSource] as int,
        ),
      ),
      match: MatchConfig(
        skipInst: _readBool(
          source[ConfigKey.matchSkipInst],
          fallbackValues[ConfigKey.matchSkipInst] as bool,
        ),
        autoSelect: _readBool(
          source[ConfigKey.matchAutoSelect],
          fallbackValues[ConfigKey.matchAutoSelect] as bool,
        ),
      ),
      translate: TranslateConfig(
        source: _readEnum(
          source[ConfigKey.translateSource],
          TranslateSource.values,
          (TranslateSource v) => v.value,
          _parseTranslateSource(
            fallbackValues[ConfigKey.translateSource] as String,
            TranslateSource.bing,
          ),
        ),
        targetLang: _readEnum(
          source[ConfigKey.translateTargetLang],
          TranslateTargetLang.values,
          (TranslateTargetLang v) => v.value,
          _parseTranslateTargetLang(
            fallbackValues[ConfigKey.translateTargetLang] as String,
            TranslateTargetLang.simplifiedChinese,
          ),
        ),
        openAi: OpenAiConfig(
          profile: _readEnum(
            source[ConfigKey.translateOpenAiProfile],
            OpenAiProfile.values,
            (OpenAiProfile v) => v.value,
            _parseOpenAiProfile(
              fallbackValues[ConfigKey.translateOpenAiProfile] as String,
              OpenAiProfile.custom,
            ),
          ),
          baseUrl: _readString(
            source[ConfigKey.translateOpenAiBaseUrl],
            fallbackValues[ConfigKey.translateOpenAiBaseUrl] as String,
          ),
          apiKey: _readString(
            source[ConfigKey.translateOpenAiApiKey],
            fallbackValues[ConfigKey.translateOpenAiApiKey] as String,
          ),
          model: _readString(
            source[ConfigKey.translateOpenAiModel],
            fallbackValues[ConfigKey.translateOpenAiModel] as String,
          ),
        ),
      ),
      desktop: DesktopConfig(
        playedColors: playedColors,
        unplayedColors: unplayedColors,
        defaultLangs: desktopDefaultLangs,
        langOrder: desktopLangOrder,
        sources: desktopSources,
        fontFamily: _readString(
          source[ConfigKey.desktopFontFamily],
          fallbackValues[ConfigKey.desktopFontFamily] as String,
        ),
        refreshRate: _readInt(
          source[ConfigKey.desktopRefreshRate],
          fallbackValues[ConfigKey.desktopRefreshRate] as int,
        ),
        windowRect: _readWindowRect(
          source[ConfigKey.desktopWindowRect],
          fallbackValues[ConfigKey.desktopWindowRect] as List<double>,
        ),
        fontSize: _readDouble(
          source[ConfigKey.desktopFontSize],
          fallbackValues[ConfigKey.desktopFontSize] as double,
        ),
        showFurigana: _readBool(
          source[ConfigKey.desktopShowFurigana],
          fallbackValues[ConfigKey.desktopShowFurigana] as bool,
        ),
        panelFontSize: _readDouble(
          source[ConfigKey.desktopPanelFontSize],
          fallbackValues[ConfigKey.desktopPanelFontSize] as double,
        ),
      ),
      app: AppUiConfig(
        language: _readEnum(
          source[ConfigKey.appLanguage],
          AppLanguage.values,
          (AppLanguage v) => v.value,
          _parseAppLanguage(
            fallbackValues[ConfigKey.appLanguage] as String,
            AppLanguage.auto,
          ),
        ),
        colorScheme: _readEnum(
          source[ConfigKey.appColorScheme],
          AppColorScheme.values,
          (AppColorScheme v) => v.value,
          _parseAppColorScheme(
            fallbackValues[ConfigKey.appColorScheme] as String,
            AppColorScheme.auto,
          ),
        ),
        logLevel: _readEnum(
          source[ConfigKey.appLogLevel],
          AppLogLevel.values,
          (AppLogLevel v) => v.value,
          _parseAppLogLevel(
            fallbackValues[ConfigKey.appLogLevel] as String,
            AppLogLevel.info,
          ),
        ),
        autoCheckUpdate: _readBool(
          source[ConfigKey.appAutoCheckUpdate],
          fallbackValues[ConfigKey.appAutoCheckUpdate] as bool,
        ),
      ),
      storage: StorageConfig(
        defaultSavePath: _readString(
          source[ConfigKey.storageDefaultSavePath],
          fallbackValues[ConfigKey.storageDefaultSavePath] as String,
        ),
      ),
      legacyExtras: legacyExtras,
    );
  }

  static Map<String, Object?> encode(AppConfig config) {
    final Map<String, Object?> values = <String, Object?>{
      configSchemaVersionKey: config.schemaVersion,
      ...ConfigDefaults.flattenRequired(config),
    };
    // 写回时把 legacyExtras 合并回配置文件，维持与Python版配置的双向兼容。
    if (config.legacyExtras.isNotEmpty) {
      for (final MapEntry<String, Object?> entry
          in config.legacyExtras.entries) {
        if (entry.key == configSchemaVersionKey) {
          continue;
        }
        if (ConfigKey.requiredKeys.contains(entry.key)) {
          continue;
        }
        values[entry.key] = _deepCopy(entry.value);
      }
    }
    return values;
  }

  static String _readString(Object? value, String fallback) {
    return DynamicReader.asString(value) ?? fallback;
  }

  static bool _readBool(Object? value, bool fallback) {
    return DynamicReader.asBool(value) ?? fallback;
  }

  static int _readInt(Object? value, int fallback) {
    return DynamicReader.asInt(value) ?? fallback;
  }

  static double _readDouble(Object? value, double fallback) {
    return DynamicReader.asDouble(value) ?? fallback;
  }

  static List<String> _readStringList(
    Object? value,
    List<String> fallback, {
    bool dedupe = false,
    String? Function(String raw)? normalizer,
  }) {
    if (value is! List) {
      return List<String>.from(fallback);
    }
    final List<String> parsed = normalizer == null
        ? DynamicReader.asStringList(value)
        : DynamicReader.readTokenList(value, normalizer: normalizer);
    if (parsed.isEmpty) {
      return List<String>.from(fallback);
    }
    if (!dedupe || normalizer != null) {
      return parsed;
    }
    final Set<String> seen = <String>{};
    final List<String> unique = <String>[];
    for (final String item in parsed) {
      if (seen.add(item)) {
        unique.add(item);
      }
    }
    return unique.isEmpty ? List<String>.from(fallback) : unique;
  }

  static List<RgbColor> _readColorList(
    Object? value,
    List<List<int>> fallbackTuples,
  ) {
    final List<RgbColor> fallback = _tupleListToColors(fallbackTuples);
    if (value is! List) {
      return fallback;
    }
    final List<RgbColor> parsed = <RgbColor>[];
    for (final Object? item in value) {
      final RgbColor? color = _parseColor(item);
      if (color == null) {
        return fallback;
      }
      parsed.add(color);
    }
    return parsed.isEmpty ? fallback : parsed;
  }

  static WindowRect? _readWindowRect(Object? value, List<double> fallbackList) {
    final WindowRect? parsed = _parseWindowRect(value);
    if (parsed != null) {
      return parsed;
    }
    return _parseWindowRect(fallbackList);
  }

  static RgbColor? _parseColor(Object? value) {
    if (value is! List || value.length != 3) {
      return null;
    }
    final int? r = _toByte(value[0]);
    final int? g = _toByte(value[1]);
    final int? b = _toByte(value[2]);
    if (r == null || g == null || b == null) {
      return null;
    }
    return RgbColor(r, g, b);
  }

  static int? _toByte(Object? value) {
    if (value is int && value >= 0 && value <= 255) {
      return value;
    }
    if (value is double &&
        value.isFinite &&
        value == value.roundToDouble() &&
        value >= 0 &&
        value <= 255) {
      return value.toInt();
    }
    return null;
  }

  static List<RgbColor> _tupleListToColors(List<List<int>> tuples) {
    final List<RgbColor> colors = <RgbColor>[];
    for (final List<int> tuple in tuples) {
      if (tuple.length != 3) {
        continue;
      }
      colors.add(RgbColor(tuple[0], tuple[1], tuple[2]));
    }
    return colors;
  }

  static WindowRect? _parseWindowRect(Object? value) {
    if (value is! List) {
      return null;
    }
    if (value.isEmpty) {
      return null;
    }
    if (value.length != 4) {
      return null;
    }
    final List<double> numbers = <double>[];
    for (final Object? item in value) {
      if (item is! num) {
        return null;
      }
      numbers.add(item.toDouble());
    }
    return WindowRect(
      left: numbers[0],
      top: numbers[1],
      width: numbers[2],
      height: numbers[3],
    );
  }

  static T _readEnum<T>(
    Object? value,
    List<T> candidates,
    String Function(T candidate) selector,
    T fallback,
  ) {
    if (value is! String) {
      return fallback;
    }
    for (final T candidate in candidates) {
      if (selector(candidate) == value) {
        return candidate;
      }
    }
    return fallback;
  }

  static Id3Version _parseId3Version(String value, Id3Version fallback) {
    return _readEnum(
      value,
      Id3Version.values,
      (Id3Version v) => v.value,
      fallback,
    );
  }

  static TranslateSource _parseTranslateSource(
    String value,
    TranslateSource fallback,
  ) {
    return _readEnum(
      value,
      TranslateSource.values,
      (TranslateSource v) => v.value,
      fallback,
    );
  }

  static TranslateTargetLang _parseTranslateTargetLang(
    String value,
    TranslateTargetLang fallback,
  ) {
    return _readEnum(
      value,
      TranslateTargetLang.values,
      (TranslateTargetLang v) => v.value,
      fallback,
    );
  }

  static OpenAiProfile _parseOpenAiProfile(
    String value,
    OpenAiProfile fallback,
  ) {
    return _readEnum(
      value,
      OpenAiProfile.values,
      (OpenAiProfile v) => v.value,
      fallback,
    );
  }

  static AppLanguage _parseAppLanguage(String value, AppLanguage fallback) {
    return _readEnum(
      value,
      AppLanguage.values,
      (AppLanguage v) => v.value,
      fallback,
    );
  }

  static AppColorScheme _parseAppColorScheme(
    String value,
    AppColorScheme fallback,
  ) {
    return _readEnum(
      value,
      AppColorScheme.values,
      (AppColorScheme v) => v.value,
      fallback,
    );
  }

  static AppLogLevel _parseAppLogLevel(String value, AppLogLevel fallback) {
    return _readEnum(
      value,
      AppLogLevel.values,
      (AppLogLevel v) => v.value,
      fallback,
    );
  }

  static Object? _deepCopy(Object? value) {
    if (value is Map) {
      final Map<Object?, Object?> copied = <Object?, Object?>{};
      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        copied[entry.key] = _deepCopy(entry.value);
      }
      return copied;
    }
    if (value is List) {
      final List<Object?> copied = <Object?>[];
      for (final Object? item in value) {
        copied.add(_deepCopy(item));
      }
      return copied;
    }
    return value;
  }
}
