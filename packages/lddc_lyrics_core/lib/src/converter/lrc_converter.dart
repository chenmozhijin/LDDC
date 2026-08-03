import '../models/models.dart';
import 'share.dart';
import 'time_utils.dart';

typedef MillisFormatter = String Function(int ms);

/// 对齐Python版 `converter/lrc.py::formattime_sub1`。
String formatTimeSub1(String formatTime) {
  final List<String> minuteAndSecond = formatTime.split(':');
  final List<String> secondAndMillis = minuteAndSecond[1].split('.');
  final int minute = int.parse(minuteAndSecond[0]);
  final int second = int.parse(secondAndMillis[0]);
  final String fraction = secondAndMillis[1];
  final int fractionDigits = fraction.length;
  final int scale = fractionDigits == 2 ? 10 : 1;
  final int totalMs =
      ((minute * 60 + second) * 1000) + int.parse(fraction) * scale;
  final int adjustedMs = totalMs - scale < 0 ? 0 : totalMs - scale;
  final int adjustedMinute = adjustedMs ~/ 60000;
  final int adjustedSecond = (adjustedMs % 60000) ~/ 1000;
  final int adjustedFraction = (adjustedMs % 1000) ~/ scale;
  return '${adjustedMinute.toString().padLeft(2, '0')}:'
      '${adjustedSecond.toString().padLeft(2, '0')}.'
      '${adjustedFraction.toString().padLeft(fractionDigits, '0')}';
}

/// 对齐Python版 `converter/lrc.py::lyrics_line2str`。
String lyricsLineToLrcString(
  LyricsLine lyricsLine,
  LyricsFormat lyricsFormat, {
  int? lineStartTime,
  int? lineEndTime,
  MillisFormatter msConverter = msToFormatTime,
}) {
  lineStartTime ??= lyricsLine.startMs;
  lineEndTime = lyricsLine.endMs ?? lineEndTime;

  final StringBuffer buffer = StringBuffer();
  bool endsWithTimestamp = false;
  if (lineStartTime != null) {
    buffer.write('[${msConverter(lineStartTime)}]');
    endsWithTimestamp = true;
  }

  if (lyricsFormat == LyricsFormat.lineByLineLrc) {
    buffer.write(joinLineText(lyricsLine, includeEmpty: false));
    return buffer.toString();
  }

  late final (String, String) symbols;
  if (lyricsFormat == LyricsFormat.verbatimLrc) {
    symbols = ('[', ']');
  } else {
    symbols = ('<', '>');
  }

  int? lastEnd = lyricsFormat == LyricsFormat.verbatimLrc
      ? lyricsLine.startMs
      : null;

  for (final LyricsWord word in lyricsLine.words) {
    final int? start = word.startMs;
    final int? end = word.endMs;
    if (start != null && start != lastEnd) {
      final int effectiveStart = _isTruthyInt(lineStartTime)
          ? lineStartTime!
          : start;
      final int stamp = start > effectiveStart ? start : effectiveStart;
      buffer.write('${symbols.$1}${msConverter(stamp)}${symbols.$2}');
      endsWithTimestamp = true;
    }

    if (word.text.isNotEmpty) {
      buffer.write(word.text);
      endsWithTimestamp = false;
    }

    if (end != null) {
      buffer.write('${symbols.$1}${msConverter(end)}${symbols.$2}');
      endsWithTimestamp = true;
    }
    lastEnd = end;
  }

  if (lineEndTime != null && !endsWithTimestamp) {
    buffer.write('${symbols.$1}${msConverter(lineEndTime)}${symbols.$2}');
  }
  return buffer.toString();
}

