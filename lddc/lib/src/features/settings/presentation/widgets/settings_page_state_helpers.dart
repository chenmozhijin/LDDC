import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/config/config.dart';
import '../../../../core/accessibility/app_action_semantics.dart';
import '../../../../core/i18n/i18n.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../../application/settings_page_controller.dart';
import '../../application/settings_page_models.dart';
import '../settings_page.dart';
import 'settings_color_editor.dart';
import 'settings_data_helpers.dart';
import 'settings_page_chrome.dart';
import 'settings_reorderable_lists.dart';
import 'settings_section_components.dart';

// 这些方法需要访问 SettingsPageState 的滚动控制器、section key 和 ref。
// 放在 extension 中可以让主页面类保持精简，同时通过显式导入看清依赖边界。
// 注意：extension 不是 State 子类，涉及 setState 的修改必须回调主状态类里的私有方法，
// 这样 Flutter 初学者也能清楚看到“状态修改仍由 State 对象负责”。
extension SettingsPageStateHelpers on SettingsPageState {
  List<SettingsSection> visibleSections(SettingsPagePayload payload) {
    final List<SettingsSection> sections = <SettingsSection>[
      SettingsSection.save,
      SettingsSection.search,
      SettingsSection.desktopLyrics,
      SettingsSection.lyrics,
      SettingsSection.translate,
      SettingsSection.app,
    ];
    if (payload.showDesktopTools) {
      sections.add(SettingsSection.tools);
    }
    return sections;
  }

  Future<void> _pickDefaultSavePath(SettingsPageController controller) async {
    await controller.pickDefaultSavePath();
  }

  void handleScroll() {
    if (_isCompactLayout) {
      return;
    }
    final AsyncViewState<SettingsPagePayload> view = ref
        .read(settingsPageControllerProvider)
        .view;
    if (view case AsyncSuccess<SettingsPagePayload>(:final data)) {
      scheduleActiveSectionSync(data);
    } else if (view case AsyncPartial<SettingsPagePayload>(:final data)) {
      scheduleActiveSectionSync(data);
    }
  }

