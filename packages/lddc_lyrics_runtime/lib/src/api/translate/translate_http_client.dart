import 'dart:typed_data';

import '../http_transport.dart';

/// 翻译 HTTP 响应模型。
class TranslateHttpResponse {
  const TranslateHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final Uint8List body;
  final Map<String, String> headers;
}

/// 翻译 HTTP 客户端端口。
abstract interface class TranslateHttpClient {
  Future<TranslateHttpResponse> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
  });

  Future<TranslateHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  });

  Future<HttpTransportStreamResponse> postStream({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  });

  /// 释放客户端持有的网络资源。
  Future<void> close();
}
