import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../json_api_reader.dart';
import 'http_content_decoder.dart';
import 'kg_http_transport.dart';
import 'lyrics_http_transport_stub.dart'
    if (dart.library.io) 'lyrics_http_transport_io.dart'
    if (dart.library.html) 'lyrics_http_transport_web.dart'
    as transport_factory;

/// KG 请求执行器抽象。
abstract interface class KgRequestExecutor {
  Future<Map<String, Object?>> execute({
    required Uri uri,
    required Map<String, Object?> params,
    required String module,
    String method = 'GET',
    String? data,
    Map<String, String>? headers,
  });

  Future<Map<String, Object?>> legacySearch({
    required String keyword,
    required SearchType searchType,
    required int page,
  });

  Future<void> close();
}

/// 酷狗请求执行器实现：负责 dfid 初始化、签名和请求解包。
class KgRequestExecutorImpl implements KgRequestExecutor {
  KgRequestExecutorImpl({
    KgHttpTransport? transport,
    this._timeout = const Duration(seconds: 10),
    Random? random,
    int Function()? nowMsProvider,
    int Function()? nowSecProvider,
  }) : _transport =
           transport ?? transport_factory.createDefaultKgHttpTransport(),
       _random = random ?? Random(),
       _nowMsProvider =
           nowMsProvider ?? (() => DateTime.now().millisecondsSinceEpoch),
       _nowSecProvider =
           nowSecProvider ??
           (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  static const List<String> _legacySearchDomains = <String>[
    'mobiles.kugou.com',
    'msearchcdn.kugou.com',
    'mobilecdnbj.kugou.com',
    'msearch.kugou.com',
  ];

  final KgHttpTransport _transport;
  final Duration _timeout;
  final Random _random;
  final int Function() _nowMsProvider;
  final int Function() _nowSecProvider;

  String? _dfid;
  int _dfidExpireSec = 0;
  Future<void>? _initFuture;

  @override
  Future<void> close() => _transport.close();

  /// 对齐Python版 `KGAPI.init`：启动时申请并缓存 `dfid`。
  Future<void> init() async {
    if (_dfid != null && _dfidExpireSec > _nowSecProvider()) {
      return;
    }
    final Future<void>? inflight = _initFuture;
    if (inflight != null) {
      return inflight;
    }

    final Future<void> future = _performInit();
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
    }
  }

  @override
  Future<Map<String, Object?>> execute({
    required Uri uri,
    required Map<String, Object?> params,
    required String module,
    String method = 'GET',
    String? data,
    Map<String, String>? headers,
  }) async {
    await init();

    final String mid = _md5('${_nowMsProvider()}');
    final Map<String, String> requestHeaders = <String, String>{
      'User-Agent': 'Android14-1070-11070-201-0-$module-wifi',
      'Connection': 'Keep-Alive',
      'Accept-Encoding': 'gzip, deflate',
      'KG-Rec': '1',
      'KG-RC': '1',
      'KG-CLIENTTIMEMS': '${_nowMsProvider()}',
      ...?headers,
    };

    final Map<String, Object?> requestParams;
    if (module == 'Lyric') {
      requestParams = <String, Object?>{
        'appid': '3116',
        'clientver': '11070',
        ...params,
      };
    } else if (module == 'album_song_list') {
      requestParams = <String, Object?>{
        'dfid': _dfid ?? '-',
        'appid': '3116',
        'mid': mid,
        'clientver': '11070',
        'clienttime': _nowSecProvider(),
        'uuid': '-',
      };
      requestHeaders['KG-TID'] = '221';
    } else {
      requestParams = <String, Object?>{
        'userid': '0',
        'appid': '3116',
        'token': '',
        'clienttime': _nowSecProvider(),
        'iscorrection': '1',
        'uuid': '-',
        'mid': mid,
        'dfid': '-',
        'clientver': '11070',
        'platform': 'AndroidFilter',
        ...params,
      };
    }

    requestHeaders['mid'] = mid;
    final String bodyText = data ?? '';
    requestParams['signature'] = _buildSignature(
      params: requestParams,
      bodyText: bodyText,
    );

    final KgHttpResponse response = await _transport.request(
      method: method,
      uri: uri,
      headers: requestHeaders,
      queryParameters: _toStringQuery(requestParams),
      timeout: _timeout,
      body: bodyText.isEmpty ? null : Uint8List.fromList(utf8.encode(bodyText)),
    );
    _ensureSuccessStatus(response.statusCode);

    final Map<String, Object?> responseData = _decodeJsonMap(
      body: response.body,
      headers: response.headers,
    );
    final int errorCode = _parseInt(responseData['error_code']) ?? 0;
    if (errorCode != 0 && errorCode != 200) {
      throw LddcApiRequestException(
        'kg API请求错误,错误码:$errorCode错误信息:${responseData['error_msg']}',
      );
    }
    return responseData;
  }

