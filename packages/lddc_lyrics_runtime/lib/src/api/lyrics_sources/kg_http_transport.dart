import 'dart:typed_data';

import '../http_transport.dart';

/// Kugou 请求传输层抽象，便于单测注入替身。
abstract interface class KgHttpTransport {
  Future<KgHttpResponse> request({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> queryParameters,
    required Duration timeout,
    Uint8List? body,
  });

  /// 释放传输层持有的网络资源。
  Future<void> close();
}

/// Kugou HTTP 响应载体。
class KgHttpResponse {
  const KgHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final Uint8List body;
  final Map<String, String> headers;
}

Uri buildKgUriWithQuery(Uri uri, Map<String, String> queryParameters) {
  if (queryParameters.isEmpty) {
    return uri;
  }
  final String queryText = queryParameters.entries
      // 对齐 requests：空字符串参数必须编码为 `key=`，不能退化成裸 `key`。
      .map<MapEntry<String, String>>(
        (MapEntry<String, String> entry) => MapEntry<String, String>(
          Uri.encodeQueryComponent(entry.key),
          Uri.encodeQueryComponent(entry.value),
        ),
      )
      .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
      .join('&');
  return uri.replace(query: queryText);
}

/// 将共享 HttpTransport 适配为酷狗请求端口。
class KgHttpTransportAdapter implements KgHttpTransport {
  const KgHttpTransportAdapter(this._transport);

  final HttpTransport _transport;

  @override
  Future<void> close() async {
    await _transport.close();
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
    final HttpTransportResponse response = await _transport.send(
      HttpTransportRequest(
        method: method,
        uri: buildKgUriWithQuery(uri, queryParameters),
        headers: headers,
        body: body,
        timeout: timeout,
      ),
    );
    return KgHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }
}
