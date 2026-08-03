import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:test/test.dart';

void main() {
  group('Translate Request Executors', () {
    test('close 释放底层 HTTP client', () async {
      final _FakeTranslateHttpClient bingClient = _FakeTranslateHttpClient();
      final _FakeTranslateHttpClient googleClient = _FakeTranslateHttpClient();
      final _FakeTranslateHttpClient openAiClient = _FakeTranslateHttpClient();

      await BingRequestExecutorImpl(client: bingClient).close();
      await GoogleRequestExecutorImpl(client: googleClient).close();
      await OpenAiRequestExecutorImpl(client: openAiClient).close();

      expect(bingClient.closed, isTrue);
      expect(googleClient.closed, isTrue);
      expect(openAiClient.closed, isTrue);
    });

    test('BingRequestExecutorImpl 解析响应并保留 from/to 查询参数', () async {
      final _FakeTranslateHttpClient client = _FakeTranslateHttpClient(
        onPost:
            ({
              required Uri uri,
              required Map<String, String> headers,
              required Uint8List body,
              required Duration timeout,
            }) async {
              expect(uri.host, 'edge.microsoft.com');
              expect(uri.path, '/translate/translatetext');
              expect(uri.queryParameters['to'], 'en');
              expect(uri.queryParameters['from'], 'ja');
              expect(jsonDecode(utf8.decode(body)), <String>['a', 'b']);
              return _jsonResponse(<Object?>[
                <String, Object?>{
                  'translations': <Object?>[
                    <String, Object?>{'text': 'A'},
                  ],
                },
                <String, Object?>{
                  'translations': <Object?>[
                    <String, Object?>{'text': 'B'},
                  ],
                },
              ]);
            },
      );

      final BingRequestExecutorImpl executor = BingRequestExecutorImpl(
        client: client,
      );
      final List<String> translated = await executor.execute(
        texts: <String>['a', 'b'],
        targetLang: 'en',
        sourceLang: 'ja',
      );
      expect(translated, <String>['A', 'B']);
    });

    test('BingRequestExecutorImpl 非 2xx 状态码抛异常', () async {
      final _FakeTranslateHttpClient client = _FakeTranslateHttpClient(
        onPost:
            ({
              required Uri uri,
              required Map<String, String> headers,
              required Uint8List body,
              required Duration timeout,
            }) async {
              return TranslateHttpResponse(statusCode: 503, body: Uint8List(0));
            },
      );

      final BingRequestExecutorImpl executor = BingRequestExecutorImpl(
        client: client,
      );
      await expectLater(
        () => executor.execute(texts: <String>['a'], targetLang: 'en'),
        throwsA(isA<LddcTranslateException>()),
      );
    });

    test('GoogleRequestExecutorImpl 刷新 auth key 并执行翻译请求', () async {
      final _FakeTranslateHttpClient client = _FakeTranslateHttpClient(
        onGet:
            ({
              required Uri uri,
              required Map<String, String> headers,
              required Duration timeout,
            }) async {
              expect(uri.host, 'translate.googleapis.com');
              return _textResponse(
                '"X-goog-api-key":"AIzaSy123456789012345678901234567890123"',
              );
            },
        onPost:
            ({
              required Uri uri,
              required Map<String, String> headers,
              required Uint8List body,
              required Duration timeout,
            }) async {
              expect(uri.host, 'translate-pa.googleapis.com');
              expect(
                headers['X-goog-api-key'],
                'AIzaSy123456789012345678901234567890123',
              );
              expect(jsonDecode(utf8.decode(body)), <Object?>[
                <Object?>[
                  <String>['line-1', 'line-2'],
                  'auto',
                  'ja',
                ],
                'te',
              ]);
              return _jsonResponse(<Object?>[
                <String>['一', '二'],
              ]);
            },
      );

      final GoogleRequestExecutorImpl executor = GoogleRequestExecutorImpl(
        client: client,
      );
      final List<String> translated = await executor.execute(
        texts: <String>['line-1', 'line-2'],
        targetLang: 'ja',
      );
      expect(translated, <String>['一', '二']);
    });

    test('OpenAiRequestExecutorImpl 对齐 endpoint 与默认禁用思考语义', () async {
      final List<Map<String, Object?>> capturedBodies =
          <Map<String, Object?>>[];
      final List<Uri> capturedUris = <Uri>[];
      final _FakeTranslateHttpClient client = _FakeTranslateHttpClient(
        onPost:
            ({
              required Uri uri,
              required Map<String, String> headers,
              required Uint8List body,
              required Duration timeout,
            }) async {
              capturedUris.add(uri);
              capturedBodies.add(
                (jsonDecode(utf8.decode(body)) as Map<Object?, Object?>)
                    .map<String, Object?>(
                      (Object? key, Object? value) =>
                          MapEntry<String, Object?>(key.toString(), value),
                    ),
              );
              return _jsonResponse(<String, Object?>{
                'choices': <Object?>[
                  <String, Object?>{
                    'message': <String, Object?>{'content': '01|ok'},
                  },
                ],
              });
            },
      );

      final OpenAiRequestExecutorImpl executor = OpenAiRequestExecutorImpl(
        client: client,
      );

      final String first = await executor.execute(
        baseUrl: 'https://api.openrouter.ai/v1/',
        apiKey: 'sk1',
        model: 'm1',
        profile: OpenAiProfile.custom,
        prompt: 'p1',
      );
      final String second = await executor.execute(
        baseUrl: 'https://example.test/v1',
        apiKey: 'sk2',
        model: 'm2',
        profile: OpenAiProfile.openRouter,
        prompt: 'p2',
      );
      final String third = await executor.execute(
        baseUrl: 'https://api.siliconflow.cn/v1',
        apiKey: 'sk3',
        model: 'm3',
        profile: OpenAiProfile.siliconFlow,
        prompt: 'p3',
      );
      final String fourth = await executor.execute(
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'sk4',
        model: 'm4',
        profile: OpenAiProfile.deepSeek,
        prompt: 'p4',
      );
      final String fifth = await executor.execute(
        baseUrl: 'https://api.moonshot.cn/v1',
        apiKey: 'sk5',
        model: 'm5',
        profile: OpenAiProfile.kimi,
        prompt: 'p5',
      );

      expect(first, '01|ok');
      expect(second, '01|ok');
      expect(third, '01|ok');
      expect(fourth, '01|ok');
      expect(fifth, '01|ok');
      expect(
        capturedUris[0].toString(),
        'https://api.openrouter.ai/v1/chat/completions',
      );
      expect(capturedBodies[0].containsKey('reasoning'), isFalse);
      expect(capturedBodies[0].containsKey('thinking'), isFalse);
      expect(
        capturedUris[1].toString(),
        'https://example.test/v1/chat/completions',
      );
      expect(capturedBodies[1]['reasoning'], <String, Object?>{
        'effort': 'none',
        'exclude': true,
      });
      expect(capturedBodies[1].containsKey('max_tokens'), isFalse);
      expect(
        capturedUris[2].toString(),
        'https://api.siliconflow.cn/v1/chat/completions',
      );
      expect(capturedBodies[2]['enable_thinking'], false);
      expect(
        capturedUris[3].toString(),
        'https://api.deepseek.com/chat/completions',
      );
      expect(capturedBodies[3]['thinking'], <String, Object?>{
        'type': 'disabled',
      });
      expect(capturedBodies[3].containsKey('reasoning_effort'), isFalse);
      expect(
        capturedUris[4].toString(),
        'https://api.moonshot.cn/v1/chat/completions',
      );
      expect(capturedBodies[4].containsKey('thinking'), isFalse);
      expect(capturedBodies[4].containsKey('reasoning'), isFalse);
    });

    test('OpenAiRequestExecutorImpl 流式响应按完整行上报进度', () async {
      final List<OpenAiTranslationProgress> progresses =
          <OpenAiTranslationProgress>[];
      final _FakeTranslateHttpClient client = _FakeTranslateHttpClient(
        onPostStream:
            ({
              required Uri uri,
              required Map<String, String> headers,
              required Uint8List body,
              required Duration timeout,
            }) async {
              return HttpTransportStreamResponse(
                statusCode: 200,
                body: Stream<List<int>>.fromIterable(<List<int>>[
                  utf8.encode(
                    'data: {"choices":[{"delta":{"content":"01|一\\n"}}]}\n\n',
                  ),
                  utf8.encode(
                    'data: {"choices":[{"delta":{"content":"02|二"}}]}\n\n',
                  ),
                  utf8.encode('data: [DONE]\n\n'),
                ]),
              );
            },
      );
      final OpenAiRequestExecutorImpl executor = OpenAiRequestExecutorImpl(
        client: client,
      );

      final String result = await executor.execute(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk',
        model: 'm',
        profile: OpenAiProfile.custom,
        prompt: 'p',
        totalLines: 2,
        onProgress: progresses.add,
      );

      expect(result, '01|一\n02|二');
      expect(
        progresses.map((OpenAiTranslationProgress progress) {
          return '${progress.completedLines}/${progress.totalLines}/${progress.isIndeterminate}';
        }),
        <String>['1/2/false', '2/2/false'],
      );
    });

    test('OpenAiRequestExecutorImpl 端点不支持流式时回退普通请求', () async {
      final List<OpenAiTranslationProgress> progresses =
          <OpenAiTranslationProgress>[];
      int bufferedCalls = 0;
      final _FakeTranslateHttpClient client = _FakeTranslateHttpClient(
        onPostStream:
            ({
              required Uri uri,
              required Map<String, String> headers,
              required Uint8List body,
              required Duration timeout,
            }) async {
              return HttpTransportStreamResponse(
                statusCode: 400,
                body: Stream<List<int>>.value(
                  utf8.encode('stream unsupported'),
                ),
              );
            },
        onPost:
            ({
              required Uri uri,
              required Map<String, String> headers,
              required Uint8List body,
              required Duration timeout,
            }) async {
              bufferedCalls += 1;
              return _jsonResponse(<String, Object?>{
                'choices': <Object?>[
                  <String, Object?>{
                    'message': <String, Object?>{'content': '01|ok'},
                  },
                ],
              });
            },
      );
      final OpenAiRequestExecutorImpl executor = OpenAiRequestExecutorImpl(
        client: client,
      );

      final String result = await executor.execute(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk',
        model: 'm',
        profile: OpenAiProfile.custom,
        prompt: 'p',
        totalLines: 1,
        onProgress: progresses.add,
      );

      expect(result, '01|ok');
      expect(bufferedCalls, 1);
      expect(progresses.last.isIndeterminate, isTrue);
    });
  });
}

