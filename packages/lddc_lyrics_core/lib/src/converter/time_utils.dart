import '../models/models.dart';

/// 毫秒拆解结果：小时、分钟、秒、毫秒。
typedef TimeParts = (int hours, int minutes, int seconds, int millis);

/// 对齐Python版 `common/time.py::get_divmod_time`。
TimeParts getDivmodTime(int ms) {
  // 歌词模型层在应用 offset 时已经会把负时间夹到 0；
  // 这里仍做一次自保，避免测试或工具函数被直接调用时导出非法负时间戳。
  final int safeMs = ms < 0 ? 0 : ms;
  final int totalSeconds = safeMs ~/ 1000;
  final int millis = safeMs % 1000;
  final int hours = totalSeconds ~/ 3600;
  final int remainder = totalSeconds % 3600;
  final int minutes = remainder ~/ 60;
  final int seconds = remainder % 60;
  return (hours, minutes, seconds, millis);
}

/// 对齐Python版 `common/time.py::ms2formattime`（三位毫秒）。
String msToFormatTime(int ms) {
  final TimeParts parts = getDivmodTime(ms);
  final int totalMinutes = parts.$1 * 60 + parts.$2;
  return '${totalMinutes.toString().padLeft(2, '0')}:${parts.$3.toString().padLeft(2, '0')}.${parts.$4.toString().padLeft(3, '0')}';
}

/// 对齐Python版 `common/time.py::ms2roundedtime`（四舍五入到两位毫秒）。
String msToRoundedTime(int ms) {
  final int roundedTotalMs = ((ms / 10).round()) * 10;
  final TimeParts parts = getDivmodTime(roundedTotalMs);
  final int totalMinutes = parts.$1 * 60 + parts.$2;
  final int twoDigitMs = parts.$4 ~/ 10;
  return '${totalMinutes.toString().padLeft(2, '0')}:${parts.$3.toString().padLeft(2, '0')}.${twoDigitMs.toString().padLeft(2, '0')}';
}

/// 对齐Python版 `converter/ass.py::ms2ass_timestamp`。
String msToAssTimestamp(int ms) {
  final int safeMs = ms < 0 ? 0 : ms;
  final int totalCentis = (safeMs / 10).round();
  final int centis = totalCentis % 100;
  final int totalSeconds = totalCentis ~/ 100;
  final int hours = totalSeconds ~/ 3600;
  final int remainder = totalSeconds % 3600;
  final int minutes = remainder ~/ 60;
  final int seconds = remainder % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${centis.toString().padLeft(2, '0')}';
}

/// 对齐Python版 `converter/srt.py::ms2srt_timestamp`。
String msToSrtTimestamp(int ms) {
  final TimeParts parts = getDivmodTime(ms);
  return '${parts.$1.toString().padLeft(2, '0')}:${parts.$2.toString().padLeft(2, '0')}:${parts.$3.toString().padLeft(2, '0')},${parts.$4.toString().padLeft(3, '0')}';
}

/// 对齐Python版 `common/models/_lyrics.py::get_full_timestamps_lyrics_data`。
LyricsData getFullTimestampsLyricsData(
  LyricsData data, {
  int? durationMs,
  bool onlyLine = false,
  bool skipNone = false,
}) {
  final LyricsData result = <LyricsLine>[];

  for (int i = 0; i < data.length; i += 1) {
    final LyricsLine line = data[i];

    int? lineStart =
        line.startMs ?? (line.words.isEmpty ? null : line.words.first.startMs);
    int? lineEnd =
        line.endMs ?? (line.words.isEmpty ? null : line.words.last.endMs);

    // 与Python版保持一致：回看上一行使用原始数据，不使用本轮推导结果。
    lineStart ??= i == 0 ? 0 : data[i - 1].endMs;

    if (lineEnd == null) {
      if (i == data.length - 1) {
        if (durationMs != null &&
            lineStart != null &&
            durationMs >= lineStart) {
          lineEnd = durationMs;
        }
      } else {
        lineEnd = data[i + 1].startMs;
      }
    }

    if (onlyLine) {
      if (!skipNone || (lineStart != null && lineEnd != null)) {
        result.add(
          LyricsLine(startMs: lineStart, endMs: lineEnd, words: line.words),
        );
      }
      continue;
    }

    final List<LyricsWord> words = <LyricsWord>[];
    for (int j = 0; j < line.words.length; j += 1) {
      final LyricsWord word = line.words[j];
      final int? wordStart =
          word.startMs ?? (j == 0 ? lineStart : line.words[j - 1].endMs);
      final int? wordEnd =
          word.endMs ??
          (j == line.words.length - 1 ? lineEnd : line.words[j + 1].startMs);

      if (skipNone && (wordStart == null || wordEnd == null)) {
        continue;
      }
      words.add(
        LyricsWord(startMs: wordStart, endMs: wordEnd, text: word.text),
      );
    }

    if (!skipNone || (lineStart != null && lineEnd != null)) {
      result.add(LyricsLine(startMs: lineStart, endMs: lineEnd, words: words));
    }
  }

  return result;
}
