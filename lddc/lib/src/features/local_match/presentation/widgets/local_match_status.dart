import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../shared/ui/components/components.dart';
import '../../application/local_match_page_state.dart';
import 'local_match_bottom_and_helpers.dart';

class LocalMatchStatusStrip extends StatelessWidget {
  const LocalMatchStatusStrip({
    super.key,
    required this.state,
    this.dense = false,
  });

  final LocalMatchPageState state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final double? progress = state.progressTotal > 0
        ? state.progressCurrent / state.progressTotal
        : (state.isBusy ? null : 0);
    return TaskProgressStatusCard(
      cardKey: const ValueKey<String>('local_match_status_strip'),
      title: localMatchPhaseLabel(context, state.taskPhase),
      detail:
          '${state.progressCurrent} / ${state.progressTotal} · ${localMatchProgressMessageText(context, state)}',
      progress: progress,
      pipelineLabel: dense
          ? null
          : localMatchPhasePipelineLabel(context, state.taskPhase),
      dense: dense,
      metrics: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: <Widget>[
          TaskMetricBadge(
            label: context.l10n.commonTotal,
            value: state.totalCount,
            icon: Icons.queue_music_outlined,
          ),
          TaskMetricBadge(
            label: context.l10n.commonSuccess,
            value: state.successCount,
            icon: Icons.check_circle_outline,
          ),
          TaskMetricBadge(
            label: context.l10n.commonSkipped,
            value: state.skipCount,
            icon: Icons.fast_forward_outlined,
          ),
          TaskMetricBadge(
            label: context.l10n.commonFailed,
            value: state.failCount,
            icon: Icons.error_outline,
          ),
        ],
      ),
    );
  }
}