TranslateHttpResponse _jsonResponse(Object? payload, {int statusCode = 200}) {
  return TranslateHttpResponse(
    statusCode: statusCode,
    body: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
  );
}

TranslateHttpResponse _textResponse(String text, {int statusCode = 200}) {
  return TranslateHttpResponse(
    statusCode: statusCode,
    body: Uint8List.fromList(utf8.encode(text)),
  );
}

class _FakeTranslateHttpClient implements TranslateHttpClient {
  _FakeTranslateHttpClient({this.onGet, this.onPost, this.onPostStream});

  final Future<TranslateHttpResponse> Function({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
  })?
  onGet;
  final Future<TranslateHttpResponse> Function({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  })?
  onPost;
  final Future<HttpTransportStreamResponse> Function({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  })?
  onPostStream;
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<TranslateHttpResponse> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final handler = onGet;
    if (handler == null) {
      throw StateError('未配置 GET 处理器');
    }
    return handler(uri: uri, headers: headers, timeout: timeout);
  }

  @override
  Future<TranslateHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  }) async {
    final handler = onPost;
    if (handler == null) {
      throw StateError('未配置 POST 处理器');
    }
    return handler(uri: uri, headers: headers, body: body, timeout: timeout);
  }

  @override
  Future<HttpTransportStreamResponse> postStream({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  }) async {
    final handler = onPostStream;
    if (handler == null) {
      throw UnsupportedError('未配置流式 POST 处理器');
    }
    return handler(uri: uri, headers: headers, body: body, timeout: timeout);
  }
}
