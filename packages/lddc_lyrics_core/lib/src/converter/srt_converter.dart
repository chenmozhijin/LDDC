import '../models/models.dart';
import 'share.dart';
import 'time_utils.dart';

/// 对齐Python版 `converter/srt.py::srt_converter`。
String srtConverter({
  required MultiLyricsData lyricsData,
  required Map<String, Map<int, int>> langsMapping,
  required List<String> langsOrder,
  required int? durationMs,
}) {
  final LyricsData? origLyrics = lyricsData['orig'];
  if (origLyrics == null || origLyrics.isEmpty) {
    return '';
  }

  final int? resolvedDuration =
      durationMs ??
      (origLyrics.last.startMs == null
          ? null
          : origLyrics.last.startMs! + 5000);
  final LyricsData fullOrigLyrics = getFullTimestampsLyricsData(
    origLyrics,
    durationMs: resolvedDuration,
    onlyLine: true,
  );

  final StringBuffer buffer = StringBuffer();
  int sequence = 1;
  for (int origIndex = 0; origIndex < fullOrigLyrics.length; origIndex += 1) {
    final LyricsLine origLine = fullOrigLyrics[origIndex];
    final int? start = origLine.startMs;
    final int? end = origLine.endMs;
    if (start == null || end == null || end < start) {
      continue;
    }
    final List<ConverterLyricsLine> lines = getLyricsLines(
      lyricsData: lyricsData,
      langsOrder: langsOrder,
      origIndex: origIndex,
      origLine: origLine,
      langsMapping: langsMapping,
    );
    if (lines.isEmpty) {
      continue;
    }
    buffer
      ..write('$sequence\n')
      ..write('${msToSrtTimestamp(start)} --> ${msToSrtTimestamp(end)}\n');
    sequence += 1;

    for (final ConverterLyricsLine line in lines) {
      buffer.write('${joinLineText(line.line, includeEmpty: false)}\n');
    }
    buffer.write('\n');
  }
  return buffer.toString();
}
