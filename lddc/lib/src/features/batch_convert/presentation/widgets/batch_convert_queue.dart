import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../../../../shared/ui/components/components.dart';
import '../../application/batch_convert_page_controller.dart';
import '../../application/batch_convert_page_state.dart';
import 'batch_convert_presentation_helpers.dart';

// 队列组件只订阅列表展示所需的最小字段，具体转换状态仍由 controller 维护。
// 行级列表通过 queueRevisionListenable 取快照，可以避免每次进度文本变化都重建整张列表。
class BatchConvertQueueCard extends ConsumerWidget {
  const BatchConvertQueueCard({
    super.key,
    required this.controller,
    required this.compact,
    this.selectedItemId,
    this.onSelectItem,
  });

  final BatchConvertPageController controller;
  final bool compact;
  final String? selectedItemId;
  final ValueChanged<String>? onSelectItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final (
      int queueLength,
      LyricsFormat targetFormat,
      bool showErrorState,
      String? errorMessage,
      bool showEmptyState,
      bool isBusy,
    ) = ref.watch(
      batchConvertPageControllerProvider.select((BatchConvertPageState state) {
        return (
          state.queueItems.length,
          state.targetFormat,
          state.showErrorState,
          state.errorMessage,
          state.showEmptyState,
          state.isBusy,
        );
      }),
    );
    return Card(
      key: const ValueKey<String>('batch_convert_queue_card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.batchConvertQueueTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.batchConvertQueueSubtitle(
                          queueLength,
                          l10n.lyricsFormatLabel(targetFormat),
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildBody(
              context,
              queueLength: queueLength,
              showErrorState: showErrorState,
              errorMessage: errorMessage,
              showEmptyState: showEmptyState,
              isBusy: isBusy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required int queueLength,
    required bool showErrorState,
    required String? errorMessage,
    required bool showEmptyState,
    required bool isBusy,
  }) {
    if (showErrorState) {
      return ErrorState(
        message: errorMessage ?? context.l10n.batchConvertPageErrorFallback,
        retryLabel: context.l10n.batchConvertRetryImport,
      );
    }
    if (showEmptyState) {
      // 队列卡片给 body 的是整块紧约束；显式居中后，空态图标和文案会围绕
      // 可用队列区域居中，而不是被内部 Column 的默认起始对齐推到顶部。
      return Center(
        key: const ValueKey<String>('batch_convert_queue_empty_center'),
        child: EmptyState(message: context.l10n.batchConvertEmptyQueue),
      );
    }
    return ValueListenableBuilder<List<String>>(
      valueListenable: controller.queueOrderListenable,
      builder: (BuildContext context, List<String> order, Widget? child) {
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          scrollCacheExtent: const ScrollCacheExtent.pixels(1000),
          itemCount: order.length,
          itemBuilder: (BuildContext context, int index) {
            final String itemId = order[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _QueueItemCard(
                itemId: itemId,
                controller: controller,
                compact: compact,
                busy: isBusy,
                selected: selectedItemId == itemId,
                onSelected: onSelectItem == null
                    ? null
                    : () => onSelectItem!(itemId),
              ),
            );
          },
        );
      },
    );
  }
}

class _QueueItemCard extends StatelessWidget {
  const _QueueItemCard({
    required this.itemId,
    required this.controller,
    required this.compact,
    required this.busy,
    required this.selected,
    this.onSelected,
  });

