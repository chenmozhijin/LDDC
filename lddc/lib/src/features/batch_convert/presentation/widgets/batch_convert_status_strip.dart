import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../shared/ui/components/components.dart';
import '../../application/batch_convert_page_controller.dart';
import '../../application/batch_convert_page_state.dart';
import 'batch_convert_presentation_helpers.dart';

class BatchConvertStatusStrip extends StatelessWidget {
  const BatchConvertStatusStrip({
    required this.view,
    required this.controller,
    this.compact = false,
    super.key,
  });

  final BatchConvertStatusView view;
  final BatchConvertPageController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final double? progress = view.progressTotal > 0
        ? view.progressCurrent / view.progressTotal
        : (view.isBusy ? null : 0);
    if (compact) {
      // 横屏手机和窄桌面的高度比宽度更紧张。紧凑状态条保留阶段、进度
      // 与详细文本，但不重复展示队列已经提供的四组徽章，避免固定状态区
      // 把中间工作区压缩到无法操作。
      return Card(
        key: const ValueKey<String>('batch_convert_status_strip'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${batchConvertPhaseLabel(context, view.taskPhase)} · '
                  '${view.progressCurrent} / ${view.progressTotal} · '
                  '${view.progressMessage.isEmpty ? batchConvertPhaseHint(context, view) : batchConvertProgressMessageText(context, view.progressMessage)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return TaskProgressStatusCard(
      cardKey: const ValueKey<String>('batch_convert_status_strip'),
      title: batchConvertPhaseLabel(context, view.taskPhase),
      detail:
          '${view.progressCurrent} / ${view.progressTotal} · ${view.progressMessage.isEmpty ? batchConvertPhaseHint(context, view) : batchConvertProgressMessageText(context, view.progressMessage)}',
      progress: progress,
      pipelineLabel: batchConvertPhasePipelineLabel(context, view.taskPhase),
      metrics: ValueListenableBuilder<int>(
        valueListenable: controller.queueRevisionListenable,
        builder: (BuildContext context, int revision, Widget? child) {
          final List<BatchConvertQueueItem> items = controller.queueSnapshot;
          final int successCount = items
              .where(
                (BatchConvertQueueItem item) =>
                    item.status == BatchConvertQueueItemStatus.success,
              )
              .length;
          final int failureCount = items
              .where(
                (BatchConvertQueueItem item) =>
                    item.status == BatchConvertQueueItemStatus.failure,
              )
              .length;
          final int waitingCount = items
              .where(
                (BatchConvertQueueItem item) =>
                    item.status == BatchConvertQueueItemStatus.waiting,
              )
              .length;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: <Widget>[
              TaskMetricBadge(
                label: l10n.commonTotal,
                value: items.length,
                icon: Icons.queue_music_outlined,
              ),
              TaskMetricBadge(
                label: l10n.commonSuccess,
                value: successCount,
                icon: Icons.check_circle_outline,
              ),
              TaskMetricBadge(
                label: l10n.commonFailed,
                value: failureCount,
                icon: Icons.error_outline,
              ),
              TaskMetricBadge(
                label: l10n.batchConvertMetricWaiting,
                value: waitingCount,
                icon: Icons.schedule_outlined,
              ),
            ],
          );
        },
      ),
    );
  }
}
