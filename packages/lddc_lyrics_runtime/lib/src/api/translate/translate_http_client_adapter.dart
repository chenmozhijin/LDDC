import 'dart:typed_data';

import '../http_transport.dart';
import 'translate_http_client.dart';

/// 将共享 HttpTransport 适配为翻译请求端口。
class TranslateHttpClientAdapter implements TranslateHttpClient {
  const TranslateHttpClientAdapter(this._transport);

  final HttpTransport _transport;

  @override
  Future<void> close() => _transport.close();

  @override
  Future<TranslateHttpResponse> get({
    required Uri uri,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final HttpTransportResponse response = await _transport.send(
      HttpTransportRequest(
        method: 'GET',
        uri: uri,
        headers: headers,
        timeout: timeout,
      ),
    );
    return _toTranslateResponse(response);
  }

  @override
  Future<TranslateHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  }) async {
    final HttpTransportResponse response = await _transport.send(
      HttpTransportRequest(
        method: 'POST',
        uri: uri,
        headers: headers,
        body: body,
        timeout: timeout,
      ),
    );
    return _toTranslateResponse(response);
  }

  @override
  Future<HttpTransportStreamResponse> postStream({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  }) async {
    final HttpTransport transport = _transport;
    if (transport is! StreamingHttpTransport) {
      throw UnsupportedError('当前平台不支持流式翻译响应');
    }
    final HttpTransportStreamResponse response = await transport.sendStream(
      HttpTransportRequest(
        method: 'POST',
        uri: uri,
        headers: headers,
        body: body,
        timeout: timeout,
      ),
    );
    return HttpTransportStreamResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers.map(
        (String key, String value) =>
            MapEntry<String, String>(key.toLowerCase(), value),
      ),
    );
  }

  TranslateHttpResponse _toTranslateResponse(HttpTransportResponse response) {
    return TranslateHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers.map(
        (String key, String value) =>
            MapEntry<String, String>(key.toLowerCase(), value),
      ),
    );
  }
}
