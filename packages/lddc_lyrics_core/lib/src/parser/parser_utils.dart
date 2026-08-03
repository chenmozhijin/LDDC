import 'dart:convert';

import '../models/models.dart';

/// 判断字节序列是否以指定魔数开头。
///
/// QRC/KRC 的输入规范化和解析路由都需要同一判断。集中实现可以确保空输入、
/// 短输入和完整前缀的边界行为一致，同时避免为了比较前缀创建子列表。
bool hasBytePrefix(List<int> data, List<int> prefix) {
  if (data.length < prefix.length) {
    return false;
  }
  for (int index = 0; index < prefix.length; index += 1) {
    if (data[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

/// 对齐Python版 `judge_lyrics_type`：
/// - 任一行含多个词 -> `verbatim`
/// - 否则若存在行起始时间 -> `lineByLine`
/// - 其余 -> `plainText`
LyricsType judgeLyricsType(LyricsData lyrics) {
  LyricsType lyricsType = LyricsType.plainText;
  for (final LyricsLine line in lyrics) {
    if (line.words.length > 1) {
      lyricsType = LyricsType.verbatim;
      break;
    }
    if (line.startMs != null) {
      lyricsType = LyricsType.lineByLine;
    }
  }
  return lyricsType;
}

/// 将纯文本按行转换为歌词数据，每行一个无时间戳词条。
LyricsData plaintextToData(String plaintext) {
  final List<String> lines = const LineSplitter().convert(plaintext);
  return <LyricsLine>[
    for (final String line in lines)
      LyricsLine(
        startMs: null,
        endMs: null,
        words: <LyricsWord>[LyricsWord(startMs: null, endMs: null, text: line)],
      ),
  ];
}
