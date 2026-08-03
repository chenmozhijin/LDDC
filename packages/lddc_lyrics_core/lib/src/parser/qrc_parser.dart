import 'dart:convert';

import '../models/models.dart';
import 'lrc_parser.dart';
import 'lyrics_parser_port.dart';
import 'parser_utils.dart';
import 'timed_word_parser.dart';

final RegExp _qrcPattern = RegExp(
  r'<Lyric_1 LyricType="1" LyricContent="(.*?)"/>',
  dotAll: true,
);
final RegExp _tagSplitPattern = RegExp(r'^\[(\w+):([^\]]*)\]$');
final RegExp _lineSplitPattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
final RegExp _wordSplitPattern = RegExp(
  r'(?:\[\d+,\d+\])?((?:(?!\(\d+,\d+\)).)*)\((\d+),(\d+)\)',
);
final RegExp _wordTimestampPattern = RegExp(r'^\(\d+,\d+\)$');

/// 迁移Python版 `QRC_MAGICHEADER` 常量。
const List<int> qrcMagicHeader = <int>[
  0x98,
  0x25,
  0xB0,
  0xAC,
  0xE3,
  0x02,
  0x83,
  0x68,
  0xE8,
  0xFC,
  0x6C,
];

/// 迁移Python版 `qrc2data` + `qrc_str_parse`：统一返回单语言歌词数据。
({Map<String, String> tags, LyricsData lyricsData}) parseQrcString(
  String lyric,
) {
  final RegExpMatch? qrcMatch = _qrcPattern.firstMatch(lyric);
  if (qrcMatch != null && qrcMatch.group(1) != null) {
    final Map<String, String> tags = <String, String>{};
    final LyricsData lyricsData = <LyricsLine>[];
    final List<String> lines = const LineSplitter().convert(qrcMatch.group(1)!);

    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      final RegExpMatch? lineMatch = _lineSplitPattern.firstMatch(line);
      if (lineMatch != null) {
        final int lineStart = int.parse(lineMatch.group(1)!);
        final int lineEnd = lineStart + int.parse(lineMatch.group(2)!);
        final String lineContent = lineMatch.group(3) ?? '';
        final List<LyricsWord> words = parseDurationWords(
          content: lineContent,
          pattern: _wordSplitPattern,
          startGroup: 2,
          durationGroup: 3,
          textGroup: 1,
          skipCarriageReturnText: true,
        );
        lyricsData.add(
          buildTimedLyricsLine(
            lineStartMs: lineStart,
            lineEndMs: lineEnd,
            content: lineContent,
            words: words,
            emptyTimestampPattern: _wordTimestampPattern,
          ),
        );
        continue;
      }

      final RegExpMatch? tagMatch = _tagSplitPattern.firstMatch(line);
      if (tagMatch != null) {
        tags[tagMatch.group(1)!] = tagMatch.group(2) ?? '';
      }
    }

    return (tags: tags, lyricsData: lyricsData);
  }

  if (lyric.contains('[') && lyric.contains(']')) {
    try {
      return parseLrcToData(lyric);
    } catch (_) {
      // 对齐Python版：LRC 解析失败时回退为纯文本。
    }
  }

  return (tags: <String, String>{}, lyricsData: plaintextToData(lyric));
}

ParsedLyricsPayload parseQrcToMultiResult(String lyric) {
  final ({Map<String, String> tags, LyricsData lyricsData}) parsed =
      parseQrcString(lyric);
  return ParsedLyricsPayload(
    tags: parsed.tags,
    lyricsData: <String, LyricsData>{'orig': parsed.lyricsData},
  );
}
