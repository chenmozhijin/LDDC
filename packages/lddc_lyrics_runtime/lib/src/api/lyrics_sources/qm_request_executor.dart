import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:brotli/brotli.dart' as brotli;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../logging/runtime_logger.dart';
import '../json_api_reader.dart';
import 'lyrics_http_transport_stub.dart'
    if (dart.library.io) 'lyrics_http_transport_io.dart'
    if (dart.library.html) 'lyrics_http_transport_web.dart'
    as transport_factory;
import 'qm_device_identity_repository.dart';
import 'qm_http_transport.dart';

final Uri _qimeiApiUri = Uri.parse(
  'https://api.tencentmusic.com/tme/trpc/proxy',
);
final Uri _qmBusinessUri = Uri.parse('https://u.y.qq.com/cgi-bin/musics.fcg');
const List<Duration> _retryBackoff = <Duration>[
  Duration(milliseconds: 500),
  Duration(milliseconds: 1500),
];
const Set<int> _qimeiRetryableStatusCodes = <int>{408, 429, 500, 502, 503, 504};

/// 有状态 QM API 客户端端口。
abstract interface class QmApiClient {
  Future<void> init({bool refresh = false});

  Future<Map<String, Object?>> request({
    required String method,
    required String module,
    required Map<String, Object?> param,
  });

  String get sessionUid;

  Future<void> close();
}

/// QIMEI 重密码学执行端口，生产实现放入短生命周期 isolate。
abstract interface class QimeiProtocolWorker {
  Future<QimeiRequestArtifacts> buildRequest({
    required QmDeviceProfile profile,
    required QimeiPayloadState state,
  });

  Future<({String qimei16, String qimei36})> parseResponse({
    required Map<String, Object?> response,
    required Uint8List requestKey,
    required Uint8List requestIv,
  });
}

final class IsolateQimeiProtocolWorker implements QimeiProtocolWorker {
  const IsolateQimeiProtocolWorker();

  @override
  Future<QimeiRequestArtifacts> buildRequest({
    required QmDeviceProfile profile,
    required QimeiPayloadState state,
  }) {
    return Isolate.run(() {
      final Uint8List payload = buildQimeiRegisterPayload(
        profile: profile,
        state: state,
      );
      return buildGetQimei36Request(payload, userAgent: profile.userAgent);
    });
  }

  @override
  Future<({String qimei16, String qimei36})> parseResponse({
    required Map<String, Object?> response,
    required Uint8List requestKey,
    required Uint8List requestIv,
  }) {
    return Isolate.run(
      () => parseQimeiResponse(response, requestKey, requestIv),
    );
  }
}

/// 单测和微基准使用的同步协议 worker。
final class DirectQimeiProtocolWorker implements QimeiProtocolWorker {
  const DirectQimeiProtocolWorker();

  @override
  Future<QimeiRequestArtifacts> buildRequest({
    required QmDeviceProfile profile,
    required QimeiPayloadState state,
  }) async {
    return buildGetQimei36Request(
      buildQimeiRegisterPayload(profile: profile, state: state),
      userAgent: profile.userAgent,
    );
  }

  @override
  Future<({String qimei16, String qimei36})> parseResponse({
    required Map<String, Object?> response,
    required Uint8List requestKey,
    required Uint8List requestIv,
  }) async => parseQimeiResponse(response, requestKey, requestIv);
}

/// QM 会话、设备身份和业务请求的统一实现。
final class QmApiClientImpl implements QmApiClient {
  QmApiClientImpl({
    required this._identityRepository,
    QmHttpTransport? transport,
    this._profile = const QmDeviceProfile(),
    this._protocolWorker = const IsolateQimeiProtocolWorker(),
    this._timeout = const Duration(seconds: 5),
    Random? random,
    int Function()? nowMsProvider,
    Future<void> Function(Duration duration)? sleep,
    QmParamRandomSource Function()? signRandomSourceFactory,
    QmParamRandomSource Function()? teaRandomSourceFactory,
    Uint8List Function(Uint8List body)? businessResponseDecoder,
    this._deviceRejectionCooldown = const Duration(seconds: 1),
    LddcRuntimeLogger logger = const LddcRuntimeLogger(),
  }) : _transport =
           transport ?? transport_factory.createDefaultQmHttpTransport(),
       _random = random ?? Random(),
       _nowMsProvider =
           nowMsProvider ?? (() => DateTime.now().millisecondsSinceEpoch),
       _sleep = sleep ?? Future<void>.delayed,
       _signRandomSourceFactory =
           signRandomSourceFactory ?? DefaultQmParamRandomSource.new,
       _teaRandomSourceFactory =
           teaRandomSourceFactory ?? DefaultQmParamRandomSource.new,
       _businessResponseDecoder =
           businessResponseDecoder ?? _decodeBrotliResponse,
       _logger = logger.child('qm');

