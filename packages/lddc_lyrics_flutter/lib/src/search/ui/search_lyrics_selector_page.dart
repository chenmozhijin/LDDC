import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../../ui/search_ui_strings.dart';
import '../search_lyrics_selector_models.dart';
import '../search_result_interaction_controller.dart';
import '../search_workflow_controller.dart';
import '../search_workflow_state.dart';
import 'search_notice_text.dart';
import 'search_preview_pane.dart';
import 'search_source_failure_dialog.dart';
import 'search_workspace.dart';

/// 搜索歌词选择器页面。
///
/// 这个页面只表达“搜索或打开一份歌词，并把结果交给调用方”的业务语义。
/// 桌面多窗口实例、payload 编解码和宿主回传都由外层组合适配层处理，
/// 避免搜索功能层反向依赖平台窗口协议。
class SearchLyricsSelectorPage extends StatefulWidget {
  const SearchLyricsSelectorPage({
    required this.controller,
    required this.strings,
    required this.initialState,
    required this.dependencies,
    required this.onLyricsSelected,
    super.key,
  });

  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final SearchLyricsSelectorInitialState? initialState;
  final SearchLyricsSelectorDependencies dependencies;
  final Future<bool> Function(SearchLyricsSelectorResult result)
  onLyricsSelected;

  @override
  State<SearchLyricsSelectorPage> createState() =>
      _SearchLyricsSelectorPageState();
}

