import 'dart:typed_data';

/// Lrclib 请求传输层抽象，便于单测注入替身。
abstract interface class LrclibHttpTransport {
  Future<LrclibHttpResponse> get({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> queryParameters,
    required Duration timeout,
  });

  /// 释放传输层持有的网络资源。
  Future<void> close();
}

/// Lrclib HTTP 响应载体。
class LrclibHttpResponse {
  const LrclibHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Uint8List body;
}
