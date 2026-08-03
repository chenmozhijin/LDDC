import 'dart:math' as math;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

enum DesktopLyricsSlotFocusKind { previous, current, next }

class DesktopLyricsSlotWindow<T> {
  const DesktopLyricsSlotWindow({
    required this.entry,
    required this.focusKind,
    required this.intervalMs,
    required this.lineStartMs,
    required this.lineEndMs,
  });

  final T entry;
  final DesktopLyricsSlotFocusKind focusKind;
  final int intervalMs;
  final int lineStartMs;
  final int lineEndMs;
}

DesktopLyricsSlotWindow<T>? resolveDesktopLyricsSlotWindow<T>({
  required List<T> entries,
  required int currentTimeMs,
  required int durationMs,
  required int? Function(T entry) resolveLineStartMs,
  required int? Function(T entry) resolveLineEndMs,
}) {
  T? previousEntry;
  T? currentEntry;
  T? nextEntry;
  int? previousEndMs;
  int? currentStartMs;
  int? currentEndMs;
  int? nextStartMs;
  int? nextEndMs;

  for (final T entry in entries) {
    final int? lineStartMs = resolveLineStartMs(entry);
    final int? lineEndMs = resolveLineEndMs(entry);
    if (lineStartMs == null || lineEndMs == null) {
      continue;
    }

    if (lineEndMs < currentTimeMs) {
      previousEntry = entry;
      previousEndMs = lineEndMs;
    } else if (lineStartMs <= currentTimeMs && currentTimeMs <= lineEndMs) {
      currentEntry = entry;
      currentStartMs = lineStartMs;
      currentEndMs = lineEndMs;
    } else if (lineStartMs > currentTimeMs) {
      nextEntry = entry;
      nextStartMs = lineStartMs;
      nextEndMs = lineEndMs;
      break;
    }
  }

  if (currentEntry != null && currentStartMs != null && currentEndMs != null) {
    return DesktopLyricsSlotWindow<T>(
      entry: currentEntry,
      focusKind: DesktopLyricsSlotFocusKind.current,
      intervalMs: 0,
      lineStartMs: currentStartMs,
      lineEndMs: currentEndMs,
    );
  }

  if (previousEntry != null &&
      previousEndMs != null &&
      nextEntry != null &&
      nextStartMs != null &&
      nextEndMs != null) {
    final int intervalMs = math.max((nextStartMs - previousEndMs) ~/ 2, 0);
    if ((currentTimeMs - previousEndMs).abs() <
        (nextStartMs - currentTimeMs).abs()) {
      return DesktopLyricsSlotWindow<T>(
        entry: previousEntry,
        focusKind: DesktopLyricsSlotFocusKind.previous,
        intervalMs: intervalMs,
        lineStartMs: resolveLineStartMs(previousEntry) ?? 0,
        lineEndMs: previousEndMs,
      );
    }
    return DesktopLyricsSlotWindow<T>(
      entry: nextEntry,
      focusKind: DesktopLyricsSlotFocusKind.next,
      intervalMs: intervalMs,
      lineStartMs: nextStartMs,
      lineEndMs: nextEndMs,
    );
  }

  if (previousEntry != null && previousEndMs != null) {
    return DesktopLyricsSlotWindow<T>(
      entry: previousEntry,
      focusKind: DesktopLyricsSlotFocusKind.previous,
      intervalMs: math.max(durationMs - previousEndMs, 0),
      lineStartMs: resolveLineStartMs(previousEntry) ?? 0,
      lineEndMs: previousEndMs,
    );
  }

  if (nextEntry != null && nextStartMs != null && nextEndMs != null) {
    return DesktopLyricsSlotWindow<T>(
      entry: nextEntry,
      focusKind: DesktopLyricsSlotFocusKind.next,
      intervalMs: math.max(nextStartMs, 0),
      lineStartMs: nextStartMs,
      lineEndMs: nextEndMs,
    );
  }

  return null;
}

