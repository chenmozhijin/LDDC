/// 歌词解析格式枚举，覆盖Python版 `core/parser/*` 的主要格式类型。
enum LyricsParserFormat {
  jsonLrc('json_lrc'),
  lrc('lrc'),
  qrc('qrc'),
  krc('krc'),
  yrc('yrc'),
  ass('ass'),
  srt('srt');

  const LyricsParserFormat(this.value);

  final String value;
}

/// 未知文本歌词的统一回退顺序。
///
/// QRC/KRC/YRC 需要各自的解密或专用结构入口；这里仅面向已经可按文本尝试的格式，
/// 让本地打开、批量转换等链路不会因为各自维护一份顺序而出现行为漂移。
const List<LyricsParserFormat> textLyricsFallbackFormats = <LyricsParserFormat>[
  LyricsParserFormat.lrc,
  LyricsParserFormat.ass,
  LyricsParserFormat.srt,
];
