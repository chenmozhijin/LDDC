import 'package:flutter/material.dart';

import '../../../../core/config/config.dart';
import '../../../../core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../../application/settings_page_models.dart';

SettingsPagePayload payloadOf(AsyncViewState<SettingsPagePayload> view) {
  return switch (view) {
    AsyncSuccess<SettingsPagePayload>(:final data) => data,
    AsyncPartial<SettingsPagePayload>(:final data) => data,
    _ => SettingsPagePayload(
      config: ConfigDefaults.current,
      activeSection: SettingsSection.save,
      showDesktopTools: false,
      visibleTranslateFields: const <SettingsTranslateField>{},
    ),
  };
}

class SettingsValueDescriptor<T> {
  const SettingsValueDescriptor({required this.value, required this.label});

  final T value;
  final String label;
}

List<SettingsValueDescriptor<String>> settingsLyricLangDescriptors(
  AppLocalizations l10n,
) {
  return <SettingsValueDescriptor<String>>[
    SettingsValueDescriptor<String>(value: 'roma', label: l10n.lyricRomanized),
    SettingsValueDescriptor<String>(value: 'orig', label: l10n.lyricOriginal),
    SettingsValueDescriptor<String>(value: 'ts', label: l10n.lyricTranslation),
  ];
}

List<SettingsValueDescriptor<String>> settingsSearchSourceDescriptors(
  AppLocalizations l10n,
) {
  return <SettingsValueDescriptor<String>>[
    SettingsValueDescriptor<String>(value: 'QM', label: l10n.sourceQQMusic),
    SettingsValueDescriptor<String>(value: 'KG', label: l10n.sourceKugou),
    SettingsValueDescriptor<String>(value: 'NE', label: l10n.sourceNetease),
    SettingsValueDescriptor<String>(value: 'LRCLIB', label: l10n.sourceLrclib),
  ];
}

List<SettingsValueDescriptor<TranslateSource>>
settingsTranslateSourceDescriptors(AppLocalizations l10n) {
  return <SettingsValueDescriptor<TranslateSource>>[
    SettingsValueDescriptor<TranslateSource>(
      value: TranslateSource.bing,
      label: l10n.settingsTranslateSourceBing,
    ),
    SettingsValueDescriptor<TranslateSource>(
      value: TranslateSource.google,
      label: l10n.settingsTranslateSourceGoogle,
    ),
    SettingsValueDescriptor<TranslateSource>(
      value: TranslateSource.openai,
      label: l10n.settingsTranslateSourceOpenAi,
    ),
  ];
}

List<SettingsValueDescriptor<TranslateTargetLang>>
settingsTranslateTargetDescriptors(AppLocalizations l10n) {
  return <SettingsValueDescriptor<TranslateTargetLang>>[
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.simplifiedChinese,
      label: l10n.settingsLangSimplifiedChinese,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.traditionalChinese,
      label: l10n.settingsLangTraditionalChinese,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.english,
      label: l10n.settingsLangEnglish,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.japanese,
      label: l10n.settingsLangJapanese,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.korean,
      label: l10n.settingsLangKorean,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.spanish,
      label: l10n.settingsLangSpanish,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.french,
      label: l10n.settingsLangFrench,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.portuguese,
      label: l10n.settingsLangPortuguese,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.german,
      label: l10n.settingsLangGerman,
    ),
    SettingsValueDescriptor<TranslateTargetLang>(
      value: TranslateTargetLang.russian,
      label: l10n.settingsLangRussian,
    ),
  ];
}

List<SettingsValueDescriptor<AppLanguage>> settingsAppLanguageDescriptors(
  AppLocalizations l10n,
) {
  return <SettingsValueDescriptor<AppLanguage>>[
    SettingsValueDescriptor<AppLanguage>(
      value: AppLanguage.auto,
      label: l10n.settingsAppLanguageAuto,
    ),
    SettingsValueDescriptor<AppLanguage>(
      value: AppLanguage.zhHans,
      // 语言名称固定使用本语言自称，切换到陌生语言后仍能找到并切回。
      label: '简体中文',
    ),
    SettingsValueDescriptor<AppLanguage>(
      value: AppLanguage.zhHant,
      label: '繁體中文',
    ),
    SettingsValueDescriptor<AppLanguage>(
      value: AppLanguage.en,
      label: 'English',
    ),
    SettingsValueDescriptor<AppLanguage>(
      value: AppLanguage.ru,
      label: 'Русский',
    ),
    SettingsValueDescriptor<AppLanguage>(value: AppLanguage.ja, label: '日本語'),
    SettingsValueDescriptor<AppLanguage>(value: AppLanguage.ko, label: '한국어'),
  ];
}

