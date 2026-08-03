import 'package:flutter/material.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../../ui/lyrics_language_summary_text.dart';
import '../../ui/search_ui_strings.dart';
import '../../ui/widgets/lyrics_preview_controls.dart';
import '../../ui/widgets/lyrics_preview_viewport.dart';
import '../../ui/widgets/lyrics_translation_progress_overlay.dart';
import '../../ui/widgets/translation_progress_ui.dart';
import '../search_workflow_controller.dart';
import '../search_workflow_state.dart';

/// 搜索预览区：负责歌词预览、预览参数与保存/翻译动作。
class SearchPreviewPane extends StatelessWidget {
  const SearchPreviewPane({
    super.key,
    required this.state,
    required this.controller,
    required this.strings,
    required this.savePathController,
    required this.isDesktopPlatform,
    required this.showTagSave,
    this.showDirectorySave,
    this.showFileSave,
    this.inSheet = false,
  });

  static const double desktopPreviewControlWideBreakpoint = 900;
  static const double desktopPreviewControlMediumBreakpoint = 560;

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final TextEditingController savePathController;
  final bool isDesktopPlatform;
  final bool showTagSave;
  final bool? showDirectorySave;
  final bool? showFileSave;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final bool effectiveShowDirectorySave =
        showDirectorySave ?? isDesktopPlatform;
    final bool effectiveShowFileSave = showFileSave ?? !isDesktopPlatform;
    final bool showSavePath =
        isDesktopPlatform &&
        (effectiveShowDirectorySave || effectiveShowFileSave);
    final Widget preview = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LyricsTranslationProgressOverlay(
        progress: state.translationProgress,
        strings: strings.lyrics,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: _SearchPreviewContent(state: state, strings: strings),
        ),
      ),
    );
    final Widget controls = _SearchPreviewControlBlock(
      state: state,
      controller: controller,
      strings: strings,
      savePathController: savePathController,
      showSavePath: showSavePath,
      showDirectorySave: effectiveShowDirectorySave,
      showFileSave: effectiveShowFileSave,
      showTagSave: showTagSave,
    );
    if (inSheet) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double maximumControlHeight = (constraints.maxHeight * 0.42)
              .clamp(96.0, 180.0);
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  strings.text(SearchUiTextKey.previewTitle),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _SearchPreviewMetadata(state: state, strings: strings),
                const SizedBox(height: 8),
                Expanded(child: preview),
                const SizedBox(height: 10),
                // 小窗口的语言、格式和偏移控件可能高于剩余空间。只让控制区
                // 自身滚动，歌词预览仍保持稳定视口，不会再次挤压到零高度。
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maximumControlHeight),
                  child: SingleChildScrollView(child: controls),
                ),
              ],
            ),
          );
        },
      );
    }
    final Widget body = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            strings.text(SearchUiTextKey.previewTitle),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _SearchPreviewMetadata(state: state, strings: strings),
          const SizedBox(height: 8),
          Expanded(child: preview),
          const SizedBox(height: 10),
          controls,
        ],
      ),
    );
    return Card(child: body);
  }
}

class _SearchPreviewContent extends StatelessWidget {
  const _SearchPreviewContent({required this.state, required this.strings});

  final SearchWorkflowState state;
  final SearchUiStrings strings;

