import 'package:collection/collection.dart';

/// 某一语言的歌词行集合。
typedef LyricsData = List<LyricsLine>;

/// 多语言歌词集合，key 为语言标识（如 `orig/ts/roma`）。
typedef MultiLyricsData = Map<String, LyricsData>;

/// 单词级歌词片段。
class LyricsWord {
  const LyricsWord({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int? startMs;
  final int? endMs;
  final String text;

  /// 统一给时间戳加偏移，缺失时间戳保持为空。
  LyricsWord withOffset(int offsetMs) {
    return LyricsWord(
      startMs: _adjustTimestamp(startMs, offsetMs),
      endMs: _adjustTimestamp(endMs, offsetMs),
      text: text,
    );
  }

  static int? _adjustTimestamp(int? value, int offsetMs) {
    if (value == null) {
      return null;
    }
    return (value + offsetMs).clamp(0, 2147483647);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LyricsWord &&
            startMs == other.startMs &&
            endMs == other.endMs &&
            text == other.text);
  }

  @override
  int get hashCode => Object.hash(startMs, endMs, text);
}

/// 行级歌词片段。
class LyricsLine {
  LyricsLine({
    required this.startMs,
    required this.endMs,
    required List<LyricsWord> words,
  }) : words = List<LyricsWord>.unmodifiable(words);

  final int? startMs;
  final int? endMs;
  final List<LyricsWord> words;

  /// 将该行所有词拼接为纯文本。
  String get text => words.map((LyricsWord word) => word.text).join();

  /// 给行/词统一加偏移。
  LyricsLine withOffset(int offsetMs) {
    return LyricsLine(
      startMs: LyricsWord._adjustTimestamp(startMs, offsetMs),
      endMs: LyricsWord._adjustTimestamp(endMs, offsetMs),
      words: words.map((LyricsWord word) => word.withOffset(offsetMs)).toList(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LyricsLine &&
            startMs == other.startMs &&
            endMs == other.endMs &&
            const ListEquality<LyricsWord>().equals(words, other.words));
  }

  @override
  int get hashCode => Object.hash(startMs, endMs, Object.hashAll(words));
}

/// 逐字播放进度：字符索引 + 该字符内进度比例。
class CharProgress {
  const CharProgress({required this.charIndex, required this.charRatio})
    : assert(charIndex >= 0),
      assert(charRatio >= 0 && charRatio <= 1);

  final int charIndex;
  final double charRatio;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CharProgress &&
            charIndex == other.charIndex &&
            charRatio == other.charRatio);
  }

  @override
  int get hashCode => Object.hash(charIndex, charRatio);
}
