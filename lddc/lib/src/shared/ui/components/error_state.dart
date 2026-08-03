import 'package:flutter/material.dart';

/// 错误态组件。
final class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.retryLabel,
    this.onRetry,
  });

  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, color: colorScheme.error, size: 28),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colorScheme.error),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null && retryLabel != null) ...<Widget>[
              const SizedBox(height: 10),
              OutlinedButton(onPressed: onRetry, child: Text(retryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
