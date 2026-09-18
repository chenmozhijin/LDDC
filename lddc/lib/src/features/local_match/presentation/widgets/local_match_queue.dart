import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../../../../shared/ui/components/components.dart';
import '../../application/local_match_page_controller.dart';
import '../../application/local_match_page_state.dart';
import 'local_match_bottom_and_helpers.dart';
import 'local_match_rules.dart';

// 队列区使用 select 订阅最外层列表状态，具体行内容通过 queueRevisionListenable
// 获取快照。这样进度文本、规则控件等变化不会无意义重建整个列表。
class LocalMatchQueueCard extends ConsumerWidget {
  const LocalMatchQueueCard({
    super.key,
    required this.controller,
    required this.desktopMode,
    required this.showEmbeddedStatusSummary,
  });

  final LocalMatchPageController controller;
  final bool desktopMode;
  final bool showEmbeddedStatusSummary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (
      int queueLength,
      bool isSelectionMode,
      Set<String> selectedItemIds,
      bool isDesktopMode,
      bool isAndroidMode,
      bool scanCompletedWithoutMatch,
    ) = ref.watch(
      localMatchPageControllerProvider.select((LocalMatchPageState state) {
        return (
          state.queueItems.length,
          state.isSelectionMode,
          state.selectedItemIds,
          state.isDesktopMode,
          state.isAndroidMode,
          state.scanCompletedWithoutMatch,
        );
      }),
    );
    final int selectedCount = selectedItemIds.length;
    final bool allSelected = queueLength > 0 && selectedCount == queueLength;
    return Card(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // 旧断点在 411 x 914 的手机上刚好启用约 240 px 高的状态摘要，留给队列的
          // 高度不足并产生纵向溢出。摘要并非队列操作的必要条件，只在确实有足够空间
          // 同时容纳标题、摘要和可操作列表时显示；更窄的视口仍可从运行按钮查看状态。
          final bool showStatusSummary =
              showEmbeddedStatusSummary && constraints.maxHeight >= 480;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (isSelectionMode)
                  LocalMatchBulkSelectionToolbar(
                    selectedCount: selectedCount,
                    selectedItemIds: selectedItemIds,
                    hasQueue: queueLength > 0,
                    isDesktopMode: isDesktopMode,
                    controller: controller,
                    allSelected: allSelected,
                  )
                else
                  LocalMatchQueueHeader(
                    queueLength: queueLength,
                    desktopMode: desktopMode,
                    isAndroidMode: isAndroidMode,
                    scanCompletedWithoutMatch: scanCompletedWithoutMatch,
                    controller: controller,
                  ),
                if (showStatusSummary) ...<Widget>[
                  const SizedBox(height: 12),
                  Consumer(
                    builder:
                        (BuildContext context, WidgetRef ref, Widget? child) {
                          final LocalMatchPageState state = ref.watch(
                            localMatchPageControllerProvider,
                          );
                          return LocalMatchCompactQueueStatusSummary(
                            state: state,
                          );
                        },
                  ),
                ],
                const SizedBox(height: 12),
                if (queueLength == 0)
                  Expanded(
                    child: Center(
                      child: EmptyState(
                        message: localMatchEmptyQueueHint(
                          context,
                          scanCompletedWithoutMatch: scanCompletedWithoutMatch,
                          isAndroidMode: isAndroidMode,
                        ),
                      ),
                    ),
                  )
                else if (desktopMode)
                  Expanded(
                    child: LocalMatchDesktopQueueList(
                      controller: controller,
                      isSelectionMode: isSelectionMode,
                    ),
                  )
                else
                  Expanded(
                    child: LocalMatchMobileQueueList(
                      controller: controller,
                      isSelectionMode: isSelectionMode,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class LocalMatchDesktopQueueList extends StatelessWidget {
  const LocalMatchDesktopQueueList({
    super.key,
    required this.controller,
    required this.isSelectionMode,
  });

  final LocalMatchPageController controller;
  final bool isSelectionMode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: controller.queueOrderListenable,
      builder: (BuildContext context, List<String> order, Widget? child) {
        return ListView.separated(
          key: const ValueKey<String>('local_match_queue_list'),
          itemCount: order.length,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (BuildContext context, int index) {
            return LocalMatchQueueRowCard(
              itemId: order[index],
              controller: controller,
              desktopMode: true,
              isSelectionMode: isSelectionMode,
            );
          },
        );
      },
    );
  }
}

class LocalMatchMobileQueueList extends StatelessWidget {
  const LocalMatchMobileQueueList({
    super.key,
    required this.controller,
    required this.isSelectionMode,
  });

  final LocalMatchPageController controller;
  final bool isSelectionMode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: controller.queueOrderListenable,
      builder: (BuildContext context, List<String> order, Widget? child) {
        return ListView.separated(
          key: const ValueKey<String>('local_match_queue_list'),
          itemCount: order.length,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (BuildContext context, int index) {
            return LocalMatchQueueRowCard(
              itemId: order[index],
              controller: controller,
              desktopMode: false,
              isSelectionMode: isSelectionMode,
            );
          },
        );
      },
    );
  }
}

