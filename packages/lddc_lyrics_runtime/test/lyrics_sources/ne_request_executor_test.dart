import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:pointycastle/export.dart' hide Digest;

void main() {
  group('NeRequestExecutorImpl', () {
    test('close 释放底层 transport', () async {
      final _FakeNeTransport transport = _FakeNeTransport(<NeHttpResponse>[]);
      final NeRequestExecutorImpl executor = NeRequestExecutorImpl(
        deviceIdPool: _createTestDeviceIdPool(),
        transport: transport,
      );

      await executor.close();

      expect(transport.closed, isTrue);
    });

    test('可解压 br/gzip 响应并完成 eapi 解密', () async {
      final _FakeNeTransport transport = _FakeNeTransport(<NeHttpResponse>[
        // 匿名登录：br 压缩 + eapi 加密响应。
        NeHttpResponse(
          statusCode: 200,
          // 由 Python 生成：brotli.compress(aes_ecb_pkcs7(json_payload)).
          body: _hexToBytes(
            '8b17804dc12a14eca8f30f33123e619c7b9c89ef9b84e022a9570e24f71e10c3'
            '14ecdd37b2d0e4ef22142b3e1c0e24fc0137f303',
          ),
          headers: const <String, String>{'content-encoding': 'br'},
          cookies: const <String, String>{
            'NMTID': 'nmt-id',
            'MUSIC_A': 'music-a',
            '__csrf': 'csrf-token',
          },
        ),
        // 业务请求：gzip 压缩 + eapi 加密响应。
        NeHttpResponse(
          statusCode: 200,
          body: _gzipBody(
            _encryptEapiJson(<String, Object?>{
              'code': 200,
              'message': 'ok',
              'data': <String, Object?>{
                'resources': <Object?>[],
                'totalCount': 0,
              },
            }),
          ),
          headers: const <String, String>{'content-encoding': 'gzip'},
        ),
      ]);
      final NeRequestExecutorImpl executor = NeRequestExecutorImpl(
        deviceIdPool: _createTestDeviceIdPool(),
        transport: transport,
        random: Random(7),
      );

      final Map<String, Object?> data = await executor.execute(
        path: '/eapi/search/song/list/page',
        params: <String, Object?>{
          'keyword': 'one future',
          'limit': '20',
          'offset': '0',
          'scene': 'NORMAL',
          'needCorrect': 'true',
        },
      );

      expect(_parseInt(data['code']), 200);
      expect(transport.calls.length, 2);
      expect(transport.calls.first.uri.path, '/eapi/register/anonimous');
      expect(transport.calls.last.uri.path, '/eapi/search/song/list/page');
      for (final call in transport.calls) {
        expect(call.headers['user-agent'], NeClientProfile.desktopUserAgent);
        expect(
          call.headers['mconfig-info'],
          contains(NeClientProfile.desktopAppVersion),
        );
      }
    });
  });
}

NeDeviceIdPool _createTestDeviceIdPool() {
  return NeDeviceIdPool(
    compressedBytesLoader: () async => Uint8List.fromList(
      GZipEncoder().encode(utf8.encode('ABCDEF0123456789\n')),
    ),
  );
}

Uint8List _encryptEapiJson(Map<String, Object?> payload) {
  final Uint8List plain = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  final Uint8List padded = _pkcs7Pad(plain);
  final Uint8List key = Uint8List.fromList(utf8.encode('e82ckenh8dichen8'));
  final BlockCipher cipher = ECBBlockCipher(AESEngine())
    ..init(true, KeyParameter(key));
  final Uint8List output = Uint8List(padded.length);
  for (int i = 0; i < padded.length; i += 16) {
    cipher.processBlock(padded, i, output, i);
  }
  return output;
}

Uint8List _pkcs7Pad(Uint8List plain) {
  final int padLen = 16 - (plain.length % 16);
  return Uint8List.fromList(<int>[
    ...plain,
    ...List<int>.filled(padLen, padLen),
  ]);
}

Uint8List _gzipBody(Uint8List body) {
  return Uint8List.fromList(GZipEncoder().encode(body));
}

int? _parseInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
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

class _FakeNeTransport implements NeHttpTransport {
  _FakeNeTransport(this._responses);

  final List<NeHttpResponse> _responses;
  final List<
    ({
      Uri uri,
      Map<String, String> headers,
      Map<String, String>? queryParameters,
    })
  >
  calls =
      <
        ({
          Uri uri,
          Map<String, String> headers,
          Map<String, String>? queryParameters,
        })
      >[];
  int _index = 0;
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<NeHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
    Map<String, String>? queryParameters,
  }) async {
    calls.add((
      uri: uri,
      headers: Map<String, String>.from(headers),
      queryParameters: queryParameters == null
          ? null
          : Map<String, String>.from(queryParameters),
    ));
    if (_index >= _responses.length) {
      throw StateError('FakeNeTransport 响应队列不足');
    }
    return _responses[_index++];
  }
}
