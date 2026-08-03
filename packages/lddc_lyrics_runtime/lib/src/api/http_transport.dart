import 'dart:typed_data';

import '../network/request_cancellation.dart';

/// 共享 HTTP 请求模型。
///
/// 各歌词源和翻译源只需要描述“要发什么请求”，真正的 IO/Web/占位实现由
/// HttpTransport 统一处理。这样新增来源时不会再复制超时、headers、字节读取和
/// close 逻辑，也能降低忘记释放 HttpClient 造成连接泄漏的风险。
class HttpTransportRequest {
  HttpTransportRequest({
    required this.method,
    required this.uri,
    required this.timeout,
    this.headers = const <String, String>{},
    this.queryParameters = const <String, String>{},
    this.body,
    RequestCancellationToken? cancellationToken,
  }) : cancellationToken =
           cancellationToken ?? RequestCancellationToken.current;

  final String method;
  final Uri uri;
  final Duration timeout;

  /// 当前请求的取消令牌；未显式传入时继承当前异步 Zone 的令牌。
  final RequestCancellationToken? cancellationToken;
  final Map<String, String> headers;
  final Map<String, String> queryParameters;
  final Uint8List? body;
}

/// 共享 HTTP 响应模型。
class HttpTransportResponse {
  const HttpTransportResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
    this.cookies = const <String, String>{},
  });

  final int statusCode;
  final Uint8List body;
  final Map<String, String> headers;
  final Map<String, String> cookies;
}

/// 共享 HTTP 流式响应模型。
class HttpTransportStreamResponse {
  const HttpTransportStreamResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
    this.cookies = const <String, String>{},
  });

  final int statusCode;
  final Stream<List<int>> body;
  final Map<String, String> headers;
  final Map<String, String> cookies;
}

/// 共享 HTTP 传输端口。
abstract interface class HttpTransport {
  Future<HttpTransportResponse> send(HttpTransportRequest request);

  /// 释放底层网络资源。
  ///
  /// IO 平台会关闭 HttpClient；Web/占位实现可以是空操作。所有 request executor
  /// 都应在不再使用时调用 close，避免长时间持有连接池。
  Future<void> close();
}

/// 支持边读边处理响应体的 HTTP 传输端口。
///
/// 目前只要求 IO 平台实现，用于 OpenAI 兼容接口的 SSE 流式翻译。
/// Web/占位实现如果无法提供真实字节流，应明确不实现该接口，让上层回落到
/// 普通请求和不确定进度，避免 UI 显示伪造的行级百分比。
abstract interface class StreamingHttpTransport implements HttpTransport {
  Future<HttpTransportStreamResponse> sendStream(HttpTransportRequest request);
}

/// 当前平台不可用时的统一占位实现。
class UnsupportedHttpTransport implements HttpTransport {
  const UnsupportedHttpTransport(this.message);

  final String message;

  @override
  Future<void> close() async {}

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) {
    request.cancellationToken?.throwIfCancelled();
    throw UnsupportedError(
      '$message: ${request.method.toUpperCase()} ${request.uri}',
    );
  }
}
