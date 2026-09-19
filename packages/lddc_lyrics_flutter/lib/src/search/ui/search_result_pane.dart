import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../../state/async_view_state.dart';
import '../../ui/search_ui_strings.dart';
import '../search_workflow_controller.dart';
import '../search_workflow_state.dart';
import 'search_cover_network_image.dart';
import 'search_source_failure_dialog.dart';

/// 搜索结果区：负责搜索类型切换、结果列表与列表级动作。
class SearchResultPane extends StatefulWidget {
  const SearchResultPane({
    super.key,
    required this.state,
    required this.rows,
    required this.controller,
    required this.strings,
    required this.readKeywordText,
    required this.isExpanded,
    required this.isDesktopPlatform,
    required this.canUseAndroidSafListSave,
    required this.selectedRowIndex,
    required this.onDesktopRowTap,
    required this.onMobileRowTap,
    required this.onReturnPath,
    required this.onOpenPreviewSheet,
    this.allowListSaveAction = true,
  });

  final SearchWorkflowState state;
  final List<SourceAware> rows;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final String Function() readKeywordText;
  final bool isExpanded;
  final bool isDesktopPlatform;
  final bool canUseAndroidSafListSave;
  final int? selectedRowIndex;
  final Future<void> Function(int rowIndex) onDesktopRowTap;
  final Future<void> Function(SourceAware row, int rowIndex) onMobileRowTap;
  final VoidCallback onReturnPath;
  final Future<void> Function() onOpenPreviewSheet;
  final bool allowListSaveAction;

  @override
  State<SearchResultPane> createState() => _SearchResultPaneState();
}

class _SearchResultPaneState extends State<SearchResultPane> {
  double _lastAutoLoadExtent = -1;
  int _lastAutoLoadRowCount = 0;

  @override
  void initState() {
    super.initState();
    _lastAutoLoadRowCount = widget.rows.length;
  }