class _SearchLyricsSelectorPageState extends State<SearchLyricsSelectorPage> {
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _savePathController = TextEditingController();
  final SearchResultInteractionController _resultInteraction =
      SearchResultInteractionController();
  String? _lastSearchedKeyword;
  String? _selectedLyricsPath;
  late SearchWorkflowController _controller;
  int? _lastNoticeId;
  int _localOpenGeneration = 0;
  bool _isOpeningLocalLyrics = false;
  bool _isSubmittingLyrics = false;
  bool _isExpandedLayout = true;
  bool _isPreviewSheetVisible = false;
  bool _isClosingPreviewSheet = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyInitialState(widget.initialState);
    });
  }

  @override
  void didUpdateWidget(covariant SearchLyricsSelectorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _controller = widget.controller;
      _controller.addListener(_handleControllerChanged);
    }
    if (_shouldApplyInitialState(oldWidget.initialState, widget.initialState)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyInitialState(widget.initialState);
      });
    }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.strings.text(SearchUiTextKey.selectorTitle)),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) {
          return _buildBottomActions(context, controller.state);
        },
      ),
      body: SearchWorkspace(
        controller: controller,
        strings: widget.strings,
        keywordController: _keywordController,
        savePathController: _savePathController,
        selectedRowIndexListenable:
            _resultInteraction.selectedRowIndexListenable,
        isDesktopPlatform: true,
        canUseAndroidSafListSave: false,
        showTagSave: false,
        compactBehavior: SearchWorkspaceCompactBehavior.resultOnly,
        allowListSaveAction: false,
        showBatchProgress: false,
        showDirectorySave: false,
        showFileSave: false,
        description: widget.strings.text(SearchUiTextKey.selectorDescription),
        hideDescriptionInCompact: true,
        onRowsChanged: _clearSelectionIfOutOfRange,
        onDesktopRowTap: _handleDesktopRowTap,
        onMobileRowTap: _handleMobileRowTap,
        onReturnPath: () {
          controller.returnPath();
          _clearSelectedRowIndex();
        },
        onOpenPreviewSheet: _showPreviewSheet,
        onExpandedLayoutChanged: _handleExpandedLayoutChanged,
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context, SearchWorkflowState state) {
    final bool previewLoading =
        state.previewPhase == SearchPreviewPhase.loading;
    final bool canOpenLocal =
        !_isOpeningLocalLyrics && !_isSubmittingLyrics && !previewLoading;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runAlignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: <Widget>[
            OutlinedButton.icon(
              key: const ValueKey<String>('selector_open_local_button'),
              onPressed: canOpenLocal ? _openLocalLyrics : null,
              icon: _isOpeningLocalLyrics
                  ? _progressIcon()
                  : const Icon(Icons.folder_open_outlined),
              label: Text(
                widget.strings.text(SearchUiTextKey.selectorOpenLocal),
              ),
            ),
            _buildSelectButton(state),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectButton(
    SearchWorkflowState state, {
    bool fillWidth = false,
    Key buttonKey = const ValueKey<String>('selector_select_lyrics_button'),
  }) {
    final bool canSubmit =
        state.currentLyrics != null &&
        state.previewPhase != SearchPreviewPhase.loading &&
        !_isOpeningLocalLyrics &&
        !_isSubmittingLyrics;
    final Widget button = FilledButton.icon(
      key: buttonKey,
      onPressed: canSubmit ? _selectCurrentLyrics : null,
      icon: _isSubmittingLyrics
          ? _progressIcon()
          : const Icon(Icons.check_circle_outline),
      label: Text(widget.strings.text(SearchUiTextKey.selectorSelect)),
    );
    return fillWidth ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _progressIcon() {
    return const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Future<void> _applyInitialState(
    SearchLyricsSelectorInitialState? initialState,
  ) async {
    if (!mounted || initialState == null) {
      return;
    }
    final String? nextKeyword = _normalizeKeyword(initialState.keyword);
    final bool keywordChanged =
        nextKeyword != null && nextKeyword != _lastSearchedKeyword;
    if (keywordChanged) {
      _lastSearchedKeyword = nextKeyword;
    }
    _localOpenGeneration += 1;
    _selectedLyricsPath = null;
    _resultInteraction.reset();
    await _controller.applyExternalPreset(
      keyword: initialState.keyword,
      lyrics: initialState.lyrics,
      selectedLangs: initialState.langs,
      offsetMs: initialState.offsetMs,
      selectedSource: keywordChanged ? Source.multi : null,
      selectedSearchType: keywordChanged ? SearchType.song : null,
      triggerSearch: keywordChanged,
      clearLyricsWhenNull: initialState.lyrics == null,
    );
  }

  Future<void> _handleDesktopRowTap(int rowIndex) async {
    await _resultInteraction.handleRowTap(
      rowIndex,
      openRow: _openNetworkResult,
    );
  }

  Future<void> _handleMobileRowTap(SourceAware row, int rowIndex) async {
    _resultInteraction.selectRow(rowIndex);
    final Future<void> openFuture = _openNetworkResult(rowIndex);
    if (row is SongListInfo) {
      await openFuture;
      return;
    }
    // openResult 在首次异步等待前同步发布 loading，先启动它再打开弹层，
    // 用户可以立即看到加载反馈，而不是等待网络结束后才出现预览。
    final Future<void> sheetFuture = _showPreviewSheet();
    await openFuture;
    if (!mounted) {
      return;
    }
    final SearchWorkflowState state = _controller.state;
    if (state.currentLyrics == null &&
        state.previewPhase != SearchPreviewPhase.loading) {
      // 歌曲可能展开为多条歌词候选；此时关闭空弹层，把候选列表交还用户。
      _schedulePreviewSheetClose();
    }
    await sheetFuture;
  }

  Future<void> _openLocalLyrics() async {
    if (_isOpeningLocalLyrics || _isSubmittingLyrics) {
      return;
    }
    final int generation = ++_localOpenGeneration;
    bool shouldOpenPreview = false;
    setState(() {
      _isOpeningLocalLyrics = true;
    });
    try {
      // 文件对话框本身也可能因子 engine 未注册平台插件而失败，因此必须
      // 与后续文件解析放在同一个错误边界内，不能让 MissingPluginException
      // 越过页面直接进入 Flutter 全局错误处理。
      final String? path = await widget.dependencies.pickLocalLyricsPath();
      if (!mounted ||
          generation != _localOpenGeneration ||
          path == null ||
          path.trim().isEmpty) {
        return;
      }
      final Lyrics lyrics = await widget.dependencies.loadLocalLyrics(path);
      if (!mounted || generation != _localOpenGeneration) {
        return;
      }
      await _controller.applyExternalPreset(
        lyrics: lyrics,
        clearLyricsWhenNull: false,
      );
      if (!mounted || generation != _localOpenGeneration) {
        return;
      }
      _selectedLyricsPath = path;
      shouldOpenPreview = !_isExpandedLayout;
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(
        widget.strings.text(
          SearchUiTextKey.selectorOpenLocalFailed,
          arguments: SearchUiTextArguments(detail: '$error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningLocalLyrics = false;
        });
      }
    }
    if (shouldOpenPreview && mounted) {
      await _showPreviewSheet();
    }
  }

  Future<void> _selectCurrentLyrics() async {
    if (_isSubmittingLyrics || _isOpeningLocalLyrics) {
      return;
    }
    final SearchWorkflowState state = _controller.state;
    final Lyrics? lyrics = state.currentLyrics;
    if (lyrics == null || state.previewPhase == SearchPreviewPhase.loading) {
      _showSnackBar(
        widget.strings.text(SearchUiTextKey.selectorSelectLyricsFirst),
      );
      return;
    }
    setState(() {
      _isSubmittingLyrics = true;
    });
    try {
      final bool selected = await widget.onLyricsSelected(
        SearchLyricsSelectorResult(
          lyrics: lyrics,
          path: _selectedLyricsPath,
          langs: _resolveOrderedLangs(state.selectedLangs),
          offsetMs: state.offsetMs,
          isInstrumental: lyrics.isInstrumental(),
        ),
      );
      if (!mounted) {
        return;
      }
      if (selected) {
        _schedulePreviewSheetClose();
      } else {
        _showSnackBar(
          widget.strings.text(SearchUiTextKey.selectorSelectFailed),
        );
      }
    } on Exception {
      if (mounted) {
        _showSnackBar(
          widget.strings.text(SearchUiTextKey.selectorSelectFailed),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingLyrics = false;
        });
      }
    }
  }

  Future<void> _openNetworkResult(int rowIndex) {
    // 网络结果一旦真正打开，本地路径就不再属于当前歌词。同步递增 generation
    // 还可以阻止较慢的本地文件解析结果晚到后覆盖用户的新选择。
    _localOpenGeneration += 1;
    _selectedLyricsPath = null;
    return _controller.openResult(rowIndex);
  }

  Future<void> _showPreviewSheet() async {
    if (_isPreviewSheetVisible || !mounted || _isExpandedLayout) {
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
          final double height = MediaQuery.sizeOf(context).height * 0.9;
          return SafeArea(
            child: SizedBox(
              height: height,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (BuildContext context, Widget? _) {
                        return SearchPreviewPane(
                          state: _controller.state,
                          controller: _controller,
                          strings: widget.strings,
                          savePathController: _savePathController,
                          isDesktopPlatform: true,
                          showTagSave: false,
                          showDirectorySave: false,
                          showFileSave: false,
                          inSheet: true,
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (BuildContext context, Widget? _) {
                        return _buildSelectButton(
                          _controller.state,
                          fillWidth: true,
                          buttonKey: const ValueKey<String>(
                            'selector_sheet_select_lyrics_button',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      _isPreviewSheetVisible = false;
    }
  }

  void _handleExpandedLayoutChanged(bool isExpanded) {
    _isExpandedLayout = isExpanded;
    if (isExpanded) {
      _schedulePreviewSheetClose();
    }
  }

  void _schedulePreviewSheetClose() {
    if (!_isPreviewSheetVisible || _isClosingPreviewSheet || !mounted) {
      return;
    }
    _isClosingPreviewSheet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) {
          return;
        }
        final NavigatorState navigator = Navigator.of(context);
        if (_isPreviewSheetVisible && navigator.canPop()) {
          await navigator.maybePop();
        }
      } finally {
        _isClosingPreviewSheet = false;
      }
    });
  }

  void _handleControllerChanged() {
    final SearchNotice? notice = _controller.state.notice;
    if (!mounted || notice == null || _lastNoticeId == notice.id) {
      return;
    }
    _lastNoticeId = notice.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller.state.notice?.id != notice.id) {
        return;
      }
      _showSnackBar(
        searchNoticeText(widget.strings, notice),
        action: isSearchSourceFailureNotice(notice.code)
            ? SnackBarAction(
                label: widget.strings.text(SearchUiTextKey.viewDetails),
                onPressed: () => showSearchSourceFailuresDialog(
                  context: context,
                  controller: _controller,
                  strings: widget.strings,
                ),
              )
            : null,
      );
      _controller.dismissNotice(notice.id);
    });
  }

  bool _shouldApplyInitialState(
    SearchLyricsSelectorInitialState? previous,
    SearchLyricsSelectorInitialState? current,
  ) {
    if (previous == null || current == null) {
      return previous != current;
    }
    return previous.keyword != current.keyword ||
        previous.offsetMs != current.offsetMs ||
        previous.refreshRevision != current.refreshRevision ||
        !listEquals(previous.langs, current.langs) ||
        previous.lyrics != current.lyrics;
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

  String? _normalizeKeyword(String? keyword) {
    final String? normalized = keyword?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  List<String> _resolveOrderedLangs(List<String> selectedLangs) {
    final List<String> preferredOrder = <String>[
      ...?widget.initialState?.langs,
      'roma',
      'orig',
      'ts',
    ];
    final List<String> ordered = <String>[];
    for (final String lang in preferredOrder) {
      if (selectedLangs.contains(lang) && !ordered.contains(lang)) {
        ordered.add(lang);
      }
    }
    for (final String lang in selectedLangs) {
      if (!ordered.contains(lang)) {
        ordered.add(lang);
      }
    }
    return List<String>.unmodifiable(ordered);
  }

  void _showSnackBar(String message, {SnackBarAction? action}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), action: action));
  }
}
