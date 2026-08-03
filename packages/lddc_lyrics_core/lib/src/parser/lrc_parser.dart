import 'dart:convert';

import '../models/models.dart';
import 'lyrics_parser_port.dart';
import 'parser_utils.dart';

final RegExp _tagSplitPattern = RegExp(r'^\[(\w+):([^\]]*)\]$');
final RegExp _lineSplitPattern = RegExp(r'^\[(\d+):(\d+)[.:](\d+)\](.*)$');
final RegExp _enhancedWordSplitPattern = RegExp(
  r'<(\d+):(\d+)[.:](\d+)>((?:(?!<\d+:\d+[.:]\d+>).)*)(?:<(\d+):(\d+)[.:](\d+)>$)?',
);
final RegExp _wordSplitPattern = RegExp(
  r'((?:(?!\[\d+:\d+[.:]\d+\]).)*)(?:\[(\d+):(\d+)[.:](\d+)\])?',
);
final RegExp _multiLineSplitPattern = RegExp(
  r'^((?:\[\d+:\d+[.:]\d+\]){2,})(.*)$',
);
final RegExp _timestampsPattern = RegExp(r'\[(\d+):(\d+)[.:](\d+)\]');

/// 将 LRC 的 `mm:ss.xx` 或 `mm:ss.xxx` 时间戳换算为毫秒。
int _timeToMs(Object minutes, Object seconds, Object milliseconds) {
  String millisecondText = milliseconds.toString();
  if (milliseconds is String && millisecondText.length == 2) {
    millisecondText = '${millisecondText}0';
  }
  final int minute = int.parse(minutes.toString());
  final int second = int.parse(seconds.toString());
  final int millisecond = int.parse(millisecondText);
  return (minute * 60 + second) * 1000 + millisecond;
}

/// 迁移Python版 `lrc2mdata`：返回标签 + 多语言歌词数据。
ParsedLyricsPayload parseLrcToMultiResult(String lrc, {Source? source}) {
  final ({Map<String, String> tags, List<LyricsData> lyricsLists}) state =
      _parseLrcToLists(lrc, source: source);
  final Map<String, LyricsData> lyricsData = <String, LyricsData>{};
  final List<LyricsData> lists = state.lyricsLists;

  if (lists.isNotEmpty) {
    lyricsData['orig'] = lists.first;
  }
  if (lists.length == 2) {
    final LyricsType firstType = judgeLyricsType(lists[0]);
    final LyricsType secondType = judgeLyricsType(lists[1]);
    if (firstType == LyricsType.verbatim && secondType == LyricsType.verbatim) {
      lyricsData
        ..clear()
        ..addAll(<String, LyricsData>{'roma': lists[0], 'orig': lists[1]});
    } else {
      lyricsData['ts'] = lists[1];
    }
  } else if (lists.length >= 3) {
    lyricsData
      ..clear()
      ..addAll(<String, LyricsData>{
        'roma': lists[0],
        'orig': lists[1],
        'ts': lists[2],
      });
  }

  return ParsedLyricsPayload(
    tags: state.tags,
    lyricsData: lyricsData,
    sourceHint: source,
  );
}

/// 迁移Python版 `lrc2data`：将多列表按起始时间合并到单列表。
({Map<String, String> tags, LyricsData lyricsData}) parseLrcToData(
  String lrc, {
  Source? source,
}) {
  final ({Map<String, String> tags, List<LyricsData> lyricsLists}) state =
      _parseLrcToLists(lrc, source: source);
  final List<LyricsData> lists = state.lyricsLists;
  if (lists.isEmpty) {
    return (tags: state.tags, lyricsData: <LyricsLine>[]);
  }

  final Map<int, List<LyricsLine>> linesByStart = <int, List<LyricsLine>>{};
  final List<int> orderedStarts = <int>[];
  for (final LyricsLine line in lists.first) {
    final int? startMs = line.startMs;
    if (startMs == null) {
      continue;
    }
    orderedStarts.add(startMs);
    linesByStart[startMs] = <LyricsLine>[line];
  }
  for (int listIndex = 1; listIndex < lists.length; listIndex += 1) {
    for (final LyricsLine line in lists[listIndex]) {
      linesByStart[line.startMs]?.add(line);
    }
  }
  final List<LyricsLine> merged = <LyricsLine>[
    for (final int startMs in orderedStarts) ...linesByStart[startMs]!,
  ];
  return (tags: state.tags, lyricsData: merged);
}

