import 'dart:typed_data';

/// NE请求传输层抽象，便于注入测试替身。
abstract interface class NeHttpTransport {
  Future<NeHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
    Map<String, String>? queryParameters,
  });

  /// 释放传输层持有的网络资源。
  Future<void> close();
}

/// NE HTTP 响应载体。
class NeHttpResponse {
  const NeHttpResponse({
    required this.statusCode,
    required this.body,
    this.cookies = const <String, String>{},
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final Uint8List body;
  final Map<String, String> cookies;
  final Map<String, String> headers;
}
