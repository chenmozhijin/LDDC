import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../json_api_reader.dart';
import 'translate_http_client.dart';
import 'translate_http_client_stub.dart'
    if (dart.library.io) 'translate_http_client_io.dart'
    if (dart.library.html) 'translate_http_client_web.dart'
    as client_factory;

/// Bing 文本翻译请求执行器。
typedef BingRequestExecutor =
    Future<List<String>> Function({
      required List<String> texts,
      required String targetLang,
      String sourceLang,
    });

/// Bing 请求执行器实现：负责 HTTP 调用与响应解包。
class BingRequestExecutorImpl {
  BingRequestExecutorImpl({
    TranslateHttpClient? client,
    this._timeout = const Duration(seconds: 30),
  }) : _client = client ?? client_factory.createDefaultTranslateHttpClient();

  final TranslateHttpClient _client;
  final Duration _timeout;

  Future<void> close() => _client.close();

  Future<List<String>> execute({
    required List<String> texts,
    required String targetLang,
    String sourceLang = 'auto',
  }) async {
    final Map<String, String> query = <String, String>{'to': targetLang};
    if (sourceLang != 'auto') {
      query['from'] = sourceLang;
    }

    final Uri uri = Uri.https(
      'edge.microsoft.com',
      '/translate/translatetext',
      query,
    );
    final TranslateHttpResponse response = await _client.post(
      uri: uri,
      headers: _headers,
      body: Uint8List.fromList(utf8.encode(jsonEncode(texts))),
      timeout: _timeout,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LddcTranslateException('Bing 翻译请求失败: ${response.statusCode}');
    }

    final Object? payload = decodeJsonBody(
      response.body,
      onParseError: () => const LddcTranslateException('Bing 翻译响应解析失败'),
    );
    final List<Object?> rows = asJsonList(payload);
    final List<String> translated = <String>[];
    for (final Object? row in rows) {
      final Map<String, Object?> rowMap = asJsonMap(row);
      final List<Object?> translations = asJsonList(rowMap['translations']);
      if (translations.isEmpty) {
        throw const LddcTranslateException('Bing 翻译响应缺少 translations');
      }
      final String? text = asJsonMap(translations.first)['text']?.toString();
      if (text == null) {
        throw const LddcTranslateException('Bing 翻译响应缺少 text');
      }
      translated.add(text);
    }
    return translated;
  }

  static const Map<String, String> _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0',
    'Connection': 'keep-alive',
    'Accept': '*/*',
    'Accept-Encoding': 'gzip, deflate, br, zstd',
    'Content-Type': 'application/json',
    'sec-ch-ua-platform': '"Windows"',
    'sec-ch-ua':
        '"Microsoft Edge";v="135", "Not-A.Brand";v="8", "Chromium";v="135"',
    'sec-ch-ua-mobile': '?0',
    'sec-mesh-client-edge-version': '135.0.3179.98',
    'sec-mesh-client-edge-channel': 'stable',
    'sec-mesh-client-os': 'Windows',
    'sec-mesh-client-os-version': '10.0.26100',
    'sec-mesh-client-arch': 'x86_64',
    'sec-mesh-client-webview': '0',
  };
}
