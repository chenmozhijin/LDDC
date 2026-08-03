import '../models/models.dart';

/// 从逐字歌词片段中解析 `start + duration` 结构。
///
/// QRC/KRC/YRC 的外层标签、语言扩展和加密入口不同，但词级时间都可以归一为：
/// 起始时间 + 持续时间 = 结束时间。把这段逻辑放到一个 helper 里，后续修时间边界时
/// 不需要在三个 parser 里各改一遍。
List<LyricsWord> parseDurationWords({
  required String content,
  required RegExp pattern,
  required int startGroup,
  required int durationGroup,
  required int textGroup,
  int baseStartMs = 0,
  bool skipCarriageReturnText = false,
}) {
  final List<LyricsWord> words = <LyricsWord>[];
  for (final RegExpMatch match in pattern.allMatches(content)) {
    final String text = match.group(textGroup) ?? '';
    if (skipCarriageReturnText && text == '\r') {
      continue;
    }
    final int startMs = baseStartMs + int.parse(match.group(startGroup)!);
    final int durationMs = int.parse(match.group(durationGroup)!);
    words.add(
      LyricsWord(startMs: startMs, endMs: startMs + durationMs, text: text),
    );
  }
  return words;
}

/// 构造带行时间的歌词行；没有词级时间时回退为整行文本。
LyricsLine buildTimedLyricsLine({
  required int lineStartMs,
  required int lineEndMs,
  required String content,
  required List<LyricsWord> words,
  RegExp? emptyTimestampPattern,
}) {
  if (emptyTimestampPattern != null &&
      content.startsWith('(') &&
      content.endsWith(')') &&
      emptyTimestampPattern.hasMatch(content)) {
    return LyricsLine(startMs: lineStartMs, endMs: lineEndMs, words: const []);
  }

  if (words.isEmpty) {
    return LyricsLine(
      startMs: lineStartMs,
      endMs: lineEndMs,
      words: <LyricsWord>[
        LyricsWord(startMs: lineStartMs, endMs: lineEndMs, text: content),
      ],
    );
  }

  return LyricsLine(startMs: lineStartMs, endMs: lineEndMs, words: words);
}
