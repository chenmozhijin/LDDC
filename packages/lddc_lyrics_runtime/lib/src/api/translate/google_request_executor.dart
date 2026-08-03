import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../json_api_reader.dart';
import 'translate_http_client.dart';
import 'translate_http_client_stub.dart'
    if (dart.library.io) 'translate_http_client_io.dart'
    if (dart.library.html) 'translate_http_client_web.dart'
    as client_factory;

/// Google 文本翻译请求执行器。
typedef GoogleRequestExecutor =
    Future<List<String>> Function({
      required List<String> texts,
      required String targetLang,
      String sourceLang,
    });

/// Google 请求执行器实现：负责 auth key 刷新与翻译请求。
class GoogleRequestExecutorImpl {
  GoogleRequestExecutorImpl({
    TranslateHttpClient? client,
    this._timeout = const Duration(seconds: 30),
  }) : _client = client ?? client_factory.createDefaultTranslateHttpClient();

  static const String _fallbackAuthKey =
      'AIzaSyATBXajvzQLTDHEQbcpq0Ihe0vWDHmO520';
  static final RegExp _authKeyPattern = RegExp(
    r'"X-goog-api-key"\s*:\s*"(\w{39})"',
  );

  final TranslateHttpClient _client;
  final Duration _timeout;

  bool _authPrepared = false;
  Future<void>? _authPrepareFuture;
  String _authKey = _fallbackAuthKey;

  Future<void> close() => _client.close();

  Future<List<String>> execute({
    required List<String> texts,
    required String targetLang,
    String sourceLang = 'auto',
  }) async {
    await _prepareAuthKey();

    final List<Object?> payload = <Object?>[
      <Object?>[texts, sourceLang, targetLang],
      'te',
    ];
    final TranslateHttpResponse response = await _client.post(
      uri: Uri.https('translate-pa.googleapis.com', '/v1/translateHtml'),
      headers: <String, String>{..._headers, 'X-goog-api-key': _authKey},
      body: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      timeout: _timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LddcTranslateException('Google 翻译请求失败: ${response.statusCode}');
    }

    final Object? data = decodeJsonBody(
      response.body,
      onParseError: () => const LddcTranslateException('Google 翻译响应解析失败'),
    );
    final List<Object?> root = asJsonList(data);
    if (root.isEmpty) {
      throw const LddcTranslateException('Google 翻译响应为空');
    }
    final List<Object?> translated = asJsonList(root.first);
    return translated.map((Object? item) => item?.toString() ?? '').toList();
  }

  Future<void> _prepareAuthKey() async {
    if (_authPrepared) {
      return;
    }
    final Future<void>? inflight = _authPrepareFuture;
    if (inflight != null) {
      return inflight;
    }
    final Future<void> future = _loadAuthKey().then((bool success) {
      if (success) {
        _authPrepared = true;
      }
    });
    _authPrepareFuture = future;
    try {
      await future;
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      _authPrepareFuture = null;
    }
    if (!_authPrepared) {
      _authPrepareFuture = null;
    }
  }

  Future<bool> _loadAuthKey() async {
    try {
      final TranslateHttpResponse response = await _client.get(
        uri: Uri.parse(
          'https://translate.googleapis.com/_/translate_http/_/js/'
          'k=translate_http.tr.zh_CN.xQDQL-zBfUc.O/am=ACA/d=1/exm=el_conf/ed=1/'
          'rs=AN8SPfq926FSxeFN_C5CEBNv9zTcTCAKGA/m=el_main',
        ),
        headers: _headers,
        timeout: _timeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final String bodyText = utf8.decode(response.body);
      final Match? match = _authKeyPattern.firstMatch(bodyText);
      if (match != null && match.groupCount >= 1) {
        _authKey = match.group(1) ?? _fallbackAuthKey;
      }
      return true;
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      // 对齐Python版：auth key 刷新失败仅记录，不阻断主流程。
      return false;
    }
  }

  static const Map<String, String> _headers = <String, String>{
    'sec-ch-ua':
        '"Not.A/Brand";v="8", "Chromium";v="114", "Google Chrome";v="114"',
    'content-type': 'application/json+protobuf',
    'sec-ch-ua-mobile': '?0',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
    'sec-ch-ua-platform': '"Windows"',
    'accept': '*/*',
    'accept-encoding': 'gzip, deflate, br',
    'accept-language': 'en,zh-CN;q=0.9,zh;q=0.8,ja;q=0.7,en-US;q=0.6',
  };
}