  @override
  void didUpdateWidget(covariant SearchResultPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rows.length != _lastAutoLoadRowCount) {
      _lastAutoLoadRowCount = widget.rows.length;
      _lastAutoLoadExtent = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncViewState<List<SourceAware>> tableState =
        widget.state.tableState;
    final String? warning = tableState is AsyncPartial<List<SourceAware>>
        ? _searchTableStatusText(widget.strings, tableState.warningMessage)
        : null;
    final bool canLoadMore = widget.state.canLoadMore;
    final bool showSource =
        widget.state.currentPathResult != null &&
        widget.state.currentPathResult!.sources.length > 1;
    final bool showListSaveAction =
        widget.allowListSaveAction &&
        (widget.isDesktopPlatform || widget.canUseAndroidSafListSave) &&
        widget.state.currentPathResult?.info is SongListInfo;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: _SearchResultHeader(
              state: widget.state,
              controller: widget.controller,
              strings: widget.strings,
              readKeywordText: widget.readKeywordText,
              warning: warning,
              showListSaveAction: showListSaveAction,
              isExpanded: widget.isExpanded,
              onReturnPath: widget.onReturnPath,
              onOpenPreviewSheet: widget.onOpenPreviewSheet,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildResultBody(
              context,
              tableState: tableState,
              rows: widget.rows,
              canLoadMore: canLoadMore,
              showSource: showSource,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBody(
    BuildContext context, {
    required AsyncViewState<List<SourceAware>> tableState,
    required List<SourceAware> rows,
    required bool canLoadMore,
    required bool showSource,
  }) {
    if (tableState is AsyncLoading<List<SourceAware>>) {
      return _SearchResultStatus(
        icon: Icons.hourglass_top_rounded,
        title:
            _searchTableStatusText(widget.strings, tableState.message) ??
            widget.strings.text(SearchUiTextKey.loading),
        description: widget.strings.text(SearchUiTextKey.loadingStepFetching),
        showProgress: true,
      );
    }
    if (!widget.state.hasSubmittedSearch) {
      return _SearchResultStatus(
        icon: Icons.search_rounded,
        title: widget.strings.text(SearchUiTextKey.initialResultTitle),
        description: widget.strings.text(
          SearchUiTextKey.initialResultDescription,
        ),
      );
    }
    if (tableState is AsyncError<List<SourceAware>>) {
      return _SearchResultStatus(
        icon: Icons.error_outline_rounded,
        title: widget.strings.text(SearchUiTextKey.commonError),
        description:
            _searchTableStatusText(widget.strings, tableState.message) ??
            tableState.message,
        action: Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            if (widget.state.sourceFailures.isNotEmpty)
              TextButton.icon(
                onPressed: () => showSearchSourceFailuresDialog(
                  context: context,
                  controller: widget.controller,
                  strings: widget.strings,
                ),
                icon: const Icon(Icons.info_outline_rounded),
                label: Text(widget.strings.text(SearchUiTextKey.viewDetails)),
              ),
            OutlinedButton.icon(
              onPressed: widget.state.sourceFailures.isEmpty
                  ? widget.controller.search
                  : widget.controller.retryFailedSources,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(widget.strings.text(SearchUiTextKey.retry)),
            ),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      final String message = switch (tableState) {
        AsyncEmpty<List<SourceAware>> value =>
          _searchTableStatusText(widget.strings, value.message) ??
              value.message ??
              widget.strings.text(SearchUiTextKey.empty),
        _ => widget.strings.text(SearchUiTextKey.empty),
      };
      return _SearchResultStatus(icon: Icons.inbox_outlined, title: message);
    }

    final bool loadMoreFailed =
        tableState is AsyncPartial<List<SourceAware>> &&
        tableState.warningMessage != null &&
        SearchTableStatusMessage.decode(tableState.warningMessage!).$1 ==
            SearchTableStatusMessageCode.loadMoreFailed;
    final String footerHint = widget.state.isSearching
        ? widget.strings.text(SearchUiTextKey.loadingStepFetching)
        : widget.state.isLoadingMore
        ? widget.strings.text(SearchUiTextKey.resultLoadingMore)
        : loadMoreFailed
        ? widget.strings.text(SearchUiTextKey.resultLoadMoreFailed)
        : widget.state.hasMore
        ? widget.strings.text(SearchUiTextKey.resultScrollForMore)
        : widget.strings.text(SearchUiTextKey.noMoreResult);

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (!canLoadMore) {
          return false;
        }
        final double remaining =
            notification.metrics.maxScrollExtent - notification.metrics.pixels;
        if (remaining <= 160) {
          if (notification.metrics.maxScrollExtent <= _lastAutoLoadExtent + 1) {
            return false;
          }
          _lastAutoLoadExtent = notification.metrics.maxScrollExtent;
          widget.controller.loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: rows.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == rows.length) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: _SearchResultContinuationFooter(
                    hint: footerHint,
                    loading:
                        widget.state.isSearching || widget.state.isLoadingMore,
                    showRetry: loadMoreFailed && canLoadMore,
                    onRetry: canLoadMore ? widget.controller.loadMore : null,
                    strings: widget.strings,
                  ),
                ),
              ],
            );
          }

          final SourceAware row = rows[index];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (index > 0) const Divider(height: 1),
              _SearchMusicResultRow(
                row: row,
                strings: widget.strings,
                index: index,
                showSource: showSource,
                selected: widget.selectedRowIndex == index,
                onTap: () async {
                  if (widget.isExpanded) {
                    await widget.onDesktopRowTap(index);
                    return;
                  }
                  await widget.onMobileRowTap(row, index);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchResultContinuationFooter extends StatelessWidget {
  const _SearchResultContinuationFooter({
    required this.hint,
    required this.loading,
    required this.showRetry,
    required this.onRetry,
    required this.strings,
  });

  final String hint;
  final bool loading;
  final bool showRetry;
  final VoidCallback? onRetry;
  final SearchUiStrings strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (loading)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (loading) const SizedBox(width: 12),
        Expanded(child: Text(hint)),
        if (showRetry) ...<Widget>[
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: loading ? null : onRetry,
            child: Text(strings.text(SearchUiTextKey.retry)),
          ),
        ],
      ],
    );
  }
}