class LocalMatchQueueRowCard extends StatefulWidget {
  const LocalMatchQueueRowCard({
    super.key,
    required this.itemId,
    required this.controller,
    required this.desktopMode,
    required this.isSelectionMode,
  });

  final String itemId;
  final LocalMatchPageController controller;
  final bool desktopMode;
  final bool isSelectionMode;

  @override
  State<LocalMatchQueueRowCard> createState() => LocalMatchQueueRowCardState();
}

class LocalMatchQueueRowCardState extends State<LocalMatchQueueRowCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final TaskQueueBinding<LocalMatchQueueItem>? binding = widget.controller
        .queueBinding(widget.itemId);
    if (binding == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<LocalMatchQueueItem>(
      valueListenable: binding.itemListenable,
      builder: (BuildContext context, LocalMatchQueueItem item, Widget? child) {
        return ValueListenableBuilder<bool>(
          valueListenable: binding.selectedListenable,
          builder: (BuildContext context, bool selected, Widget? child) {
            return ValueListenableBuilder<bool>(
              valueListenable: binding.focusedListenable,
              builder: (BuildContext context, bool focused, Widget? child) {
                final LocalMatchPageController controller = widget.controller;
                final ColorScheme colorScheme = Theme.of(context).colorScheme;
                // 安卓端保存结果是编码 URI：用当前已知的授权树标签还原成可读层级路径。
                final LocalMatchAndroidTreeLabels androidLabels =
                    LocalMatchAndroidTreeLabels.of(controller.currentState);
                final String lyricsPath = localMatchQueueItemDisplayLyricsPath(
                  context,
                  item,
                  androidLabels: androidLabels,
                );
                // 源文件路径在安卓端也是编码 URI（content://…%2F…）：
                // 与歌词路径一起还原成可读层级路径，同一行不能出现两种风格。
                final String songPathText = androidLabels.formatPath(
                  item.songInfo.path,
                );
                final String songPathDisplay = songPathText.isEmpty
                    ? '-'
                    : songPathText;
                final String? failureSummary =
                    localMatchQueueItemFailureSummary(
                      context,
                      item,
                      androidLabels: androidLabels,
                    );
                return RepaintBoundary(
                  child: Material(
                    color: selected
                        ? colorScheme.secondaryContainer
                        : (focused
                              ? colorScheme.surfaceContainerHigh
                              : colorScheme.surfaceContainerLowest),
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onSecondaryTapDown:
                          widget.desktopMode && !widget.isSelectionMode
                          ? (TapDownDetails details) {
                              controller.focusItem(item.id);
                              _showDesktopRowMenu(
                                context,
                                details.globalPosition,
                                item,
                                controller,
                                widget.isSelectionMode,
                              );
                            }
                          : null,
                      child: InkWell(
                        key: ValueKey<String>(
                          'local_match_queue_row_${item.id}',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          if (widget.isSelectionMode) {
                            controller.toggleItemSelected(item.id);
                            return;
                          }
                          controller.focusItem(item.id);
                        },
                        onLongPress: () async {
                          if (widget.isSelectionMode) {
                            controller.toggleItemSelected(item.id);
                            return;
                          }
                          if (!widget.desktopMode) {
                            controller.focusItem(item.id);
                            await _showMobileRowActionsSheet(
                              context,
                              item,
                              controller,
                              widget.isSelectionMode,
                            );
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.all(widget.desktopMode ? 14 : 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (widget.isSelectionMode)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Checkbox(
                                        value: selected,
                                        onChanged: (_) => controller
                                            .toggleItemSelected(item.id),
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      localMatchSongTitle(context, item),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  LocalMatchStatusChip(status: item.lastStatus),
                                  if (!widget.desktopMode &&
                                      !widget.isSelectionMode) ...<Widget>[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      key: ValueKey<String>(
                                        'local_match_row_more_${item.id}',
                                      ),
                                      icon: const Icon(Icons.more_vert_rounded),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () async {
                                        controller.focusItem(item.id);
                                        await _showMobileRowActionsSheet(
                                          context,
                                          item,
                                          controller,
                                          widget.isSelectionMode,
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      localMatchArtistAlbumSubtitle(item),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 72,
                                    child: Text(
                                      localMatchDurationLabel(
                                        context,
                                        item.songInfo,
                                      ),
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (_expanded) ...<Widget>[
                                QueueExpandedPathBlock(
                                  key: ValueKey<String>(
                                    'local_match_path_song_${item.id}',
                                  ),
                                  label: context.l10n.localMatchSongPathLabel,
                                  fullText: songPathDisplay,
                                ),
                                const SizedBox(height: 10),
                                QueueExpandedPathBlock(
                                  key: ValueKey<String>(
                                    'local_match_path_lyrics_${item.id}',
                                  ),
                                  label: context.l10n.localMatchLyricsPathLabel,
                                  fullText: lyricsPath,
                                ),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(
                                      child: QueuePathPreview(
                                        key: ValueKey<String>(
                                          'local_match_path_song_${item.id}',
                                        ),
                                        label: context
                                            .l10n
                                            .localMatchSongPathLabel,
                                        value: songPathDisplay,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: QueuePathPreview(
                                        key: ValueKey<String>(
                                          'local_match_path_lyrics_${item.id}',
                                        ),
                                        label: context
                                            .l10n
                                            .localMatchLyricsPathLabel,
                                        value: lyricsPath,
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  key: ValueKey<String>(
                                    'local_match_expand_row_${item.id}',
                                  ),
                                  tooltip: _expanded
                                      ? context.l10n.localMatchCollapseDetails
                                      : context.l10n.localMatchExpandDetails,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    controller.focusItem(item.id);
                                    setState(() {
                                      _expanded = !_expanded;
                                    });
                                  },
                                  icon: Icon(
                                    _expanded
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                  ),
                                ),
                              ),
                              if (failureSummary
                                  case final String summary) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(
                                  summary,
                                  maxLines: _expanded ? null : 1,
                                  overflow: _expanded
                                      ? null
                                      : TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: colorScheme.error),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

Future<void> _showDesktopRowMenu(
  BuildContext context,
  Offset globalPosition,
  LocalMatchQueueItem item,
  LocalMatchPageController controller,
  bool isSelectionMode,
) async {
  final OverlayState? overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    return;
  }
  final RenderBox overlayBox = overlay.context.findRenderObject()! as RenderBox;
  final String? action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      Offset.zero & overlayBox.size,
    ),
    items: localMatchRowActions(
      context,
      item,
      isSelectionMode,
    ).map(_desktopPopupAction).toList(growable: false),
  );
  await _handleRowAction(action, item, controller);
}

PopupMenuEntry<String> _desktopPopupAction(LocalMatchRowAction action) {
  return PopupMenuItem<String>(
    value: action.value,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(action.icon, size: 18),
        const SizedBox(width: 10),
        Text(action.label),
      ],
    ),
  );
}

Future<void> _showMobileRowActionsSheet(
  BuildContext context,
  LocalMatchQueueItem item,
  LocalMatchPageController controller,
  bool isSelectionMode,
) async {
  final String? action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: localMatchRowActions(context, item, isSelectionMode)
              .map((LocalMatchRowAction action) {
                return ListTile(
                  leading: Icon(action.icon),
                  title: Text(action.label),
                  onTap: () => Navigator.of(context).pop(action.value),
                );
              })
              .toList(growable: false),
        ),
      );
    },
  );
  await _handleRowAction(action, item, controller);
}

Future<void> _handleRowAction(
  String? action,
  LocalMatchQueueItem item,
  LocalMatchPageController controller,
) async {
  switch (action) {
    case 'songDir':
      await controller.openSongDirectory(item.id);
      return;
    case 'saveDir':
      await controller.openSaveDirectory(item.id);
      return;
    case 'lyricsFile':
      await controller.openLyricsFile(item.id);
      return;
    case 'search':
      await controller.openInSearch(item.id);
      return;
    case 'selectMode':
      controller.enterSelectionMode(item.id);
      return;
    case null:
      return;
  }
}

class LocalMatchStatusChip extends StatelessWidget {
  const LocalMatchStatusChip({super.key, required this.status});

  final LocalMatchingStatus? status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final (String label, Color background, Color foreground) value =
        switch (status?.type) {
          LocalMatchingStatusType.success => (
            context.l10n.commonSuccess,
            colorScheme.primaryContainer,
            colorScheme.onPrimaryContainer,
          ),
          LocalMatchingStatusType.skipInst ||
          LocalMatchingStatusType.skipExisting => (
            context.l10n.commonSkipped,
            colorScheme.secondaryContainer,
            colorScheme.onSecondaryContainer,
          ),
          LocalMatchingStatusType.autoFetchFail ||
          LocalMatchingStatusType.saveFail ||
          LocalMatchingStatusType.unknownError => (
            context.l10n.commonFailed,
            colorScheme.errorContainer,
            colorScheme.onErrorContainer,
          ),
          null => (
            context.l10n.localMatchStatusNotStarted,
            colorScheme.surfaceContainerHighest,
            colorScheme.onSurface,
          ),
        };
    return Chip(
      label: Text(value.$1, style: TextStyle(color: value.$3)),
      backgroundColor: value.$2,
      side: BorderSide.none,
    );
  }
}

/// 扫描/匹配失败明细面板。
///
/// 这些错误过去只存在于 controller state 里，没有任何渲染出口：用户可以"扫描完成
/// 但队列是空的"，却看不到任何原因（设计文档《Android 本地匹配专项设计》§9 要求
/// 显示失败明细，§10 要求失败不静默）。面板自身订阅 provider，无错误时渲染为空，
/// 因此各布局只需放一个 const 调用。
///
/// 条数上限由 controller 强制为最近 20 条，明细列表不随目录规模增长，不存在无界内存。
class LocalMatchErrorDetailsPanel extends ConsumerWidget {
  const LocalMatchErrorDetailsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (
      List<String> errors,
      AndroidSafTreeToken? songTreeToken,
      AndroidSafTreeToken? saveTreeToken,
    ) = ref.watch(
      localMatchPageControllerProvider.select((LocalMatchPageState state) {
        return (
          state.recentErrors,
          state.androidTreeToken,
          state.androidSaveTreeToken,
        );
      }),
    );
    if (errors.isEmpty) {
      return const SizedBox.shrink();
    }
    // 错误原文来自原生，里面嵌的是编码 URI；这里换成可读层级路径，
    // 否则用户看到一长串 `content://…%2F…` 完全无法定位文件。
    final LocalMatchAndroidTreeLabels androidLabels =
        LocalMatchAndroidTreeLabels.fromTokens(
          songTreeToken: songTreeToken,
          saveTreeToken: saveTreeToken,
        );
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    // 面板自带下间距：无错误时整块消失（含间距），布局方只需放一个 const 调用，
    // 不需要额外判断是否存在明细。
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: const ValueKey<String>('local_match_error_details'),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExpansionTile(
          dense: true,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: colorScheme.onErrorContainer,
          collapsedIconColor: colorScheme.onErrorContainer,
          leading: Icon(
            Icons.error_outline,
            color: colorScheme.onErrorContainer,
          ),
          title: Text(
            context.l10n.localMatchErrorDetailsTitle(errors.length),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: <Widget>[
            for (final String error in errors)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    androidLabels.humanize(error),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
