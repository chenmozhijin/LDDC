import 'dart:convert';

import '../models/models.dart';
import 'lyrics_parser_port.dart';

final RegExp _srtBlockSeparatorPattern = RegExp(r'\r?\n\r?\n+');
final RegExp _srtTimestampPattern = RegExp(
  r'(\d{2}:\d{2}:\d{2}[,.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,.]\d{3})',
);

/// 解析 SRT 内容，返回 `(开始毫秒, 结束毫秒, 文本行列表)` 迭代序列。
Iterable<({int startMs, int endMs, List<String> contents})> _parseSrt(
  String srtContent,
) sync* {
  final String trimmed = srtContent.trim();
  if (trimmed.isEmpty) {
    return;
  }

  for (final String block in trimmed.split(_srtBlockSeparatorPattern)) {
    final List<String> lines = const LineSplitter().convert(block.trim());
    if (lines.length < 3) {
      continue;
    }

    final RegExpMatch? match = _srtTimestampPattern.firstMatch(lines[1]);
    if (match == null) {
      continue;
    }

    try {
      yield (
        startMs: _parseSrtTime(match.group(1)!),
        endMs: _parseSrtTime(match.group(2)!),
        contents: lines.sublist(2),
      );
    } on FormatException {
      continue;
    }
  }
}

/// 迁移Python版 `srt2mdata`：输出 `orig/roma/ts` 三语结构。
ParsedLyricsPayload parseSrtToMultiResult(String srtContent) {
  final Map<String, LyricsData> lyricsData = <String, LyricsData>{
    'orig': <LyricsLine>[],
    'roma': <LyricsLine>[],
    'ts': <LyricsLine>[],
  };

  for (final ({int startMs, int endMs, List<String> contents}) item
      in _parseSrt(srtContent)) {
    if (item.contents.length == 1) {
      lyricsData['orig']!.add(
        _buildSrtLine(item.startMs, item.endMs, item.contents[0]),
      );
      continue;
    }

    if (item.contents.length == 2) {
      lyricsData['orig']!.add(
        _buildSrtLine(item.startMs, item.endMs, item.contents[0]),
      );
      lyricsData['ts']!.add(
        _buildSrtLine(item.startMs, item.endMs, item.contents[1]),
      );
      continue;
    }

    if (item.contents.length == 3) {
      lyricsData['roma']!.add(
        _buildSrtLine(item.startMs, item.endMs, item.contents[0]),
      );
      lyricsData['orig']!.add(
        _buildSrtLine(item.startMs, item.endMs, item.contents[1]),
      );
      lyricsData['ts']!.add(
        _buildSrtLine(item.startMs, item.endMs, item.contents[2]),
      );
      continue;
    }

    lyricsData['orig']!.add(
      _buildSrtLine(item.startMs, item.endMs, item.contents.join()),
    );
  }

  lyricsData.removeWhere((String _, LyricsData value) => value.isEmpty);
  return ParsedLyricsPayload(
    tags: const <String, String>{},
    lyricsData: lyricsData,
  );
}

int _parseSrtTime(String value) {
  final String normalized = value.replaceAll(',', '.');
  final List<String> hourMinuteSecond = normalized.split(':');
  if (hourMinuteSecond.length != 3) {
    throw const FormatException('无效的 SRT 时间格式');
  }

  final List<String> secondAndMs = hourMinuteSecond[2].split('.');
  final int hours = int.parse(hourMinuteSecond[0]);
  final int minutes = int.parse(hourMinuteSecond[1]);
  final int seconds = int.parse(secondAndMs[0]);
  final int milliseconds = secondAndMs.length > 1
      ? int.parse(secondAndMs[1])
      : 0;
  return (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds;
}

LyricsLine _buildSrtLine(int startMs, int endMs, String text) {
  return LyricsLine(
    startMs: startMs,
    endMs: endMs,
    words: <LyricsWord>[LyricsWord(startMs: startMs, endMs: endMs, text: text)],
  );
}
