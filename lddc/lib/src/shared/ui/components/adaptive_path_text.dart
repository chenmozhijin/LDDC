import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

final class AdaptivePathText extends StatelessWidget {
  const AdaptivePathText({
    super.key,
    required this.fullPath,
    required this.emptyText,
    this.style,
  });

  final String? fullPath;
  final String emptyText;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final String normalized = fullPath?.trim() ?? '';
    final bool hasPath = normalized.isNotEmpty;
    final String tooltipText = hasPath ? normalized : emptyText;
    final TextStyle effectiveStyle =
        style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final String displayText = hasPath
            ? _summarizePathForWidth(
                normalized,
                maxWidth: constraints.maxWidth,
                style: effectiveStyle,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )
            : emptyText;
        return Tooltip(
          message: tooltipText,
          child: Text(
            displayText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: effectiveStyle,
          ),
        );
      },
    );
  }
}

String _summarizePathForWidth(
  String value, {
  required double maxWidth,
  required TextStyle style,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final String normalized = value.trim();
  if (normalized.isEmpty || !maxWidth.isFinite || maxWidth <= 0) {
    return normalized;
  }
  if (_fitsText(
    normalized,
    maxWidth: maxWidth,
    style: style,
    textDirection: textDirection,
    textScaler: textScaler,
  )) {
    return normalized;
  }
  final String root = p.rootPrefix(normalized);
  final String separator = normalized.contains('\\') ? '\\' : '/';
  final String rest = root.isEmpty
      ? normalized
      : normalized.substring(root.length);
  final List<String> segments = rest
      .split(RegExp(r'[\\/]+'))
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
  final int tailSegments = segments.length >= 2 ? 2 : 1;
  if (segments.length > tailSegments) {
    for (
      int headSegments = segments.length - tailSegments - 1;
      headSegments >= 0;
      headSegments -= 1
    ) {
      final String candidate = _buildPathSummaryCandidate(
        root: root,
        headSegments: segments.take(headSegments).toList(growable: false),
        tailSegments: segments
            .skip(segments.length - tailSegments)
            .toList(growable: false),
        separator: separator,
      );
      if (_fitsText(
        candidate,
        maxWidth: maxWidth,
        style: style,
        textDirection: textDirection,
        textScaler: textScaler,
      )) {
        return candidate;
      }
    }
  }
  return _characterMiddleEllipsisForWidth(
    normalized,
    maxWidth: maxWidth,
    style: style,
    textDirection: textDirection,
    textScaler: textScaler,
  );
}

String _buildPathSummaryCandidate({
  required String root,
  required List<String> headSegments,
  required List<String> tailSegments,
  required String separator,
}) {
  final String head = _composePathHead(root, headSegments, separator);
  final String tail = tailSegments.join(separator);
  return switch ((head.isEmpty, tail.isEmpty)) {
    (true, true) => '...',
    (true, false) => '...$separator$tail',
    (false, true) => '$head$separator...',
    (false, false) => '$head$separator...$separator$tail',
  };
}

String _composePathHead(
  String root,
  List<String> headSegments,
  String separator,
) {
  if (headSegments.isEmpty) {
    return root;
  }
  final String joined = headSegments.join(separator);
  if (root.isEmpty) {
    return joined;
  }
  if (root.endsWith('\\') || root.endsWith('/')) {
    return '$root$joined';
  }
  return '$root$separator$joined';
}

String _characterMiddleEllipsisForWidth(
  String value, {
  required double maxWidth,
  required TextStyle style,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  if (value.isEmpty) {
    return value;
  }
  const String ellipsis = '...';
  if (!_fitsText(
    ellipsis,
    maxWidth: maxWidth,
    style: style,
    textDirection: textDirection,
    textScaler: textScaler,
  )) {
    return ellipsis;
  }
  int low = 0;
  final Characters graphemes = value.characters;
  int high = graphemes.length;
  String best = ellipsis;
  while (low <= high) {
    final int preservedChars = (low + high) ~/ 2;
    final String candidate = _characterMiddleEllipsis(
      value,
      preservedChars: preservedChars,
    );
    if (_fitsText(
      candidate,
      maxWidth: maxWidth,
      style: style,
      textDirection: textDirection,
      textScaler: textScaler,
    )) {
      best = candidate;
      low = preservedChars + 1;
    } else {
      high = preservedChars - 1;
    }
  }
  return best;
}

String _characterMiddleEllipsis(String value, {required int preservedChars}) {
  if (preservedChars <= 0) {
    return '...';
  }
  final Characters graphemes = value.characters;
  if (preservedChars >= graphemes.length) {
    return value;
  }
  final int head = (preservedChars / 2).ceil();
  final int tail = preservedChars - head;
  if (tail <= 0) {
    return '${graphemes.take(head)}...';
  }
  return '${graphemes.take(head)}...${graphemes.skip(graphemes.length - tail)}';
}

bool _fitsText(
  String value, {
  required double maxWidth,
  required TextStyle style,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: value, style: style),
    maxLines: 1,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: double.infinity);
  return painter.width <= maxWidth + 0.5;
}
