import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import 'app_config.dart';
import 'config_keys.dart';

/// 默认配置与必需键校验。
class ConfigDefaults {
  ConfigDefaults._();

  static const int currentSchemaVersion = 1;
  static const String defaultSavePath = '';

  /// 配置迁移最小必需键默认值（用于缺失键补齐）。
  ///
  /// Map 必须从强类型快照派生，避免新增字段时同时维护两份默认值而发生漂移。
  static final Map<String, Object?> requiredKeyDefaults =
      Map<String, Object?>.unmodifiable(flattenRequired(current));

  /// 当前内置配置快照（强类型结构）。
  static final AppConfig current = AppConfig(
    schemaVersion: currentSchemaVersion,
    search: SearchConfig(sources: <String>['QM', 'KG', 'NE']),
    lyrics: LyricsConfig(
      fileNameFormat: '%<artist> - %<title> (%<id>)',
      id3Version: Id3Version.v23,
      langOrder: <String>['roma', 'orig', 'ts'],
      addEndTimestamp: false,
      msDigits: 3,
      lastRefStyle: 0,
      tagInfoSource: 0,
    ),
    match: const MatchConfig(skipInst: true, autoSelect: true),
    translate: const TranslateConfig(
      source: TranslateSource.bing,
      targetLang: TranslateTargetLang.simplifiedChinese,
      openAi: OpenAiConfig(
        profile: OpenAiProfile.custom,
        baseUrl: '',
        apiKey: '',
        model: '',
      ),
    ),
    desktop: DesktopConfig(
      playedColors: const <RgbColor>[
        RgbColor(0, 255, 255),
        RgbColor(0, 128, 255),
      ],
      unplayedColors: const <RgbColor>[
        RgbColor(255, 0, 0),
        RgbColor(255, 128, 128),
      ],
      defaultLangs: <String>['orig', 'ts'],
      langOrder: <String>['roma', 'orig', 'ts'],
      sources: <String>['QM', 'KG', 'NE'],
      fontFamily: '',
      refreshRate: -1,
      windowRect: null,
      fontSize: 30.0,
      showFurigana: true,
      panelFontSize: 12.0,
    ),
    app: const AppUiConfig(
      language: AppLanguage.auto,
      colorScheme: AppColorScheme.auto,
      logLevel: AppLogLevel.info,
      autoCheckUpdate: true,
    ),
    storage: StorageConfig(defaultSavePath: defaultSavePath),
  );

  static AppConfig currentWithDefaultSavePath(String defaultSavePath) {
    return current.copyWith(
      storage: StorageConfig(defaultSavePath: defaultSavePath),
    );
  }

  static Map<String, Object?> requiredKeyDefaultsWithDefaultSavePath(
    String defaultSavePath,
  ) {
    return <String, Object?>{
      ...requiredKeyDefaults,
      ConfigKey.storageDefaultSavePath: defaultSavePath,
    };
  }

  /// 将强类型配置展开成 key-value 结构，便于迁移校验。
  static Map<String, Object?> flattenRequired(AppConfig config) {
    return <String, Object?>{
      ConfigKey.lyricsFileNameFormat: config.lyrics.fileNameFormat,
      ConfigKey.storageDefaultSavePath: config.storage.defaultSavePath,
      ConfigKey.lyricsId3Version: config.lyrics.id3Version.value,
      ConfigKey.searchSources: config.search.sources.toList(growable: false),
      ConfigKey.lyricsLangOrder: config.lyrics.langOrder.toList(
        growable: false,
      ),
      ConfigKey.matchSkipInst: config.match.skipInst,
      ConfigKey.matchAutoSelect: config.match.autoSelect,
      ConfigKey.lyricsAddEndTimestamp: config.lyrics.addEndTimestamp,
      ConfigKey.lyricsMsDigits: config.lyrics.msDigits,
      ConfigKey.lyricsLastRefStyle: config.lyrics.lastRefStyle,
      ConfigKey.lyricsTagInfoSource: config.lyrics.tagInfoSource,
      ConfigKey.translateSource: config.translate.source.value,
      ConfigKey.translateTargetLang: config.translate.targetLang.value,
      ConfigKey.translateOpenAiProfile: config.translate.openAi.profile.value,
      ConfigKey.translateOpenAiBaseUrl: config.translate.openAi.baseUrl,
      ConfigKey.translateOpenAiApiKey: config.translate.openAi.apiKey,
      ConfigKey.translateOpenAiModel: config.translate.openAi.model,
      ConfigKey.desktopPlayedColors: config.desktop.playedColors
          .map((RgbColor color) => color.toTuple())
          .toList(growable: false),
      ConfigKey.desktopUnplayedColors: config.desktop.unplayedColors
          .map((RgbColor color) => color.toTuple())
          .toList(growable: false),
      ConfigKey.desktopDefaultLangs: config.desktop.defaultLangs.toList(
        growable: false,
      ),
      ConfigKey.desktopLangOrder: config.desktop.langOrder.toList(
        growable: false,
      ),
      ConfigKey.desktopSources: config.desktop.sources.toList(growable: false),
      ConfigKey.desktopFontFamily: config.desktop.fontFamily,
      ConfigKey.desktopRefreshRate: config.desktop.refreshRate,
      ConfigKey.desktopWindowRect:
          config.desktop.windowRect?.toList() ?? <double>[],
      ConfigKey.desktopFontSize: config.desktop.fontSize,
      ConfigKey.desktopShowFurigana: config.desktop.showFurigana,
      ConfigKey.desktopPanelFontSize: config.desktop.panelFontSize,
      ConfigKey.appLanguage: config.app.language.value,
      ConfigKey.appColorScheme: config.app.colorScheme.value,
      ConfigKey.appLogLevel: config.app.logLevel.value,
      ConfigKey.appAutoCheckUpdate: config.app.autoCheckUpdate,
    };
  }

  /// 判断配置字典是否覆盖全部必需键。
  static bool hasAllRequiredKeys(Map<String, Object?> values) {
    for (final String key in ConfigKey.requiredKeys) {
      if (!values.containsKey(key)) {
        return false;
      }
    }
    return true;
  }
}
