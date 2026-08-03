import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

const String _q16 = '0123456789abcdef';
const String _firstQ36 = 'b925092ce71e51774071587c100013f14a01';
const String _secondQ36 = 'cb4578cd9a55a5464ba75bea10001f91a70b';

void main() {
  group('QmApiClientImpl', () {
    test('close 释放底层 transport', () async {
      final _Harness harness = _Harness(<_FakeTransportAction>[]);
      await harness.client.close();
      expect(harness.transport.closed, isTrue);
      await harness.disposeCache();
    });

    test('首次初始化 REGISTER、持久化身份并取得 session', () async {
      final _Harness harness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.response(_qimeiResponse()),
        _FakeTransportAction.response(_sessionResponse()),
      ]);

      await harness.client.init();

      expect(harness.client.isInitialized, isTrue);
      expect(harness.client.sessionUid, '1');
      expect(harness.client.activeIdentity?.qimei36, _firstQ36);
      expect(harness.client.commSnapshot['QIMEI36'], _firstQ36);
      expect(
        harness.client.commSnapshot['aid'],
        harness.client.activeIdentity?.androidId,
      );
      final Object? cached = await harness.cache.get('qm_device', 'identity');
      expect(QmDeviceIdentity.tryDecode(cached)?.qimei36, _firstQ36);
      await harness.dispose();
    });

    test('有效缓存身份跳过 REGISTER，直接使用同一 q36 初始化 session', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade cache = CacheFacade(store: store);
      final QmDeviceIdentityRepository repository = QmDeviceIdentityRepository(
        cache: cache,
      );
      final QmDeviceIdentity created = await repository.loadOrCreate(
        const QmDeviceProfile(),
      );
      final QmDeviceIdentity cached = await repository.ensureQimei(
        const QmDeviceProfile(),
        created,
        (_) async => (qimei16: _q16, qimei36: _firstQ36),
      );
      final _FakeQimeiWorker protocol = _FakeQimeiWorker(const <String>[
        _secondQ36,
      ]);
      final _FakeQmHttpTransport transport = _FakeQmHttpTransport(
        <_FakeTransportAction>[
          _FakeTransportAction.response(_sessionResponse()),
        ],
      );
      final QmApiClientImpl client = QmApiClientImpl(
        identityRepository: repository,
        transport: transport,
        protocolWorker: protocol,
        businessResponseDecoder: _identityDecoder,
      );

      await client.init();

      expect(protocol.buildCalls, 0);
      expect(client.activeIdentity?.androidId, cached.androidId);
      expect(client.commSnapshot['QIMEI36'], _firstQ36);
      expect(transport.requests.single.uri.host, 'u.y.qq.com');
      await client.close();
      await cache.dispose();
    });

    test('QIMEI HTTP 503 按白名单重试，HTTP 400 不重试', () async {
      final List<Duration> retrySleeps = <Duration>[];
      final _Harness retryHarness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.response(_statusResponse(503)),
        _FakeTransportAction.response(_qimeiResponse()),
        _FakeTransportAction.response(_sessionResponse()),
      ], sleep: (Duration duration) async => retrySleeps.add(duration));
      await retryHarness.client.init();
      expect(retryHarness.protocol.buildCalls, 2);
      expect(retrySleeps, const <Duration>[Duration(milliseconds: 500)]);
      await retryHarness.dispose();

      final _Harness noRetryHarness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.response(_statusResponse(400)),
        _FakeTransportAction.response(_sessionResponse()),
      ], sleep: (_) async => fail('HTTP 400 不应进入 REGISTER 退避'));
      await noRetryHarness.client.init();
      expect(noRetryHarness.protocol.buildCalls, 1);
      expect(noRetryHarness.client.commSnapshot['QIMEI36'], defaultQimei36);
      await noRetryHarness.dispose();
    });

    test('REGISTER 重试复用 head token，并让 counter 逐次递增', () async {
      final _Harness harness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.error(const QmTransportException('network-1')),
        _FakeTransportAction.error(const QmTransportException('network-2')),
        _FakeTransportAction.response(_qimeiResponse()),
        _FakeTransportAction.response(_sessionResponse()),
      ], sleep: (_) async {});

      await harness.client.init();

      expect(
        harness.protocol.states.map((state) => state.registerCounter),
        <int>[0, 1, 2],
      );
      expect(
        harness.protocol.states.map((state) => state.headDeviceToken).toSet(),
        hasLength(1),
      );
      expect(harness.protocol.states.first.headDeviceToken, isNotEmpty);
      await harness.dispose();
    });

    test('QIMEI 网络失败按 0.5/1.5 秒重试且默认值不入缓存', () async {
      final List<Duration> sleeps = <Duration>[];
      final _Harness harness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.error(const QmTransportException('network-1')),
        _FakeTransportAction.error(const QmTransportException('network-2')),
        _FakeTransportAction.error(const QmTransportException('network-3')),
        _FakeTransportAction.response(_sessionResponse()),
      ], sleep: (Duration duration) async => sleeps.add(duration));

      await harness.client.init();

      expect(sleeps, const <Duration>[
        Duration(milliseconds: 500),
        Duration(milliseconds: 1500),
      ]);
      expect(harness.client.commSnapshot['QIMEI36'], defaultQimei36);
      final Object? cached = await harness.cache.get('qm_device', 'identity');
      expect(QmDeviceIdentity.tryDecode(cached)?.qimei36, isEmpty);
      await harness.dispose();
    });

    test('非预期 QIMEI 异常不会被静默降级', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade cache = CacheFacade(store: store);
      final QmApiClientImpl client = QmApiClientImpl(
        identityRepository: QmDeviceIdentityRepository(cache: cache),
        transport: _FakeQmHttpTransport(const <_FakeTransportAction>[]),
        protocolWorker: const _ThrowingQimeiWorker(),
        businessResponseDecoder: _identityDecoder,
      );

      await expectLater(client.init, throwsA(isA<StateError>()));

      await client.close();
      await cache.dispose();
    });

    test('初始化失败后清理单飞 Future，下一次调用可继续初始化', () async {
      final _Harness harness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.response(_qimeiResponse()),
        _FakeTransportAction.error(const QmTransportException('session-1')),
        _FakeTransportAction.error(const QmTransportException('session-2')),
        _FakeTransportAction.error(const QmTransportException('session-3')),
        _FakeTransportAction.response(_sessionResponse()),
      ], sleep: (_) async {});

      await expectLater(
        harness.client.init,
        throwsA(isA<QmTransportException>()),
      );
      expect(harness.client.isInitialized, isFalse);
      await harness.client.init();

      expect(harness.client.isInitialized, isTrue);
      expect(harness.protocol.buildCalls, 1);
      await harness.dispose();
    });

    test('comm 与业务 User-Agent 完整来自同一个 profile 和 identity', () async {
      const QmDeviceProfile profile = QmDeviceProfile(
        androidVersion: '13',
        model: 'TestModel',
        rom: 'TestRom',
        appCode: '99990001',
        qimeiChannel: '12345',
      );
      final _Harness harness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.response(_qimeiResponse()),
        _FakeTransportAction.response(_sessionResponse()),
      ], profile: profile);

      await harness.client.init();

      final QmDeviceIdentity identity = harness.client.activeIdentity!;
      expect(harness.client.commSnapshot['os_ver'], profile.androidVersion);
      expect(harness.client.commSnapshot['phonetype'], profile.model);
      expect(harness.client.commSnapshot['rom'], profile.rom);
      expect(harness.client.commSnapshot['cv'], profile.appCode);
      expect(harness.client.commSnapshot['chid'], profile.qimeiChannel);
      expect(harness.client.commSnapshot['aid'], identity.androidId);
      expect(harness.client.commSnapshot['OpenUDID2'], identity.openUdid2);
      expect(
        harness.transport.requests.last.headers['User-Agent'],
        profile.userAgent,
      );
      await harness.dispose();
    });

    test('两个客户端共享仓储时只执行一次同 generation REGISTER', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade cache = CacheFacade(store: store);
      final QmDeviceIdentityRepository repository = QmDeviceIdentityRepository(
        cache: cache,
      );
      final _FakeQimeiWorker firstWorker = _FakeQimeiWorker(const <String>[
        _firstQ36,
      ]);
      final _FakeQimeiWorker secondWorker = _FakeQimeiWorker(const <String>[
        _firstQ36,
      ]);
      final _SharedInitTransport firstTransport = _SharedInitTransport();
      final _SharedInitTransport secondTransport = _SharedInitTransport();
      final QmApiClientImpl firstClient = QmApiClientImpl(
        identityRepository: repository,
        transport: firstTransport,
        protocolWorker: firstWorker,
        businessResponseDecoder: _identityDecoder,
      );
      final QmApiClientImpl secondClient = QmApiClientImpl(
        identityRepository: repository,
        transport: secondTransport,
        protocolWorker: secondWorker,
        businessResponseDecoder: _identityDecoder,
      );

      await Future.wait(<Future<void>>[
        firstClient.init(),
        secondClient.init(),
      ]);

      expect(firstWorker.buildCalls + secondWorker.buildCalls, 1);
      expect(
        firstClient.activeIdentity?.androidId,
        secondClient.activeIdentity?.androidId,
      );
      expect(firstClient.commSnapshot['QIMEI36'], _firstQ36);
      expect(secondClient.commSnapshot['QIMEI36'], _firstQ36);
      expect(repository.pendingRegisterCount, 0);
      await firstClient.close();
      await secondClient.close();
      await cache.dispose();
    });

    test('业务传输失败固定同域、复用同一请求体重试三次', () async {
      final List<Duration> sleeps = <Duration>[];
      final _Harness harness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.response(_qimeiResponse()),
        _FakeTransportAction.response(_sessionResponse()),
        _FakeTransportAction.error(const QmTransportException('network-1')),
        _FakeTransportAction.error(const QmTransportException('network-2')),
        _FakeTransportAction.response(
          _businessResponse(
            'module.Method',
            data: <String, Object?>{'ok': true},
          ),
        ),
      ], sleep: (Duration duration) async => sleeps.add(duration));

      final Map<String, Object?> result = await harness.client.request(
        method: 'Method',
        module: 'module',
        param: const <String, Object?>{},
      );

      expect(result, <String, Object?>{'ok': true});
      final List<_CapturedRequest> business = harness.transport.requests
          .where((_CapturedRequest request) => request.uri.host == 'u.y.qq.com')
          .toList(growable: false);
      expect(business.length, 4); // GetSession + 三次业务发送。
      expect(
        business.skip(1).map((_CapturedRequest item) => item.body),
        everyElement(orderedEquals(business[1].body)),
      );
      expect(sleeps, const <Duration>[
        Duration(milliseconds: 500),
        Duration(milliseconds: 1500),
      ]);
      await harness.dispose();
    });

    test('瞬态 2001 使用同一身份重试且不重新 REGISTER', () async {
      final List<Duration> sleeps = <Duration>[];
      final _Harness harness = _Harness(<_FakeTransportAction>[
        _FakeTransportAction.response(_qimeiResponse()),
        _FakeTransportAction.response(_sessionResponse()),
        _FakeTransportAction.response(
          _businessResponse('module.Method', requestCode: 2001),
        ),
        _FakeTransportAction.response(
          _businessResponse(
            'module.Method',
            data: <String, Object?>{'ok': true},
          ),
        ),
      ], sleep: (Duration duration) async => sleeps.add(duration));

      final Map<String, Object?> result = await harness.client.request(
        method: 'Method',
        module: 'module',
        param: const <String, Object?>{},
      );

      expect(result['ok'], true);
      expect(harness.protocol.buildCalls, 1);
      expect(harness.client.activeIdentity?.generation, 0);
      expect(sleeps, const <Duration>[Duration(seconds: 1)]);
      await harness.dispose();
    });

    for (final ({int outerCode, int requestCode}) codes
        in const <({int outerCode, int requestCode})>[
          (outerCode: 2001, requestCode: 0),
          (outerCode: 0, requestCode: 2001),
        ]) {
      test('外层/接口级 2001 换完整身份并只重放一次 $codes', () async {
        final _Harness harness = _Harness(
          <_FakeTransportAction>[
            _FakeTransportAction.response(_qimeiResponse()),
            _FakeTransportAction.response(_sessionResponse()),
            _FakeTransportAction.response(
              _businessResponse(
                'module.Method',
                outerCode: codes.outerCode,
                requestCode: codes.requestCode,
              ),
            ),
            _FakeTransportAction.response(
              _businessResponse(
                'module.Method',
                outerCode: codes.outerCode,
                requestCode: codes.requestCode,
              ),
            ),
            _FakeTransportAction.response(_qimeiResponse()),
            _FakeTransportAction.response(_sessionResponse()),
            _FakeTransportAction.response(
              _businessResponse(
                'module.Method',
                data: <String, Object?>{'ok': true},
              ),
            ),
          ],
          qimeiValues: const <String>[_firstQ36, _secondQ36],
          deviceRejectionCooldown: Duration.zero,
        );

        final Map<String, Object?> result = await harness.client.request(
          method: 'Method',
          module: 'module',
          param: const <String, Object?>{},
        );

        expect(result['ok'], true);
        expect(harness.client.activeIdentity?.generation, 1);
        expect(harness.client.activeIdentity?.qimei36, _secondQ36);
        expect(harness.protocol.buildCalls, 2);
        await harness.dispose();
      });
    }

    test('新身份重放后仍连续 2001 时终止，不再次提升 generation', () async {
      final _Harness harness = _Harness(
        <_FakeTransportAction>[
          _FakeTransportAction.response(_qimeiResponse()),
          _FakeTransportAction.response(_sessionResponse()),
          _FakeTransportAction.response(
            _businessResponse('module.Method', requestCode: 2001),
          ),
          _FakeTransportAction.response(
            _businessResponse('module.Method', requestCode: 2001),
          ),
          _FakeTransportAction.response(_qimeiResponse()),
          _FakeTransportAction.response(_sessionResponse()),
          _FakeTransportAction.response(
            _businessResponse('module.Method', requestCode: 2001),
          ),
          _FakeTransportAction.response(
            _businessResponse('module.Method', requestCode: 2001),
          ),
        ],
        qimeiValues: const <String>[_firstQ36, _secondQ36],
        deviceRejectionCooldown: Duration.zero,
      );

      await expectLater(
        () => harness.client.request(
          method: 'Method',
          module: 'module',
          param: const <String, Object?>{},
        ),
        throwsA(isA<LddcApiRequestException>()),
      );
      expect(harness.client.activeIdentity?.generation, 1);
      expect(harness.protocol.buildCalls, 2);
      await harness.dispose();
    });

    test('并发 2001 只生成一个新身份并执行一次新 REGISTER', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade cache = CacheFacade(store: store);
      final QmDeviceIdentityRepository repository = QmDeviceIdentityRepository(
        cache: cache,
      );
      final _FakeQimeiWorker protocol = _FakeQimeiWorker(const <String>[
        _firstQ36,
        _secondQ36,
      ]);
      final _GenerationTransport transport = _GenerationTransport();
      final QmApiClientImpl client = QmApiClientImpl(
        identityRepository: repository,
        transport: transport,
        protocolWorker: protocol,
        businessResponseDecoder: _identityDecoder,
        deviceRejectionCooldown: Duration.zero,
      );

      await client.init();
      final List<Map<String, Object?>> results = await Future.wait(
        List<Future<Map<String, Object?>>>.generate(
          2,
          (_) => client.request(
            method: 'Method',
            module: 'module',
            param: const <String, Object?>{},
          ),
        ),
      );

      expect(results, <Map<String, Object?>>[
        <String, Object?>{'ok': true},
        <String, Object?>{'ok': true},
      ]);
      expect(transport.qimeiCalls, 2); // 初始 REGISTER + 唯一一次刷新 REGISTER。
      expect(transport.sessionCalls, 2);
      expect(client.activeIdentity?.generation, 1);
      expect(repository.pendingRegisterCount, 0);
      await client.close();
      await cache.dispose();
    });

    test('生产默认路径拒绝非 Brotli 业务响应', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade cache = CacheFacade(store: store);
      final _FakeQmHttpTransport transport =
          _FakeQmHttpTransport(<_FakeTransportAction>[
            _FakeTransportAction.response(_qimeiResponse()),
            _FakeTransportAction.response(_sessionResponse()),
          ]);
      final QmApiClientImpl client = QmApiClientImpl(
        identityRepository: QmDeviceIdentityRepository(cache: cache),
        transport: transport,
        protocolWorker: _FakeQimeiWorker(const <String>[_firstQ36]),
      );

      await expectLater(client.init, throwsA(isA<LddcApiRequestException>()));
      await client.close();
      await cache.dispose();
    });

    test('生产默认路径可解析真实 Brotli GetSession 样本', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade cache = CacheFacade(store: store);
      final _FakeQmHttpTransport transport =
          _FakeQmHttpTransport(<_FakeTransportAction>[
            _FakeTransportAction.response(_qimeiResponse()),
            _FakeTransportAction.response(_brotliSessionResponse()),
          ]);
      final QmApiClientImpl client = QmApiClientImpl(
        identityRepository: QmDeviceIdentityRepository(cache: cache),
        transport: transport,
        protocolWorker: _FakeQimeiWorker(const <String>[_firstQ36]),
      );

      await client.init();
      expect(client.sessionUid, '1');
      await client.close();
      await cache.dispose();
    });

    test('IsolateQimeiProtocolWorker 可跨 isolate 构造并解析协议对象', () async {
      const IsolateQimeiProtocolWorker worker = IsolateQimeiProtocolWorker();
      final QimeiRequestArtifacts artifacts = await worker.buildRequest(
        profile: const QmDeviceProfile(),
        state: const QimeiPayloadState(
          headDeviceToken: '0011223344556677',
          dataLocalTimestampSeconds: 1783352230,
          preauditEnabled: false,
        ),
      );
      final Uint8List plaintext = serializeQimeiProtoMessage(<QimeiProtoField>[
        QimeiProtoField(
          field: 1,
          wire: 2,
          value: Uint8List.fromList(ascii.encode(_q16)),
        ),
        QimeiProtoField(
          field: 2,
          wire: 2,
          value: Uint8List.fromList(ascii.encode(_firstQ36)),
        ),
      ]);

      final ({String qimei16, String qimei36}) parsed = await worker
          .parseResponse(
            response: <String, Object?>{
              'code': 0,
              'data': <String, Object?>{
                'code': 0,
                'data': base64Encode(
                  qimeiAesEncryptCbc(
                    plaintext,
                    artifacts.requestKey,
                    artifacts.requestIv,
                  ),
                ),
              },
            },
            requestKey: artifacts.requestKey,
            requestIv: artifacts.requestIv,
          );

      expect(parsed.qimei16, _q16);
      expect(parsed.qimei36, _firstQ36);
    });
  });
}