/// 对齐Python版 `converter/lrc.py::lrc_converter`。
String lrcConverter({
  required Map<String, String> tags,
  required MultiLyricsData lyricsData,
  required LyricsFormat lyricsFormat,
  required Map<String, Map<int, int>> langsMapping,
  required List<String> langsOrder,
  required int lrcMsDigitCount,
  required bool addEndTimestampLine,
  required int lastRefLineTimeStyle,
  required String lddcVersion,
}) {
  final MillisFormatter msConverter = lrcMsDigitCount == 2
      ? msToRoundedTime
      : msToFormatTime;

  final StringBuffer buffer = StringBuffer();
  if (tags.isNotEmpty) {
    bool wroteTag = false;
    for (final MapEntry<String, String> entry in tags.entries) {
      if ((entry.key == 'al' ||
              entry.key == 'ar' ||
              entry.key == 'au' ||
              entry.key == 'by' ||
              entry.key == 'offset' ||
              entry.key == 'ti') &&
          entry.value.isNotEmpty) {
        buffer.write('[${entry.key}:${entry.value}]\n');
        wroteTag = true;
      }
    }
    if (!wroteTag) {
      buffer.write('\n');
    }
    buffer.write(
      '[tool:LDDC $lddcVersion https://github.com/chenmozhijin/LDDC]',
    );
    buffer.write('\n\n');
  }

  final LyricsData? origLyrics = lyricsData['orig'];
  if (origLyrics == null) {
    return buffer.toString();
  }

  for (int origIndex = 0; origIndex < origLyrics.length; origIndex += 1) {
    final LyricsLine origLine = origLyrics[origIndex];
    final int? lineStartTime =
        origLine.words.isNotEmpty && origLine.words.first.startMs != null
        ? origLine.words.first.startMs
        : origLine.startMs;
    final int? lineEndTime =
        origLine.words.isNotEmpty && origLine.words.last.endMs != null
        ? origLine.words.last.endMs
        : origLine.endMs;

    for (final ConverterLyricsLine item in getLyricsLines(
      lyricsData: lyricsData,
      langsOrder: langsOrder,
      origIndex: origIndex,
      origLine: origLine,
      langsMapping: langsMapping,
      lastRefLineTimeStyle: lastRefLineTimeStyle,
    )) {
      if (!item.lastSub1) {
        buffer.write(
          lyricsLineToLrcString(
            item.line,
            lyricsFormat,
            lineStartTime: lineStartTime,
            lineEndTime: lineEndTime,
            msConverter: msConverter,
          ),
        );
        buffer.write('\n');
        continue;
      }

      final int? tsSub1StartTime;
      if (origIndex + 1 < origLyrics.length) {
        final LyricsLine nextLine = origLyrics[origIndex + 1];
        tsSub1StartTime =
            nextLine.words.isNotEmpty && nextLine.words.first.startMs != null
            ? nextLine.words.first.startMs
            : nextLine.startMs;
      } else if (_isTruthyInt(lineEndTime)) {
        tsSub1StartTime = lineEndTime! + 10;
      } else if (_isTruthyInt(lineStartTime)) {
        tsSub1StartTime = lineStartTime! + 10;
      } else {
        tsSub1StartTime = null;
      }

      final String tsSub1 = tsSub1StartTime == null
          ? ''
          : formatTimeSub1(msConverter(tsSub1StartTime));
      if (tsSub1.isNotEmpty) {
        buffer.write('[$tsSub1]');
      }
      buffer.write(joinLineText(item.line, includeEmpty: false));
      if (tsSub1.isNotEmpty && lyricsFormat == LyricsFormat.verbatimLrc) {
        buffer.write('[$tsSub1]');
      } else if (tsSub1.isNotEmpty &&
          lyricsFormat == LyricsFormat.enhancedLrc) {
        buffer.write('<$tsSub1>');
      }
      buffer.write('\n');
    }

    final bool isLastLine = origIndex == origLyrics.length - 1;
    final int? nextStart = isLastLine
        ? null
        : origLyrics[origIndex + 1].startMs;
    if (lyricsFormat == LyricsFormat.lineByLineLrc &&
        addEndTimestampLine &&
        lineEndTime != null &&
        (isLastLine || nextStart != lineEndTime)) {
      buffer.write('[${msConverter(lineEndTime)}]\n');
    }
  }

  return buffer.toString();
}

bool _isTruthyInt(int? value) {
  return value != null && value != 0;
}
