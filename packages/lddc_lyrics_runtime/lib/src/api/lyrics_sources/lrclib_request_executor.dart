import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../json_api_reader.dart';
import 'lrclib_http_transport.dart';
import 'lyrics_http_transport_stub.dart'
    if (dart.library.io) 'lyrics_http_transport_io.dart'
    if (dart.library.html) 'lyrics_http_transport_web.dart'
    as transport_factory;

/// Lrclib 请求执行器。
typedef LrclibRequestExecutor =
    Future<Object?> Function({
      required String endpoint,
      Map<String, String>? params,
    });

/// Lrclib 执行器实现：负责 HTTP 请求与 JSON 解包。
class LrclibRequestExecutorImpl {
  LrclibRequestExecutorImpl({
    LrclibHttpTransport? transport,
    this._timeout = const Duration(seconds: 30),
    this._userAgent = 'LDDC-Flutter',
  }) : _transport =
           transport ?? transport_factory.createDefaultLrclibHttpTransport();

  final LrclibHttpTransport _transport;
  final Duration _timeout;
  final String _userAgent;

  Future<void> close() => _transport.close();

  Future<Object?> execute({
    required String endpoint,
    Map<String, String>? params,
  }) async {
    final LrclibHttpResponse response = await _transport.get(
      uri: Uri.parse('https://lrclib.net/api$endpoint'),
      headers: <String, String>{
        'User-Agent': _userAgent,
        'Accept': 'application/json',
      },
      queryParameters: params ?? const <String, String>{},
      timeout: _timeout,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LddcApiRequestException('lrclib API请求失败: ${response.statusCode}');
    }

    return decodeJsonBody(
      response.body,
      onParseError: () => const LddcApiRequestException('lrclib API响应解析失败'),
    );
  }
}
