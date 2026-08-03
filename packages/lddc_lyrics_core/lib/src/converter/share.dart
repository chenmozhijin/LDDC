import '../models/models.dart';

/// 转换阶段的一行候选输出：歌词行 + 是否使用 next-line-1ms 语义。
class ConverterLyricsLine {
  const ConverterLyricsLine({
    required this.lang,
    required this.line,
    required this.lastSub1,
  });

  /// 真实语言标识。部分语言行会被空内容过滤，不能再用返回列表下标反推语言。
  final String lang;
  final LyricsLine line;
  final bool lastSub1;
}

final RegExp _contentCleanPattern = RegExp(
  r'\[\d+:\d+\.\d+\]|\[\d+,\d+\]|<\d+:\d+\.\d+>',
);

/// 对齐Python版 `common/utils.py::has_content`。
bool hasContent(String line) {
  final String content = line.replaceAll(_contentCleanPattern, '').trim();
  if (content.isEmpty || content == '//') {
    return false;
  }
  return !(content.length == 2 &&
      _isAsciiUppercase(content.codeUnitAt(0)) &&
      content[1] == '：');
}

/// 对齐Python版 `converter/share.py::get_lyrics_lines`。
List<ConverterLyricsLine> getLyricsLines({
  required MultiLyricsData lyricsData,
  required List<String> langsOrder,
  required int origIndex,
  required LyricsLine origLine,
  required Map<String, Map<int, int>> langsMapping,
  int lastRefLineTimeStyle = 0,
}) {
  final List<ConverterLyricsLine> lines = <ConverterLyricsLine>[];
  for (int i = 0; i < langsOrder.length; i += 1) {
    final String lang = langsOrder[i];
    late final LyricsLine lyricsLine;
    if (lang == 'orig') {
      lyricsLine = origLine;
    } else {
      final int? index = langsMapping[lang]?[origIndex];
      if (index == null) {
        continue;
      }
      final LyricsData? languageLines = lyricsData[lang];
      if (languageLines == null || index < 0 || index >= languageLines.length) {
        continue;
      }
      lyricsLine = languageLines[index];
    }

    final String text = joinLineText(lyricsLine, includeEmpty: false);
    if (hasContent(text)) {
      lines.add(
        ConverterLyricsLine(
          lang: lang,
          line: lyricsLine,
          lastSub1:
              lastRefLineTimeStyle == 1 &&
              i == langsOrder.length - 1 &&
              lyricsLine.words.length == 1,
        ),
      );
    }
  }
  return lines;
}

/// 拼接一行歌词文本。
String joinLineText(LyricsLine line, {bool includeEmpty = true}) {
  if (includeEmpty) {
    return line.words.map((LyricsWord word) => word.text).join();
  }
  return line.words
      .where((LyricsWord word) => word.text.isNotEmpty)
      .map((LyricsWord word) => word.text)
      .join();
}

bool _isAsciiUppercase(int codeUnit) {
  return codeUnit >= 0x41 && codeUnit <= 0x5A;
}
