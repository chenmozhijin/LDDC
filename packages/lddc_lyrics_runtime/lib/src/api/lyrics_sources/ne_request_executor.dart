import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../json_api_reader.dart';
import 'http_content_decoder.dart';
import 'ne_client_profile.dart';
import 'ne_device_ids.dart';
import 'ne_http_transport.dart';
import 'lyrics_http_transport_stub.dart'
    if (dart.library.io) 'lyrics_http_transport_io.dart'
    if (dart.library.html) 'lyrics_http_transport_web.dart'
    as transport_factory;

/// NE 请求执行器：负责 eapi 加密请求与响应解包。
typedef NeRequestExecutor =
    Future<Map<String, Object?>> Function({
      required String path,
      required Map<String, Object?> params,
    });

/// NE请求执行器实现（对齐Python版 `NEAPI.request`）。
class NeRequestExecutorImpl {
  NeRequestExecutorImpl({
    required this._deviceIdPool,
    NeHttpTransport? transport,
    this._timeout = const Duration(seconds: 10),
    Random? random,
    int Function()? nowMsProvider,
    int Function()? nowSecProvider,
  }) : _transport =
           transport ?? transport_factory.createDefaultNeHttpTransport(),
       _random = random ?? Random(),
       _nowMsProvider =
           nowMsProvider ?? (() => DateTime.now().millisecondsSinceEpoch),
       _nowSecProvider =
           nowSecProvider ??
           (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  static const List<String> _modeCandidates = <String>[
    'MS-iCraft B760M WIFI',
    'ASUS ROG STRIX Z790',
    'MSI MAG B550 TOMAHAWK',
    'ASRock X670E Taichi',
  ];

  final NeHttpTransport _transport;
  final Duration _timeout;
  final NeDeviceIdPool _deviceIdPool;
  final Random _random;
  final int Function() _nowMsProvider;
  final int Function() _nowSecProvider;

  bool _initialized = false;
  int _expireSec = 0;
  Map<String, String> _cookies = <String, String>{};
  Future<void>? _initFuture;

  Future<void> close() => _transport.close();

  /// 对齐Python版匿名登录流程：过期后重新注册游客态。
  Future<void> init() async {
    if (_initialized && _expireSec > _nowSecProvider()) {
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

  /// 执行 eapi 请求。
  Future<Map<String, Object?>> execute({
    required String path,
    required Map<String, Object?> params,
  }) async {
    await init();

    final Map<String, Object?> requestParams = Map<String, Object?>.from(params)
      ..['e_r'] = true
      ..['header'] = _buildParamsHeader(_cookies);
    final String encrypted = eapiParamsEncrypt(
      path: _apiPath(path),
      params: requestParams,
    );

    final String? cacheKey = params['cache_key']?.toString();
    final Map<String, String>? queryParameters =
        cacheKey == null || cacheKey.isEmpty
        ? null
        : <String, String>{'cache_key': cacheKey};

    final NeHttpResponse response = await _transport.post(
      uri: Uri.https('interface.music.163.com', path),
      headers: _buildHeaders(_cookies),
      body: Uint8List.fromList(utf8.encode(encrypted)),
      timeout: _timeout,
      queryParameters: queryParameters,
    );
    _ensureSuccessStatus(response.statusCode);

    final Map<String, Object?> data = _decodeResponse(
      body: response.body,
      headers: response.headers,
    );
    final int code = _parseInt(data['code']) ?? -1;
    if (code != 200) {
      throw LddcApiRequestException(
        'ne API请求错误,错误码:$code,错误信息:${data['message']}',
      );
    }
    return data;
  }

  Future<void> _performInit() async {
    final Map<String, String> preCookies = await _buildPreCookies();
    final String path = '/eapi/register/anonimous';
    final Map<String, Object?> params = <String, Object?>{
      'username': eapiGetAnonymousUsername(preCookies['deviceId']!),
      'e_r': true,
      'header': _buildParamsHeader(preCookies),
    };
    final String encrypted = eapiParamsEncrypt(
      path: _apiPath(path),
      params: params,
    );

    final NeHttpResponse response = await _transport.post(
      uri: Uri.https('interface.music.163.com', path),
      headers: _buildHeaders(preCookies),
      body: Uint8List.fromList(utf8.encode(encrypted)),
      timeout: _timeout,
    );
    _ensureSuccessStatus(response.statusCode);

    final Map<String, Object?> data = _decodeResponse(
      body: response.body,
      headers: response.headers,
    );
    final int code = _parseInt(data['code']) ?? -1;
    if (code != 200) {
      throw LddcApiRequestException(
        'ne API请求错误,错误码:$code,错误信息:${data['message']}',
      );
    }

    final Map<String, String> cookies = <String, String>{
      'WEVNSM': '1.0.0',
      'os': preCookies['os']!,
      'deviceId': preCookies['deviceId']!,
      'osver': preCookies['osver']!,
      'clientSign': preCookies['clientSign']!,
      'channel': 'netease',
      'mode': preCookies['mode']!,
      'NMTID': response.cookies['NMTID'] ?? '',
      'MUSIC_A': response.cookies['MUSIC_A'] ?? '',
      '__csrf': response.cookies['__csrf'] ?? '',
      'appver': preCookies['appver']!,
      'WNMCID':
          '${_randomLetters(6)}.${_nowMsProvider() - _random.nextInt(9001) - 1000}.01.0',
    };
    cookies.removeWhere((String _, String value) => value.isEmpty);

    _cookies = cookies;
    _expireSec = _nowSecProvider() + 864000;
    _initialized = true;
  }

  Future<Map<String, String>> _buildPreCookies() async {
    final String mac = List<String>.generate(
      6,
      (_) =>
          _random.nextInt(255).toRadixString(16).padLeft(2, '0').toUpperCase(),
    ).join(':');
    final String randomUpper = List<String>.generate(
      8,
      (_) => String.fromCharCode('A'.codeUnitAt(0) + _random.nextInt(26)),
    ).join();
    final String hashPart = List<String>.generate(
      64,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();

    final String deviceId = await _deviceIdPool.pick(_random);
    return <String, String>{
      'os': 'pc',
      // 对齐Python版：deviceId 必须来自完整样本池，避免游客注册 400 风控。
      'deviceId': deviceId,
      'osver':
          'Microsoft-Windows-10--build-${200 + _random.nextInt(101)}00-64bit',
      'clientSign': '$mac@@@$randomUpper@@@@@@$hashPart',
      'channel': 'netease',
      'mode': _modeCandidates[_random.nextInt(_modeCandidates.length)],
      'appver': NeClientProfile.desktopAppVersion,
    };
  }

  String _buildParamsHeader(Map<String, String> cookies) {
    return jsonEncode(<String, Object?>{
      'clientSign': cookies['clientSign'],
      'os': cookies['os'],
      'appver': cookies['appver'],
      'deviceId': cookies['deviceId'],
      'requestId': 0,
      'osver': cookies['osver'],
    });
  }

  Map<String, String> _buildHeaders(Map<String, String> cookies) {
    final String cookieHeader = cookies.entries
        .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
        .join('; ');
    return <String, String>{
      'accept': '*/*',
      'content-type': 'application/x-www-form-urlencoded',
      if (cookieHeader.isNotEmpty) 'cookie': cookieHeader,
      'mconfig-info':
          '{"IuRPVVmc3WWul9fT":{"version":${NeClientProfile.mconfigVersion},'
          '"appver":"${NeClientProfile.desktopAppVersion}"}}',
      'origin': 'orpheus://orpheus',
      'user-agent': NeClientProfile.desktopUserAgent,
      'sec-ch-ua': '"Chromium";v="${NeClientProfile.chromiumMajorVersion}"',
      'sec-ch-ua-mobile': '?0',
      'sec-fetch-site': 'cross-site',
      'sec-fetch-mode': 'cors',
      'sec-fetch-dest': 'empty',
      'accept-encoding': 'gzip, deflate, br',
      'accept-language': 'en-US,en;q=0.9',
    };
  }

  Uint8List _apiPath(String path) {
    final String normalized = path.replaceFirst('/eapi', '/api');
    return Uint8List.fromList(utf8.encode(normalized));
  }

  void _ensureSuccessStatus(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) {
      return;
    }
    throw LddcApiRequestException('ne API请求错误,HTTP状态码:$statusCode');
  }

  Map<String, Object?> _decodeResponse({
    required Uint8List body,
    required Map<String, String> headers,
  }) {
    try {
      final Uint8List decodedBody = decodeHttpBody(body, headers);
      final Uint8List plainBytes = eapiResponseDecrypt(decodedBody);
      final Object? decoded = decodeJsonBody(
        plainBytes,
        onParseError: () => const FormatException('invalid json'),
      );
      final Map<String, Object?> data = asJsonMap(decoded);
      if (data.isEmpty) {
        throw const FormatException('empty payload');
      }
      return data;
    } catch (error) {
      throw LddcApiRequestException('ne API响应解析失败:$error');
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

  String _randomLetters(int count) {
    return List<String>.generate(
      count,
      (_) => String.fromCharCode('a'.codeUnitAt(0) + _random.nextInt(26)),
    ).join();
  }
}
