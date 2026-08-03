/// 配置键名常量表。
///
/// 约束：
/// - 键名使用点分路径
/// - `requiredKeys` 用于迁移与默认值覆盖校验
abstract final class ConfigKey {
  static const lyricsFileNameFormat = 'lyrics.fileNameFormat';
  static const storageDefaultSavePath = 'storage.defaultSavePath';
  static const lyricsId3Version = 'lyrics.id3Version';
  static const searchSources = 'search.sources';
  static const lyricsLangOrder = 'lyrics.langOrder';
  static const matchSkipInst = 'match.skipInst';
  static const matchAutoSelect = 'match.autoSelect';
  static const lyricsAddEndTimestamp = 'lyrics.addEndTimestamp';
  static const lyricsMsDigits = 'lyrics.msDigits';
  static const lyricsLastRefStyle = 'lyrics.lastRefStyle';
  static const lyricsTagInfoSource = 'lyrics.tagInfoSource';
  static const translateSource = 'translate.source';
  static const translateTargetLang = 'translate.targetLang';
  static const translateOpenAiProfile = 'translate.openai.profile';
  static const translateOpenAiBaseUrl = 'translate.openai.baseUrl';
  static const translateOpenAiApiKey = 'translate.openai.apiKey';
  static const translateOpenAiModel = 'translate.openai.model';
  static const desktopPlayedColors = 'desktop.playedColors';
  static const desktopUnplayedColors = 'desktop.unplayedColors';
  static const desktopDefaultLangs = 'desktop.defaultLangs';
  static const desktopLangOrder = 'desktop.langOrder';
  static const desktopSources = 'desktop.sources';
  static const desktopFontFamily = 'desktop.fontFamily';
  static const desktopRefreshRate = 'desktop.refreshRate';
  static const desktopWindowRect = 'desktop.windowRect';
  static const desktopFontSize = 'desktop.fontSize';
  static const desktopShowFurigana = 'desktop.showFurigana';
  static const desktopPanelFontSize = 'desktop.panelFontSize';
  static const appLanguage = 'app.language';
  static const appColorScheme = 'app.colorScheme';
  static const appLogLevel = 'app.logLevel';
  static const appAutoCheckUpdate = 'app.autoCheckUpdate';

  static const requiredKeys = <String>{
    lyricsFileNameFormat,
    storageDefaultSavePath,
    lyricsId3Version,
    searchSources,
    lyricsLangOrder,
    matchSkipInst,
    matchAutoSelect,
    lyricsAddEndTimestamp,
    lyricsMsDigits,
    lyricsLastRefStyle,
    lyricsTagInfoSource,
    translateSource,
    translateTargetLang,
    translateOpenAiProfile,
    translateOpenAiBaseUrl,
    translateOpenAiApiKey,
    translateOpenAiModel,
    desktopPlayedColors,
    desktopUnplayedColors,
    desktopDefaultLangs,
    desktopLangOrder,
    desktopSources,
    desktopFontFamily,
    desktopRefreshRate,
    desktopWindowRect,
    desktopFontSize,
    desktopShowFurigana,
    desktopPanelFontSize,
    appLanguage,
    appColorScheme,
    appLogLevel,
    appAutoCheckUpdate,
  };
}
