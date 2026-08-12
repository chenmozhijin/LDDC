import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/accessibility/app_action_semantics.dart';
import '../../../core/i18n/lyrics_ui_host_mapper.dart';
import '../../../shared/ui/components/components.dart';
import '../../../shared/ui/drag_drop/desktop_drop_region_scaffold.dart';
import '../application/open_lyrics_dependencies.dart';
import '../application/open_lyrics_page_controller.dart';
import '../application/open_lyrics_page_state.dart';

class OpenLyricsPage extends ConsumerStatefulWidget {
  const OpenLyricsPage({super.key});

  @override
  ConsumerState<OpenLyricsPage> createState() => _OpenLyricsPageState();
}

class _OpenLyricsPageState extends ConsumerState<OpenLyricsPage> {
  static const double _adaptiveWorkspaceWidth = 720;
  static const double _adaptiveWorkspaceHeight = 640;
  static const double _scrollingPreviewHeight = 320;

  @override
  Widget build(BuildContext context) {
    ref.listen<OpenLyricsPageState>(openLyricsPageControllerProvider, (
      OpenLyricsPageState? previous,
      OpenLyricsPageState next,
    ) {
      final OpenLyricsNotice? notice = next.notice;
      if (notice == null || previous?.notice?.id == notice.id || !mounted) {
        return;
      }
      _showNotice(context, notice);
      Future<void>.microtask(() {
        if (!mounted) {
          return;
        }
        ref
            .read(openLyricsPageControllerProvider.notifier)
            .dismissNotice(notice.id);
      });
    });

    final OpenLyricsPageState state = ref.watch(
      openLyricsPageControllerProvider,
    );
    final OpenLyricsPageController controller = ref.read(
      openLyricsPageControllerProvider.notifier,
    );
    final OpenLyricsDependencies dependencies = ref.watch(
      openLyricsDependenciesProvider,
    );
    final bool isDesktopPlatform = dependencies.capability.multiWindow;

    final Widget page = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 720;
        // 这里收到的是 AppShell 扣除标题栏、导航栏后的真实页面高度。控制卡在
        // 转换后会增加格式、翻译和保存动作；仅凭初始态 400dp 会让预览被压到
        // 不足 100dp 并产生 overflow。高度不足 640dp 时改用统一滚动布局，
        // 控件仍完整保留且可访问，不通过裁剪或放大 CI viewport 掩盖问题。
        final bool fillsAvailableHeight =
            constraints.maxWidth >= _adaptiveWorkspaceWidth &&
            constraints.maxHeight >= _adaptiveWorkspaceHeight;
        final Widget previewCard = _PreviewCard(
          state: state,
          contentHeight: fillsAvailableHeight ? null : _scrollingPreviewHeight,
        );
        final Widget controlCard = _ControlCard(
          state: state,
          controller: controller,
          compact: compact,
        );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: fillsAvailableHeight
              ? Column(
                  key: const ValueKey<String>(
                    'open_lyrics_adaptive_height_layout',
                  ),
                  children: <Widget>[
                    Expanded(child: previewCard),
                    const SizedBox(height: 12),
                    controlCard,
                  ],
                )
              : ListView(
                  key: const ValueKey<String>('open_lyrics_scrolling_layout'),
                  children: <Widget>[
                    previewCard,
                    const SizedBox(height: 12),
                    controlCard,
                  ],
                ),
        );
      },
    );
    final Widget withShortcuts = isDesktopPlatform
        ? DesktopPageInteractionScope(
            shortcuts: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () {
                controller.openLyricsFile();
              },
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (state.currentLyrics == null) {
                  controller.convert();
                }
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                controller.disposeSession();
              },
              const SingleActivator(LogicalKeyboardKey.delete): () {
                controller.disposeSession();
              },
            },
            child: page,
          )
        : page;
    if (!isDesktopPlatform) {
      return withShortcuts;
    }
    final DragDropPort dragDropPort = dependencies.dragDropPort;
    return DesktopDropRegionScaffold(
      dragDropPort: dragDropPort,
      semanticsIdentifier: AppSemanticsIdentifiers.openLyricsDropRegion,
      onDrop: (DragDropParseResult result) => _handleDrop(result, controller),
      unsupportedItemMessage: context.l10n.openLyricsDropUnsupportedItem,
      errorMessageBuilder: (BuildContext context, Object error) =>
          context.l10n.commonDropFailed('$error'),
      child: withShortcuts,
    );
  }

  void _showNotice(BuildContext context, OpenLyricsNotice notice) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final (Color backgroundColor, Color foregroundColor) colors =
        switch (notice.severity) {
          PageNoticeSeverity.success => (
            colorScheme.primaryContainer,
            colorScheme.onPrimaryContainer,
          ),
          PageNoticeSeverity.warning => (
            colorScheme.tertiaryContainer,
            colorScheme.onTertiaryContainer,
          ),
          PageNoticeSeverity.error => (
            colorScheme.errorContainer,
            colorScheme.onErrorContainer,
          ),
          PageNoticeSeverity.info => (
            colorScheme.surfaceContainerHighest,
            colorScheme.onSurface,
          ),
        };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: ValueKey<String>('open_lyrics_notice_${notice.code.name}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.$1,
          content: Semantics(
            identifier: switch (notice.code) {
              OpenLyricsNoticeCode.saveTagSucceeded =>
                AppSemanticsIdentifiers.openLyricsSaveTagSucceeded,
              OpenLyricsNoticeCode.saveTagFailed =>
                AppSemanticsIdentifiers.openLyricsSaveTagFailed,
              OpenLyricsNoticeCode.convertFailed =>
                AppSemanticsIdentifiers.openLyricsConvertFailed,
              _ => null,
            },
            container: true,
            liveRegion: true,
            child: Text(
              _openLyricsNoticeText(context, notice),
              style: TextStyle(color: colors.$2),
            ),
          ),
        ),
      );
  }

  Future<bool> _handleDrop(
    DragDropParseResult result,
    OpenLyricsPageController controller,
  ) async {
    final DragDropItemDescriptor? localFile = result.items.firstWhereOrNull(
      (DragDropItemDescriptor item) => item.kind == DragDropItemKind.localFile,
    );
    if (localFile == null) {
      return false;
    }
    final String extension = localFile.path.split('.').last.toLowerCase();
    if (audioFileExtensionSet.contains(extension)) {
      await controller.openExternalSongFile(localFile.path);
      return true;
    }
    await controller.openExternalLyricsFile(localFile.path);
    return true;
  }
}

