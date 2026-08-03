import 'dart:typed_data';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 打开歌词页本地输入解码器：对齐Python版“先展示原始文本，再执行转换”语义。
class OpenLyricsInputDecoder {
  OpenLyricsInputDecoder({LocalLyricsInputNormalizer? normalizer})
    : _normalizer = normalizer ?? LocalLyricsInputNormalizer();

  final LocalLyricsInputNormalizer _normalizer;

  String decodeLyricsFile({required Uint8List data, String? path}) {
    return _normalizer.decodeDisplayText(data: data, path: path);
  }
}
