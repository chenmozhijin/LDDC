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
    super.key,
  });

  final BatchConvertStatusView view;
  final BatchConvertPageController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final double? progress = view.progressTotal > 0
        ? view.progressCurrent / view.progressTotal
        : (view.isBusy ? null : 0);
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
