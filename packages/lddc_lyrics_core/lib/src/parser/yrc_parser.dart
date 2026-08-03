import 'dart:convert';

import '../models/models.dart';
import 'lyrics_parser_port.dart';
import 'timed_word_parser.dart';

final RegExp _lineSplitPattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
final RegExp _wordSplitPattern = RegExp(
  r'(?:\[\d+,\d+\])?\((\d+),(\d+),\d+\)((?:.(?!\d+,\d+,\d+\)))*)',
);

ParsedLyricsPayload parseYrcToMultiResult(String yrc) {
  final LyricsData lyricsData = <LyricsLine>[];

  for (final String rawLine in const LineSplitter().convert(yrc)) {
    final String line = rawLine.trim();
    if (!line.startsWith('[')) {
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
    );
    lyricsData.add(
      buildTimedLyricsLine(
        lineStartMs: lineStart,
        lineEndMs: lineEnd,
        content: lineContent,
        words: words,
      ),
    );
  }

  return ParsedLyricsPayload(
    lyricsData: <String, LyricsData>{'orig': lyricsData},
  );
}