double computeDesktopLyricsSlotOpacity<T>({
  required DesktopLyricsSlotWindow<T> slotWindow,
  required int currentTimeMs,
  required int track,
}) {
  if (slotWindow.focusKind == DesktopLyricsSlotFocusKind.current) {
    return 1.0;
  }

  const int maxFadeTimeMs = 10000;
  final int intervalMs = track != 0
      ? math.min(slotWindow.intervalMs, maxFadeTimeMs)
      : slotWindow.intervalMs;
  if (intervalMs == 0) {
    return 1.0;
  }

  int alpha = 255;
  if (slotWindow.focusKind == DesktopLyricsSlotFocusKind.previous) {
    final int fadeTimeMs = track != 0
        ? math.min(currentTimeMs - slotWindow.lineEndMs, maxFadeTimeMs)
        : currentTimeMs - slotWindow.lineEndMs;
    alpha = 255 - ((fadeTimeMs / intervalMs) * 255).toInt();
  } else if (slotWindow.focusKind == DesktopLyricsSlotFocusKind.next) {
    final int fadeTimeMs = track != 0
        ? math.min(slotWindow.lineStartMs - currentTimeMs, maxFadeTimeMs)
        : slotWindow.lineStartMs - currentTimeMs;
    alpha = 255 - ((fadeTimeMs / intervalMs) * 255).toInt();
  }

  return alpha.clamp(0, 255) / 255.0;
}

int? resolveDesktopLyricsTransitionStartMs<T>(
  DesktopLyricsSlotWindow<T> slotWindow,
) {
  return switch (slotWindow.focusKind) {
    DesktopLyricsSlotFocusKind.current => null,
    DesktopLyricsSlotFocusKind.previous => slotWindow.lineEndMs,
    DesktopLyricsSlotFocusKind.next =>
      slotWindow.lineStartMs - slotWindow.intervalMs,
  };
}

int? resolveDesktopLyricsTransitionEndMs<T>(
  DesktopLyricsSlotWindow<T> slotWindow,
) {
  return switch (slotWindow.focusKind) {
    DesktopLyricsSlotFocusKind.current => null,
    DesktopLyricsSlotFocusKind.previous =>
      slotWindow.lineEndMs + slotWindow.intervalMs,
    DesktopLyricsSlotFocusKind.next => slotWindow.lineStartMs,
  };
}

int? resolveDesktopLyricsLineStartMs(LyricsLine line) {
  if (line.startMs != null) {
    return line.startMs;
  }
  if (line.words.isNotEmpty) {
    return line.words.first.startMs;
  }
  return null;
}

int? resolveDesktopLyricsLineEndMs(LyricsLine line) {
  if (line.endMs != null) {
    return line.endMs;
  }
  if (line.words.isNotEmpty) {
    return line.words.last.endMs;
  }
  return null;
}

int? resolveDesktopLyricsWordStartMs(LyricsLine line, int wordIndex) {
  final LyricsWord word = line.words[wordIndex];
  if (word.startMs != null) {
    return word.startMs;
  }
  if (wordIndex == 0) {
    return resolveDesktopLyricsLineStartMs(line);
  }
  return line.words[wordIndex - 1].endMs;
}

int? resolveDesktopLyricsWordEndMs(LyricsLine line, int wordIndex) {
  final LyricsWord word = line.words[wordIndex];
  if (word.endMs != null) {
    return word.endMs;
  }
  if (wordIndex == line.words.length - 1) {
    return resolveDesktopLyricsLineEndMs(line);
  }
  return line.words[wordIndex + 1].startMs;
}

bool shouldUseDesktopLineLevelWordPlan(LyricsLine line) {
  if (line.words.length <= 1) {
    return true;
  }
  final int? lineStartMs = resolveDesktopLyricsLineStartMs(line);
  final int? lineEndMs = resolveDesktopLyricsLineEndMs(line);
  if (lineStartMs == null || lineEndMs == null) {
    return false;
  }
  for (int index = 0; index < line.words.length; index += 1) {
    final int? startMs = resolveDesktopLyricsWordStartMs(line, index);
    final int? endMs = resolveDesktopLyricsWordEndMs(line, index);
    if (startMs == null || endMs == null) {
      continue;
    }
    if ((index == 0 && startMs != lineStartMs) ||
        (index == line.words.length - 1 && endMs != lineEndMs) ||
        (index > 0 && startMs != lineStartMs) ||
        (index < line.words.length - 1 && endMs != lineEndMs)) {
      return false;
    }
  }
  return true;
}
