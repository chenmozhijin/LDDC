import 'dart:convert';

import '../error/error.dart';
import '../models/models.dart';
import 'lyrics_parser_port.dart';
import 'parser_utils.dart';

final RegExp _assTimePattern = RegExp(r'^(\d+):(\d+):(\d+)\.(\d{2})$');
final RegExp _titlePattern = RegExp(
  r'^Title:\s*(.*?)\s*$',
  caseSensitive: false,
  multiLine: true,
);
final RegExp _sectionPattern = RegExp(
  r'^\[([^\]]+)\]\s*$',
  caseSensitive: false,
  multiLine: true,
);
const Set<String> _lddcAssStyles = <String>{'orig', 'ts', 'roma'};

/// 将 `h:mm:ss.cc` 的 ASS 时间格式转换为毫秒。
int _parseAssTime(String timestamp) {
  final RegExpMatch? match = _assTimePattern.firstMatch(timestamp.trim());
  if (match == null) {
    throw LddcLyricsFormatException('无效的 ASS 时间格式: $timestamp');
  }
  final int hours = int.parse(match.group(1)!);
  final int minutes = int.parse(match.group(2)!);
  final int seconds = int.parse(match.group(3)!);
  final int centiSeconds = int.parse(match.group(4)!);
  return ((hours * 3600 + minutes * 60 + seconds) * 1000) + centiSeconds * 10;
}