String _openLyricsNoticeText(BuildContext context, OpenLyricsNotice notice) {
  final l10n = context.l10n;
  final String? detail = notice.detail;
  return switch (notice.code) {
    OpenLyricsNoticeCode.openFailed => l10n.openLyricsNoticeOpenFailed(
      detail ?? '',
    ),
    OpenLyricsNoticeCode.lyricsFileUnavailable =>
      l10n.openLyricsNoticeLyricsFileUnavailable,
    OpenLyricsNoticeCode.songFileUnavailable =>
      l10n.openLyricsNoticeSongFileUnavailable,
    OpenLyricsNoticeCode.noEmbeddedLyrics =>
      l10n.openLyricsNoticeNoEmbeddedLyrics,
    OpenLyricsNoticeCode.alreadyConverted =>
      l10n.openLyricsNoticeAlreadyConverted,
    OpenLyricsNoticeCode.emptyLyrics => l10n.openLyricsNoticeEmptyLyrics,
    OpenLyricsNoticeCode.convertFailed => l10n.openLyricsNoticeConvertFailed(
      detail ?? '',
    ),
    OpenLyricsNoticeCode.convertFirst => l10n.openLyricsNoticeConvertFirst,
    OpenLyricsNoticeCode.translationCancelled =>
      l10n.commonTranslationCancelled,
    OpenLyricsNoticeCode.translationCompleted =>
      l10n.commonTranslationCompleted,
    OpenLyricsNoticeCode.translationFailed => l10n.commonTranslationFailed(
      detail ?? '',
    ),
    OpenLyricsNoticeCode.noLyricsToSave => l10n.openLyricsNoticeNoLyricsToSave,
    OpenLyricsNoticeCode.saveFileSucceeded =>
      l10n.openLyricsNoticeSaveFileSucceeded(detail ?? ''),
    OpenLyricsNoticeCode.saveFileFailed => l10n.openLyricsNoticeSaveFileFailed(
      detail ?? '',
    ),
    OpenLyricsNoticeCode.openSongFirst => l10n.openLyricsNoticeOpenSongFirst,
    OpenLyricsNoticeCode.audioTagUnsupported =>
      l10n.openLyricsNoticeAudioTagUnsupported,
    OpenLyricsNoticeCode.audioTagRequiresLrc => l10n.commonAudioTagRequiresLrc,
    OpenLyricsNoticeCode.saveTagSucceeded => l10n.commonLyricsSaved,
    OpenLyricsNoticeCode.saveTagFailed => l10n.commonLyricsSaveFailed(
      detail ?? '',
    ),
  };
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.state, required this.contentHeight});

  static const int _semanticsPreviewLimit = 256;

  final OpenLyricsPageState state;
  final double? contentHeight;

  @override
  Widget build(BuildContext context) {
    final String? inputDisplayText = switch (state.inputPath?.trim()) {
      final String path when path.isNotEmpty => path,
      _ when state.inputName.trim().isNotEmpty => state.inputName,
      _ => null,
    };
    final Lyrics? lyrics = state.currentLyrics;
    final String languageSummary = lyrics == null
        ? ''
        : lyricsLanguageSummaryText(
            lyrics: lyrics,
            strings: context.l10n.toLyricsUiStrings(),
          );
    return Card(
      key: const ValueKey<String>('open_lyrics_preview_card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: contentHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.openLyricsPreviewTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  Chip(
                    avatar: const Icon(Icons.subtitles_outlined, size: 18),
                    label: Text(
                      state.currentLyrics == null
                          ? context.l10n.openLyricsPreviewRawText
                          : context.l10n.openLyricsPreviewLanguages(
                              languageSummary.isEmpty ? '-' : languageSummary,
                            ),
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.swap_horiz_outlined, size: 18),
                    label: Text(switch (state.previewState) {
                      OpenLyricsPreviewState.idle =>
                        context.l10n.openLyricsPreviewStateIdle,
                      OpenLyricsPreviewState.rawLoaded =>
                        context.l10n.openLyricsPreviewStateRawLoaded,
                      OpenLyricsPreviewState.converted =>
                        context.l10n.openLyricsPreviewStateConverted,
                    }),
                  ),
                ],
              ),
              if (inputDisplayText != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  inputDisplayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Expanded(
                child: Semantics(
                  identifier: AppSemanticsIdentifiers.openLyricsPreview,
                  container: true,
                  // Flutter 的可滚动歌词正文会在 iOS 远程 AX snapshot 中被视觉截断，
                  // 读屏用户也无法从预览容器直接获知当前内容。把首个非空行作为
                  // 有界 value 暴露在稳定根节点上，既保留完整子语义供逐行阅读，
                  // 也避免把整份歌词复制进 semantics tree 造成额外内存开销。
                  value: _previewSemanticsValue(state.previewText),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: LyricsTranslationProgressOverlay(
                      progress: state.translationProgress,
                      strings: context.l10n.toLyricsUiStrings(),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _buildPreviewContent(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent(BuildContext context) {
    if (state.previewText.trim().isNotEmpty) {
      return LyricsPreviewViewport(text: state.previewText);
    }
    final String message = switch (state.emptyReason) {
      OpenLyricsEmptyReason.noLanguage => context.l10n.searchPreviewNoLanguage,
      OpenLyricsEmptyReason.noContent => context.l10n.searchPreviewNoContent,
      OpenLyricsEmptyReason.noInput ||
      null => context.l10n.openLyricsPreviewEmptyNoInput,
    };
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String? _previewSemanticsValue(String text) {
    for (final String rawLine in LineSplitter.split(text)) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final List<String> boundedGraphemes = line.characters
          .take(_semanticsPreviewLimit + 1)
          .toList(growable: false);
      if (boundedGraphemes.length <= _semanticsPreviewLimit) {
        return line;
      }
      return boundedGraphemes.take(_semanticsPreviewLimit).join();
    }
    return null;
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.state,
    required this.controller,
    required this.compact,
  });

  final OpenLyricsPageState state;
  final OpenLyricsPageController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? openLyricsAction = state.isOpening
        ? null
        : controller.openLyricsFile;
    final VoidCallback? openSongAction = state.isOpening
        ? null
        : controller.openSongFile;
    final VoidCallback? saveFileAction = state.canSaveFile
        ? controller.saveToFile
        : null;
    final VoidCallback? saveTagAction = state.canSaveToTag
        ? controller.saveToTag
        : null;
    final VoidCallback? translateAction = state.canTranslate
        ? controller.toggleTranslation
        : null;
    final String openLyricsLabel = state.isOpening
        ? context.l10n.openLyricsActionOpening
        : context.l10n.openLyricsActionOpenLyricsFile;
    final String translateLabel = translationProgressButtonLabel(
      strings: context.l10n.toLyricsUiStrings(),
      hasTranslation:
          state.currentLyrics != null &&
          LyricsLanguageRegistry.hasGeneratedTranslationLayer(
            state.currentLyrics!,
          ),
      isTranslating: state.isTranslating,
      progress: state.translationProgress,
      idleLabel: context.l10n.openLyricsActionTranslate,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double formatWidth = compact
                ? constraints.maxWidth
                : constraints.maxWidth >= 900
                ? 210
                : 184;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: LyricsLanguageSegments(
                    key: const ValueKey<String>(
                      'open_lyrics_language_segments',
                    ),
                    compact: compact,
                    strings: context.l10n.toLyricsUiStrings(),
                    selected: state.selectedLangs.toSet(),
                    onSelectionChanged: controller.updateSelectedLangs,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: formatWidth,
                      child: LyricsFormatDropdown(
                        key: const ValueKey<String>(
                          'open_lyrics_format_dropdown',
                        ),
                        value: state.lyricsFormat,
                        strings: context.l10n.toLyricsUiStrings(),
                        compact: true,
                        labelText: context.l10n.commonFormat,
                        onChanged: controller.updateLyricsFormat,
                      ),
                    ),
                    LyricsOffsetStepper(
                      key: const ValueKey<String>('open_lyrics_offset_stepper'),
                      offsetMs: state.offsetMs,
                      strings: context.l10n.toLyricsUiStrings(),
                      compact: true,
                      labelText: context.l10n.commonOffset,
                      onChanged: controller.updateOffsetMs,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OverflowBar(
                  key: const ValueKey<String>('open_lyrics_action_bar'),
                  spacing: 6,
                  overflowSpacing: 6,
                  alignment: MainAxisAlignment.start,
                  overflowAlignment: OverflowBarAlignment.start,
                  children: <Widget>[
                    AppActionSemantics(
                      identifier: AppSemanticsIdentifiers.openLyricsFile,
                      label: openLyricsLabel,
                      onTap: openLyricsAction,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'open_lyrics_open_lyrics_button',
                        ),
                        onPressed: openLyricsAction,
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text(openLyricsLabel),
                      ),
                    ),
                    AppActionSemantics(
                      identifier: AppSemanticsIdentifiers.openSongFile,
                      label: context.l10n.openLyricsActionOpenSongFile,
                      onTap: openSongAction,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'open_lyrics_open_song_button',
                        ),
                        onPressed: openSongAction,
                        icon: const Icon(Icons.audiotrack_outlined),
                        label: Text(context.l10n.openLyricsActionOpenSongFile),
                      ),
                    ),
                    AppActionSemantics(
                      identifier: AppSemanticsIdentifiers.convertOpenLyrics,
                      label: context.l10n.openLyricsActionConvertFormat,
                      onTap: state.canConvert ? controller.convert : null,
                      child: FilledButton(
                        key: const ValueKey<String>(
                          'open_lyrics_convert_button',
                        ),
                        onPressed: state.canConvert ? controller.convert : null,
                        child: Text(context.l10n.openLyricsActionConvertFormat),
                      ),
                    ),
                    AppActionSemantics(
                      identifier: AppSemanticsIdentifiers.saveLyricsFile,
                      label: context.l10n.openLyricsActionSaveLyrics,
                      onTap: saveFileAction,
                      child: FilledButton(
                        key: const ValueKey<String>('open_lyrics_save_button'),
                        onPressed: saveFileAction,
                        child: Text(context.l10n.openLyricsActionSaveLyrics),
                      ),
                    ),
                    AppActionSemantics(
                      identifier: AppSemanticsIdentifiers.saveLyricsTag,
                      label: context.l10n.openLyricsActionSaveToTag,
                      onTap: saveTagAction,
                      child: OutlinedButton(
                        key: const ValueKey<String>(
                          'open_lyrics_save_to_tag_button',
                        ),
                        onPressed: saveTagAction,
                        child: Text(context.l10n.openLyricsActionSaveToTag),
                      ),
                    ),
                    AppActionSemantics(
                      identifier: AppSemanticsIdentifiers.translateLyrics,
                      label: translateLabel,
                      onTap: translateAction,
                      child: FilledButton.tonal(
                        key: const ValueKey<String>(
                          'open_lyrics_translate_button',
                        ),
                        onPressed: translateAction,
                        child: Text(translateLabel),
                      ),
                    ),
                  ],
                ),
                if (state.currentLyrics != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    LyricsFormatCapabilities.isLrcFamily(state.lyricsFormat)
                        ? context.l10n.openLyricsExportFormatCanWriteTag(
                            context.l10n.lyricsFormatLabel(state.lyricsFormat),
                          )
                        : context.l10n.openLyricsExportFormatFileOnly(
                            context.l10n.lyricsFormatLabel(state.lyricsFormat),
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