final class _Harness {
  _Harness(
    List<_FakeTransportAction> actions, {
    List<String> qimeiValues = const <String>[_firstQ36],
    Future<void> Function(Duration duration)? sleep,
    Duration deviceRejectionCooldown = const Duration(seconds: 1),
    QmDeviceProfile profile = const QmDeviceProfile(),
  }) : store = PersistentCacheStore(executor: NativeDatabase.memory()),
       transport = _FakeQmHttpTransport(actions),
       protocol = _FakeQimeiWorker(qimeiValues) {
    cache = CacheFacade(store: store);
    client = QmApiClientImpl(
      identityRepository: QmDeviceIdentityRepository(cache: cache),
      transport: transport,
      protocolWorker: protocol,
      profile: profile,
      businessResponseDecoder: _identityDecoder,
      sleep: sleep,
      deviceRejectionCooldown: deviceRejectionCooldown,
    );
  }

  final PersistentCacheStore store;
  final _FakeQmHttpTransport transport;
  final _FakeQimeiWorker protocol;
  late final CacheFacade cache;
  late final QmApiClientImpl client;

  Future<void> dispose() async {
    await client.close();
    await cache.dispose();
  }

  Future<void> disposeCache() => cache.dispose();
}

final class _FakeQimeiWorker implements QimeiProtocolWorker {
  _FakeQimeiWorker(List<String> values) : _values = List<String>.from(values);