List<SettingsValueDescriptor<AppColorScheme>> settingsColorSchemeDescriptors(
  AppLocalizations l10n,
) {
  return <SettingsValueDescriptor<AppColorScheme>>[
    SettingsValueDescriptor<AppColorScheme>(
      value: AppColorScheme.auto,
      label: l10n.settingsColorSchemeAuto,
    ),
    SettingsValueDescriptor<AppColorScheme>(
      value: AppColorScheme.light,
      label: l10n.settingsColorSchemeLight,
    ),
    SettingsValueDescriptor<AppColorScheme>(
      value: AppColorScheme.dark,
      label: l10n.settingsColorSchemeDark,
    ),
  ];
}

const List<SettingsValueDescriptor<AppLogLevel>> settingsLogLevelDescriptors =
    <SettingsValueDescriptor<AppLogLevel>>[
      SettingsValueDescriptor<AppLogLevel>(
        value: AppLogLevel.trace,
        label: 'TRACE',
      ),
      SettingsValueDescriptor<AppLogLevel>(
        value: AppLogLevel.debug,
        label: 'DEBUG',
      ),
      SettingsValueDescriptor<AppLogLevel>(
        value: AppLogLevel.info,
        label: 'INFO',
      ),
      SettingsValueDescriptor<AppLogLevel>(
        value: AppLogLevel.warning,
        label: 'WARNING',
      ),
      SettingsValueDescriptor<AppLogLevel>(
        value: AppLogLevel.error,
        label: 'ERROR',
      ),
    ];

List<SettingsOrderedToggleItem> buildLyricLangItems(
  List<String> order,
  AppLocalizations l10n,
) {
  return _normalizeOrder(
        order,
        descriptorValues(settingsLyricLangDescriptors(l10n)),
      )
      .map(
        (String value) => SettingsOrderedToggleItem(
          value: value,
          label: settingsLangLabel(value, l10n),
          selected: true,
        ),
      )
      .toList(growable: false);
}

List<SettingsOrderedToggleItem> buildDesktopLangItems(
  List<String> selected,
  List<String> order,
  AppLocalizations l10n,
) {
  final Set<String> selectedSet = selected.toSet();
  return _normalizeOrder(
        order,
        descriptorValues(settingsLyricLangDescriptors(l10n)),
      )
      .map(
        (String value) => SettingsOrderedToggleItem(
          value: value,
          label: settingsLangLabel(value, l10n),
          selected: selectedSet.contains(value),
        ),
      )
      .toList(growable: false);
}

List<SettingsOrderedToggleItem> buildSourceItems(
  List<String> selectedSources,
  AppLocalizations l10n,
) {
  final Set<String> selectedSet = selectedSources.toSet();
  return _normalizeOrder(
        selectedSources,
        descriptorValues(settingsSearchSourceDescriptors(l10n)),
      )
      .map(
        (String value) => SettingsOrderedToggleItem(
          value: value,
          label: settingsSourceLabel(value, l10n),
          selected: selectedSet.contains(value),
        ),
      )
      .toList(growable: false);
}

List<String> _normalizeOrder(List<String> current, List<String> allowed) {
  final List<String> normalized = <String>[];
  for (final String value in current) {
    if (allowed.contains(value) && !normalized.contains(value)) {
      normalized.add(value);
    }
  }
  for (final String value in allowed) {
    if (!normalized.contains(value)) {
      normalized.add(value);
    }
  }
  return normalized;
}

List<String> orderedValues(List<SettingsOrderedToggleItem> items) {
  return items
      .map((SettingsOrderedToggleItem item) => item.value)
      .toList(growable: false);
}

List<String> selectedValues(List<SettingsOrderedToggleItem> items) {
  return items
      .where((SettingsOrderedToggleItem item) => item.selected)
      .map((SettingsOrderedToggleItem item) => item.value)
      .toList(growable: false);
}

