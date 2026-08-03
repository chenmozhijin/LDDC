import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  group('UnknownEncodingReader', () {
    test('可正常解码 UTF-8 数据', () {
      final Uint8List data = Uint8List.fromList(utf8.encode('[00:01.00]你好'));
      expect(decodeUnknownEncoding(data), '[00:01.00]你好');
    });

    test('显式传入空字节时返回空文本', () {
      expect(decodeUnknownEncoding(Uint8List(0)), '');
    });

    test('可按优先编码解码 GB18030 数据', () {
      final Uint8List data = Uint8List.fromList(<int>[
        0x5B,
        0x30,
        0x30,
        0x3A,
        0x30,
        0x31,
        0x2E,
        0x30,
        0x30,
        0x5D,
        0xC4,
        0xE3,
        0xBA,
        0xC3,
      ]);

      expect(
        decodeUnknownEncoding(
          data,
          preferredEncodings: const <String>['gb18030'],
        ),
        '[00:01.00]你好',
      );
    });

    test('signWords 不匹配时抛解码失败', () {
      final Uint8List data = Uint8List.fromList(utf8.encode('just plain text'));
      expect(
        () => decodeUnknownEncoding(data, signWords: const <String>['[', ']']),
        throwsA(isA<LddcDecodingException>()),
      );
    });

    test('UTF-8 BOM 内容不会被 gb18030 误判结果污染', () {
      final Uint8List data = Uint8List.fromList(utf8.encode('\uFEFFABC'));
      final String decoded = readUnknownEncoding(
        data: data,
        preferredEncodings: const <String>['gb18030'],
      );

      expect(decoded, contains('ABC'));
      expect(decoded.contains('锘縍EM'), isFalse);
    });

    test('支持通过 path 读取并解码', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-unknown-encoding-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final File file = File('${dir.path}${Platform.pathSeparator}demo.lrc');
      await file.writeAsBytes(<int>[
        0x5B,
        0x30,
        0x30,
        0x3A,
        0x30,
        0x32,
        0x2E,
        0x30,
        0x30,
        0x5D,
        0xC4,
        0xE3,
        0xBA,
        0xC3,
      ]);

      expect(
        readUnknownEncodingFile(
          file.path,
          preferredEncodings: const <String>['gb18030'],
        ),
        '[00:02.00]你好',
      );
    });
  });
}
