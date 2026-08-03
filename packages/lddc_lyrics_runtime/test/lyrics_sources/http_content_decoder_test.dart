import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('decodeHttpBody', () {
    test('无 Content-Encoding 时直接返回原始数据', () {
      final Uint8List body = Uint8List.fromList(utf8.encode('plain-text'));

      final Uint8List decoded = decodeHttpBody(body, const <String, String>{});

      expect(utf8.decode(decoded), 'plain-text');
    });

    test('可解码 gzip 响应', () {
      final Uint8List plain = Uint8List.fromList(utf8.encode('hello-gzip'));
      final Uint8List gzipBody = Uint8List.fromList(
        GZipEncoder().encode(plain),
      );

      final Uint8List decoded = decodeHttpBody(gzipBody, <String, String>{
        'content-encoding': 'gzip',
      });

      expect(utf8.decode(decoded), 'hello-gzip');
    });

    test('可解码 deflate 响应', () {
      final Uint8List plain = Uint8List.fromList(utf8.encode('hello-deflate'));
      final Uint8List deflateBody = Uint8List.fromList(
        ZLibEncoder().encode(plain),
      );

      final Uint8List decoded = decodeHttpBody(deflateBody, <String, String>{
        'content-encoding': 'deflate',
      });

      expect(utf8.decode(decoded), 'hello-deflate');
    });

    test('可解码 br 响应', () {
      // 由 Python `brotli.compress(b'hello-br')` 生成。
      final Uint8List brBody = _hexToBytes('8b038068656c6c6f2d627203');

      final Uint8List decoded = decodeHttpBody(brBody, <String, String>{
        'content-encoding': 'br',
      });

      expect(utf8.decode(decoded), 'hello-br');
    });

    test('按 Content-Encoding 反向顺序解码多重压缩', () {
      final Uint8List plain = Uint8List.fromList(utf8.encode('hello-stack'));
      final Uint8List gzipThenDeflate = Uint8List.fromList(
        ZLibEncoder().encode(GZipEncoder().encode(plain)),
      );

      final Uint8List decoded = decodeHttpBody(
        gzipThenDeflate,
        <String, String>{'Content-Encoding': 'gzip, deflate'},
      );

      expect(utf8.decode(decoded), 'hello-stack');
    });

    test('多重编码会忽略 identity 并保留清晰未知编码错误', () {
      final Uint8List plain = Uint8List.fromList(utf8.encode('hello-stack'));
      final Uint8List deflateThenGzip = Uint8List.fromList(
        GZipEncoder().encode(ZLibEncoder().encode(plain)),
      );

      final Uint8List decoded = decodeHttpBody(
        deflateThenGzip,
        <String, String>{'content-encoding': 'deflate, identity, gzip'},
      );
      expect(utf8.decode(decoded), 'hello-stack');

      expect(
        () => decodeHttpBody(deflateThenGzip, <String, String>{
          'content-encoding': 'deflate, zstd, gzip',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('未知编码时抛出异常', () {
      final Uint8List plain = Uint8List.fromList(utf8.encode('hello-unknown'));

      expect(
        () =>
            decodeHttpBody(plain, <String, String>{'content-encoding': 'lz4'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Uint8List _hexToBytes(String hex) {
  final int length = hex.length ~/ 2;
  final Uint8List bytes = Uint8List(length);
  for (int index = 0; index < length; index += 1) {
    final int start = index * 2;
    bytes[index] = int.parse(hex.substring(start, start + 2), radix: 16);
  }
  return bytes;
}