  @override
  Future<Map<String, Object?>> legacySearch({
    required String keyword,
    required SearchType searchType,
    required int page,
  }) async {
    final String domain =
        _legacySearchDomains[_random.nextInt(_legacySearchDomains.length)];

    late final Uri uri;
    late final Map<String, String> params;

    switch (searchType) {
      case SearchType.song:
        uri = Uri.parse('http://$domain/api/v3/search/song');
        params = <String, String>{
          'showtype': '14',
          'highlight': '',
          'pagesize': '30',
          'tag_aggr': '1',
          'plat': '0',
          'sver': '5',
          'keyword': keyword,
          'correct': '1',
          'api_ver': '1',
          'version': '9108',
          'page': '$page',
        };
      case SearchType.songlist:
        uri = Uri.parse('http://$domain/api/v3/search/special');
        params = <String, String>{
          'version': '9108',
          'highlight': '',
          'keyword': keyword,
          'pagesize': '20',
          'filter': '0',
          'page': '$page',
          'sver': '2',
        };
      case SearchType.album:
        uri = Uri.parse('http://$domain/api/v3/search/album');
        params = <String, String>{
          'version': '9108',
          'iscorrection': '1',
          'highlight': '',
          'plat': '0',
          'keyword': keyword,
          'pagesize': '20',
          'page': '$page',
          'sver': '2',
        };
      default:
        throw LddcApiParamsException('KG 旧搜索不支持类型: ${searchType.value}');
    }

    final KgHttpResponse response = await _transport.request(
      method: 'GET',
      uri: uri,
      headers: const <String, String>{},
      queryParameters: params,
      timeout: const Duration(seconds: 3),
    );
    _ensureSuccessStatus(response.statusCode);
    return _decodeJsonMap(body: response.body, headers: response.headers);
  }

  Future<void> _performInit() async {
    try {
      final String mid = _md5('${_nowMsProvider()}');
      final Map<String, String> params = <String, String>{
        'appid': '1014',
        'platid': '4',
        'mid': mid,
      };

      final List<String> sortedValues =
          params.values
              .where((String value) => value.isNotEmpty)
              .toList(growable: false)
            ..sort();
      params['signature'] = _md5('1014${sortedValues.join()}1014');

      final Uint8List payload = Uint8List.fromList(
        utf8.encode(base64Encode(utf8.encode('{"uuid":""}'))),
      );

      final KgHttpResponse response = await _transport.request(
        method: 'POST',
        uri: Uri.parse('https://userservice.kugou.com/risk/v1/r_register_dev'),
        headers: const <String, String>{},
        queryParameters: params,
        timeout: _timeout,
        body: payload,
      );
      _ensureSuccessStatus(response.statusCode);

      final Map<String, Object?> responseData = _decodeJsonMap(
        body: response.body,
        headers: response.headers,
      );
      final String? dfid = asJsonMap(
        responseData['data'],
      )['dfid']?.toString().trim();
      _dfid = (dfid == null || dfid.isEmpty) ? '-' : dfid;
    } catch (error) {
      if (error is Error) {
        rethrow;
      }
      // 对齐Python版：初始化失败时降级使用 "-"，后续请求继续执行。
      _dfid = '-';
    }

    _dfidExpireSec = _nowSecProvider() + 1800;
  }

  String _buildSignature({
    required Map<String, Object?> params,
    required String bodyText,
  }) {
    final List<String> keys = params.keys.toList(growable: false)..sort();
    final String sortedPairs = keys
        .map((String key) => '$key=${_normalizeValue(params[key])}')
        .join();
    return _md5(
      'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'
      '$sortedPairs'
      '$bodyText'
      'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA',
    );
  }

  String _normalizeValue(Object? value) {
    if (value is Map<Object?, Object?> || value is List<dynamic>) {
      return jsonEncode(value);
    }
    return value?.toString() ?? '';
  }

  String _md5(String text) {
    return md5.convert(utf8.encode(text)).toString();
  }

  void _ensureSuccessStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    throw LddcApiRequestException('kg API请求错误,HTTP状态码:$statusCode');
  }

  Map<String, String> _toStringQuery(Map<String, Object?> params) {
    final Map<String, String> query = <String, String>{};
    for (final MapEntry<String, Object?> entry in params.entries) {
      final Object? value = entry.value;
      if (value == null) {
        continue;
      }
      query[entry.key] = value.toString();
    }
    return query;
  }

  Map<String, Object?> _decodeJsonMap({
    required Uint8List body,
    required Map<String, String> headers,
  }) {
    try {
      final Uint8List decodedBody = decodeHttpBody(body, headers);
      final Object? decoded = decodeJsonBody(
        decodedBody,
        onParseError: () => const FormatException('invalid json'),
      );
      final Map<String, Object?> data = asJsonMap(decoded);
      if (data.isEmpty) {
        throw const FormatException('empty payload');
      }
      return data;
    } catch (error) {
      throw LddcApiRequestException('kg API响应解析失败:$error');
    }
  }

  static int? _parseInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
