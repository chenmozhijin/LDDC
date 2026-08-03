import 'package:flutter/widgets.dart';

import '../../../core/i18n/i18n.dart';
import '../application/settings_page_models.dart';

String settingsNoticeText(BuildContext context, String codeName) {
  final SettingsNoticeCode? code = _decodeSettingsNoticeCode(codeName);
  if (code == null) {
    return codeName;
  }
  final l10n = context.l10n;
  return switch (code) {
    SettingsNoticeCode.defaultSavePathUpdated =>
      l10n.settingsNoticeDefaultSavePathUpdated,
    SettingsNoticeCode.defaultSavePathRestored =>
      l10n.settingsNoticeDefaultSavePathRestored,
    SettingsNoticeCode.lyricsFileNameFormatUpdated =>
      l10n.settingsNoticeLyricsFileNameFormatUpdated,
    SettingsNoticeCode.id3VersionUpdated =>
      l10n.settingsNoticeId3VersionUpdated,
    SettingsNoticeCode.lyricsLangOrderEmpty =>
      l10n.settingsNoticeLyricsLangOrderEmpty,
    SettingsNoticeCode.lyricsLangOrderUpdated =>
      l10n.settingsNoticeLyricsLangOrderUpdated,
    SettingsNoticeCode.skipInstUpdated => l10n.settingsNoticeSkipInstUpdated,
    SettingsNoticeCode.autoSelectUpdated =>
      l10n.settingsNoticeAutoSelectUpdated,
    SettingsNoticeCode.addEndTimestampUpdated =>
      l10n.settingsNoticeAddEndTimestampUpdated,
    SettingsNoticeCode.msDigitsUpdated => l10n.settingsNoticeMsDigitsUpdated,
    SettingsNoticeCode.lastRefStyleUpdated =>
      l10n.settingsNoticeLastRefStyleUpdated,
    SettingsNoticeCode.tagInfoSourceUpdated =>
      l10n.settingsNoticeTagInfoSourceUpdated,
    SettingsNoticeCode.desktopSourcesEmpty =>
      l10n.settingsNoticeDesktopSourcesEmpty,
    SettingsNoticeCode.desktopSourcesUpdated =>
      l10n.settingsNoticeDesktopSourcesUpdated,
    SettingsNoticeCode.desktopDefaultLangsEmpty =>
      l10n.settingsNoticeDesktopDefaultLangsEmpty,
    SettingsNoticeCode.desktopLangsUpdated =>
      l10n.settingsNoticeDesktopLangsUpdated,
    SettingsNoticeCode.desktopFontFamilyUpdated =>
      l10n.settingsNoticeDesktopFontFamilyUpdated,
    SettingsNoticeCode.desktopRefreshRateUpdated =>
      l10n.settingsNoticeDesktopRefreshRateUpdated,
    SettingsNoticeCode.desktopPlayedColorsUpdated =>
      l10n.settingsNoticeDesktopPlayedColorsUpdated,
    SettingsNoticeCode.desktopUnplayedColorsUpdated =>
      l10n.settingsNoticeDesktopUnplayedColorsUpdated,
    SettingsNoticeCode.desktopFontSizeUpdated =>
      l10n.settingsNoticeDesktopFontSizeUpdated,
    SettingsNoticeCode.desktopPanelFontSizeUpdated =>
      l10n.settingsNoticeDesktopPanelFontSizeUpdated,
    SettingsNoticeCode.desktopShowFuriganaUpdated =>
      l10n.settingsNoticeDesktopShowFuriganaUpdated,
    SettingsNoticeCode.translateSourceUpdated =>
      l10n.settingsNoticeTranslateSourceUpdated,
    SettingsNoticeCode.translateTargetLangUpdated =>
      l10n.settingsNoticeTranslateTargetLangUpdated,
    SettingsNoticeCode.openAiProfileUpdated =>
      l10n.settingsNoticeOpenAiProfileUpdated,
    SettingsNoticeCode.openAiBaseUrlUpdated =>
      l10n.settingsNoticeOpenAiBaseUrlUpdated,
    SettingsNoticeCode.openAiApiKeyUpdated =>
      l10n.settingsNoticeOpenAiApiKeyUpdated,
    SettingsNoticeCode.openAiModelUpdated =>
      l10n.settingsNoticeOpenAiModelUpdated,
    SettingsNoticeCode.searchSourcesEmpty =>
      l10n.settingsNoticeSearchSourcesEmpty,
    SettingsNoticeCode.searchSourcesUpdated =>
      l10n.settingsNoticeSearchSourcesUpdated,
    SettingsNoticeCode.appLanguageUpdated =>
      l10n.settingsNoticeAppLanguageUpdated,
    SettingsNoticeCode.appColorSchemeUpdated =>
      l10n.settingsNoticeAppColorSchemeUpdated,
    SettingsNoticeCode.appLogLevelUpdated =>
      l10n.settingsNoticeAppLogLevelUpdated,
    SettingsNoticeCode.autoCheckUpdateUpdated =>
      l10n.settingsNoticeAutoCheckUpdateUpdated,
    SettingsNoticeCode.sectionNoRestorableConfig =>
      l10n.settingsNoticeSectionNoRestorableConfig,
    SettingsNoticeCode.sectionDefaultsRestored =>
      l10n.settingsNoticeSectionDefaultsRestored,
    SettingsNoticeCode.allDefaultsRestored =>
      l10n.settingsNoticeAllDefaultsRestored,
    SettingsNoticeCode.associationManagerOpened =>
      l10n.settingsNoticeAssociationManagerOpened,
    SettingsNoticeCode.logDirectoryOpened =>
      l10n.settingsNoticeLogDirectoryOpened,
    SettingsNoticeCode.logDirectoryOpenFailed =>
      l10n.settingsNoticeLogDirectoryOpenFailed,
    SettingsNoticeCode.cacheCleared => l10n.settingsNoticeCacheCleared,
    SettingsNoticeCode.cacheClearFailed => l10n.settingsNoticeCacheClearFailed,
    SettingsNoticeCode.configWriteFailed =>
      l10n.settingsNoticeConfigWriteFailed,
  };
}

SettingsNoticeCode? _decodeSettingsNoticeCode(String name) {
  for (final SettingsNoticeCode code in SettingsNoticeCode.values) {
    if (code.name == name) {
      return code;
    }
  }
  return null;
}