/// 解析 ASS 卡拉 OK 标签，返回 `(持续时间毫秒, 文本)` 段落列表。
List<({int durationMs, String text})> _parseAssKaraokeTags(String text) {
  final List<({int durationMs, String text})> segments =
      <({int durationMs, String text})>[];
  final StringBuffer currentText = StringBuffer();
  int currentDurationMs = 0;
  int baseTimeMs = 0;

  void commitCurrent() {
    if (currentText.isNotEmpty && currentDurationMs > 0) {
      segments.add((
        durationMs: currentDurationMs,
        text: currentText.toString(),
      ));
      currentText.clear();
      currentDurationMs = 0;
    }
  }

  void processStyleBlock(String content) {
    int index = 0;
    while (index < content.length) {
      final String char = content[index];
      if (char == r'\') {
        if (index + 1 >= content.length) {
          currentText.write(char);
          index += 1;
          continue;
        }

        if (_startsWithIgnoreCase(content, index + 1, 'kt')) {
          final int valueStart = index + 3;
          final int valueEnd = _consumeDigitsEnd(content, valueStart);
          if (valueEnd > valueStart) {
            final int? parsed = int.tryParse(
              content.substring(valueStart, valueEnd),
            );
            if (parsed != null) {
              baseTimeMs = parsed * 10;
            }
            index = valueEnd;
            continue;
          }
        }

        if (_charEqualsIgnoreCase(content, index + 1, 'k')) {
          int valueStart = index + 2;
          if (valueStart < content.length) {
            final String marker = content[valueStart].toLowerCase();
            if (marker == 'o' || marker == 'f') {
              valueStart += 1;
            }
          }
          final int valueEnd = _consumeDigitsEnd(content, valueStart);
          if (valueEnd > valueStart) {
            commitCurrent();
            final int? parsed = int.tryParse(
              content.substring(valueStart, valueEnd),
            );
            if (parsed != null) {
              currentDurationMs = baseTimeMs + parsed * 10;
              baseTimeMs = 0;
            }
            index = valueEnd;
            continue;
          }
        }

        final String next = content[index + 1];
        if (next == r'\') {
          currentText.write(r'\');
          index += 2;
          continue;
        }
        if (next == '{' || next == '}') {
          currentText.write(next);
          index += 2;
          continue;
        }

        // 未识别的转义在Python版中按普通字符处理。
        currentText.write(char);
        index += 1;
        continue;
      }

      currentText.write(char);
      index += 1;
    }
  }

  int cursor = 0;
  while (cursor < text.length) {
    final String char = text[cursor];
    if (char == '{') {
      final int end = text.indexOf('}', cursor + 1);
      if (end > cursor) {
        processStyleBlock(text.substring(cursor + 1, end));
        cursor = end + 1;
        continue;
      }
    }

    if (char == r'\' && cursor + 1 < text.length) {
      final String next = text[cursor + 1];
      if (next == 'n' || next == 'N') {
        currentText.write('\n');
        cursor += 2;
        continue;
      }
      if (next == r'\') {
        currentText.write(r'\');
        cursor += 2;
        continue;
      }
      if (next == '{' || next == '}') {
        currentText.write(next);
        cursor += 2;
        continue;
      }
    }

    currentText.write(char);
    cursor += 1;
  }

  if (segments.isNotEmpty || currentDurationMs > 0) {
    commitCurrent();
    return segments;
  }
  // 普通行虽然没有卡拉 OK 时长标签，仍可能包含 ASS 的换行与字面字符转义。
  // 返回扫描后的文本可保证自家导出的 `\\N`、`\\`、`\\{`、`\\}` 再次打开时
  // 恢复为原始歌词，而不是把文件格式的转义符泄漏到歌词模型中。
  return <({int durationMs, String text})>[
    (durationMs: 0, text: currentText.toString()),
  ];
}

/// 迁移Python版 `ass2mdata`：输出标签与多语言歌词结构。
ParsedLyricsPayload parseAssToMultiResult(String assContent) {
  final ({
    List<({LyricsLine line, String style})> dialogues,
    Map<String, String> tags,
  })
  parsed = _parseAssDialogues(assContent);

  final List<({LyricsLine line, String style})> dialogues = parsed.dialogues;
  final Map<String, String> tags = parsed.tags;
  final Set<String> styles = dialogues
      .map((({LyricsLine line, String style}) dialogue) => dialogue.style)
      .toSet();

  if (assContent.contains('Script generated by LDDC') &&
      styles.every(_lddcAssStyles.contains)) {
    final Map<String, LyricsData> byStyle = <String, LyricsData>{};
    for (final String style in styles) {
      final LyricsData lines =
          dialogues
              .where(
                (({LyricsLine line, String style}) dialogue) =>
                    dialogue.style == style,
              )
              .map(
                (({LyricsLine line, String style}) dialogue) => dialogue.line,
              )
              .toList()
            ..sort(
              (LyricsLine left, LyricsLine right) =>
                  (left.startMs ?? 0).compareTo(right.startMs ?? 0),
            );
      byStyle[style] = lines;
    }
    return ParsedLyricsPayload(tags: tags, lyricsData: byStyle);
  }

  final List<_AssDataGroup> groups = <_AssDataGroup>[];
  for (final ({LyricsLine line, String style}) dialogue in dialogues) {
    bool assigned = false;
    for (final _AssDataGroup group in groups) {
      if (!group.startTimes.contains(dialogue.line.startMs)) {
        group.lines.add(dialogue.line);
        group.startTimes.add(dialogue.line.startMs);
        assigned = true;
        break;
      }
    }
    if (!assigned) {
      groups.add(
        _AssDataGroup(
          lines: <LyricsLine>[dialogue.line],
          startTimes: <int?>{dialogue.line.startMs},
        ),
      );
    }
  }

  for (final _AssDataGroup group in groups) {
    group.lines.sort(
      (LyricsLine left, LyricsLine right) =>
          (left.startMs ?? 0).compareTo(right.startMs ?? 0),
    );
  }

  final Map<String, LyricsData> lyricsData = <String, LyricsData>{};
  if (groups.isEmpty) {
    return ParsedLyricsPayload(tags: tags, lyricsData: lyricsData);
  }
  if (groups.length == 1) {
    lyricsData['orig'] = groups[0].lines;
    return ParsedLyricsPayload(tags: tags, lyricsData: lyricsData);
  }
  if (groups.length == 2) {
    final LyricsType firstType = judgeLyricsType(groups[0].lines);
    final LyricsType secondType = judgeLyricsType(groups[1].lines);
    if (firstType == LyricsType.verbatim && secondType == LyricsType.verbatim) {
      lyricsData['roma'] = groups[0].lines;
      lyricsData['orig'] = groups[1].lines;
    } else {
      lyricsData['orig'] = groups[0].lines;
      lyricsData['ts'] = groups[1].lines;
    }
    return ParsedLyricsPayload(tags: tags, lyricsData: lyricsData);
  }

  lyricsData['roma'] = groups[0].lines;
  lyricsData['orig'] = groups[1].lines;
  lyricsData['ts'] = groups[2].lines;
  return ParsedLyricsPayload(tags: tags, lyricsData: lyricsData);
}

({List<({LyricsLine line, String style})> dialogues, Map<String, String> tags})
_parseAssDialogues(String assContent) {
  final Map<String, String> tags = <String, String>{};
  final RegExpMatch? titleMatch = _titlePattern.firstMatch(assContent);
  if (titleMatch != null) {
    tags['title'] = titleMatch.group(1) ?? '';
  }

  final String eventsSection = _extractSectionContent(assContent, 'events');
  if (eventsSection.isEmpty) {
    return (dialogues: <({LyricsLine line, String style})>[], tags: tags);
  }

  final List<String> sectionLines = const LineSplitter().convert(eventsSection);
  final String formatLine = sectionLines.firstWhere(
    (String line) => line.toLowerCase().startsWith('format:'),
    orElse: () => '',
  );
  if (formatLine.isEmpty) {
    return (dialogues: <({LyricsLine line, String style})>[], tags: tags);
  }

  final List<String> fields = formatLine
      .substring('Format:'.length)
      .split(',')
      .map((String item) => item.trim().toLowerCase())
      .toList();
  final Map<String, int> fieldMap = <String, int>{
    for (int index = 0; index < fields.length; index += 1) fields[index]: index,
  };
  if (!fieldMap.containsKey('start') ||
      !fieldMap.containsKey('end') ||
      !fieldMap.containsKey('style') ||
      !fieldMap.containsKey('text')) {
    return (dialogues: <({LyricsLine line, String style})>[], tags: tags);
  }
  final int startIndex = fieldMap['start']!;
  final int endIndex = fieldMap['end']!;
  final int styleIndex = fieldMap['style']!;
  final int textIndex = fieldMap['text']!;
  final int lastRequiredIndex = _maxIndex(
    startIndex,
    endIndex,
    styleIndex,
    textIndex,
  );

  final List<({LyricsLine line, String style})> dialogues =
      <({LyricsLine line, String style})>[];

  for (final String line in sectionLines) {
    if (!line.toLowerCase().startsWith('dialogue:')) {
      continue;
    }
    final List<String> parts = _splitAssDialogueFields(
      line.substring('Dialogue:'.length),
      fieldMap.length,
    );
    if (parts.length <= lastRequiredIndex) {
      continue;
    }

    late final int startMs;
    late final int endMs;
    try {
      startMs = _parseAssTime(parts[startIndex]);
      endMs = _parseAssTime(parts[endIndex]);
    } on LddcLyricsFormatException {
      continue;
    }
    if (endMs < startMs) {
      continue;
    }

    final String style = parts[styleIndex].toLowerCase();
    final String text = parts[textIndex];
    final List<LyricsWord> words = <LyricsWord>[];
    int currentTime = startMs;
    final int totalDuration = endMs - startMs;

    for (final ({int durationMs, String text}) segment in _parseAssKaraokeTags(
      text,
    )) {
      final int remaining = endMs - currentTime;
      final int blockDuration = segment.durationMs == 0
          ? totalDuration
          : (segment.durationMs < remaining ? segment.durationMs : remaining);
      if (blockDuration <= 0) {
        continue;
      }
      words.add(
        LyricsWord(
          startMs: currentTime,
          endMs: currentTime + blockDuration,
          text: segment.text,
        ),
      );
      currentTime += blockDuration;
    }

    dialogues.add((
      line: LyricsLine(startMs: startMs, endMs: endMs, words: words),
      style: style,
    ));
  }

  return (dialogues: dialogues, tags: tags);
}

String _extractSectionContent(String assContent, String targetSectionName) {
  final String normalizedTarget = targetSectionName.toLowerCase();
  RegExpMatch? targetMatch;
  for (final RegExpMatch match in _sectionPattern.allMatches(assContent)) {
    if (targetMatch != null) {
      return assContent.substring(targetMatch.end, match.start).trim();
    }
    if ((match.group(1) ?? '').toLowerCase() == normalizedTarget) {
      targetMatch = match;
    }
  }
  return targetMatch == null
      ? ''
      : assContent.substring(targetMatch.end).trim();
}

int _maxIndex(int first, int second, int third, int fourth) {
  int result = first;
  if (second > result) {
    result = second;
  }
  if (third > result) {
    result = third;
  }
  if (fourth > result) {
    result = fourth;
  }
  return result;
}

List<String> _splitAssDialogueFields(String text, int maxParts) {
  if (maxParts <= 1) {
    return <String>[text.trim()];
  }
  final List<String> result = <String>[];
  int start = 0;
  int splits = 0;

  while (splits < maxParts - 1) {
    final int index = text.indexOf(',', start);
    if (index < 0) {
      break;
    }
    result.add(text.substring(start, index).trim());
    start = index + 1;
    splits += 1;
  }

  result.add(text.substring(start).trim());
  return result;
}

int _consumeDigitsEnd(String text, int start) {
  int index = start;
  while (index < text.length && _isAsciiDigit(text.codeUnitAt(index))) {
    index += 1;
  }
  return index;
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

bool _charEqualsIgnoreCase(String text, int index, String expected) {
  if (index < 0 || index >= text.length) {
    return false;
  }
  return text[index].toLowerCase() == expected.toLowerCase();
}

bool _startsWithIgnoreCase(String text, int start, String pattern) {
  if (start < 0 || start + pattern.length > text.length) {
    return false;
  }
  return text.substring(start, start + pattern.length).toLowerCase() ==
      pattern.toLowerCase();
}

final class _AssDataGroup {
  _AssDataGroup({required this.lines, required this.startTimes});

  final LyricsData lines;
  final Set<int?> startTimes;
}
