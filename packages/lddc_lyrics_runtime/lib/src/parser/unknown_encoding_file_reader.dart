import 'dart:io';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 同步读取文件并使用纯 Dart 核心执行未知编码解码。
String readUnknownEncodingFile(
  String path, {
  Iterable<String>? signWords,
  List<String>? preferredEncodings,
}) {
  final Uint8List data = File(path).readAsBytesSync();
  return decodeUnknownEncoding(
    data,
    signWords: signWords,
    preferredEncodings: preferredEncodings,
  );
}

/// 异步读取文件并使用纯 Dart 核心执行未知编码解码。
Future<String> readUnknownEncodingFileAsync(
  String path, {
  Iterable<String>? signWords,
  List<String>? preferredEncodings,
}) async {
  final Uint8List data = await File(path).readAsBytes();
  return decodeUnknownEncoding(
    data,
    signWords: signWords,
    preferredEncodings: preferredEncodings,
  );
}