  void scheduleActiveSectionSync(SettingsPagePayload payload) {
    if (syncQueued) {
      return;
    }
    syncQueued = true;
    // 滚动监听和宽屏 build 都可能连续触发；统一压缩到下一帧只同步一次，
    // 避免频繁 addPostFrameCallback 造成多余 rebuild 或选中态抖动。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      syncQueued = false;
      if (!mounted) {
        return;
      }
      syncActiveSection(payload);
    });
  }

  void syncActiveSection(SettingsPagePayload payload) {
    if (_isCompactLayout) {
      return;
    }
    final RenderObject? rootObject = context.findRenderObject();
    if (rootObject is! RenderBox) {
      return;
    }
    final List<SettingsSection> sections = visibleSections(payload);
    if (sections.isEmpty) {
      return;
    }
    SettingsSection active = sections.first;
    final double threshold = SettingsPageState.anchorBarExtent + 20;
    for (final SettingsSection section in sections) {
      final BuildContext? sectionContext = sectionKeys[section]?.currentContext;
      if (sectionContext == null) {
        continue;
      }
      final RenderObject? renderObject = sectionContext.findRenderObject();
      if (renderObject is! RenderBox) {
        continue;
      }
      final Offset offset = renderObject.localToGlobal(
        Offset.zero,
        ancestor: rootObject,
      );
      if (offset.dy <= threshold) {
        active = section;
      } else {
        break;
      }
    }
    ref.read(settingsPageControllerProvider.notifier).setActiveSection(active);
  }

  Future<void> scrollToSection(SettingsSection section) async {
    final BuildContext? targetContext = sectionKeys[section]?.currentContext;
    if (targetContext == null || !settingsScrollController.hasClients) {
      return;
    }
    final RenderObject? targetObject = targetContext.findRenderObject();
    if (targetObject == null) {
      return;
    }
    final RenderAbstractViewport? viewport = RenderAbstractViewport.maybeOf(
      targetObject,
    );
    if (viewport == null) {
      return;
    }
    final RevealedOffset revealed = viewport.getOffsetToReveal(targetObject, 0);
    final double targetOffset =
        (revealed.offset - SettingsPageState.anchorBarExtent - 12).clamp(
          0,
          settingsScrollController.position.maxScrollExtent,
        );
    await settingsScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget buildSection({
    required BuildContext context,
    required SettingsPagePayload payload,
    required SettingsSection section,
    required SettingsPageController controller,
    bool showHeader = true,
  }) {
    final AppConfig config = payload.config;
    final SettingsSectionMeta sectionMeta = settingsSectionMeta(
      section,
      context.l10n,
    );
    final Widget? restoreAction = _buildSectionRestoreAction(
      context: context,
      section: section,
      sectionTitle: sectionMeta.title,
      controller: controller,
    );

    switch (section) {
      case SettingsSection.save:
        return SettingsSectionBlock(
          title: sectionMeta.title,
          summary: sectionMeta.summary,
          showHeader: showHeader,
          headerAction: restoreAction,
          cards: <Widget>[
            SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SettingsTextField(
                    label: context.l10n.settingsCurrentSavePathLabel,
                    initialValue: config.storage.defaultSavePath,
                    helperText: context.l10n.settingsDefaultSavePathHelper,
                    onSubmitted: controller.updateDefaultSavePath,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: () => _pickDefaultSavePath(controller),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(context.l10n.settingsChooseFolder),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SettingsTextField(
                    label: context.l10n.settingsLyricsFileNameFormat,
                    initialValue: config.lyrics.fileNameFormat,
                    helperText: context.l10n.settingsLyricsFileNameFormatHelper,
                    onSubmitted: controller.updateLyricsFileNameFormat,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Id3Version>(
                    initialValue: config.lyrics.id3Version,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsId3Version,
                      helperText: context.l10n.settingsId3VersionHelper,
                    ),
                    items: Id3Version.values
                        .map(
                          (Id3Version value) => DropdownMenuItem<Id3Version>(
                            value: value,
                            child: Text(value.value),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (Id3Version? value) {
                      if (value != null) {
                        controller.updateId3Version(value);
                      }
                    },
                  ),
                ],
              ),
            ),
            SettingsCard(
              child: SettingsPlaceholderHintCard(
                template: config.lyrics.fileNameFormat,
              ),
            ),
          ],
        );
      case SettingsSection.search:
        final List<SettingsOrderedToggleItem> sourceItems = buildSourceItems(
          config.search.sources,
          context.l10n,
        );
        return SettingsSectionBlock(
          title: sectionMeta.title,
          summary: sectionMeta.summary,
          showHeader: showHeader,
          headerAction: restoreAction,
          cards: <Widget>[
            SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SettingsSubsectionHeader(
                    key: const ValueKey<String>(
                      'settings_search_sources_header',
                    ),
                    title: context.l10n.settingsSearchSourcesTitle,
                    description: context.l10n.settingsSearchSourcesDescription,
                  ),
                  const SizedBox(height: 12),
                  SettingsReorderableToggleList(
                    key: const ValueKey<String>('settings_search_sources'),
                    items: sourceItems,
                    reorderHint: context.l10n.settingsReorderPriorityHint,
                    onChanged: (List<SettingsOrderedToggleItem> items) {
                      controller.updateSearchSources(selectedValues(items));
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      case SettingsSection.desktopLyrics:
        final List<SettingsOrderedToggleItem> langItems = buildDesktopLangItems(
          config.desktop.defaultLangs,
          config.desktop.langOrder,
          context.l10n,
        );
        final List<SettingsOrderedToggleItem> sourceItems = buildSourceItems(
          config.desktop.sources,
          context.l10n,
        );
        final List<String> fontChoices = desktopFontChoices(
          config.desktop.fontFamily,
        );
        return SettingsSectionBlock(
          title: sectionMeta.title,
          summary: sectionMeta.summary,
          showHeader: showHeader,
          headerAction: restoreAction,
          cards: <Widget>[
            SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SettingsSubsectionHeader(
                    key: const ValueKey<String>(
                      'settings_desktop_languages_header',
                    ),
                    title: context.l10n.settingsDefaultLanguage,
                    description:
                        context.l10n.settingsDefaultLanguageDescription,
                  ),
                  const SizedBox(height: 12),
                  SettingsReorderableToggleList(
                    key: const ValueKey<String>('settings_desktop_langs'),
                    items: langItems,
                    reorderHint: context.l10n.settingsReorderOrderHint,
                    onChanged: (List<SettingsOrderedToggleItem> items) {
                      controller.updateDesktopLangSelection(
                        selected: selectedValues(items),
                        order: orderedValues(items),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SettingsSubsectionHeader(
                    key: const ValueKey<String>(
                      'settings_desktop_sources_header',
                    ),
                    title: context.l10n.settingsDesktopAutoFetchSources,
                    description:
                        context.l10n.settingsDesktopAutoFetchSourcesDescription,
                  ),
                  const SizedBox(height: 12),
                  SettingsReorderableToggleList(
                    key: const ValueKey<String>('settings_desktop_sources'),
                    items: sourceItems,
                    reorderHint: context.l10n.settingsReorderPriorityHint,
                    onChanged: (List<SettingsOrderedToggleItem> items) {
                      controller.updateDesktopSources(selectedValues(items));
                    },
                  ),
                ],
              ),
            ),
            SettingsCard(
              child: DesktopColorSettings(
                playedColors: config.desktop.playedColors,
                unplayedColors: config.desktop.unplayedColors,
                onPlayedColorsChanged: controller.updateDesktopPlayedColors,
                onUnplayedColorsChanged: controller.updateDesktopUnplayedColors,
              ),
            ),
            SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue:
                        fontChoices.contains(config.desktop.fontFamily)
                        ? config.desktop.fontFamily
                        : fontChoices.first,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsFont,
                    ),
                    items: fontChoices
                        .map(
                          (String value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(
                              value.isEmpty
                                  ? context.l10n.settingsFollowSystemFont
                                  : value,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (String? value) {
                      if (value != null) {
                        controller.updateDesktopFontFamily(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.settingsFontSizeByResize,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  SettingsSliderField(
                    label: context.l10n.settingsPanelFontSize,
                    value: config.desktop.panelFontSize,
                    min: 8,
                    max: 30,
                    divisions: 22,
                    valueLabel:
                        '${config.desktop.panelFontSize.toStringAsFixed(0)} px',
                    onChanged: controller.updateDesktopPanelFontSize,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.settingsAdaptiveRefreshRate),
                    subtitle: Text(
                      context.l10n.settingsAdaptiveRefreshRateSubtitle,
                    ),
                    value: config.desktop.refreshRate == -1,
                    onChanged: (bool value) {
                      controller.updateDesktopRefreshRate(value ? -1 : 60);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: config.desktop.refreshRate == -1
                        ? 60
                        : config.desktop.refreshRate,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsFixedRefreshRate,
                    ),
                    items: const <int>[30, 60, 90, 120, 144, 240]
                        .map(
                          (int value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value Hz'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: config.desktop.refreshRate == -1
                        ? null
                        : (int? value) {
                            if (value != null) {
                              controller.updateDesktopRefreshRate(value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: config.desktop.showFurigana,
                    onChanged: controller.updateDesktopShowFurigana,
                    title: Text(context.l10n.settingsShowFurigana),
                  ),
                ],
              ),
            ),
          ],
        );
      case SettingsSection.lyrics:
        final List<SettingsOrderedToggleItem> lyricLangItems =
            buildLyricLangItems(config.lyrics.langOrder, context.l10n);
        return SettingsSectionBlock(
          title: sectionMeta.title,
          summary: sectionMeta.summary,
          showHeader: showHeader,
          headerAction: restoreAction,
          cards: <Widget>[
            SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SettingsSubsectionHeader(
                    key: const ValueKey<String>('settings_lyrics_match_header'),
                    title: context.l10n.settingsLyricsMatchBehavior,
                    description:
                        context.l10n.settingsLyricsMatchBehaviorDescription,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: config.match.skipInst,
                    onChanged: controller.updateSkipInst,
                    title: Text(context.l10n.settingsSkipInstrumental),
                    subtitle: Text(
                      context.l10n.settingsSkipInstrumentalSubtitle,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: config.match.autoSelect,
                    onChanged: controller.updateAutoSelect,
                    title: Text(context.l10n.settingsAutoSelectKugou),
                    subtitle: Text(
                      context.l10n.settingsAutoSelectKugouSubtitle,
                    ),
                  ),
                ],
              ),
            ),
            SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SettingsSubsectionHeader(
                    key: const ValueKey<String>(
                      'settings_lyrics_export_header',
                    ),
                    title: context.l10n.settingsLyricsExport,
                    description: context.l10n.settingsLyricsExportDescription,
                  ),
                  const SizedBox(height: 16),
                  SettingsSubsectionHeader(
                    key: const ValueKey<String>(
                      'settings_lyrics_language_order_header',
                    ),
                    title: context.l10n.settingsDisplayOrder,
                    description: context.l10n.settingsDisplayOrderDescription,
                  ),
                  const SizedBox(height: 12),
                  SettingsReorderableLabelList(
                    key: const ValueKey<String>('settings_lyrics_lang_order'),
                    items: lyricLangItems,
                    reorderHint: context.l10n.settingsReorderOrderHint,
                    onChanged: (List<SettingsOrderedToggleItem> items) {
                      controller.updateLyricsLangOrder(orderedValues(items));
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: config.lyrics.addEndTimestamp,
                    onChanged: controller.updateAddEndTimestamp,
                    title: Text(context.l10n.settingsAddLrcEndTimestamp),
                    subtitle: Text(
                      context.l10n.settingsAddLrcEndTimestampSubtitle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: config.lyrics.msDigits,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsMillisecondsDigits,
                      helperText: context.l10n.settingsMillisecondsDigitsHelper,
                    ),
                    items: const <int>[2, 3]
                        .map(
                          (int value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text(
                              context.l10n.settingsDigitsValue(value),
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (int? value) {
                      if (value != null) {
                        controller.updateMsDigits(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: config.lyrics.lastRefStyle,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsLastRefStyle,
                      helperText: context.l10n.settingsLastRefStyleHelper,
                    ),
                    items: <DropdownMenuItem<int>>[
                      DropdownMenuItem<int>(
                        value: 0,
                        child: Text(context.l10n.settingsLastRefCurrentLine),
                      ),
                      DropdownMenuItem<int>(
                        value: 1,
                        child: Text(context.l10n.settingsLastRefNextLine),
                      ),
                    ],
                    onChanged: (int? value) {
                      if (value != null) {
                        controller.updateLastRefStyle(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: config.lyrics.tagInfoSource,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsTagInfoSource,
                    ),
                    items: <DropdownMenuItem<int>>[
                      DropdownMenuItem<int>(
                        value: 0,
                        child: Text(context.l10n.settingsTagInfoLyricsSource),
                      ),
                      DropdownMenuItem<int>(
                        value: 1,
                        child: Text(context.l10n.settingsTagInfoSongInfo),
                      ),
                    ],
                    onChanged: (int? value) {
                      if (value != null) {
                        controller.updateTagInfoSource(value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      case SettingsSection.translate:
        return SettingsSectionBlock(
          title: sectionMeta.title,
          summary: sectionMeta.summary,
          showHeader: showHeader,
          headerAction: restoreAction,
          cards: <Widget>[
            SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<TranslateSource>(
                    key: const ValueKey<String>('settings_translate_source'),
                    initialValue: config.translate.source,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsTranslateSourceLabel,
                    ),
                    items: settingsTranslateSourceDescriptors(context.l10n)
                        .map(
                          (SettingsValueDescriptor<TranslateSource> item) =>
                              DropdownMenuItem<TranslateSource>(
                                value: item.value,
                                child: Text(item.label),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (TranslateSource? value) {
                      if (value != null) {
                        controller.updateTranslateSource(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TranslateTargetLang>(
                    initialValue: config.translate.targetLang,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsTranslateTargetLabel,
                    ),
                    items: settingsTranslateTargetDescriptors(context.l10n)
                        .map(
                          (SettingsValueDescriptor<TranslateTargetLang> item) =>
                              DropdownMenuItem<TranslateTargetLang>(
                                value: item.value,
                                child: Text(item.label),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (TranslateTargetLang? value) {
                      if (value != null) {
                        controller.updateTranslateTargetLang(value);
                      }
                    },
                  ),
                  if (payload.visibleTranslateFields.contains(
                    SettingsTranslateField.openAiProfile,
                  )) ...<Widget>[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<OpenAiProfile>(
                      key: const ValueKey<String>(
                        'settings_translate_openai_profile',
                      ),
                      initialValue: config.translate.openAi.profile,
                      decoration: InputDecoration(
                        labelText: context.l10n.settingsOpenAiProfileLabel,
                        helperText: context.l10n.settingsOpenAiProfileHelper,
                      ),
                      items: OpenAiProfile.values
                          .map(
                            (OpenAiProfile value) =>
                                DropdownMenuItem<OpenAiProfile>(
                                  value: value,
                                  child: Text(
                                    settingsOpenAiProfileLabel(value),
                                  ),
                                ),
                          )
                          .toList(growable: false),
                      onChanged: (OpenAiProfile? value) {
                        if (value != null) {
                          controller.updateOpenAiProfile(value);
                        }
                      },
                    ),
                  ],
                  if (payload.visibleTranslateFields.contains(
                    SettingsTranslateField.openAiBaseUrl,
                  )) ...<Widget>[
                    const SizedBox(height: 16),
                    SettingsTextField(
                      key: const ValueKey<String>(
                        'settings_translate_openai_base_url',
                      ),
                      label: 'Base URL',
                      initialValue: config.translate.openAi.baseUrl,
                      onSubmitted: controller.updateOpenAiBaseUrl,
                    ),
                  ],
                  if (payload.visibleTranslateFields.contains(
                    SettingsTranslateField.openAiApiKey,
                  )) ...<Widget>[
                    const SizedBox(height: 16),
                    SettingsTextField(
                      key: const ValueKey<String>(
                        'settings_translate_openai_api_key',
                      ),
                      label: 'API Key',
                      initialValue: config.translate.openAi.apiKey,
                      obscureText: true,
                      onSubmitted: controller.updateOpenAiApiKey,
                    ),
                  ],
                  if (payload.visibleTranslateFields.contains(
                    SettingsTranslateField.openAiModel,
                  )) ...<Widget>[
                    const SizedBox(height: 16),
                    SettingsTextField(
                      key: const ValueKey<String>(
                        'settings_translate_openai_model',
                      ),
                      label: 'Model',
                      initialValue: config.translate.openAi.model,
                      onSubmitted: controller.updateOpenAiModel,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      case SettingsSection.app:
        return SettingsSectionBlock(
          title: sectionMeta.title,
          summary: sectionMeta.summary,
          showHeader: showHeader,
          headerAction: restoreAction,
          cards: <Widget>[
            SettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<AppLanguage>(
                    key: const ValueKey<String>(
                      'settings_app_language_dropdown',
                    ),
                    initialValue: config.app.language,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsAppLanguageLabel,
                    ),
                    items: settingsAppLanguageDescriptors(context.l10n)
                        .map(
                          (SettingsValueDescriptor<AppLanguage> item) =>
                              DropdownMenuItem<AppLanguage>(
                                value: item.value,
                                child: Text(item.label),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (AppLanguage? value) {
                      if (value != null) {
                        controller.updateAppLanguage(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AppColorScheme>(
                    initialValue: config.app.colorScheme,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsColorSchemeLabel,
                    ),
                    items: settingsColorSchemeDescriptors(context.l10n)
                        .map(
                          (SettingsValueDescriptor<AppColorScheme> item) =>
                              DropdownMenuItem<AppColorScheme>(
                                value: item.value,
                                child: Text(item.label),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (AppColorScheme? value) {
                      if (value != null) {
                        controller.updateAppColorScheme(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AppLogLevel>(
                    initialValue: config.app.logLevel,
                    decoration: InputDecoration(
                      labelText: context.l10n.settingsLogLevelLabel,
                      helperText: context.l10n.settingsLogLevelHelper,
                    ),
                    items: settingsLogLevelDescriptors
                        .map(
                          (SettingsValueDescriptor<AppLogLevel> item) =>
                              DropdownMenuItem<AppLogLevel>(
                                value: item.value,
                                child: Text(item.label),
                              ),
                        )
                        .toList(growable: false),
                    onChanged: (AppLogLevel? value) {
                      if (value != null) {
                        controller.updateAppLogLevel(value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: config.app.autoCheckUpdate,
                    onChanged: controller.updateAutoCheckUpdate,
                    title: Text(context.l10n.settingsAutoCheckUpdateLabel),
                  ),
                ],
              ),
            ),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.warning_amber_outlined),
                    Text(context.l10n.settingsRestoreDefaultsWarning),
                    FilledButton.tonal(
                      key: const ValueKey<String>('settings_restore_defaults'),
                      onPressed: () => _confirmAndRun(
                        context,
                        title: context.l10n.settingsRestoreAllTitle,
                        content: context.l10n.settingsRestoreAllContent,
                        action: controller.restoreAllDefaults,
                      ),
                      child: Text(context.l10n.settingsRestoreAllAction),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      case SettingsSection.tools:
        return SettingsSectionBlock(
          title: sectionMeta.title,
          summary: sectionMeta.summary,
          showHeader: showHeader,
          cards: <Widget>[
            SettingsCard(
              child: Column(
                children: <Widget>[
                  ListTile(
                    key: const ValueKey<String>(
                      'settings_tools_open_association_manager',
                    ),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_outlined),
                    title: Text(context.l10n.settingsOpenAssociationManager),
                    subtitle: Text(
                      context.l10n.settingsOpenAssociationManagerSubtitle,
                    ),
                    onTap: controller.openAssociationManager,
                  ),
                  const Divider(),
                  AppActionSemantics(
                    identifier:
                        AppSemanticsIdentifiers.settingsOpenLogDirectory,
                    label: context.l10n.settingsOpenLogDirectory,
                    onTap: controller.openLogDirectory,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_open_outlined),
                      title: Text(context.l10n.settingsOpenLogDirectory),
                      subtitle: Text(
                        context.l10n.settingsOpenLogDirectorySubtitle,
                      ),
                      onTap: controller.openLogDirectory,
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    key: const ValueKey<String>('settings_tools_clear_cache'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: Text(context.l10n.settingsClearCache),
                    subtitle: Text(context.l10n.settingsClearCacheSubtitle),
                    onTap: () => _confirmAndRun(
                      context,
                      title: context.l10n.settingsClearCache,
                      content: context.l10n.settingsClearCacheContent,
                      action: controller.clearCache,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget? _buildSectionRestoreAction({
    required BuildContext context,
    required SettingsSection section,
    required String sectionTitle,
    required SettingsPageController controller,
  }) {
    if (section == SettingsSection.tools) {
      return null;
    }
    void handlePressed() {
      unawaited(
        _confirmAndRun(
          context,
          title: context.l10n.settingsRestoreSectionTitle,
          content: context.l10n.settingsRestoreSectionContent(sectionTitle),
          action: () => controller.restoreSectionDefaults(section),
        ),
      );
    }

    if (MediaQuery.sizeOf(context).width <
        SettingsPageState.compactBreakpoint) {
      return IconButton(
        key: ValueKey<String>('settings_restore_section_${section.name}'),
        tooltip: context.l10n.settingsRestoreSectionTitle,
        onPressed: handlePressed,
        icon: const Icon(Icons.restore_outlined),
      );
    }
    return Tooltip(
      message: context.l10n.settingsRestoreSectionTooltip(sectionTitle),
      child: TextButton.icon(
        key: ValueKey<String>('settings_restore_section_${section.name}'),
        onPressed: handlePressed,
        icon: const Icon(Icons.restore_outlined, size: 18),
        label: Text(context.l10n.settingsRestoreSectionTitle),
      ),
    );
  }

  Future<void> _confirmAndRun(
    BuildContext context, {
    required String title,
    required String content,
    required Future<void> Function() action,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.commonConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await action();
    }
  }

  Widget buildCompactLayout({
    required BuildContext context,
    required SettingsPagePayload payload,
    required SettingsPageController controller,
    required List<SettingsSection> sections,
    required EdgeInsets pagePadding,
  }) {
    return PopScope<Object?>(
      canPop: compactSection == null,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || compactSection == null) {
          return;
        }
        setCompactSection(null);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: compactSection == null
            ? _buildCompactOverview(
                context: context,
                sections: sections,
                pagePadding: pagePadding,
              )
            : _buildCompactDetail(
                context: context,
                payload: payload,
                controller: controller,
                section: compactSection!,
                pagePadding: pagePadding,
              ),
      ),
    );
  }

  Widget _buildCompactOverview({
    required BuildContext context,
    required List<SettingsSection> sections,
    required EdgeInsets pagePadding,
  }) {
    return ListView.separated(
      key: const ValueKey<String>('settings_compact_overview_list'),
      controller: settingsScrollController,
      padding: pagePadding,
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (BuildContext context, int index) {
        final SettingsSection section = sections[index];
        final SettingsSectionMeta meta = settingsSectionMeta(
          section,
          context.l10n,
        );
        return SettingsPageBounds(
          child: SettingsCompactSectionEntry(
            key: ValueKey<String>('settings_compact_entry_${section.name}'),
            icon: meta.icon,
            title: meta.title,
            summary: meta.summary,
            onTap: () => _openCompactSection(section),
          ),
        );
      },
    );
  }

  Widget _buildCompactDetail({
    required BuildContext context,
    required SettingsPagePayload payload,
    required SettingsPageController controller,
    required SettingsSection section,
    required EdgeInsets pagePadding,
  }) {
    final SettingsSectionMeta meta = settingsSectionMeta(section, context.l10n);
    return ListView(
      key: const ValueKey<String>('settings_compact_detail'),
      controller: settingsScrollController,
      padding: pagePadding,
      children: <Widget>[
        SettingsPageBounds(
          child: SettingsCompactSectionHeader(
            title: meta.title,
            summary: meta.summary,
            onBack: _closeCompactSection,
            action: _buildSectionRestoreAction(
              context: context,
              section: section,
              sectionTitle: meta.title,
              controller: controller,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SettingsPageBounds(
          child: buildSection(
            context: context,
            payload: payload,
            section: section,
            controller: controller,
            showHeader: false,
          ),
        ),
      ],
    );
  }

  void _openCompactSection(SettingsSection section) {
    ref.read(settingsPageControllerProvider.notifier).setActiveSection(section);
    setCompactSection(section);
  }

  void _closeCompactSection() {
    if (compactSection == null) {
      return;
    }
    setCompactSection(null);
  }

  bool get _isCompactLayout => mounted && compactLayoutActive;
}
