import 'dart:typed_data';

import '../http_transport.dart';
import 'lrclib_http_transport.dart';
import 'ne_http_transport.dart';
import 'qm_http_transport.dart';

/// 将共享 HttpTransport 适配为 QQ 音乐请求端口。
class QmHttpTransportAdapter implements QmHttpTransport {
  const QmHttpTransportAdapter(this._transport);

  final HttpTransport _transport;

  @override
  Future<void> close() => _transport.close();

  @override
  Future<QmHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  }) async {
    try {
      final HttpTransportResponse response = await _transport.send(
        HttpTransportRequest(
          method: 'POST',
          uri: uri,
          headers: headers,
          body: body,
          timeout: timeout,
        ),
      );
      return QmHttpResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      throw QmTransportException(error);
    }
  }
}

/// 将共享 HttpTransport 适配为NE云音乐请求端口。
class NeHttpTransportAdapter implements NeHttpTransport {
  const NeHttpTransportAdapter(this._transport);

  final HttpTransport _transport;

  @override
  Future<void> close() => _transport.close();

  @override
  Future<NeHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
    Map<String, String>? queryParameters,
  }) async {
    final HttpTransportResponse response = await _transport.send(
      HttpTransportRequest(
        method: 'POST',
        uri: uri,
        headers: headers,
        queryParameters: queryParameters ?? const <String, String>{},
        body: body,
        timeout: timeout,
      ),
    );
    return NeHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
      cookies: response.cookies,
      headers: response.headers,
    );
  }
}

/// 将共享 HttpTransport 适配为 Lrclib 请求端口。
class LrclibHttpTransportAdapter implements LrclibHttpTransport {
  const LrclibHttpTransportAdapter(this._transport);

  final HttpTransport _transport;

  @override
  Future<void> close() => _transport.close();

  @override
  Future<LrclibHttpResponse> get({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> queryParameters,
    required Duration timeout,
  }) async {
    final HttpTransportResponse response = await _transport.send(
      HttpTransportRequest(
        method: 'GET',
        uri: uri,
        headers: headers,
        queryParameters: queryParameters,
        timeout: timeout,
      ),
    );
    return LrclibHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
  }
}