  @override
  Widget build(BuildContext context) {
    if (state.previewPhase == SearchPreviewPhase.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 12),
            Text(strings.text(SearchUiTextKey.previewLoading)),
          ],
        ),
      );
    }
    if (state.previewText.trim().isNotEmpty) {
      return LyricsPreviewViewport(text: state.previewText);
    }
    return Center(
      child: Text(
        _previewPlaceholder(strings, state),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SearchPreviewMetadata extends StatelessWidget {
  const _SearchPreviewMetadata({required this.state, required this.strings});

  final SearchWorkflowState state;
  final SearchUiStrings strings;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Lyrics? lyrics = state.currentLyrics;
    final String languageSummary = lyrics == null
        ? ''
        : lyricsLanguageSummaryText(lyrics: lyrics, strings: strings.lyrics);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        Chip(
          avatar: Icon(
            Icons.subtitles_outlined,
            size: 18,
            color: colorScheme.primary,
          ),
          label: Text(
            '${strings.text(SearchUiTextKey.previewLangsLabel)} · ${languageSummary.isEmpty ? '-' : languageSummary}',
          ),
        ),
        Chip(
          avatar: Icon(
            Icons.tag_outlined,
            size: 18,
            color: colorScheme.primary,
          ),
          label: Text(
            '${strings.text(SearchUiTextKey.previewSongIdLabel)} · ${state.songIdText.isEmpty ? '-' : state.songIdText}',
          ),
        ),
      ],
    );
  }
}

class _SearchPreviewControlBlock extends StatelessWidget {
  const _SearchPreviewControlBlock({
    required this.state,
    required this.controller,
    required this.strings,
    required this.savePathController,
    required this.showSavePath,
    required this.showDirectorySave,
    required this.showFileSave,
    required this.showTagSave,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final TextEditingController savePathController;
  final bool showSavePath;
  final bool showDirectorySave;
  final bool showFileSave;
  final bool showTagSave;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: showSavePath
          ? _DesktopPreviewControlLayout(
              state: state,
              controller: controller,
              strings: strings,
              savePathController: savePathController,
              showDirectorySave: showDirectorySave,
              showFileSave: showFileSave,
              showTagSave: showTagSave,
            )
          : _MobilePreviewControlLayout(
              state: state,
              controller: controller,
              strings: strings,
              showDirectorySave: showDirectorySave,
              showFileSave: showFileSave,
              showTagSave: showTagSave,
            ),
    );
  }
}

class _DesktopPreviewControlLayout extends StatelessWidget {
  const _DesktopPreviewControlLayout({
    required this.state,
    required this.controller,
    required this.strings,
    required this.savePathController,
    required this.showDirectorySave,
    required this.showFileSave,
    required this.showTagSave,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final TextEditingController savePathController;
  final bool showDirectorySave;
  final bool showFileSave;
  final bool showTagSave;

  @override
  Widget build(BuildContext context) {
    final bool controlsEnabled = !state.isSavingPreview && !state.isBatchSaving;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget savePathField = _SavePathField(
          controller: controller,
          strings: strings,
          savePathController: savePathController,
          enabled: controlsEnabled,
        );
        final Widget selectPathButton = _SelectSavePathButton(
          controller: controller,
          strings: strings,
          enabled: controlsEnabled,
        );
        final Widget languageSegments = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _LanguageSegments(
            state: state,
            controller: controller,
            strings: strings,
            compact: true,
          ),
        );
        final Widget actions = _BottomActions(
          state: state,
          controller: controller,
          strings: strings,
          showDirectorySave: showDirectorySave,
          showFileSave: showFileSave,
          showTagSave: showTagSave,
          compact: true,
        );
        final double maxWidth = constraints.maxWidth;
        final double formatWidth =
            maxWidth >= SearchPreviewPane.desktopPreviewControlWideBreakpoint
            ? 180
            : maxWidth >=
                  SearchPreviewPane.desktopPreviewControlMediumBreakpoint
            ? 160
            : 154;

        if (maxWidth >= SearchPreviewPane.desktopPreviewControlWideBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: savePathField),
                  const SizedBox(width: 8),
                  selectPathButton,
                  const SizedBox(width: 8),
                  SizedBox(
                    width: formatWidth,
                    child: _FormatField(
                      state: state,
                      controller: controller,
                      strings: strings,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _OffsetControl(
                    state: state,
                    controller: controller,
                    strings: strings,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: languageSegments,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        if (maxWidth >=
            SearchPreviewPane.desktopPreviewControlMediumBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: savePathField),
                  const SizedBox(width: 8),
                  selectPathButton,
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: languageSegments,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: formatWidth,
                    child: _FormatField(
                      state: state,
                      controller: controller,
                      strings: strings,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _OffsetControl(
                    state: state,
                    controller: controller,
                    strings: strings,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              actions,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: savePathField),
                const SizedBox(width: 6),
                selectPathButton,
              ],
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: languageSegments),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: formatWidth,
                  child: _FormatField(
                    state: state,
                    controller: controller,
                    strings: strings,
                    compact: true,
                  ),
                ),
                _OffsetControl(
                  state: state,
                  controller: controller,
                  strings: strings,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            actions,
          ],
        );
      },
    );
  }
}