  final List<String> _values;
  int buildCalls = 0;
  int parseCalls = 0;
  final List<QimeiPayloadState> states = <QimeiPayloadState>[];

  @override
  Future<QimeiRequestArtifacts> buildRequest({
    required QmDeviceProfile profile,
    required QimeiPayloadState state,
  }) async {
    buildCalls += 1;
    states.add(state);
    return QimeiRequestArtifacts(
      command: QimeiCommand.register,
      cpt: '1',
      headers: const <String, String>{'Content-Type': 'application/json'},
      requestBody: const <String, Object?>{'app': 0},
      reqData: const <String, String>{'pms': ''},
      packedPayload: Uint8List(0),
      pmsPlain: Uint8List(0),
      pmsCipher: Uint8List(0),
      requestKey: Uint8List(16),
      requestIv: Uint8List(16),
      ky: '',
      snInput: Uint8List(0),
      sn: '',
    );
  }

  @override
  Future<({String qimei16, String qimei36})> parseResponse({
    required Map<String, Object?> response,
    required Uint8List requestKey,
    required Uint8List requestIv,
  }) async {
    final int index = parseCalls++;
    return (qimei16: _q16, qimei36: _values[index]);
  }
}

final class _ThrowingQimeiWorker implements QimeiProtocolWorker {
  const _ThrowingQimeiWorker();

