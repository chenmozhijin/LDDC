import 'dart:convert';

import '../error/error.dart';
import '../models/models.dart';
import 'lyrics_parser_port.dart';
import 'timed_word_parser.dart';

final RegExp _tagSplitPattern = RegExp(r'^\[(\w+):([^\]]*)\]$');
final RegExp _lineSplitPattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
final RegExp _wordSplitPattern = RegExp(
  r'(?:\[\d+,\d+\])?<(\d+),(\d+),\d+>((?:.(?!\d+,\d+,\d+>))*)',
);

/// 迁移Python版 `KRC_MAGICHEADER` 常量。
const List<int> krcMagicHeader = <int>[0x6B, 0x72, 0x63, 0x31, 0x38];

ParsedLyricsPayload parseKrcToMultiResult(String krc) {
  final Map<String, String> tags = <String, String>{};
  final LyricsData origList = <LyricsLine>[];
  final LyricsData romaList = <LyricsLine>[];
  final LyricsData tsList = <LyricsLine>[];

  for (final String rawLine in const LineSplitter().convert(krc)) {
    final String line = rawLine.trim();
    if (!line.startsWith('[')) {
      continue;
    }

    final RegExpMatch? tagMatch = _tagSplitPattern.firstMatch(line);
    if (tagMatch != null) {
      tags[tagMatch.group(1)!] = tagMatch.group(2) ?? '';
      continue;
    }

    final RegExpMatch? lineMatch = _lineSplitPattern.firstMatch(line);
    if (lineMatch == null) {
      continue;
    }

    final int lineStart = int.parse(lineMatch.group(1)!);
    final int lineEnd = lineStart + int.parse(lineMatch.group(2)!);
    final String lineContent = lineMatch.group(3) ?? '';

    final List<LyricsWord> words = parseDurationWords(
      content: lineContent,
      pattern: _wordSplitPattern,
      startGroup: 1,
      durationGroup: 2,
      textGroup: 3,
      baseStartMs: lineStart,
    );
    origList.add(
      buildTimedLyricsLine(
        lineStartMs: lineStart,
        lineEndMs: lineEnd,
        content: lineContent,
        words: words,
      ),
    );
  }

  final String? languageTag = tags['language'];
  if (languageTag != null && languageTag.trim().isNotEmpty) {
    for (final dynamic language in _decodeLanguageContent(languageTag)) {
      if (language is! Map<String, dynamic>) {
        continue;
      }
      final int? type = _asInt(language['type']);
      final dynamic rawLyricContent = language['lyricContent'];
      if (type == null) {
        continue;
      }
      if (rawLyricContent is! List<dynamic>) {
        throw const LddcLyricsFormatException('KRC language 标签格式错误');
      }
      final List<dynamic> lyricContent = rawLyricContent;

      if (type == 0) {
        int offset = 0;
        for (int i = 0; i < origList.length; i += 1) {
          final LyricsLine line = origList[i];
          if (line.words.every((LyricsWord word) => word.text.isEmpty)) {
            offset += 1;
            continue;
          }

          final int rowIndex = i - offset;
          if (rowIndex < 0 ||
              rowIndex >= lyricContent.length ||
              lyricContent[rowIndex] is! List<dynamic>) {
            throw const LddcLyricsFormatException('KRC 罗马音行数与原文不一致');
          }
          final List<dynamic> row = lyricContent[rowIndex] as List<dynamic>;
          if (row.length < line.words.length) {
            throw const LddcLyricsFormatException('KRC 罗马音词数与原文不一致');
          }

          romaList.add(
            LyricsLine(
              startMs: line.startMs,
              endMs: line.endMs,
              words: <LyricsWord>[
                for (int j = 0; j < line.words.length; j += 1)
                  LyricsWord(
                    startMs: line.words[j].startMs,
                    endMs: line.words[j].endMs,
                    text: row[j].toString(),
                  ),
              ],
            ),
          );
        }
      } else if (type == 1) {
        for (int i = 0; i < origList.length; i += 1) {
          if (i >= lyricContent.length || lyricContent[i] is! List<dynamic>) {
            throw const LddcLyricsFormatException('KRC 翻译行数与原文不一致');
          }
          final List<dynamic> row = lyricContent[i] as List<dynamic>;
          if (row.isEmpty) {
            throw const LddcLyricsFormatException('KRC 翻译内容为空');
          }
          final LyricsLine origLine = origList[i];
          tsList.add(
            LyricsLine(
              startMs: origLine.startMs,
              endMs: origLine.endMs,
              words: <LyricsWord>[
                LyricsWord(
                  startMs: origLine.startMs,
                  endMs: origLine.endMs,
                  text: row.first.toString(),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  final Map<String, LyricsData> lyricsData = <String, LyricsData>{};
  if (origList.isNotEmpty) {
    lyricsData['orig'] = origList;
  }
  if (romaList.isNotEmpty) {
    lyricsData['roma'] = romaList;
  }
  if (tsList.isNotEmpty) {
    lyricsData['ts'] = tsList;
  }

  return ParsedLyricsPayload(tags: tags, lyricsData: lyricsData);
}

List<dynamic> _decodeLanguageContent(String languageTag) {
  try {
    final dynamic decoded = jsonDecode(
      utf8.decode(base64Decode(languageTag.trim())),
    );
    if (decoded is Map<String, dynamic> &&
        decoded['content'] is List<dynamic>) {
      return decoded['content'] as List<dynamic>;
    }
  } on FormatException {
    // Base64、UTF-8 和 JSON 都属于外部歌词数据边界，损坏时统一转为
    // 可被 dispatcher 识别的歌词格式异常，而不是泄漏底层解码异常。
  }
  throw const LddcLyricsFormatException('KRC language 标签格式错误');
}

int? _asInt(Object? value) {
  return switch (value) {
    int v => v,
    num v when v.isFinite => v.toInt(),
    _ => null,
  };
}
