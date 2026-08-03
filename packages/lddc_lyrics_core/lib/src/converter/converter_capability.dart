import '../models/models.dart';

/// 歌词导出格式能力注册表。
final class LyricsFormatCapabilities {
  const LyricsFormatCapabilities._();

  /// 当前转换器能够直接编码写出的格式。
  ///
  /// JSON 是完整结构快照，不适用于批量转换中的语言裁剪和时间偏移；
  /// QRC、KRC、YRC 只有解析或解密能力，没有对应编码器，因此不列入此清单。
  /// 展示名称属于界面本地化职责，不在核心转换层保存任何语言文案。
  static const List<LyricsFormat> exportableFormats = <LyricsFormat>[
    LyricsFormat.verbatimLrc,
    LyricsFormat.lineByLineLrc,
    LyricsFormat.enhancedLrc,
    LyricsFormat.srt,
    LyricsFormat.ass,
  ];

  static bool isLrcFamily(LyricsFormat format) {
    return switch (format) {
      LyricsFormat.verbatimLrc ||
      LyricsFormat.lineByLineLrc ||
      LyricsFormat.enhancedLrc => true,
      _ => false,
    };
  }
}