  @override
  Future<QimeiRequestArtifacts> buildRequest({
    required QmDeviceProfile profile,
    required QimeiPayloadState state,
  }) {
    throw StateError('unexpected-qimei-error');
  }

  @override
  Future<({String qimei16, String qimei36})> parseResponse({
    required Map<String, Object?> response,
    required Uint8List requestKey,
    required Uint8List requestIv,
  }) {
    throw StateError('unexpected-qimei-error');
  }
}

final class _FakeQmHttpTransport implements QmHttpTransport {
  _FakeQmHttpTransport(this._actions);

  final List<_FakeTransportAction> _actions;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];
  int _cursor = 0;
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<QmHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  }) async {
    requests.add(
      _CapturedRequest(
        uri: uri,
        headers: Map<String, String>.unmodifiable(headers),
        body: Uint8List.fromList(body),
      ),
    );
    if (_cursor >= _actions.length) {
      throw StateError('测试 transport action 不足: $uri');
    }
    final _FakeTransportAction action = _actions[_cursor++];
    if (action.error != null) {
      throw action.error!;
    }
    return action.response!;
  }
}

final class _GenerationTransport implements QmHttpTransport {
  int qimeiCalls = 0;
  int sessionCalls = 0;
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<QmHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  }) async {
    if (uri.host == 'api.tencentmusic.com') {
      qimeiCalls += 1;
      return _qimeiResponse();
    }
    final Map<String, Object?> payload = _decodeBusinessRequest(body);
    if (payload.containsKey('music.getSession.session.GetSession')) {
      sessionCalls += 1;
      return _sessionResponse();
    }
    final String qimei =
        (payload['comm']! as Map<String, Object?>)['QIMEI36']! as String;
    return qimei == _firstQ36
        ? _businessResponse('module.Method', requestCode: 2001)
        : _businessResponse(
            'module.Method',
            data: <String, Object?>{'ok': true},
          );
  }
}

