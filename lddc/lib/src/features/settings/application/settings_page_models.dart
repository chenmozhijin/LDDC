import '../../../core/config/config.dart';

/// 设置页分组：对齐Python版 `setting.py` 的配置分区语义。
enum SettingsSection {
  save,
  search,
  desktopLyrics,
  lyrics,
  translate,
  app,
  tools,
}

/// 翻译配置区的条件字段。
enum SettingsTranslateField {
  openAiProfile,
  openAiBaseUrl,
  openAiApiKey,
  openAiModel,
}

/// 设置页一次性提示码。
///
/// Controller 只保存稳定 code，具体中文/英文文案由 UI 层根据当前语言渲染。
/// 这样运行时切换语言后不会把旧中文提示继续带到 Snackbar 中，也避免业务层散落可见文案。
enum SettingsNoticeCode {
  defaultSavePathUpdated,
  defaultSavePathRestored,
  lyricsFileNameFormatUpdated,
  id3VersionUpdated,
  lyricsLangOrderEmpty,
  lyricsLangOrderUpdated,
  skipInstUpdated,
  autoSelectUpdated,
  addEndTimestampUpdated,
  msDigitsUpdated,
  lastRefStyleUpdated,
  tagInfoSourceUpdated,
  desktopSourcesEmpty,
  desktopSourcesUpdated,
  desktopDefaultLangsEmpty,
  desktopLangsUpdated,
  desktopFontFamilyUpdated,
  desktopRefreshRateUpdated,
  desktopPlayedColorsUpdated,
  desktopUnplayedColorsUpdated,
  desktopFontSizeUpdated,
  desktopPanelFontSizeUpdated,
  desktopShowFuriganaUpdated,
  translateSourceUpdated,
  translateTargetLangUpdated,
  openAiProfileUpdated,
  openAiBaseUrlUpdated,
  openAiApiKeyUpdated,
  openAiModelUpdated,
  searchSourcesEmpty,
  searchSourcesUpdated,
  appLanguageUpdated,
  appColorSchemeUpdated,
  appLogLevelUpdated,
  autoCheckUpdateUpdated,
  sectionNoRestorableConfig,
  sectionDefaultsRestored,
  allDefaultsRestored,
  associationManagerOpened,
  logDirectoryOpened,
  logDirectoryOpenFailed,
  cacheCleared,
  cacheClearFailed,
  configWriteFailed,
}

/// 排序/勾选复合项：用于承载Python版顺序列表与来源列表的结构化语义。
class SettingsOrderedToggleItem {
  const SettingsOrderedToggleItem({
    required this.value,
    required this.label,
    required this.selected,
  });

  final String value;
  final String label;
  final bool selected;

  SettingsOrderedToggleItem copyWith({
    String? value,
    String? label,
    bool? selected,
  }) {
    return SettingsOrderedToggleItem(
      value: value ?? this.value,
      label: label ?? this.label,
      selected: selected ?? this.selected,
    );
  }
}

/// 设置页载荷：承载当前配置快照与锚点状态。
class SettingsPagePayload {
  const SettingsPagePayload({
    required this.config,
    required this.activeSection,
    required this.showDesktopTools,
    required this.visibleTranslateFields,
  });

  final AppConfig config;
  final SettingsSection activeSection;
  final bool showDesktopTools;
  final Set<SettingsTranslateField> visibleTranslateFields;

  SettingsPagePayload copyWith({
    AppConfig? config,
    SettingsSection? activeSection,
    bool? showDesktopTools,
    Set<SettingsTranslateField>? visibleTranslateFields,
  }) {
    return SettingsPagePayload(
      config: config ?? this.config,
      activeSection: activeSection ?? this.activeSection,
      showDesktopTools: showDesktopTools ?? this.showDesktopTools,
      visibleTranslateFields:
          visibleTranslateFields ?? this.visibleTranslateFields,
    );
  }
}
