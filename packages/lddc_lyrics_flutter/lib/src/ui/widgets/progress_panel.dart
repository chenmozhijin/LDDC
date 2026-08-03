import 'package:flutter/material.dart';

/// 通用任务进度面板。
final class ProgressPanel extends StatelessWidget {
  const ProgressPanel({
    super.key,
    required this.title,
    required this.currentValue,
    required this.maxValue,
    this.statusText,
  });

  final String title;
  final int currentValue;
  final int maxValue;
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    final double? progress = maxValue > 0
        ? (currentValue / maxValue).clamp(0.0, 1.0)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('$currentValue / $maxValue'),
            if (statusText != null && statusText!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(statusText!),
            ],
          ],
        ),
      ),
    );
  }
}