  final QmDeviceIdentityRepository _identityRepository;
  final QmHttpTransport _transport;
  final QmDeviceProfile _profile;
  final QimeiProtocolWorker _protocolWorker;
  final Duration _timeout;
  final Random _random;
  final int Function() _nowMsProvider;
  final Future<void> Function(Duration duration) _sleep;
  final QmParamRandomSource Function() _signRandomSourceFactory;
  final QmParamRandomSource Function() _teaRandomSourceFactory;
  final Uint8List Function(Uint8List body) _businessResponseDecoder;
  final Duration _deviceRejectionCooldown;
  final LddcRuntimeLogger _logger;

  final Map<String, Object?> _comm = <String, Object?>{};
  bool _inited = false;
  Future<void>? _initFuture;
  Future<void>? _recoveryFuture;
  QmDeviceIdentity? _activeIdentity;
  _QimeiRegisterRuntime? _qimeiRuntime;

  @override
  String get sessionUid => _comm['uid']?.toString() ?? '';

  QmDeviceIdentity? get activeIdentity => _activeIdentity;
  Map<String, Object?> get commSnapshot =>
      Map<String, Object?>.unmodifiable(_comm);
  bool get isInitialized => _inited;

  @override
  Future<void> close() => _transport.close();

  @override
  Future<void> init({bool refresh = false}) async {
    if (refresh) {
      _inited = false;
    }
    if (_inited) {
      return;
    }
    final Future<void>? active = _initFuture;
    if (active != null) {
      return active;
    }
    final Future<void> future = _runInitialization(allowDeviceRefresh: true);
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
    }
  }

  Future<void> _runInitialization({required bool allowDeviceRefresh}) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    _logger.info(
      '初始化开始',
      fields: <String, Object?>{'allowDeviceRefresh': allowDeviceRefresh},
    );
    QmDeviceIdentity identity = await _identityRepository.loadOrCreate(
      _profile,
    );
    identity = await _ensureQimeiWithFallback(identity);
    _applyIdentity(identity);
    try {
      await _initializeSession();
    } on _QmDeviceRejectedException {
      if (!allowDeviceRefresh) {
        rethrow;
      }
      final ({QmDeviceIdentity identity, bool replaced}) replacement =
          await _identityRepository.replaceIfGeneration(
            _profile,
            identity.generation,
          );
      _logger.warning(
        'GetSession 返回 2001，替换设备身份',
        fields: <String, Object?>{
          'oldGeneration': identity.generation,
          'newGeneration': replacement.identity.generation,
          'replaced': replacement.replaced,
        },
      );
      identity = await _ensureQimeiWithFallback(replacement.identity);
      _applyIdentity(identity);
      try {
        await _initializeSession();
      } on _QmDeviceRejectedException catch (error) {
        throw LddcApiRequestException(error.message);
      }
    }
    _logger.info(
      '初始化完成',
      fields: <String, Object?>{
        'generation': _activeIdentity?.generation,
        'qimei': _maskQimei(_comm['QIMEI36']?.toString()),
        'uid': sessionUid,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      },
    );
  }

  Future<QmDeviceIdentity> _ensureQimeiWithFallback(
    QmDeviceIdentity identity,
  ) async {
    try {
      return await _identityRepository.ensureQimei(
        _profile,
        identity,
        _requestQimei,
      );
    } on QmTransportException catch (error) {
      _logQimeiFallback(error);
      return identity;
    } on _QimeiHttpException catch (error) {
      _logQimeiFallback(error);
      return identity;
    } on QimeiProtocolException catch (error) {
      _logQimeiFallback(error);
      return identity;
    }
  }

  void _logQimeiFallback(Object error) {
    _logger.warning(
      'QIMEI36 获取失败，使用运行时默认值',
      fields: <String, Object?>{'errorType': error.runtimeType.toString()},
    );
  }

  void _applyIdentity(QmDeviceIdentity identity) {
    final QmParamGenerator generator = QmParamGenerator(
      profile: _profile,
      identity: identity,
      teaRandomSourceFactory: _teaRandomSourceFactory,
    );
    final String qimei = hasValidCachedQimei(identity, _profile)
        ? identity.qimei36
        : defaultQimei36;
    _comm
      ..clear()
      ..addAll(<String, Object?>{
        'tyt_exp_env': '0',
        'OpenUDID': generator.openUdid,
        'udid': generator.openUdid,
        'ct': '11',
        'cv': _profile.appCode,
        'v': _profile.appCode,
        'chid': _profile.qimeiChannel,
        'os_ver': _profile.androidVersion,
        'aid': generator.aid,
        'phonetype': _profile.model,
        'OpenUDID2': generator.openUdid2,
        'devicelevel': '50',
        'newdevicelevel': '20',
        'deviceScore': '616.14',
        'QIMEI36': qimei,
        'tmeAppID': 'qqmusic',
        'modeSwitch': '6',
        'teenMode': '0',
        'M-Value': generator.mValue,
        'ui_mode': '1',
        'nettype': '1030',
        'wid': null,
        'rom': _profile.rom,
        'uid': null,
        'sid': null,
        'tmeLoginType': '0',
        'tmeLoginMethod': '0',
        'fPersonality': '0',
        'v4ip': null,
        'hotfix': '200000000',
        'br': '1',
      });
    _activeIdentity = identity;
    _inited = false;
  }

  Future<void> _initializeSession() async {
    final Map<String, Object?> data = await _requestWithSameIdentityRetry(
      method: 'GetSession',
      module: 'music.getSession.session',
      param: const <String, Object?>{'caller': 0, 'uid': '0', 'vkey': 0},
    );
    final Map<String, Object?> session = asJsonMap(data['session']);
    final String uid = session['uid']?.toString() ?? '';
    _comm['wid'] = uid;
    _comm['uid'] = uid;
    _comm['sid'] = session['sid']?.toString();
    _comm['v4ip'] = session['userip']?.toString();
    _inited = true;
  }

  Future<({String qimei16, String qimei36})> _requestQimei(
    QmDeviceIdentity identity,
  ) async {
    final _QimeiRegisterRuntime runtime = _runtimeForIdentity(identity);
    final QimeiPayloadState baseState = QimeiPayloadState(
      cacheQ16: identity.qimei16,
      cacheQ36: identity.qimei36,
      headDeviceToken: runtime.headToken,
      dataLocalSnapshot: identity.dataLocalSnapshot,
      preauditEnabled: _profile.qimeiPreauditEnabled,
    );
    for (int attempt = 0; attempt < 3; attempt += 1) {
      if (attempt > 0) {
        await _sleep(_retryBackoff[attempt - 1]);
      }
      final QimeiRequestArtifacts artifacts = await _protocolWorker
          .buildRequest(
            profile: _profile,
            state: baseState.copyWith(registerCounter: runtime.nextCounter()),
          );
      try {
        final QmHttpResponse response = await _transport.post(
          uri: _qimeiApiUri,
          headers: artifacts.headers,
          body: Uint8List.fromList(
            utf8.encode(jsonEncode(artifacts.requestBody)),
          ),
          timeout: _timeout,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final _QimeiHttpException error = _QimeiHttpException(
            response.statusCode,
          );
          if (!_qimeiRetryableStatusCodes.contains(response.statusCode) ||
              attempt == 2) {
            throw error;
          }
          continue;
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(response.body));
        } catch (_) {
          throw const QimeiProtocolException('QIMEI 响应不是有效 JSON');
        }
        if (decoded is! Map) {
          throw const QimeiProtocolException('QIMEI 响应不是有效 JSON');
        }
        final Map<String, Object?> responseJson = <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in decoded.entries)
            if (entry.key is String) entry.key! as String: entry.value,
        };
        final ({String qimei16, String qimei36}) result = await _protocolWorker
            .parseResponse(
              response: responseJson,
              requestKey: artifacts.requestKey,
              requestIv: artifacts.requestIv,
            );
        _logger.info(
          'QIMEI REGISTER 成功',
          fields: <String, Object?>{
            'attempt': attempt + 1,
            'generation': identity.generation,
            'qimei': _maskQimei(result.qimei36),
          },
        );
        return result;
      } on QmTransportException {
        if (attempt == 2) {
          rethrow;
        }
      }
    }
    throw StateError('QIMEI36 重试循环异常结束');
  }

  _QimeiRegisterRuntime _runtimeForIdentity(QmDeviceIdentity identity) {
    final _QimeiRegisterRuntime? current = _qimeiRuntime;
    if (current != null &&
        current.generation == identity.generation &&
        current.androidId == identity.androidId) {
      return current;
    }
    final _QimeiRegisterRuntime runtime = _QimeiRegisterRuntime(
      generation: identity.generation,
      androidId: identity.androidId,
      headToken: _nativeQimeiHeadToken(_nowMsProvider() ~/ 1000),
    );
    _qimeiRuntime = runtime;
    return runtime;
  }

  @override
  Future<Map<String, Object?>> request({
    required String method,
    required String module,
    required Map<String, Object?> param,
  }) async {
    if (!_inited) {
      await init();
    }
    final int requestGeneration = _activeIdentity?.generation ?? -1;
    try {
      return await _requestWithSameIdentityRetry(
        method: method,
        module: module,
        param: param,
      );
    } on _QmDeviceRejectedException {
      await _ensureRecovery(requestGeneration);
      try {
        return await _requestWithSameIdentityRetry(
          method: method,
          module: module,
          param: param,
        );
      } on _QmDeviceRejectedException catch (error) {
        throw LddcApiRequestException(error.message);
      }
    }
  }

  Future<void> _ensureRecovery(int requestGeneration) async {
    final Future<void>? active = _recoveryFuture;
    if (active != null) {
      return active;
    }
    final Future<void> future = _recoverDevice(requestGeneration);
    _recoveryFuture = future;
    try {
      await future;
    } finally {
      if (identical(_recoveryFuture, future)) {
        _recoveryFuture = null;
      }
    }
  }

  Future<void> _recoverDevice(int requestGeneration) async {
    final ({QmDeviceIdentity identity, bool replaced}) replacement =
        await _identityRepository.replaceIfGeneration(
          _profile,
          requestGeneration,
        );
    if (_activeIdentity?.generation != replacement.identity.generation ||
        _activeIdentity?.androidId != replacement.identity.androidId) {
      _inited = false;
    }
    _logger.warning(
      '开始 2001 设备恢复',
      fields: <String, Object?>{
        'requestGeneration': requestGeneration,
        'currentGeneration': replacement.identity.generation,
        'replaced': replacement.replaced,
      },
    );
    if (!_inited) {
      await _runInitialization(allowDeviceRefresh: false);
    }
  }

  Future<Map<String, Object?>> _requestWithSameIdentityRetry({
    required String method,
    required String module,
    required Map<String, Object?> param,
  }) async {
    try {
      return await _requestOnce(method: method, module: module, param: param);
    } on _QmDeviceRejectedException {
      if (_deviceRejectionCooldown > Duration.zero) {
        await _sleep(_deviceRejectionCooldown);
      }
      return _requestOnce(method: method, module: module, param: param);
    }
  }

  Future<Map<String, Object?>> _requestOnce({
    required String method,
    required String module,
    required Map<String, Object?> param,
  }) async {
    final int startedAt = _nowMsProvider();
    final String reqName = '$module.$method';
    final Uint8List payload = _buildPayload(
      reqName: reqName,
      module: module,
      method: method,
      param: param,
    );
    final QmParamSignResult sign = calcQmParamSign(
      body: payload,
      headers: _buildMaskData(),
      randomSource: _signRandomSourceFactory(),
    );
    final Map<String, String> headers = <String, String>{
      'Cookie': '',
      'Accept': '*/*',
      'sign': sign.p1,
      'User-Agent': _profile.userAgent,
      'M-Encoding': 'm1',
      'Accept-Encoding': '',
      'x-sign-data-type': 'json',
      'mask': sign.p2,
      'Content-Type': 'application/x-www-form-urlencoded',
      'Connection': 'Keep-Alive',
    };
    final Uint8List body = _buildRequestBody(payload);
    late QmHttpResponse response;
    for (int attempt = 0; attempt < 3; attempt += 1) {
      try {
        response = await _transport.post(
          uri: _qmBusinessUri,
          headers: headers,
          body: body,
          timeout: _timeout,
        );
        break;
      } on QmTransportException {
        if (attempt == 2) {
          rethrow;
        }
        await _sleep(_retryBackoff[attempt]);
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LddcApiRequestException(
        'qm API请求错误,HTTP状态码:${response.statusCode}',
      );
    }
    final Uint8List decompressed;
    try {
      decompressed = _businessResponseDecoder(response.body);
    } catch (error) {
      throw LddcApiRequestException('qm API响应Brotli解压失败:$error');
    }
    final Object? decoded;
    try {
      decoded = decodeJsonBody(
        decompressed,
        onParseError: () => const FormatException('invalid json'),
      );
    } catch (error) {
      throw LddcApiRequestException('qm API响应解析失败:$error');
    }
    final Map<String, Object?> responseData = asJsonMap(decoded);
    final int outerCode = _parseInt(responseData['code']) ?? -1;
    final Map<String, Object?> reqData = asJsonMap(responseData[reqName]);
    final int requestCode = _parseInt(reqData['code']) ?? -1;
    final int errorCode = outerCode != 0 ? outerCode : requestCode;
    if (errorCode == 2001) {
      _logger.warning(
        '业务 API 返回 2001',
        fields: <String, Object?>{
          'method': method,
          'generation': _activeIdentity?.generation,
          'qimei': _maskQimei(_comm['QIMEI36']?.toString()),
          'outerCode': outerCode,
          'requestCode': requestCode,
        },
      );
      throw const _QmDeviceRejectedException('QQMusic 设备指纹已失效');
    }
    if (errorCode != 0) {
      throw LddcApiRequestException('qm API请求错误,错误码:$errorCode');
    }
    final Map<String, Object?> data = asJsonMap(reqData['data']);
    if (data.isEmpty && reqData['data'] != null) {
      throw const LddcApiRequestException('qm API响应数据格式错误');
    }
    _logger.info(
      '业务 API 请求成功',
      fields: <String, Object?>{
        'method': method,
        'generation': _activeIdentity?.generation,
        'elapsedMs': _nowMsProvider() - startedAt,
      },
    );
    return data;
  }

  Uint8List _buildPayload({
    required String reqName,
    required String module,
    required String method,
    required Map<String, Object?> param,
  }) {
    final String uid = sessionUid.trim();
    final String traceUid = uid.isEmpty ? 'UnknownUserId' : uid;
    final int traceTimestamp = (_nowMsProvider() ~/ 1000) + 140;
    final Map<String, Object?> comm = <String, Object?>{
      for (final MapEntry<String, Object?> entry in _comm.entries)
        if (entry.value != null) entry.key: entry.value,
      'traceid': '11_${traceUid}_$traceTimestamp',
    };
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'comm': comm,
          reqName: <String, Object?>{
            'module': module,
            'method': method,
            'param': param,
          },
        }),
      ),
    );
  }

  String _buildMaskData() {
    final List<String?> parts = <String?>[
      _comm['ct']?.toString(),
      _comm['cv']?.toString(),
      _comm['uid']?.toString(),
      null,
      _nowMsProvider().toString(),
      _comm['udid']?.toString(),
      'android',
    ];
    return parts
        .map((String? item) => item == null || item.isEmpty ? 'null' : item)
        .join('&');
  }

  Uint8List _buildRequestBody(Uint8List payload) {
    final List<int> compressed = ZLibEncoder().encode(payload);
    final Uint8List body = Uint8List(5 + compressed.length);
    for (int index = 0; index < 5; index += 1) {
      body[index] = _random.nextInt(100);
    }
    body.setRange(5, body.length, compressed);
    return body;
  }

  static int? _parseInt(Object? value) {
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

Uint8List _decodeBrotliResponse(Uint8List body) {
  return Uint8List.fromList(brotli.brotliDecode(body));
}

final class _QimeiRegisterRuntime {
  _QimeiRegisterRuntime({
    required this.generation,
    required this.androidId,
    required this.headToken,
  });

  final int generation;
  final String androidId;
  final String headToken;
  int _counter = 0;

  int nextCounter() => _counter++;
}

final class _QmDeviceRejectedException implements Exception {
  const _QmDeviceRejectedException(this.message);

  final String message;
}

final class _QimeiHttpException implements Exception {
  const _QimeiHttpException(this.statusCode);

  final int statusCode;
}

String _nativeQimeiHeadToken(int timestampSeconds) {
  final Uint8List bytes = Uint8List(8);
  bytes.buffer.asByteData()
    ..setUint32(0, 0x12417050, Endian.little)
    ..setUint32(4, timestampSeconds, Endian.little);
  return bytes
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

String _maskQimei(String? qimei) {
  if (qimei == null || qimei.isEmpty) {
    return '<empty>';
  }
  if (qimei.length <= 12) {
    return '<short>';
  }
  return '${qimei.substring(0, 6)}...${qimei.substring(qimei.length - 6)}';
}