final class _SharedInitTransport implements QmHttpTransport {
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<QmHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List body,
    required Duration timeout,
  }) async {
    return uri.host == 'api.tencentmusic.com'
        ? _qimeiResponse()
        : _sessionResponse();
  }
}

final class _FakeTransportAction {
  const _FakeTransportAction._({this.response, this.error});

  factory _FakeTransportAction.response(QmHttpResponse response) =>
      _FakeTransportAction._(response: response);
  factory _FakeTransportAction.error(Object error) =>
      _FakeTransportAction._(error: error);

  final QmHttpResponse? response;
  final Object? error;
}

final class _CapturedRequest {
  const _CapturedRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final Map<String, String> headers;
  final Uint8List body;
}

QmHttpResponse _qimeiResponse() => QmHttpResponse(
  statusCode: 200,
  body: Uint8List.fromList(utf8.encode('{}')),
);

QmHttpResponse _statusResponse(int statusCode) =>
    QmHttpResponse(statusCode: statusCode, body: Uint8List(0));

QmHttpResponse _sessionResponse() => _businessResponse(
  'music.getSession.session.GetSession',
  data: <String, Object?>{
    'session': <String, Object?>{
      'uid': 1,
      'sid': 'sid-1',
      'userip': '127.0.0.1',
    },
  },
);

