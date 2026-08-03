import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('KgRequestExecutorImpl', () {
    test('close 释放底层 transport', () async {
      final _FakeKgTransport transport = _FakeKgTransport(<KgHttpResponse>[]);
      final KgRequestExecutorImpl executor = KgRequestExecutorImpl(
        transport: transport,
      );

      await executor.close();

      expect(transport.closed, isTrue);
    });

    test('execute 可解压 gzip 响应并解析 JSON', () async {
      final _FakeKgTransport transport = _FakeKgTransport(<KgHttpResponse>[
        KgHttpResponse(
          statusCode: 200,
          body: Uint8List.fromList(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'error_code': 0,
                'data': <String, Object?>{'dfid': 'dfid-123'},
              }),
            ),
          ),
        ),
        KgHttpResponse(
          statusCode: 200,
          body: _gzipBody(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'error_code': 0,
                  'data': <String, Object?>{
                    'lists': <Object?>[
                      <String, Object?>{'albumid': 1, 'albumname': 'A'},
                    ],
                  },
                }),
              ),
            ),
          ),
          headers: const <String, String>{'content-encoding': 'gzip'},
        ),
      ]);
      final KgRequestExecutorImpl executor = KgRequestExecutorImpl(
        transport: transport,
        random: Random(7),
      );

      final Map<String, Object?> result = await executor.execute(
        uri: Uri.parse('http://complexsearch.kugou.com/v1/search/album'),
        params: <String, Object?>{
          'sorttype': '0',
          'keyword': 'Kud Wafter Original SoundTrack',
          'pagesize': 20,
          'page': 1,
        },
        module: 'SearchAlbum',
        headers: const <String, String>{'x-router': 'complexsearch.kugou.com'},
      );

      expect(_asList(_asMap(result['data'])['lists']).length, 1);
      expect(transport.calls.length, 2);
      expect(transport.calls.first.uri.path, '/risk/v1/r_register_dev');
      expect(transport.calls.last.uri.path, '/v1/search/album');
    });

    test('legacySearch 可解压 gzip 响应', () async {
      final _FakeKgTransport transport = _FakeKgTransport(<KgHttpResponse>[
        KgHttpResponse(
          statusCode: 200,
          body: _gzipBody(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'status': 1,
                  'error_code': 0,
                  'data': <String, Object?>{
                    'info': <Object?>[
                      <String, Object?>{'specialid': 1, 'specialname': 'S1'},
                    ],
                  },
                }),
              ),
            ),
          ),
          headers: const <String, String>{'content-encoding': 'gzip'},
        ),
      ]);
      final KgRequestExecutorImpl executor = KgRequestExecutorImpl(
        transport: transport,
      );

      final Map<String, Object?> result = await executor.legacySearch(
        keyword: 'Kud Wafter',
        searchType: SearchType.songlist,
        page: 1,
      );

      expect(_asList(_asMap(result['data'])['info']).length, 1);
      expect(transport.calls.length, 1);
    });
  });
}

Uint8List _gzipBody(Uint8List body) {
  return Uint8List.fromList(GZipEncoder().encode(body));
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return value.map<String, Object?>(
      (Object? key, Object? value) =>
          MapEntry<String, Object?>(key?.toString() ?? '', value),
    );
  }
  return <String, Object?>{};
}

List<Object?> _asList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List<dynamic>) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

class _FakeKgTransport implements KgHttpTransport {
  _FakeKgTransport(this._responses);

  final List<KgHttpResponse> _responses;
  final List<
    ({
      String method,
      Uri uri,
      Map<String, String> headers,
      Map<String, String> queryParameters,
    })
  >
  calls =
      <
        ({
          String method,
          Uri uri,
          Map<String, String> headers,
          Map<String, String> queryParameters,
        })
      >[];
  int _index = 0;
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<KgHttpResponse> request({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> queryParameters,
    required Duration timeout,
    Uint8List? body,
  }) async {
    calls.add((
      method: method,
      uri: uri,
      headers: Map<String, String>.from(headers),
      queryParameters: Map<String, String>.from(queryParameters),
    ));
    if (_index >= _responses.length) {
      throw StateError('FakeKgTransport 响应队列不足');
    }
    return _responses[_index++];
  }
}