  final String itemId;
  final BatchConvertPageController controller;
  final bool compact;
  final bool busy;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final TaskQueueBinding<BatchConvertQueueItem>? binding = controller
        .queueBinding(itemId);
    if (binding == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<BatchConvertQueueItem>(
      valueListenable: binding.itemListenable,
      builder: (BuildContext context, BatchConvertQueueItem item, Widget? child) {
        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        return RepaintBoundary(
          child: InkWell(
            key: ValueKey<String>('batch_convert_queue_row_${item.id}'),
            onTap: onSelected,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.secondaryContainer
                    : colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? colorScheme.secondary
                      : colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: <Widget>[
                                  _StatusChip(status: item.status),
                                  if (item.shortMessage != null &&
                                      !item.shortMessage!.isEmpty)
                                    Text(
                                      batchConvertProgressMessageText(
                                        context,
                                        item.shortMessage!,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color:
                                                item.status ==
                                                    BatchConvertQueueItemStatus
                                                        .failure
                                                ? colorScheme.error
                                                : null,
                                          ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _QueueItemMenu(
                          item: item,
                          controller: controller,
                          busy: busy,
                          compact: compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    QueuePathPreview(
                      label: context.l10n.batchConvertOutputPathLabel,
                      value: item.targetPath,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final BatchConvertQueueItemStatus status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final (
      Color background,
      Color foreground,
      IconData icon,
      String label,
    ) = switch (status) {
      BatchConvertQueueItemStatus.waiting => (
        colorScheme.surfaceContainerHigh,
        colorScheme.onSurface,
        Icons.hourglass_empty_outlined,
        l10n.batchConvertQueueStatusWaiting,
      ),
      BatchConvertQueueItemStatus.running => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
        Icons.sync_outlined,
        l10n.batchConvertQueueStatusRunning,
      ),
      BatchConvertQueueItemStatus.success => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        Icons.task_alt_outlined,
        l10n.batchConvertQueueStatusSuccess,
      ),
      BatchConvertQueueItemStatus.failure => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        Icons.error_outline,
        l10n.batchConvertQueueStatusFailure,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: foreground)),
          ],
        ),
      ),
    );
  }
}

enum _QueueItemAction {
  delete,
  openSourceDirectory,
  openSaveDirectory,
  openOutputFile,
  openInOpenLyrics,
}

class _QueueItemMenu extends StatelessWidget {
  const _QueueItemMenu({
    required this.item,
    required this.controller,
    required this.busy,
    required this.compact,
  });

  final BatchConvertQueueItem item;
  final BatchConvertPageController controller;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool canOpenOutput =
        item.status == BatchConvertQueueItemStatus.success;
    final l10n = context.l10n;
    return PopupMenuButton<_QueueItemAction>(
      tooltip: l10n.batchConvertMoreActions,
      onSelected: (_QueueItemAction action) async {
        switch (action) {
          case _QueueItemAction.delete:
            controller.removeQueueItem(item.id);
            break;
          case _QueueItemAction.openSourceDirectory:
            await controller.openSourceDirectory(item.id);
            break;
          case _QueueItemAction.openSaveDirectory:
            await controller.openSaveDirectory(item.id);
            break;
          case _QueueItemAction.openOutputFile:
            await controller.openOutputFile(item.id);
            break;
          case _QueueItemAction.openInOpenLyrics:
            await controller.openInOpenLyrics(item.id);
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_QueueItemAction>>[
        if (!busy)
          PopupMenuItem<_QueueItemAction>(
            value: _QueueItemAction.delete,
            child: ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.commonDelete),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem<_QueueItemAction>(
          value: _QueueItemAction.openSourceDirectory,
          child: ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(l10n.batchConvertActionOpenSourceDirectory),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_QueueItemAction>(
          value: _QueueItemAction.openSaveDirectory,
          child: ListTile(
            leading: const Icon(Icons.drive_folder_upload_outlined),
            title: Text(l10n.batchConvertActionOpenSaveDirectory),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canOpenOutput)
          PopupMenuItem<_QueueItemAction>(
            value: _QueueItemAction.openOutputFile,
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.batchConvertActionOpenOutputFile),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canOpenOutput)
          PopupMenuItem<_QueueItemAction>(
            value: _QueueItemAction.openInOpenLyrics,
            child: ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: Text(l10n.batchConvertActionOpenInOpenLyrics),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
      icon: Icon(compact ? Icons.more_horiz : Icons.more_vert),
    );
  }
}