QmHttpResponse _businessResponse(
  String reqName, {
  int outerCode = 0,
  int requestCode = 0,
  Map<String, Object?> data = const <String, Object?>{},
}) {
  return QmHttpResponse(
    statusCode: 200,
    body: Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'code': outerCode,
          reqName: <String, Object?>{'code': requestCode, 'data': data},
        }),
      ),
    ),
  );
}

QmHttpResponse _brotliSessionResponse() {
  // 由 Python `brotli.compress` 生成，内容为 GetSession 成功 JSON。
  const String hex =
      '1b5700282c0eecd6de5c9817119d7d51955d09c6e55e0c4c1f9dcdd5499db2b4'
      '167121a35b2c7d4e3960cf5b5b1448f2931cf06e63c7293e4189688e8c2d519b'
      'fd89784c223cac70039e06f9617e';
  return QmHttpResponse(statusCode: 200, body: _hexToBytes(hex));
}

Uint8List _identityDecoder(Uint8List body) => Uint8List.fromList(body);

Map<String, Object?> _decodeBusinessRequest(Uint8List body) {
  final Uint8List compressed = Uint8List.sublistView(body, 5);
  final String text = utf8.decode(ZLibDecoder().decodeBytes(compressed));
  return jsonDecode(text) as Map<String, Object?>;
}

Uint8List _hexToBytes(String hex) {
  final Uint8List bytes = Uint8List(hex.length ~/ 2);
  for (int index = 0; index < bytes.length; index += 1) {
    bytes[index] = int.parse(
      hex.substring(index * 2, (index * 2) + 2),
      radix: 16,
    );
  }
  return bytes;
}
