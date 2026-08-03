import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:brotli/brotli.dart' as brotli;

/// 按 HTTP `Content-Encoding` 对响应体做解码。
Uint8List decodeHttpBody(Uint8List body, Map<String, String> headers) {
  final String? encodingValue = _readHeader(headers, 'content-encoding');
  if (encodingValue == null || encodingValue.trim().isEmpty) {
    return body;
  }

  Uint8List decoded = body;
  final List<String> encodings = encodingValue
      .split(',')
      .map((String value) => value.trim().toLowerCase())
      .where((String value) => value.isNotEmpty && value != 'identity')
      .toList(growable: false);

  // HTTP 头里的 Content-Encoding 记录的是“压缩时的应用顺序”。
  // 解码时必须反过来剥离，否则 `gzip, br` 这类多重编码会先拿 gzip
  // 去解最外层的 br 数据，导致线上响应偶发解析失败。
  for (final String encoding in encodings.reversed) {
    switch (encoding) {
      case 'gzip':
      case 'x-gzip':
        decoded = Uint8List.fromList(GZipDecoder().decodeBytes(decoded));
      case 'deflate':
        decoded = Uint8List.fromList(ZLibDecoder().decodeBytes(decoded));
      case 'br':
        decoded = Uint8List.fromList(brotli.brotliDecode(decoded));
      default:
        throw FormatException('不支持的 Content-Encoding: $encoding');
    }
  }
  return decoded;
}

String? _readHeader(Map<String, String> headers, String key) {
  if (headers.containsKey(key)) {
    return headers[key];
  }
  final String lowered = key.toLowerCase();
  for (final MapEntry<String, String> entry in headers.entries) {
    if (entry.key.toLowerCase() == lowered) {
      return entry.value;
    }
  }
  return null;
}