class _SearchResultHeader extends StatelessWidget {
  const _SearchResultHeader({
    required this.state,
    required this.controller,
    required this.strings,
    required this.readKeywordText,
    required this.warning,
    required this.showListSaveAction,
    required this.isExpanded,
    required this.onReturnPath,
    required this.onOpenPreviewSheet,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final String Function() readKeywordText;
  final String? warning;
  final bool showListSaveAction;
  final bool isExpanded;
  final VoidCallback onReturnPath;
  final Future<void> Function() onOpenPreviewSheet;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.text(SearchUiTextKey.resultTitle),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (warning != null && warning!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (state.sourceFailures.isNotEmpty)
                IconButton(
                  tooltip: strings.text(SearchUiTextKey.viewDetails),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showSearchSourceFailuresDialog(
                    context: context,
                    controller: controller,
                    strings: strings,
                  ),
                  icon: const Icon(Icons.info_outline_rounded),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget tabs = _SearchTypeTabs(
              state: state,
              controller: controller,
              strings: strings,
              readKeywordText: readKeywordText,
            );
            final Widget actionStrip = _SearchResultActionStrip(
              state: state,
              controller: controller,
              strings: strings,
              showListSaveAction: showListSaveAction,
              isExpanded: isExpanded,
              onReturnPath: onReturnPath,
              onOpenPreviewSheet: onOpenPreviewSheet,
            );
            final bool shouldStack =
                constraints.maxWidth < 780 &&
                (showListSaveAction || constraints.maxWidth < 480);
            if (shouldStack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  tabs,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: actionStrip),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: tabs),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.45,
                  ),
                  child: actionStrip,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SearchTypeTabs extends StatefulWidget {
  const _SearchTypeTabs({
    required this.state,
    required this.controller,
    required this.strings,
    required this.readKeywordText,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final String Function() readKeywordText;

  @override
  State<_SearchTypeTabs> createState() => _SearchTypeTabsState();
}

class _SearchTypeTabsState extends State<_SearchTypeTabs>
    with TickerProviderStateMixin {
  TabController? _tabController;
  List<SearchType> _types = const <SearchType>[];

  @override
  void initState() {
    super.initState();
    _replaceTabController(widget.state.availableSearchTypes);
  }

  @override
  void didUpdateWidget(covariant _SearchTypeTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final List<SearchType> nextTypes = widget.state.availableSearchTypes;
    if (!listEquals(_types, nextTypes)) {
      // 来源切换会改变可用搜索类型。旧 controller 的 length 不能复用，
      // 必须先释放再按新列表创建，避免 ticker 和 TabBar 索引越界。
      _replaceTabController(nextTypes);
      return;
    }
    _syncSelectedType();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _replaceTabController(List<SearchType> types) {
    _tabController?.dispose();
    _types = List<SearchType>.unmodifiable(types);
    if (_types.isEmpty) {
      _tabController = null;
      return;
    }
    _tabController = TabController(
      length: _types.length,
      initialIndex: _resolvedIndex(),
      vsync: this,
    );
  }

  void _syncSelectedType() {
    final TabController? tabController = _tabController;
    if (tabController == null) {
      return;
    }
    final int nextIndex = _resolvedIndex();
    if (tabController.index != nextIndex) {
      // 外部自动搜索先更新业务状态，再由这里控制可见 Tab；直接赋值不会
      // 触发 TabBar.onTap，因此不会产生第二次搜索请求。
      tabController.index = nextIndex;
    }
  }

  int _resolvedIndex() {
    final SearchType selectedType = widget.state.selectedSearchType;
    return _types.contains(selectedType) ? _types.indexOf(selectedType) : 0;
  }

  @override
  Widget build(BuildContext context) {
    final List<SearchType> types = _types;
    if (types.isEmpty) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: types
            .map(
              (SearchType type) => Tab(
                key: ValueKey<String>('search_type_tab_${type.value}'),
                text: widget.strings.searchTypeLabel(type),
              ),
            )
            .toList(growable: false),
        labelStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: theme.textTheme.titleSmall,
        onTap: (int index) {
          final SearchType type = types[index];
          if (type == widget.state.selectedSearchType) {
            return;
          }
          final String keywordText = widget.readKeywordText();
          widget.controller.updateSearchType(type);
          widget.controller.setKeyword(keywordText);
          if (keywordText.trim().isNotEmpty) {
            widget.controller.search();
          }
        },
      ),
    );
  }
}

class _SearchResultActionStrip extends StatelessWidget {
  const _SearchResultActionStrip({
    required this.state,
    required this.controller,
    required this.strings,
    required this.showListSaveAction,
    required this.isExpanded,
    required this.onReturnPath,
    required this.onOpenPreviewSheet,
  });

  final SearchWorkflowState state;
  final SearchWorkflowController controller;
  final SearchUiStrings strings;
  final bool showListSaveAction;
  final bool isExpanded;
  final VoidCallback onReturnPath;
  final Future<void> Function() onOpenPreviewSheet;

  @override
  Widget build(BuildContext context) {
    final List<Widget> actions = <Widget>[
      if (state.canReturn)
        OutlinedButton.icon(
          onPressed: onReturnPath,
          icon: const Icon(Icons.arrow_back),
          label: Text(strings.text(SearchUiTextKey.resultReturn)),
        ),
      if (showListSaveAction)
        OutlinedButton.icon(
          key: const ValueKey<String>('search_result_batch_save_button'),
          onPressed: controller.saveCurrentListLyrics,
          icon: Icon(
            state.isBatchSaving
                ? Icons.close_rounded
                : Icons.library_music_outlined,
          ),
          label: Text(
            state.isBatchSaving
                ? strings.text(SearchUiTextKey.saveListLyricsCancel)
                : strings.text(SearchUiTextKey.saveListLyrics),
          ),
        ),
      if (!isExpanded)
        IconButton.filledTonal(
          key: const ValueKey<String>('search_result_open_preview_button'),
          onPressed:
              state.currentLyrics != null ||
                  state.previewPhase == SearchPreviewPhase.loading
              ? () async {
                  await onOpenPreviewSheet();
                }
              : null,
          icon: const Icon(Icons.lyrics_outlined),
          tooltip: strings.text(SearchUiTextKey.previewTitle),
        ),
    ];
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.topRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int index = 0; index < actions.length; index += 1) ...<Widget>[
              if (index > 0) const SizedBox(width: 8),
              actions[index],
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchResultStatus extends StatelessWidget {
  const _SearchResultStatus({
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.showProgress = false,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool dense = constraints.maxHeight < 160;
        final Widget content = Padding(
          padding: EdgeInsets.all(dense ? 8 : 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: dense ? 24 : 30,
                  color: colorScheme.onSurfaceVariant,
                ),
                SizedBox(height: dense ? 4 : 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: dense
                      ? Theme.of(context).textTheme.bodyMedium
                      : Theme.of(context).textTheme.titleMedium,
                ),
                if (!dense &&
                    description != null &&
                    description!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    description!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (showProgress) ...<Widget>[
                  SizedBox(height: dense ? 8 : 16),
                  SizedBox(
                    width: dense ? 120 : 160,
                    child: const LinearProgressIndicator(),
                  ),
                ],
                if (action != null) ...<Widget>[
                  SizedBox(height: dense ? 8 : 16),
                  action!,
                ],
              ],
            ),
          ),
        );
        // 极端短高度下允许状态内容自身滚动，避免一个临时 loading/error
        // 状态撑破整个结果卡；结果到达后会立即替换为虚拟化列表。
        return Center(
          child: constraints.maxHeight < 88
              ? SingleChildScrollView(child: content)
              : content,
        );
      },
    );
  }
}

String? _searchTableStatusText(SearchUiStrings strings, String? message) {
  if (message == null || message.isEmpty) {
    return null;
  }
  final (String code, String? detail) = SearchTableStatusMessage.decode(
    message,
  );
  return switch (code) {
    SearchTableStatusMessageCode.autoFetching => strings.text(
      SearchUiTextKey.tableStatusAutoFetching,
    ),
    SearchTableStatusMessageCode.searching => strings.text(
      SearchUiTextKey.tableStatusSearching,
    ),
    SearchTableStatusMessageCode.fetchingSongList => strings.text(
      SearchUiTextKey.tableStatusFetchingSongList,
    ),
    SearchTableStatusMessageCode.noResults => strings.text(
      SearchUiTextKey.tableStatusNoResults,
    ),
    SearchTableStatusMessageCode.emptyList => strings.text(
      SearchUiTextKey.tableStatusEmptyList,
    ),
    SearchTableStatusMessageCode.unsupportedSearchType => strings.text(
      SearchUiTextKey.tableStatusUnsupportedSearchType,
    ),
    SearchTableStatusMessageCode.searchFailed =>
      detail == null || detail.isEmpty
          ? strings.text(SearchUiTextKey.tableStatusSearchFailed)
          : strings.text(
              SearchUiTextKey.tableStatusSearchFailedWithDetail,
              arguments: SearchUiTextArguments(detail: detail),
            ),
    SearchTableStatusMessageCode.autoFetchFailed => strings.text(
      SearchUiTextKey.tableStatusAutoFetchFailed,
      arguments: SearchUiTextArguments(detail: detail ?? ''),
    ),
    SearchTableStatusMessageCode.songListFailed => strings.text(
      SearchUiTextKey.tableStatusSongListFailed,
      arguments: SearchUiTextArguments(detail: detail ?? ''),
    ),
    SearchTableStatusMessageCode.partialSourceUnavailable => strings.text(
      SearchUiTextKey.tableStatusPartialSourceUnavailable,
    ),
    SearchTableStatusMessageCode.loadMoreFailed => strings.text(
      SearchUiTextKey.tableStatusLoadMoreFailed,
    ),
    _ => message,
  };
}

class _SearchMusicResultRow extends StatelessWidget {
  const _SearchMusicResultRow({
    required this.row,
    required this.strings,
    required this.index,
    required this.showSource,
    required this.selected,
    required this.onTap,
  });

  final SourceAware row;
  final SearchUiStrings strings;
  final int index;
  final bool showSource;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String title = _rowTitle(row);
    final String subtitle = _rowSubtitle(strings, row);
    final String meta = _rowMeta(row);
    final Widget cover = _SearchRowCover(row: row);
    final String sourceLabel = strings.sourceLabel(row.source);

    return InkWell(
      key: ValueKey<String>('search_result_row_$index'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
              : null,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 34,
              child: Text(
                '${index + 1}'.padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            cover,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title.isEmpty ? '-' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.isEmpty ? sourceLabel : subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (showSource)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  label: Text(sourceLabel),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            SizedBox(
              width: 88,
              child: Text(
                meta,
                maxLines: 1,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchRowCover extends StatelessWidget {
  const _SearchRowCover({required this.row});

  final SourceAware row;

  @override
  Widget build(BuildContext context) {
    const BorderRadius radius = BorderRadius.all(Radius.circular(8));
    final String? coverUrl = switch (row) {
      SongInfo value when value.imgUrl?.trim().isNotEmpty ?? false =>
        value.imgUrl,
      SongListInfo value when value.imgUrl.trim().isNotEmpty => value.imgUrl,
      _ => null,
    };
    if (coverUrl != null) {
      return ClipRRect(
        borderRadius: radius,
        child: SearchCoverNetworkImage(
          url: coverUrl,
          source: row.source,
          errorFallback: _SearchCoverPlaceholder(row: row),
        ),
      );
    }
    return _SearchCoverPlaceholder(row: row);
  }
}

class _SearchCoverPlaceholder extends StatelessWidget {
  const _SearchCoverPlaceholder({required this.row});

  final SourceAware row;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (row) {
      SongInfo _ => Icons.music_note_rounded,
      SongListInfo value when value.type == SongListType.album =>
        Icons.album_rounded,
      SongListInfo _ => Icons.queue_music_rounded,
      LyricInfo _ => Icons.lyrics_outlined,
      _ => Icons.music_note_rounded,
    };
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFB1C9BC), Color(0xFF87A59A)],
        ),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

String _rowTitle(SourceAware row) {
  return switch (row) {
    SongInfo value => value.fullTitle,
    SongListInfo value => value.title,
    LyricInfo value =>
      value.songInfo.fullTitle.isNotEmpty
          ? value.songInfo.fullTitle
          : (value.id ?? ''),
    _ => '',
  };
}

String _rowSubtitle(SearchUiStrings strings, SourceAware row) {
  return switch (row) {
    SongInfo value =>
      value.album != null && value.album!.trim().isNotEmpty
          ? '${value.artistText} · ${value.album}'
          : value.artistText,
    SongListInfo value =>
      '${value.author} · ${strings.text(SearchUiTextKey.tableSongCount, arguments: SearchUiTextArguments(count: value.songCount ?? 0))}',
    LyricInfo value => value.songInfo.artistText,
    _ => '',
  };
}

String _rowMeta(SourceAware row) {
  return switch (row) {
    SongInfo value => value.formattedDuration,
    SongListInfo value => value.formattedPublishTime,
    LyricInfo value => value.formattedDuration,
    _ => '',
  };
}