List<SettingsOrderedToggleItem> reorderItems(
  List<SettingsOrderedToggleItem> items,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 || oldIndex >= items.length) {
    return List<SettingsOrderedToggleItem>.from(items);
  }
  final List<SettingsOrderedToggleItem> reordered =
      List<SettingsOrderedToggleItem>.from(items);
  final SettingsOrderedToggleItem item = reordered.removeAt(oldIndex);
  // ReorderableListView 的 newIndex 是“拖动前列表”的插入位置；向下拖动时，
  // removeAt 会先移除旧项，因此真实插入位置需要减 1，避免顺序偏后一格。
  final int adjustedIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
  reordered.insert(adjustedIndex.clamp(0, reordered.length), item);
  return reordered;
}

String settingsLangLabel(String value, AppLocalizations l10n) {
  return descriptorLabel(settingsLyricLangDescriptors(l10n), value);
}

String settingsSourceLabel(String value, AppLocalizations l10n) {
  return descriptorLabel(settingsSearchSourceDescriptors(l10n), value);
}

List<String> desktopFontChoices(String currentValue) {
  final List<String> choices = <String>[
    '',
    'Microsoft YaHei UI',
    'Segoe UI',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Consolas',
  ];
  if (currentValue.isNotEmpty && !choices.contains(currentValue)) {
    choices.insert(1, currentValue);
  }
  return choices;
}

String settingsTranslateSourceLabel(
  TranslateSource value,
  AppLocalizations l10n,
) {
  return descriptorLabel(settingsTranslateSourceDescriptors(l10n), value);
}

String settingsTranslateTargetLabel(
  TranslateTargetLang value,
  AppLocalizations l10n,
) {
  return descriptorLabel(settingsTranslateTargetDescriptors(l10n), value);
}

String settingsOpenAiProfileLabel(OpenAiProfile value) {
  return OpenAiProfileSpec.of(value).label;
}

String settingsAppLanguageLabel(AppLanguage value, AppLocalizations l10n) {
  return descriptorLabel(settingsAppLanguageDescriptors(l10n), value);
}

String settingsColorSchemeLabel(AppColorScheme value, AppLocalizations l10n) {
  return descriptorLabel(settingsColorSchemeDescriptors(l10n), value);
}

String settingsLogLevelLabel(AppLogLevel value) {
  return descriptorLabel(settingsLogLevelDescriptors, value);
}

List<T> descriptorValues<T>(List<SettingsValueDescriptor<T>> descriptors) {
  return descriptors
      .map((SettingsValueDescriptor<T> descriptor) => descriptor.value)
      .toList(growable: false);
}

String descriptorLabel<T>(
  List<SettingsValueDescriptor<T>> descriptors,
  T value,
) {
  for (final SettingsValueDescriptor<T> descriptor in descriptors) {
    if (descriptor.value == value) {
      return descriptor.label;
    }
  }
  return value.toString();
}

class SettingsSectionMeta {
  const SettingsSectionMeta({
    required this.title,
    required this.summary,
    required this.icon,
  });

  final String title;
  final String summary;
  final IconData icon;
}

SettingsSectionMeta settingsSectionMeta(
  SettingsSection section,
  AppLocalizations l10n,
) {
  return switch (section) {
    SettingsSection.save => SettingsSectionMeta(
      title: l10n.settingsSectionSave,
      summary: l10n.settingsSectionSaveSummary,
      icon: Icons.save_outlined,
    ),
    SettingsSection.search => SettingsSectionMeta(
      title: l10n.settingsSectionSearch,
      summary: l10n.settingsSectionSearchSummary,
      icon: Icons.search_outlined,
    ),
    SettingsSection.desktopLyrics => SettingsSectionMeta(
      title: l10n.settingsSectionDesktopLyrics,
      summary: l10n.settingsSectionDesktopLyricsSummary,
      icon: Icons.desktop_windows_outlined,
    ),
    SettingsSection.lyrics => SettingsSectionMeta(
      title: l10n.settingsSectionLyrics,
      summary: l10n.settingsSectionLyricsSummary,
      icon: Icons.lyrics_outlined,
    ),
    SettingsSection.translate => SettingsSectionMeta(
      title: l10n.settingsSectionTranslate,
      summary: l10n.settingsSectionTranslateSummary,
      icon: Icons.translate_outlined,
    ),
    SettingsSection.app => SettingsSectionMeta(
      title: l10n.settingsSectionApp,
      summary: l10n.settingsSectionAppSummary,
      icon: Icons.tune_outlined,
    ),
    SettingsSection.tools => SettingsSectionMeta(
      title: l10n.settingsSectionTools,
      summary: l10n.settingsSectionToolsSummary,
      icon: Icons.build_outlined,
    ),
  };
}
