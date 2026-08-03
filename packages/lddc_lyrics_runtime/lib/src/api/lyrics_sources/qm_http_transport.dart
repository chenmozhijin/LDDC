import 'dart:typed_data';

/// 抽象网络传输层，便于单测注入假实现。
abstract interface class QmHttpTransport {
  Future<QmHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  });

  /// 释放传输层持有的网络资源。
  Future<void> close();
}

/// 底层 HTTP transport 在发出请求或读取响应时失败。
///
/// 只有这个异常允许 QM 客户端执行传输重试；HTTP 状态码和协议解析失败必须由
/// 上层分别处理，避免旧实现把所有错误都误判成可跨域重试。
final class QmTransportException implements Exception {
  const QmTransportException(this.cause);

  final Object cause;

  @override
  String toString() => 'QmTransportException: $cause';
}

/// HTTP 响应数据载体。
class QmHttpResponse {
  const QmHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Uint8List body;
}
