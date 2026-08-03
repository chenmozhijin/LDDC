import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide AsyncError, AsyncLoading;
import 'package:flutter/services.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/accessibility/app_action_semantics.dart';
import '../../../shared/ui/components/components.dart';
import '../../../shared/ui/drag_drop/desktop_drop_region_scaffold.dart';
import '../application/search_workflow_providers.dart';
import '../application/search_ui_host_mapper.dart';

/// 搜索页面：桌面端双栏集成预览控制，移动端结果主视图 + 底部预览抽屉。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _savePathController = TextEditingController();
  final SearchResultInteractionController _resultInteraction =
      SearchResultInteractionController();
  bool? _lastExpandedLayout;
  bool _isPreviewSheetVisible = false;
  bool _isClosingPreviewSheet = false;
  late final SearchWorkflowController _controller;
  int? _lastNoticeId;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(searchWorkflowControllerInstanceProvider);
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _keywordController.dispose();
    _savePathController.dispose();
    _resultInteraction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SearchWorkflowController controller = _controller;
    final SearchUiStrings strings = context.l10n.toSearchUiStrings();
    final SearchWorkflowDependencies dependencies = ref.watch(
      searchWorkflowDependenciesProvider,
    );
    final SearchWorkflowCapabilities appCapability = dependencies.capabilities;
    final bool isDesktopPlatform = appCapability.multiWindow;
    final bool showTagSave = appCapability.audioTagWrite;

    final Widget page = SearchWorkspace(
      controller: controller,
      strings: strings,
      keywordController: _keywordController,
      savePathController: _savePathController,
      selectedRowIndexListenable: _resultInteraction.selectedRowIndexListenable,
      isDesktopPlatform: isDesktopPlatform,
      canUseAndroidSafListSave: appCapability.androidSafTreeAccess,
      showTagSave: showTagSave,
      onRowsChanged: _clearSelectionIfOutOfRange,
      onDesktopRowTap: _handleDesktopRowTap,
      onMobileRowTap: _handleMobileRowTap,
      onReturnPath: () {
        controller.returnPath();
        _clearSelectedRowIndex();
      },
      onOpenPreviewSheet: _showMobilePreviewSheet,
      onExpandedLayoutChanged: _handleExpandedLayoutChange,
    );
    final Widget withInteractions = isDesktopPlatform
        ? DesktopPageInteractionScope(
            shortcuts: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () {
                controller.openSongFileForSearch();
              },
              const SingleActivator(LogicalKeyboardKey.enter): () {
                final int? selected = _resultInteraction.selectedRowIndex;
                if (selected != null) {
                  controller.openResult(selected);
                }
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (_isPreviewSheetVisible) {
                  _schedulePreviewSheetClose();
                }
                _clearSelectedRowIndex();
              },
              const SingleActivator(LogicalKeyboardKey.delete): () {
                _clearSelectedRowIndex();
              },
            },
            child: page,
          )
        : page;
    if (!isDesktopPlatform) {
      return withInteractions;
    }
    final DragDropPort dragDropPort = dependencies.dragDropPort;
    return DesktopDropRegionScaffold(
      dragDropPort: dragDropPort,
      semanticsIdentifier: AppSemanticsIdentifiers.searchDropRegion,
      onDrop: (DragDropParseResult result) => _handleDrop(result, controller),
      unsupportedItemMessage: context.l10n.searchDropUnsupportedItem,
      errorMessageBuilder: (BuildContext context, Object error) =>
          context.l10n.commonDropFailed('$error'),
      child: withInteractions,
    );
  }

  void _clearSelectedRowIndex() {
    _resultInteraction.clearSelection();
  }

  void _clearSelectionIfOutOfRange(int rowCount) {
    _resultInteraction.clearSelectionIfOutOfRange(
      rowCount,
      isMounted: () => mounted,
    );
  }

  Future<void> _handleDesktopRowTap(int rowIndex) async {
    await _resultInteraction.handleRowTap(
      rowIndex,
      openRow: _controller.openResult,
    );
  }

  Future<void> _handleMobileRowTap(SourceAware row, int rowIndex) async {
    await _resultInteraction.handleRowTap(
      rowIndex,
      openRow: _controller.openResult,
    );
    if (row is SongListInfo) {
      return;
    }
    final SearchWorkflowState latest = _controller.state;
    if (latest.currentLyrics != null ||
        latest.previewPhase == SearchPreviewPhase.loading) {
      await _showMobilePreviewSheet();
    }
  }

  void _handleExpandedLayoutChange(bool isExpanded) {
    final bool? previous = _lastExpandedLayout;
    _lastExpandedLayout = isExpanded;
    if (previous == false && isExpanded) {
      _schedulePreviewSheetClose();
    }
  }

  void _schedulePreviewSheetClose() {
    if (!_isPreviewSheetVisible || _isClosingPreviewSheet || !mounted) {
      return;
    }
    _isClosingPreviewSheet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isClosingPreviewSheet = false;
        return;
      }
      try {
        final NavigatorState navigator = Navigator.of(context);
        if (_isPreviewSheetVisible && navigator.canPop()) {
          await navigator.maybePop();
        }
      } finally {
        _isClosingPreviewSheet = false;
      }
    });
  }

  Future<void> _showMobilePreviewSheet() async {
    if (_isPreviewSheetVisible || !mounted) {
      return;
    }
    final SearchWorkflowState state = _controller.state;
    if (state.currentLyrics == null &&
        state.previewPhase != SearchPreviewPhase.loading) {
      return;
    }
    _isPreviewSheetVisible = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext context) {
          final double maxHeight = MediaQuery.sizeOf(context).height * 0.88;
          return SafeArea(
            child: SizedBox(
              height: maxHeight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (BuildContext context, Widget? _) {
                    final SearchWorkflowState state = _controller.state;
                    final SearchWorkflowCapabilities appCapability = ref
                        .read(searchWorkflowDependenciesProvider)
                        .capabilities;
                    return SearchPreviewPane(
                      state: state,
                      controller: _controller,
                      strings: context.l10n.toSearchUiStrings(),
                      savePathController: _savePathController,
                      isDesktopPlatform: appCapability.multiWindow,
                      showTagSave: appCapability.audioTagWrite,
                      inSheet: true,
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _isPreviewSheetVisible = false;
      _isClosingPreviewSheet = false;
    }
  }

  void _handleControllerChanged() {
    final SearchNotice? notice = _controller.state.notice;
    if (!mounted || notice == null || _lastNoticeId == notice.id) {
      return;
    }
    _lastNoticeId = notice.id;
    // 控制器通知只由用户命令或异步任务完成回调产生，不会在组件 build 中发出。
    // 立即交给 ScaffoldMessenger 可保留原有的即时反馈语义，也避免通知对象为了等待
    // 下一帧而延长生命周期；dismiss 会触发一次轻量状态通知，但不会再次展示。
    _showNotice(context, notice);
    _controller.dismissNotice(notice.id);
  }

  void _showNotice(BuildContext context, SearchNotice notice) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final SearchUiStrings strings = context.l10n.toSearchUiStrings();
    final Color backgroundColor;
    final Color foregroundColor;
    switch (notice.severity) {
      case PageNoticeSeverity.success:
        backgroundColor = colorScheme.primaryContainer;
        foregroundColor = colorScheme.onPrimaryContainer;
      case PageNoticeSeverity.warning:
        backgroundColor = colorScheme.tertiaryContainer;
        foregroundColor = colorScheme.onTertiaryContainer;
      case PageNoticeSeverity.error:
        backgroundColor = colorScheme.errorContainer;
        foregroundColor = colorScheme.onErrorContainer;
      case PageNoticeSeverity.info:
        backgroundColor = colorScheme.surfaceContainerHighest;
        foregroundColor = colorScheme.onSurface;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: ValueKey<String>('search_notice_${notice.code.name}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
          content: Text(
            searchNoticeText(strings, notice),
            style: TextStyle(color: foregroundColor),
          ),
          action: isSearchSourceFailureNotice(notice.code)
              ? SnackBarAction(
                  label: strings.text(SearchUiTextKey.viewDetails),
                  textColor: foregroundColor,
                  onPressed: () => showSearchSourceFailuresDialog(
                    context: context,
                    controller: _controller,
                    strings: strings,
                  ),
                )
              : null,
        ),
      );
  }

  Future<bool> _handleDrop(
    DragDropParseResult result,
    SearchWorkflowController controller,
  ) async {
    final DragDropSongDescriptor? song = result.items
        .firstWhereOrNull(
          (DragDropItemDescriptor item) =>
              item.kind == DragDropItemKind.songInfoLike,
        )
        ?.song;
    if (song != null) {
      await controller.openDroppedSongFile(
        song.path,
        track: song.track,
        index: song.index,
      );
      return true;
    }
    final DragDropItemDescriptor? audioFile = result.items.firstWhereOrNull(
      (DragDropItemDescriptor item) =>
          item.kind == DragDropItemKind.localFile &&
          audioFileExtensionSet.contains(
            item.path.split('.').last.toLowerCase(),
          ),
    );
    if (audioFile == null) {
      return false;
    }
    await controller.openDroppedSongFile(audioFile.path);
    return true;
  }
}