class _MobilePreviewControlLayout extends StatelessWidget {
  const _MobilePreviewControlLayout({
    required this.state,
    required this.controller,
    required this.strings,
    required this.showDirectorySave,
    required this.showFileSave,
    required this.showTagSave,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final bool showDirectorySave;
  final bool showFileSave;
  final bool showTagSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth >= 860) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _LanguageSegments(
                          state: state,
                          controller: controller,
                          strings: strings,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 188,
                    child: _FormatField(
                      state: state,
                      controller: controller,
                      strings: strings,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _OffsetControl(
                    state: state,
                    controller: controller,
                    strings: strings,
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _LanguageSegments(
                    state: state,
                    controller: controller,
                    strings: strings,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 196,
                      child: _FormatField(
                        state: state,
                        controller: controller,
                        strings: strings,
                      ),
                    ),
                    _OffsetControl(
                      state: state,
                      controller: controller,
                      strings: strings,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        _BottomActions(
          state: state,
          controller: controller,
          strings: strings,
          showDirectorySave: showDirectorySave,
          showFileSave: showFileSave,
          showTagSave: showTagSave,
        ),
      ],
    );
  }
}

class _SavePathField extends StatelessWidget {
  const _SavePathField({
    required this.controller,
    required this.strings,
    required this.savePathController,
    required this.enabled,
  });

  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final TextEditingController savePathController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey<String>('search_preview_save_path_field'),
      controller: savePathController,
      enabled: enabled,
      onChanged: controller.updateSaveDirectoryPath,
      decoration: InputDecoration(
        labelText: strings.text(SearchUiTextKey.savePathLabel),
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

class _SelectSavePathButton extends StatelessWidget {
  const _SelectSavePathButton({
    required this.controller,
    required this.strings,
    required this.enabled,
  });

  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const ValueKey<String>('search_preview_select_path_button'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onPressed: enabled ? controller.selectSaveDirectory : null,
      child: Text(strings.text(SearchUiTextKey.selectSavePath)),
    );
  }
}

class _FormatField extends StatelessWidget {
  const _FormatField({
    required this.state,
    required this.controller,
    required this.strings,
    this.compact = false,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LyricsFormatDropdown(
      key: const ValueKey<String>('search_preview_format_field'),
      value: state.lyricsFormat,
      strings: strings.lyrics,
      compact: compact,
      onChanged: (LyricsFormat value) {
        controller.updatePreviewOptions(lyricsFormat: value);
      },
    );
  }
}

class _OffsetControl extends StatelessWidget {
  const _OffsetControl({
    required this.state,
    required this.controller,
    required this.strings,
    this.compact = false,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LyricsOffsetStepper(
      key: const ValueKey<String>('search_preview_offset_control'),
      offsetMs: state.offsetMs,
      strings: strings.lyrics,
      compact: compact,
      onChanged: (int nextOffset) {
        controller.updatePreviewOptions(offsetMs: nextOffset);
      },
    );
  }
}

class _LanguageSegments extends StatelessWidget {
  const _LanguageSegments({
    required this.state,
    required this.controller,
    required this.strings,
    this.compact = false,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LyricsLanguageSegments(
      key: const ValueKey<String>('search_preview_language_segments'),
      compact: compact,
      strings: strings.lyrics,
      selected: state.selectedLangs.toSet(),
      onSelectionChanged: controller.updateSelectedLangs,
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.state,
    required this.controller,
    required this.strings,
    required this.showDirectorySave,
    required this.showFileSave,
    required this.showTagSave,
    this.compact = false,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final bool showDirectorySave;
  final bool showFileSave;
  final bool showTagSave;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool canSave = controller.canSavePreview(state);
    final bool isSaving = state.isSavingPreview;
    final bool canTranslate =
        state.currentLyrics != null &&
        state.previewPhase != SearchPreviewPhase.loading &&
        !isSaving &&
        !state.isTranslating;
    final ButtonStyle filledStyle = FilledButton.styleFrom(
      visualDensity: compact ? VisualDensity.compact : null,
      tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 10 : 12,
      ),
    );
    final ButtonStyle outlinedStyle = OutlinedButton.styleFrom(
      visualDensity: compact ? VisualDensity.compact : null,
      tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 10 : 12,
      ),
    );
    final ButtonStyle tonalStyle = FilledButton.styleFrom(
      visualDensity: compact ? VisualDensity.compact : null,
      tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 10 : 12,
      ),
    );
    return OverflowBar(
      key: const ValueKey<String>('search_preview_action_bar'),
      spacing: compact ? 6 : 8,
      overflowSpacing: compact ? 6 : 8,
      alignment: MainAxisAlignment.start,
      overflowAlignment: OverflowBarAlignment.start,
      children: <Widget>[
        if (showDirectorySave)
          FilledButton(
            key: const ValueKey<String>('search_preview_save_directory_button'),
            style: filledStyle,
            onPressed: canSave ? controller.savePreviewToDirectory : null,
            child: Text(
              isSaving &&
                      state.lastFileAction ==
                          SearchPreviewFileAction.saveDirectory
                  ? strings.text(SearchUiTextKey.saving)
                  : strings.text(SearchUiTextKey.savePreviewToDirectory),
            ),
          )
        else if (showFileSave)
          FilledButton(
            key: const ValueKey<String>('search_preview_save_file_button'),
            style: filledStyle,
            onPressed: canSave ? controller.savePreviewToFile : null,
            child: Text(
              isSaving &&
                      state.lastFileAction == SearchPreviewFileAction.saveFile
                  ? strings.text(SearchUiTextKey.saving)
                  : strings.text(SearchUiTextKey.savePreviewToFile),
            ),
          ),
        if (showTagSave)
          OutlinedButton(
            key: const ValueKey<String>('search_preview_save_tag_button'),
            style: outlinedStyle,
            onPressed: canSave ? controller.savePreviewToTag : null,
            child: Text(
              isSaving &&
                      state.lastFileAction == SearchPreviewFileAction.saveTag
                  ? strings.text(SearchUiTextKey.saving)
                  : strings.text(SearchUiTextKey.savePreviewToTag),
            ),
          ),
        FilledButton.tonal(
          key: const ValueKey<String>('search_preview_translate_button'),
          style: tonalStyle,
          onPressed: canTranslate ? controller.toggleTranslation : null,
          child: Text(
            translationProgressButtonLabel(
              strings: strings.lyrics,
              hasTranslation:
                  state.currentLyrics != null &&
                  LyricsLanguageRegistry.hasGeneratedTranslationLayer(
                    state.currentLyrics!,
                  ),
              isTranslating: state.isTranslating,
              progress: state.translationProgress,
              idleLabel: strings.text(SearchUiTextKey.translateLyrics),
            ),
          ),
        ),
      ],
    );
  }
}

String _previewPlaceholder(SearchUiStrings strings, SearchWorkflowState state) {
  return switch (state.previewEmptyReason) {
    SearchPreviewEmptyReason.noLanguage => strings.text(
      SearchUiTextKey.previewNoLanguage,
    ),
    SearchPreviewEmptyReason.noContent => strings.text(
      SearchUiTextKey.previewNoContent,
    ),
    SearchPreviewEmptyReason.noSelection ||
    null => strings.text(SearchUiTextKey.previewPlaceholder),
  };
}
