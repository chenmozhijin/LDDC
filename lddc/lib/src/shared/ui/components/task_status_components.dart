import 'package:flutter/material.dart';

import 'adaptive_path_text.dart';

/// 任务类页面复用的统计徽章。
///
/// 这里只展示 label/value/icon，不绑定任何业务状态；批量转换、本地匹配等页面
/// 仍然由各自 controller 计算统计值，避免共享组件反向依赖具体业务模型。
final class TaskMetricBadge extends StatelessWidget {
  const TaskMetricBadge({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(width: 8),
          Text('$value', style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// 任务进度状态卡片。
///
/// 页面负责传入阶段文案和统计组件；本组件只复用“说明 + 进度条 + 统计区”的
/// 布局。这样可以减少重复 UI 代码，又不会把不同任务的状态枚举硬合并到一起。
final class TaskProgressStatusCard extends StatelessWidget {
  const TaskProgressStatusCard({
    super.key,
    this.cardKey,
    required this.title,
    required this.detail,
    required this.progress,
    required this.metrics,
    this.pipelineLabel,
    this.dense = false,
  });

  final Key? cardKey;
  final String title;
  final String detail;
  final double? progress;
  final Widget metrics;
  final String? pipelineLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: cardKey,
      child: Padding(
        padding: EdgeInsets.all(dense ? 12 : 16),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool stacked = constraints.maxWidth < 980;
            final Widget info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
            final Widget progressBar = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                ),
                if (pipelineLabel != null &&
                    pipelineLabel!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    pipelineLabel!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  info,
                  const SizedBox(height: 12),
                  progressBar,
                  const SizedBox(height: 12),
                  metrics,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(flex: 24, child: info),
                const SizedBox(width: 16),
                Expanded(flex: 38, child: progressBar),
                const SizedBox(width: 16),
                Expanded(
                  flex: 38,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: metrics,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 队列行折叠状态下的路径摘要。
final class QueuePathPreview extends StatelessWidget {
  const QueuePathPreview({
    super.key,
    required this.label,
    required this.value,
    this.style,
  });

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final String resolved = value.trim().isEmpty ? '-' : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(width: 8),
        Expanded(
          child: AdaptivePathText(
            fullPath: resolved,
            emptyText: '-',
            style:
                style ??
                Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

/// 队列行展开状态下的完整路径文本。
final class QueueExpandedPathBlock extends StatelessWidget {
  const QueueExpandedPathBlock({
    super.key,
    required this.label,
    required this.fullText,
  });

  final String label;
  final String fullText;

  @override
  Widget build(BuildContext context) {
    final String value = fullText.trim().isEmpty ? '-' : fullText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectionArea(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 轻量提示条，用于设置/规则区域里不需要 Snackbar 的静态说明。
///
/// 说明文字允许自然换行，避免窄屏或系统大字号把关键规则截成省略号。容器高度
/// 随文字增加，由外层页面正常参与滚动，不使用固定高度隐藏内容。
final class TonalInlineNotice extends StatelessWidget {
  const TonalInlineNotice({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
