import 'dart:collection';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

export 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart'
    show
        Id3Version,
        OpenAiConfig,
        OpenAiProfile,
        TranslateSource,
        TranslateTargetLang,
        TranslationOptions;

/// 应用语言。
enum AppLanguage {
  auto('auto'),
  zhHans('zh-Hans'),
  zhHant('zh-Hant'),
  en('en'),
  ru('ru'),
  ja('ja'),
  ko('ko');

  const AppLanguage(this.value);

  final String value;
}

/// 应用配色模式。
enum AppColorScheme {
  auto('auto'),
  light('light'),
  dark('dark');

  const AppColorScheme(this.value);

  final String value;
}

/// 应用日志级别。
enum AppLogLevel {
  trace('TRACE'),
  debug('DEBUG'),
  info('INFO'),
  warning('WARNING'),
  error('ERROR');

  const AppLogLevel(this.value);

  final String value;
}

/// 搜索模块配置。
class SearchConfig {
  SearchConfig({required List<String> sources})
    : sources = UnmodifiableListView<String>(List<String>.from(sources));

  final UnmodifiableListView<String> sources;
}

/// 歌词导出/写回配置。
class LyricsConfig {
  LyricsConfig({
    required this.fileNameFormat,
    required this.id3Version,
    required List<String> langOrder,
    required this.addEndTimestamp,
    required this.msDigits,
    required this.lastRefStyle,
    required this.tagInfoSource,
  }) : langOrder = UnmodifiableListView<String>(List<String>.from(langOrder));

  final String fileNameFormat;
  final Id3Version id3Version;
  final UnmodifiableListView<String> langOrder;
  final bool addEndTimestamp;
  final int msDigits;
  final int lastRefStyle;
  final int tagInfoSource;
}

/// 本地匹配配置。
class MatchConfig {
  const MatchConfig({required this.skipInst, required this.autoSelect});

  final bool skipInst;
  final bool autoSelect;
}

/// 翻译配置。
class TranslateConfig {
  const TranslateConfig({
    required this.source,
    required this.targetLang,
    required this.openAi,
  });

  final TranslateSource source;
  final TranslateTargetLang targetLang;
  final OpenAiConfig openAi;
}

/// 桌面歌词配置。
class DesktopConfig {
  DesktopConfig({
    required List<RgbColor> playedColors,
    required List<RgbColor> unplayedColors,
    required List<String> defaultLangs,
    required List<String> langOrder,
    required List<String> sources,
    required this.fontFamily,
    required this.refreshRate,
    required this.windowRect,
    required this.fontSize,
    required this.showFurigana,
    required this.panelFontSize,
  }) : playedColors = UnmodifiableListView<RgbColor>(
         List<RgbColor>.from(playedColors),
       ),
       unplayedColors = UnmodifiableListView<RgbColor>(
         List<RgbColor>.from(unplayedColors),
       ),
       defaultLangs = UnmodifiableListView<String>(
         List<String>.from(defaultLangs),
       ),
       langOrder = UnmodifiableListView<String>(List<String>.from(langOrder)),
       sources = UnmodifiableListView<String>(List<String>.from(sources));

  final UnmodifiableListView<RgbColor> playedColors;
  final UnmodifiableListView<RgbColor> unplayedColors;
  final UnmodifiableListView<String> defaultLangs;
  final UnmodifiableListView<String> langOrder;
  final UnmodifiableListView<String> sources;
  final String fontFamily;
  final int refreshRate;
  final WindowRect? windowRect;
  final double fontSize;
  final bool showFurigana;
  final double panelFontSize;
}

/// 应用 UI 配置。
class AppUiConfig {
  const AppUiConfig({
    required this.language,
    required this.colorScheme,
    required this.logLevel,
    required this.autoCheckUpdate,
  });

  final AppLanguage language;
  final AppColorScheme colorScheme;
  final AppLogLevel logLevel;
  final bool autoCheckUpdate;
}

/// 存储配置。
class StorageConfig {
  const StorageConfig({required this.defaultSavePath});

  final String defaultSavePath;
}

/// 全局配置聚合。
class AppConfig {
  AppConfig({
    required this.schemaVersion,
    required this.search,
    required this.lyrics,
    required this.match,
    required this.translate,
    required this.desktop,
    required this.app,
    required this.storage,
    Map<String, Object?> legacyExtras = const <String, Object?>{},
  }) : legacyExtras = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.from(legacyExtras),
       );

  final int schemaVersion;
  final SearchConfig search;
  final LyricsConfig lyrics;
  final MatchConfig match;
  final TranslateConfig translate;
  final DesktopConfig desktop;
  final AppUiConfig app;
  final StorageConfig storage;

  /// 未识别配置键归档。
  ///
  /// 这里不是 Flutter 内部兼容包袱，而是面向Python版
  /// 配置文件的安全兜底：Python 版本可能比 Flutter 版本多出一些配置项，
  /// 读取后如果直接丢弃，用户再切回 Python 版时这些设置就会丢失。
  /// 因此仓储会保留未知键并在写回时原样带上；Flutter 业务代码不要依赖
  /// 这些键实现新功能，新配置应当显式加入 `ConfigKey` 和强类型字段。
  final UnmodifiableMapView<String, Object?> legacyExtras;

  AppConfig copyWith({
    int? schemaVersion,
    SearchConfig? search,
    LyricsConfig? lyrics,
    MatchConfig? match,
    TranslateConfig? translate,
    DesktopConfig? desktop,
    AppUiConfig? app,
    StorageConfig? storage,
    Map<String, Object?>? legacyExtras,
  }) {
    return AppConfig(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      search: search ?? this.search,
      lyrics: lyrics ?? this.lyrics,
      match: match ?? this.match,
      translate: translate ?? this.translate,
      desktop: desktop ?? this.desktop,
      app: app ?? this.app,
      storage: storage ?? this.storage,
      legacyExtras: legacyExtras ?? this.legacyExtras,
    );
  }
}