({Map<String, String> tags, List<LyricsData> lyricsLists}) _parseLrcToLists(
  String lrc, {
  Source? source,
}) {
  final List<LyricsData> lyricsLists = <LyricsData>[<LyricsLine>[]];
  final List<Set<int>> startTimeSets = <Set<int>>[<int>{}];

  void addLine(LyricsLine line) {
    final int? startMs = line.startMs;
    if (startMs == null) {
      return;
    }
    for (int index = 0; index < lyricsLists.length; index += 1) {
      if (!startTimeSets[index].contains(startMs)) {
        lyricsLists[index].add(line);
        startTimeSets[index].add(startMs);
        return;
      }
    }
    if (line.words.isNotEmpty) {
      lyricsLists.add(<LyricsLine>[line]);
      startTimeSets.add(<int>{startMs});
    }
  }

  final Map<String, String> tags = <String, String>{};
  final List<String> lines = const LineSplitter().convert(lrc);

  for (final String rawLine in lines) {
    final String line = rawLine.trim();
    if (line.isEmpty || !line.startsWith('[')) {
      continue;
    }

    final RegExpMatch? lineMatch = _lineSplitPattern.firstMatch(line);
    if (lineMatch != null) {
      final int lineStart = _timeToMs(
        lineMatch.group(1)!,
        lineMatch.group(2)!,
        lineMatch.group(3)!,
      );
      String lineContent = lineMatch.group(4) ?? '';
      final List<LyricsWord> words = <LyricsWord>[];
      int? lineEnd;

      if (source == Source.ne) {
        final RegExpMatch? multiMatch = _multiLineSplitPattern.firstMatch(line);
        if (multiMatch != null) {
          final String timestamps = multiMatch.group(1)!;
          lineContent = multiMatch.group(2) ?? '';
          for (final RegExpMatch tsMatch in _timestampsPattern.allMatches(
            timestamps,
          )) {
            final int start = _timeToMs(
              tsMatch.group(1)!,
              tsMatch.group(2)!,
              tsMatch.group(3)!,
            );
            addLine(
              LyricsLine(
                startMs: start,
                endMs: null,
                words: <LyricsWord>[
                  LyricsWord(startMs: start, endMs: null, text: lineContent),
                ],
              ),
            );
          }
          continue;
        }
      }

      if (lineContent.contains('<') && lineContent.contains('>')) {
        for (final RegExpMatch match in _enhancedWordSplitPattern.allMatches(
          lineContent,
        )) {
          final int wordStart = _timeToMs(
            match.group(1)!,
            match.group(2)!,
            match.group(3)!,
          );
          final bool hasEnd =
              match.group(5) != null &&
              match.group(6) != null &&
              match.group(7) != null;
          final int? wordEnd = hasEnd
              ? _timeToMs(match.group(5)!, match.group(6)!, match.group(7)!)
              : null;
          lineEnd = wordEnd ?? lineEnd;

          if (words.isNotEmpty) {
            final LyricsWord previous = words.last;
            words[words.length - 1] = LyricsWord(
              startMs: previous.startMs,
              endMs: wordStart,
              text: previous.text,
            );
          }

          final String wordText = match.group(4) ?? '';
          if (wordText.isNotEmpty) {
            words.add(
              LyricsWord(startMs: wordStart, endMs: wordEnd, text: wordText),
            );
          }
        }
      } else {
        for (final RegExpMatch match in _wordSplitPattern.allMatches(
          lineContent,
        )) {
          final String wordText = match.group(1) ?? '';
          final int? wordStart = words.isEmpty ? lineStart : words.last.endMs;
          final bool hasEnd =
              match.group(2) != null &&
              match.group(3) != null &&
              match.group(4) != null;
          final int? wordEnd = hasEnd
              ? _timeToMs(match.group(2)!, match.group(3)!, match.group(4)!)
              : null;
          // 某些 LRC 会在最后一个真实词后留下空匹配。每次遇到有效结束
          // 时间就更新行尾，可避免空匹配把已经解析出的末词时间丢掉。
          lineEnd = wordEnd ?? lineEnd;
          if (wordText.isNotEmpty) {
            words.add(
              LyricsWord(startMs: wordStart, endMs: wordEnd, text: wordText),
            );
          }
        }
      }

      addLine(LyricsLine(startMs: lineStart, endMs: lineEnd, words: words));
      continue;
    }

    final RegExpMatch? tagMatch = _tagSplitPattern.firstMatch(line);
    if (tagMatch != null) {
      tags[tagMatch.group(1)!] = tagMatch.group(2) ?? '';
    }
  }

  for (int i = 0; i < lyricsLists.length; i += 1) {
    final List<LyricsLine> sorted = List<LyricsLine>.from(lyricsLists[i])
      ..sort(
        (LyricsLine left, LyricsLine right) =>
            left.startMs!.compareTo(right.startMs!),
      );

    for (int lineIndex = 1; lineIndex < sorted.length; lineIndex += 1) {
      final LyricsLine previous = sorted[lineIndex - 1];
      final LyricsLine current = sorted[lineIndex];
      if (previous.endMs == null && current.startMs != null) {
        sorted[lineIndex - 1] = LyricsLine(
          startMs: previous.startMs,
          endMs: current.startMs,
          words: previous.words,
        );
      }
    }

    lyricsLists[i] = sorted
        .where((LyricsLine line) => line.words.isNotEmpty)
        .toList(growable: false);
  }

  return (tags: tags, lyricsLists: lyricsLists);
}
