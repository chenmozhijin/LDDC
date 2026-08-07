import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../../state/async_view_state.dart';
import '../../ui/search_ui_strings.dart';
import '../../ui/widgets/progress_panel.dart';
import '../../ui/widgets/search_toolbar.dart';
import '../search_batch_save_models.dart';
import '../search_source_descriptor.dart';
import '../search_workflow_controller.dart';
import '../search_workflow_state.dart';
import 'search_preview_pane.dart';
import 'search_result_pane.dart';

enum SearchWorkspaceCompactBehavior { resultOnly, stackedPreview }

class SearchWorkspace extends StatefulWidget {
  const SearchWorkspace({
    required this.controller,
    required this.strings,
    required this.keywordController,
    required this.savePathController,
    required this.selectedRowIndexListenable,
    required this.isDesktopPlatform,
    required this.canUseAndroidSafListSave,
    required this.showTagSave,
    required this.onRowsChanged,
    required this.onDesktopRowTap,
    required this.onMobileRowTap,
    required this.onReturnPath,
    required this.onOpenPreviewSheet,
    this.onExpandedLayoutChanged,
    this.description,
    this.hideDescriptionInCompact = false,
    this.compactBehavior = SearchWorkspaceCompactBehavior.resultOnly,
    this.allowListSaveAction = true,
    this.showBatchProgress = true,
    this.showDirectorySave,
    this.showFileSave,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  static const double expandedBreakpoint = 1024;
  static const double compactToolbarBreakpoint = 720;

  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final TextEditingController keywordController;
  final TextEditingController savePathController;
  final ValueListenable<int?> selectedRowIndexListenable;
  final bool isDesktopPlatform;
  final bool canUseAndroidSafListSave;
  final bool showTagSave;
  final ValueChanged<int> onRowsChanged;
  final Future<void> Function(int rowIndex) onDesktopRowTap;
  final Future<void> Function(SourceAware row, int rowIndex) onMobileRowTap;
  final VoidCallback onReturnPath;
  final Future<void> Function() onOpenPreviewSheet;
  final ValueChanged<bool>? onExpandedLayoutChanged;
  final String? description;
  final bool hideDescriptionInCompact;
  final SearchWorkspaceCompactBehavior compactBehavior;
  final bool allowListSaveAction;
  final bool showBatchProgress;
  final bool? showDirectorySave;
  final bool? showFileSave;
  final EdgeInsetsGeometry padding;

  @override
  State<SearchWorkspace> createState() => _SearchWorkspaceState();
}

class _SearchWorkspaceState extends State<SearchWorkspace> {
  static const double _defaultResultFraction = 0.4;
  static const double _minimumResultWidth = 320;
  static const double _minimumPreviewWidth = 420;
  static const double _splitterGapWidth = 12;
  static const double _splitterHitWidth = 48;
  static const double _keyboardFractionStep = 0.05;

  bool _controllerSyncScheduled = false;
  // 受控状态通过 post-frame 回写时，必须区分用户在等待期间产生的编辑。
  // 编辑代数由 TextEditingController listener 递增，旧回调看到代数变化后
  // 会放弃写入，避免窄屏预览关闭等重建流程恢复已经被用户清空的文本。
  int _keywordEditGeneration = 0;
  int _savePathEditGeneration = 0;
  late final VoidCallback _keywordControllerListener;
  late final VoidCallback _savePathControllerListener;
  bool? _lastExpandedLayout;
  late final ValueNotifier<double> _expandedResultFraction;

  @override
  void initState() {
    super.initState();
    _expandedResultFraction = ValueNotifier<double>(_defaultResultFraction);
    _keywordControllerListener = () => _keywordEditGeneration += 1;
    _savePathControllerListener = () => _savePathEditGeneration += 1;
    widget.keywordController.addListener(_keywordControllerListener);
    widget.savePathController.addListener(_savePathControllerListener);
  }

  @override
  void didUpdateWidget(covariant SearchWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keywordController != widget.keywordController) {
      oldWidget.keywordController.removeListener(_keywordControllerListener);
      widget.keywordController.addListener(_keywordControllerListener);
      _keywordEditGeneration += 1;
    }
    if (oldWidget.savePathController != widget.savePathController) {
      oldWidget.savePathController.removeListener(_savePathControllerListener);
      widget.savePathController.addListener(_savePathControllerListener);
      _savePathEditGeneration += 1;
    }
  }

  @override
  void dispose() {
    widget.keywordController.removeListener(_keywordControllerListener);
    widget.savePathController.removeListener(_savePathControllerListener);
    _expandedResultFraction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final SearchWorkflowState workflowState = widget.controller.state;
    final ({
      SearchBatchSaveProgress? batchProgress,
      String keyword,
      String? saveDirectoryPath,
      Source selectedSource,
    })
    shellState = (
      batchProgress: workflowState.batchProgress,
      keyword: workflowState.keyword,
      saveDirectoryPath: workflowState.saveDirectoryPath,
      selectedSource: workflowState.selectedSource,
    );
    final SearchWorkflowController controller = widget.controller;

    _scheduleControllerSync(
      keyword: shellState.keyword,
      savePath: shellState.saveDirectoryPath ?? '',
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isExpanded =
            constraints.maxWidth >= SearchWorkspace.expandedBreakpoint;
        final bool isCompact =
            constraints.maxWidth < SearchWorkspace.compactToolbarBreakpoint;
        _notifyExpandedLayoutChanged(isExpanded);
        return Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SearchToolbar(
                keywordController: widget.keywordController,
                sourceItems: <SearchToolbarSourceItem>[
                  for (final SearchSourceDescriptor descriptor
                      in kSearchToolbarSourceDescriptors)
                    SearchToolbarSourceItem(
                      value: descriptor.source.value,
                      label: descriptor.label(widget.strings),
                    ),
                ],
                selectedSource: shellState.selectedSource.value,
                searchButtonLabel: widget.strings.text(
                  SearchUiTextKey.commonSearch,
                ),
                keywordHint: widget.strings.text(SearchUiTextKey.keywordHint),
                sourceLabel: widget.strings.text(SearchUiTextKey.commonSource),
                isCompact: isCompact,
                onSourceChanged: (String value) {
                  try {
                    controller.updateSource(Source.fromValue(value));
                  } on ArgumentError {
                    // 搜索来源来自下拉控件，理论上不会无效；防御式处理可以避免异常打断页面。
                  }
                },
                onSearchPressed: () async {
                  controller.setKeyword(widget.keywordController.text);
                  await controller.search();
                },
                onKeywordChanged: (String value) {
                  // onChanged 发生在 controller listener 之后；显式递增一次，
                  // 让同一帧已经注册的状态回写也能识别这次用户编辑。
                  _keywordEditGeneration += 1;
                  controller.setKeyword(value);
                },
              ),
              if ((!isCompact || !widget.hideDescriptionInCompact) &&
                  widget.description != null &&
                  widget.description!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  widget.description!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: isExpanded
                    ? _buildExpandedLayout(controller)
                    : _buildCompactLayout(controller),
              ),
              if (widget.showBatchProgress &&
                  shellState.batchProgress != null &&
                  shellState.batchProgress!.total > 0) ...<Widget>[
                const SizedBox(height: 12),
                ProgressPanel(
                  title: widget.strings.text(
                    SearchUiTextKey.batchSaveProgressTitle,
                  ),
                  currentValue: shellState.batchProgress!.current,
                  maxValue: shellState.batchProgress!.total,
                  statusText: _batchSaveProgressMessageText(
                    widget.strings,
                    shellState.batchProgress!.message,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _scheduleControllerSync({
    required String keyword,
    required String savePath,
  }) {
    if (_controllerSyncScheduled) {
      return;
    }
    final int scheduledKeywordGeneration = _keywordEditGeneration;
    final int scheduledSavePathGeneration = _savePathEditGeneration;
    final String scheduledKeywordText = widget.keywordController.text;
    final String scheduledSavePathText = widget.savePathController.text;
    final String scheduledKeywordState = keyword;
    final String scheduledSavePathState = savePath;
    _controllerSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _controllerSyncScheduled = false;
      final SearchWorkflowState latestState = widget.controller.state;
      final String latestKeyword = latestState.keyword;
      final String latestSavePath = latestState.saveDirectoryPath ?? '';
      final bool keywordIsUnchanged =
          _keywordEditGeneration == scheduledKeywordGeneration &&
          widget.keywordController.text == scheduledKeywordText &&
          latestKeyword == scheduledKeywordState;
      final bool savePathIsUnchanged =
          _savePathEditGeneration == scheduledSavePathGeneration &&
          widget.savePathController.text == scheduledSavePathText &&
          latestSavePath == scheduledSavePathState;

      // 只有注册回调时的代数和文本都未变化，才允许业务状态回写。
      // 如果回调因为用户输入或外部 controller 替换而过期，不能把旧 pending
      // 值直接丢掉：下一帧重新读取 controller.state，确保新的业务状态最终能够
      // 收敛到输入框，同时不会覆盖用户刚刚输入的内容。
      if (keywordIsUnchanged) {
        _syncTextController(widget.keywordController, latestKeyword);
      }
      if (savePathIsUnchanged) {
        _syncTextController(widget.savePathController, latestSavePath);
      }
      if ((!keywordIsUnchanged &&
              latestKeyword != widget.keywordController.text) ||
          (!savePathIsUnchanged &&
              latestSavePath != widget.savePathController.text)) {
        _scheduleControllerSync(
          keyword: latestKeyword,
          savePath: latestSavePath,
        );
      }
    });
  }

  void _syncTextController(TextEditingController controller, String text) {
    if (controller.text == text || _isComposing(controller)) {
      return;
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  bool _isComposing(TextEditingController controller) {
    final TextRange composing = controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void _notifyExpandedLayoutChanged(bool isExpanded) {
    if (_lastExpandedLayout == isExpanded) {
      return;
    }
    _lastExpandedLayout = isExpanded;
    final ValueChanged<bool>? callback = widget.onExpandedLayoutChanged;
    if (callback == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastExpandedLayout != isExpanded) {
        return;
      }
      callback(isExpanded);
    });
  }

  Widget _buildExpandedLayout(SearchWorkflowController controller) {
    final Widget resultPane = _buildResultPane(controller, true);
    final Widget previewPane = _buildPreviewPane(controller);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double paneWidth = constraints.maxWidth - _splitterGapWidth;
        final double minimumFraction = _minimumResultWidth / paneWidth;
        final double maximumFraction = 1 - _minimumPreviewWidth / paneWidth;
        return ValueListenableBuilder<double>(
          valueListenable: _expandedResultFraction,
          builder: (BuildContext context, double fraction, Widget? child) {
            final double effectiveFraction = fraction
                .clamp(minimumFraction, maximumFraction)
                .toDouble();
            final double resultWidth = paneWidth * effectiveFraction;
            final double splitterCenter = resultWidth + _splitterGapWidth / 2;
            return Stack(
              key: const ValueKey<String>('search_workspace_split_layout'),
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      key: const ValueKey<String>(
                        'search_workspace_result_pane',
                      ),
                      width: resultWidth,
                      child: resultPane,
                    ),
                    const SizedBox(width: _splitterGapWidth),
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey<String>(
                          'search_workspace_preview_pane',
                        ),
                        child: previewPane,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: splitterCenter - _splitterHitWidth / 2,
                  top: 0,
                  bottom: 0,
                  width: _splitterHitWidth,
                  child: _SearchWorkspaceSplitter(
                    fraction: effectiveFraction,
                    tooltip: widget.strings.text(
                      SearchUiTextKey.resizeWorkspacePanes,
                    ),
                    onDragDelta: (double delta) {
                      // 高频鼠标事件可能在下一帧重建前连续到达；若基于本次 build
                      // 捕获的 resultWidth 计算，每个事件都会覆盖前一个事件，只留下
                      // 一帧内最后几个像素。直接从 notifier 当前值累加，才能完整保留
                      // 同一帧内的全部位移并让分隔条持续跟手。
                      final double currentFraction = _expandedResultFraction
                          .value
                          .clamp(minimumFraction, maximumFraction)
                          .toDouble();
                      _setExpandedResultFraction(
                        currentFraction + delta / paneWidth,
                        minimumFraction: minimumFraction,
                        maximumFraction: maximumFraction,
                      );
                    },
                    onDecrease: () {
                      _setExpandedResultFraction(
                        effectiveFraction - _keyboardFractionStep,
                        minimumFraction: minimumFraction,
                        maximumFraction: maximumFraction,
                      );
                    },
                    onIncrease: () {
                      _setExpandedResultFraction(
                        effectiveFraction + _keyboardFractionStep,
                        minimumFraction: minimumFraction,
                        maximumFraction: maximumFraction,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _setExpandedResultFraction(
    double value, {
    required double minimumFraction,
    required double maximumFraction,
  }) {
    final double next = value
        .clamp(minimumFraction, maximumFraction)
        .toDouble();
    if ((_expandedResultFraction.value - next).abs() < 0.0001) {
      return;
    }
    _expandedResultFraction.value = next;
  }

  Widget _buildCompactLayout(SearchWorkflowController controller) {
    if (widget.compactBehavior == SearchWorkspaceCompactBehavior.resultOnly) {
      return _buildResultPane(controller, false);
    }
    return Column(
      children: <Widget>[
        Expanded(flex: 4, child: _buildResultPane(controller, false)),
        const SizedBox(height: 12),
        Expanded(flex: 5, child: _buildPreviewPane(controller)),
      ],
    );
  }

  Widget _buildResultPane(
    SearchWorkflowController controller,
    bool isExpanded,
  ) {
    return _SearchResultPaneConsumer(
      controller: controller,
      strings: widget.strings,
      selectedRowIndexListenable: widget.selectedRowIndexListenable,
      readKeywordText: () => widget.keywordController.text,
      isExpanded: isExpanded,
      isDesktopPlatform: widget.isDesktopPlatform,
      canUseAndroidSafListSave: widget.canUseAndroidSafListSave,
      allowListSaveAction: widget.allowListSaveAction,
      onRowsChanged: widget.onRowsChanged,
      onDesktopRowTap: widget.onDesktopRowTap,
      onMobileRowTap: widget.onMobileRowTap,
      onReturnPath: widget.onReturnPath,
      onOpenPreviewSheet: widget.onOpenPreviewSheet,
    );
  }

  Widget _buildPreviewPane(SearchWorkflowController controller) {
    return _SearchPreviewPaneConsumer(
      controller: controller,
      strings: widget.strings,
      savePathController: widget.savePathController,
      isDesktopPlatform: widget.isDesktopPlatform,
      showTagSave: widget.showTagSave,
      showDirectorySave: widget.showDirectorySave,
      showFileSave: widget.showFileSave,
    );
  }
}

class _SearchWorkspaceSplitter extends StatefulWidget {
  const _SearchWorkspaceSplitter({
    required this.fraction,
    required this.tooltip,
    required this.onDragDelta,
    required this.onDecrease,
    required this.onIncrease,
  });

  final double fraction;
  final String tooltip;
  final ValueChanged<double> onDragDelta;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  State<_SearchWorkspaceSplitter> createState() =>
      _SearchWorkspaceSplitterState();
}

class _SearchWorkspaceSplitterState extends State<_SearchWorkspaceSplitter> {
  bool _hovered = false;
  bool _focused = false;
  double? _lastDragGlobalX;
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'search-workspace-splitter',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color lineColor = _hovered || _focused
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    return Semantics(
      label: widget.tooltip,
      value: '${(widget.fraction * 100).round()}%',
      decreasedValue:
          '${((widget.fraction - _SearchWorkspaceState._keyboardFractionStep).clamp(0, 1) * 100).round()}%',
      increasedValue:
          '${((widget.fraction + _SearchWorkspaceState._keyboardFractionStep).clamp(0, 1) * 100).round()}%',
      onDecrease: widget.onDecrease,
      onIncrease: widget.onIncrease,
      child: FocusableActionDetector(
        key: const ValueKey<String>('search_workspace_splitter'),
        focusNode: _focusNode,
        mouseCursor: SystemMouseCursors.resizeColumn,
        onShowHoverHighlight: (bool value) {
          if (_hovered != value) {
            setState(() => _hovered = value);
          }
        },
        onShowFocusHighlight: (bool value) {
          if (_focused != value) {
            setState(() => _focused = value);
          }
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _ResizeResultPaneIntent(false),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _ResizeResultPaneIntent(true),
        },
        actions: <Type, Action<Intent>>{
          _ResizeResultPaneIntent: CallbackAction<_ResizeResultPaneIntent>(
            onInvoke: (_ResizeResultPaneIntent intent) {
              intent.increase ? widget.onIncrease() : widget.onDecrease();
              return null;
            },
          ),
        },
        child: Tooltip(
          message: widget.tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 从按下位置计算拖动，避免 Flutter 手势识别阈值吞掉最初一段位移。
            dragStartBehavior: DragStartBehavior.down,
            onTap: _focusNode.requestFocus,
            onHorizontalDragStart: (DragStartDetails details) {
              _focusNode.requestFocus();
              _lastDragGlobalX = details.globalPosition.dx;
            },
            onHorizontalDragUpdate: _handleHorizontalDragUpdate,
            onHorizontalDragEnd: (_) => _lastDragGlobalX = null,
            onHorizontalDragCancel: () => _lastDragGlobalX = null,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: _hovered || _focused ? 4 : 2,
                height: double.infinity,
                color: lineColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final double currentGlobalX = details.globalPosition.dx;
    final double? previousGlobalX = _lastDragGlobalX;
    _lastDragGlobalX = currentGlobalX;
    if (previousGlobalX == null) {
      return;
    }
    // 分隔条会在每次更新后移动并重建，局部 delta 会被新的坐标原点抵消，
    // 表现为鼠标移动很远但分隔条只挪动一点。全局坐标不随组件移动，按相邻
    // 指针事件求差后可以保持 1dp 鼠标位移对应 1dp 面板位移。
    widget.onDragDelta(currentGlobalX - previousGlobalX);
  }
}

final class _ResizeResultPaneIntent extends Intent {
  const _ResizeResultPaneIntent(this.increase);

  final bool increase;
}

String _batchSaveProgressMessageText(
  SearchUiStrings strings,
  SearchBatchSaveProgressMessage message,
) {
  return switch (message.code) {
    SearchBatchSaveProgressMessageCode.empty => '',
    SearchBatchSaveProgressMessageCode.preparing => strings.text(
      SearchUiTextKey.batchSaveProgressPreparing,
    ),
    SearchBatchSaveProgressMessageCode.fetchingLyrics => strings.text(
      SearchUiTextKey.batchSaveProgressFetchingLyrics,
      arguments: SearchUiTextArguments(songName: message.songName ?? ''),
    ),
  };
}

class _SearchResultPaneConsumer extends StatelessWidget {
  const _SearchResultPaneConsumer({
    required this.controller,
    required this.strings,
    required this.selectedRowIndexListenable,
    required this.readKeywordText,
    required this.isExpanded,
    required this.isDesktopPlatform,
    required this.canUseAndroidSafListSave,
    required this.allowListSaveAction,
    required this.onRowsChanged,
    required this.onDesktopRowTap,
    required this.onMobileRowTap,
    required this.onReturnPath,
    required this.onOpenPreviewSheet,
  });

  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final ValueListenable<int?> selectedRowIndexListenable;
  final String Function() readKeywordText;
  final bool isExpanded;
  final bool isDesktopPlatform;
  final bool canUseAndroidSafListSave;
  final bool allowListSaveAction;
  final ValueChanged<int> onRowsChanged;
  final Future<void> Function(int rowIndex) onDesktopRowTap;
  final Future<void> Function(SourceAware row, int rowIndex) onMobileRowTap;
  final VoidCallback onReturnPath;
  final Future<void> Function() onOpenPreviewSheet;

  @override
  Widget build(BuildContext context) {
    final SearchWorkflowState state = controller.state;
    final List<SourceAware> rows = _rowsFromSearchTableState(state.tableState);
    onRowsChanged(rows.length);
    // 选中行只是列表高亮和桌面快捷键需要的临时状态，放在 ValueListenable
    // 可以让单击结果时只刷新结果列表，不牵动预览区、工具栏和拖拽遮罩重建。
    return ValueListenableBuilder<int?>(
      valueListenable: selectedRowIndexListenable,
      builder: (BuildContext context, int? selectedRowIndex, Widget? _) {
        return SearchResultPane(
          state: state,
          rows: rows,
          controller: controller,
          strings: strings,
          readKeywordText: readKeywordText,
          isExpanded: isExpanded,
          isDesktopPlatform: isDesktopPlatform,
          canUseAndroidSafListSave: canUseAndroidSafListSave,
          selectedRowIndex: selectedRowIndex,
          onDesktopRowTap: onDesktopRowTap,
          onMobileRowTap: onMobileRowTap,
          onReturnPath: onReturnPath,
          onOpenPreviewSheet: onOpenPreviewSheet,
          allowListSaveAction: allowListSaveAction,
        );
      },
    );
  }
}

class _SearchPreviewPaneConsumer extends StatelessWidget {
  const _SearchPreviewPaneConsumer({
    required this.controller,
    required this.strings,
    required this.savePathController,
    required this.isDesktopPlatform,
    required this.showTagSave,
    required this.showDirectorySave,
    required this.showFileSave,
  });

  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final TextEditingController savePathController;
  final bool isDesktopPlatform;
  final bool showTagSave;
  final bool? showDirectorySave;
  final bool? showFileSave;

  @override
  Widget build(BuildContext context) {
    final SearchWorkflowState state = controller.state;
    return SearchPreviewPane(
      state: state,
      controller: controller,
      strings: strings,
      savePathController: savePathController,
      isDesktopPlatform: isDesktopPlatform,
      showTagSave: showTagSave,
      showDirectorySave: showDirectorySave,
      showFileSave: showFileSave,
    );
  }
}

List<SourceAware> _rowsFromSearchTableState(
  AsyncViewState<List<SourceAware>> state,
) {
  if (state is AsyncSuccess<List<SourceAware>>) {
    return state.data;
  }
  if (state is AsyncPartial<List<SourceAware>>) {
    return state.data;
  }
  return const <SourceAware>[];
}
