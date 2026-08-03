import 'dart:convert';

import 'ass_parser.dart';
import '../error/error.dart';
import 'json_lrc_parser.dart';
import 'krc_parser.dart';
import 'lrc_parser.dart';
import 'lyrics_parser_port.dart';
import 'parser_format.dart';
import 'qrc_parser.dart';
import 'srt_parser.dart';
import 'unknown_encoding_reader.dart';
import 'yrc_parser.dart';

/// 解析器实现聚合：按格式调用各子解析器。
///
/// QRC/KRC 在文件形态下通常是加密字节；本类只处理已经由本地歌词入口解密后的文本，
/// 不应把原始 `.qrc/.krc` 文件字节直接传给这里。
final class LyricsParserEngine implements LyricsParserPort {
  const LyricsParserEngine();

  static const Set<LyricsParserFormat> _supportedFormats = <LyricsParserFormat>{
    LyricsParserFormat.jsonLrc,
    LyricsParserFormat.lrc,
    LyricsParserFormat.qrc,
    LyricsParserFormat.krc,
    LyricsParserFormat.yrc,
    LyricsParserFormat.ass,
    LyricsParserFormat.srt,
  };

  @override
  Set<LyricsParserFormat> get supportedFormats => _supportedFormats;

  @override
  ParsedLyricsPayload parse({
    required LyricsParserFormat format,
    required LyricsParserRequest request,
  }) {
    // 所有文本格式共用同一未知编码入口，避免格式解析器各自维护编码兜底。
    final String text = decodeUnknownEncoding(request.data);
    return switch (format) {
      LyricsParserFormat.jsonLrc => parseJsonLrcToMultiResult(_parseJson(text)),
      LyricsParserFormat.lrc => parseLrcToMultiResult(text),
      LyricsParserFormat.qrc => parseQrcToMultiResult(text),
      LyricsParserFormat.krc => parseKrcToMultiResult(text),
      LyricsParserFormat.yrc => parseYrcToMultiResult(text),
      LyricsParserFormat.ass => parseAssToMultiResult(text),
      LyricsParserFormat.srt => parseSrtToMultiResult(text),
    };
  }

  Object? _parseJson(String text) {
    final String normalized = _stripBom(text);
    try {
      return jsonDecode(normalized);
    } on FormatException {
      throw const LddcLyricsFormatException('JSON歌词数据不是合法 JSON');
    }
  }

  String _stripBom(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }
}
