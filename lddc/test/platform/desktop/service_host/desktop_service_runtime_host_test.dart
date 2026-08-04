import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'package:lddc/src/infra/storage/app_storage_paths_io.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_floating_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_panel_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_panel_host_bridge.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_bootstrap_io.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_coordinator.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_launch_arguments.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_selector_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_runtime_host_io.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_session_reducer.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_session_state.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/platform/desktop/window/desktop_panel_snapshot_host_mapper.dart';

import '../../../support/desktop_service_test_support.dart';

void main() {
  group('DesktopServiceHost', () {
    test('hello 初始化会把 panelFontSize 带入首个 session', () async {
      final DesktopSessionReducer reducer = DesktopSessionReducer(
        config: DesktopSessionReducerConfig(panelFontSize: 19),
      );
      final _FakeSingletonBootstrapPort bootstrapPort =
          _FakeSingletonBootstrapPort();
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: bootstrapPort,
        exitHandler: (_) {},
      );
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: reducer,
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: reducer,
        bootstrap: bootstrap,
      );
      addTearDown(() async {
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      await host.ensureStarted();

      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      addTearDown(socket.destroy);
      final TestSocketFrameReader reader = TestSocketFrameReader(socket);
      addTearDown(reader.dispose);
      final DesktopIpcFramer framer = const DesktopIpcFramer();
      socket.add(framer.encodeJson(const DesktopHelloMessage().toJson()));
      await socket.flush();

      final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
          .decodeInstanceAck(await reader.nextFrame());
      final DesktopSessionState? state = coordinator.sessionFor(ack.instanceId);

      expect(state, isNotNull);
      expect(state!.config.panelFontSize, 19);
      expect(buildDesktopPanelWindowSnapshot(state).session.fontSize, 19);
      await waitForCondition(
        () => backend.floatingHost.showCalls.contains(ack.instanceId),
      );
      expect(state.lyricsRuntime.hasStaticDisplay, isTrue);
    });

    test('启动后会注册端口并响应 hello/ack', () async {
      final _FakeSingletonBootstrapPort bootstrapPort =
          _FakeSingletonBootstrapPort();
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: bootstrapPort,
        exitHandler: (_) {},
      );
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: DesktopSessionReducer(),
        bootstrap: bootstrap,
      );
      addTearDown(() async {
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      await host.ensureStarted();

      expect(host.port, isNotNull);
      expect(bootstrapPort.servicePort, host.port);

      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      addTearDown(socket.destroy);
      final TestSocketFrameReader reader = TestSocketFrameReader(socket);
      addTearDown(reader.dispose);
      final DesktopIpcFramer framer = const DesktopIpcFramer();
      socket.add(
        framer.encodeJson(
          const DesktopHelloMessage(
            pid: 1234,
            availableTaskNames: <String>['play', 'pause'],
            clientInfo: DesktopClientInfo(name: 'foo_lddc', version: '1.0'),
          ).toJson(),
        ),
      );
      await socket.flush();

      final Map<String, Object?> ackPayload = await reader.nextFrame();
      final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
          .decodeInstanceAck(ackPayload);

      expect(ack.apiVersion, kDesktopServiceApiVersion);
      expect(ack.instanceId, 1024);
      expect(coordinator.sessionFor(ack.instanceId), isNotNull);
      expect(coordinator.sessionFor(ack.instanceId)?.client.name, 'foo_lddc');
      expect(
        coordinator
            .sessionFor(ack.instanceId)
            ?.lyricsRuntime
            .staticDisplayLines,
        kDesktopServiceWelcomeLines,
      );
      await waitForCondition(
        () => backend.floatingHost.showCalls.contains(ack.instanceId),
      );
      expect(backend.floatingHost.showCalls, contains(ack.instanceId));
    });

    test('macOS 私有控制帧复用业务端口且不影响公开 hello 协议', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'lddc_macos_shared_listener_',
      );
      final AppStoragePaths storagePaths = _createTestStoragePaths(tempDir);
      final DesktopServiceRuntimePaths runtimePaths =
          DesktopServiceRuntimePaths(paths: storagePaths);
      final DesktopMacOsSingletonBootstrapPort singletonPort =
          DesktopMacOsSingletonBootstrapPort(
            runtimePaths: runtimePaths,
            tokenFactory: () => 'e' * 64,
          );
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        infoWriter: DesktopServiceInfoWriter(
          paths: storagePaths,
          commandProvider: () =>
              const DesktopServiceLaunchCommand(executable: 'lddc-test'),
        ),
        singletonPort: singletonPort,
        exitHandler: (_) {},
      );
      final DesktopSessionReducer reducer = DesktopSessionReducer();
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: reducer,
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: reducer,
        bootstrap: bootstrap,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() async {
        debugDefaultTargetPlatformOverride = null;
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final DesktopServiceEntrypointResult entrypoint = await bootstrap
          .prepareEntrypoint(
            windowLaunch: const DesktopWindowLaunchArguments.main(),
            launchArguments: const DesktopServiceLaunchArguments(),
          );
      expect(entrypoint.shouldRunApp, isTrue);
      final File endpoint = await runtimePaths
          .resolveMacOsControlEndpointFile();
      expect(endpoint.existsSync(), isFalse);

      await host.ensureStarted();

      expect(await singletonPort.request('get_service_port'), '${host.port}');
      expect(await singletonPort.request('show'), 'message_received');
      final Map<String, Object?> endpointPayload = Map<String, Object?>.from(
        jsonDecode(endpoint.readAsStringSync())! as Map<Object?, Object?>,
      );
      expect(
        endpointPayload.keys,
        unorderedEquals(<String>['schema', 'port', 'token']),
      );
      expect(endpointPayload['port'], host.port);

      final Socket publicClient = await Socket.connect(
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      final TestSocketFrameReader reader = TestSocketFrameReader(publicClient);
      publicClient.add(
        const DesktopIpcFramer().encodeJson(
          const DesktopHelloMessage().toJson(),
        ),
      );
      await publicClient.flush();
      final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
          .decodeInstanceAck(await reader.nextFrame());
      expect(ack.instanceId, greaterThanOrEqualTo(1024));
      await reader.dispose();

      await host.dispose();
      expect(endpoint.existsSync(), isFalse);
      expect(await singletonPort.hasPrimaryInstance(), isTrue);
      await bootstrap.dispose();
      final DesktopMacOsSingletonBootstrapPort probe =
          DesktopMacOsSingletonBootstrapPort(runtimePaths: runtimePaths);
      addTearDown(probe.close);
      expect(await probe.hasPrimaryInstance(), isFalse);
    });

    test('并发启动只绑定一个服务端口，释放后不能重新启动', () async {
      int binderCallCount = 0;
      final _RuntimeHostHarness harness = _RuntimeHostHarness.create(
        serverSocketBinder: () async {
          binderCallCount += 1;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        },
      );
      addTearDown(harness.dispose);

      await Future.wait(<Future<void>>[
        harness.host.ensureStarted(),
        harness.host.ensureStarted(),
        harness.host.ensureStarted(),
      ]);

      expect(binderCallCount, 1);
      expect(harness.host.isRunning, isTrue);
      expect(harness.bootstrapPort.servicePort, harness.host.port);

      await Future.wait(<Future<void>>[
        harness.host.dispose(),
        harness.host.dispose(),
      ]);
      expect(harness.host.isRunning, isFalse);
      await expectLater(harness.host.ensureStarted(), throwsStateError);
    });

    test('并发 hello 分配不同实例，连接不能操作其他连接的实例', () async {
      final _RuntimeHostHarness harness = _RuntimeHostHarness.create();
      addTearDown(harness.dispose);
      await harness.host.ensureStarted();

      final Socket firstSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        harness.host.port!,
      );
      final Socket secondSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        harness.host.port!,
      );
      final TestSocketFrameReader firstReader = TestSocketFrameReader(
        firstSocket,
      );
      final TestSocketFrameReader secondReader = TestSocketFrameReader(
        secondSocket,
      );
      addTearDown(firstReader.dispose);
      addTearDown(secondReader.dispose);

      const DesktopIpcFramer framer = DesktopIpcFramer();
      firstSocket.add(framer.encodeJson(const DesktopHelloMessage().toJson()));
      secondSocket.add(framer.encodeJson(const DesktopHelloMessage().toJson()));
      await Future.wait(<Future<void>>[
        firstSocket.flush(),
        secondSocket.flush(),
      ]);
      final List<Map<String, Object?>> ackPayloads = await Future.wait(
        <Future<Map<String, Object?>>>[
          firstReader.nextFrame(),
          secondReader.nextFrame(),
        ],
      );
      final DesktopIpcMessageCodec codec = const DesktopIpcMessageCodec();
      final DesktopInstanceAckMessage firstAck = codec.decodeInstanceAck(
        ackPayloads[0],
      );
      final DesktopInstanceAckMessage secondAck = codec.decodeInstanceAck(
        ackPayloads[1],
      );

      expect(firstAck.instanceId, isNot(secondAck.instanceId));

      // 第二个连接先伪造删除第一个实例，再发送自己的同步消息。同步消息被处理
      // 说明前一帧已经走完同一连接的串行队列，此时可稳定检查所有权隔离结果。
      secondSocket
        ..add(
          framer.encodeJson(<String, Object?>{
            'task': 'del_instance',
            'id': firstAck.instanceId,
          }),
        )
        ..add(
          framer.encodeJson(
            DesktopSimpleTaskMessage(
              task: DesktopIpcTask.sync,
              instanceId: secondAck.instanceId,
              playbackTimeMs: 321,
            ).toJson(),
          ),
        );
      await secondSocket.flush();
      await waitForCondition(
        () =>
            harness.coordinator
                .sessionFor(secondAck.instanceId)
                ?.playbackSync
                .pluginPlaybackTimeMs ==
            321,
      );

      expect(harness.coordinator.sessionFor(firstAck.instanceId), isNotNull);
      expect(harness.coordinator.sessionFor(secondAck.instanceId), isNotNull);
    });

    test('释放宿主会等待 panel bridge 完成异步销毁', () async {
      final DesktopSessionReducer reducer = DesktopSessionReducer();
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: reducer,
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final _DelayedDestroyPanelHost panelHost = _DelayedDestroyPanelHost();
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: _FakeSingletonBootstrapPort(),
        exitHandler: (_) {},
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: reducer,
        bootstrap: bootstrap,
        panelHostBridgeController: bridge,
      );
      addTearDown(() async {
        panelHost.completeDestroy();
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      coordinator.upsertSession(
        DesktopSessionState.initial().attachHello(
          hello: const DesktopHelloMessage(),
          apiVersion: kDesktopServiceApiVersion,
          instanceId: 7,
        ),
      );
      await bridge.createPanel(instanceId: 7, panelId: 9, hostWindowId: 11);

      bool disposeCompleted = false;
      final Future<void> disposeFuture = host.dispose().whenComplete(() {
        disposeCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(disposeCompleted, isFalse);
      panelHost.completeDestroy();
      await disposeFuture;
      expect(panelHost.destroyCalls, contains((instanceId: 7, panelId: 9)));
    });

    test('会按 available_tasks 主动回控客户端任务', () async {
      final _FakeSingletonBootstrapPort bootstrapPort =
          _FakeSingletonBootstrapPort();
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: bootstrapPort,
        exitHandler: (_) {},
      );
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: DesktopSessionReducer(),
        bootstrap: bootstrap,
      );
      addTearDown(() async {
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      await host.ensureStarted();

      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      addTearDown(socket.destroy);
      final TestSocketFrameReader reader = TestSocketFrameReader(socket);
      addTearDown(reader.dispose);
      final DesktopIpcFramer framer = const DesktopIpcFramer();
      socket.add(
        framer.encodeJson(
          const DesktopHelloMessage(
            availableTaskNames: <String>['play', 'pause'],
          ).toJson(),
        ),
      );
      await socket.flush();
      final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
          .decodeInstanceAck(await reader.nextFrame());

      final bool sent = await host.sendControlCommand(
        instanceId: ack.instanceId,
        task: DesktopControlCommandTask.play,
      );

      expect(sent, isTrue);
      final DesktopControlCommandMessage command =
          const DesktopIpcMessageCodec().decodeControlCommand(
            await reader.nextFrame(),
          );
      expect(command.task, DesktopControlCommandTask.play);
    });

    test('不支持的 control task 不会回发到客户端', () async {
      final _FakeSingletonBootstrapPort bootstrapPort =
          _FakeSingletonBootstrapPort();
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: bootstrapPort,
        exitHandler: (_) {},
      );
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: DesktopSessionReducer(),
        bootstrap: bootstrap,
      );
      addTearDown(() async {
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      await host.ensureStarted();

      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      addTearDown(socket.destroy);
      final TestSocketFrameReader reader = TestSocketFrameReader(socket);
      addTearDown(reader.dispose);
      final DesktopIpcFramer framer = const DesktopIpcFramer();
      socket.add(
        framer.encodeJson(
          const DesktopHelloMessage(
            availableTaskNames: <String>['pause'],
          ).toJson(),
        ),
      );
      await socket.flush();
      final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
          .decodeInstanceAck(await reader.nextFrame());

      final bool sent = await host.sendControlCommand(
        instanceId: ack.instanceId,
        task: DesktopControlCommandTask.play,
      );

      expect(sent, isFalse);
      final Map<String, Object?>? payload = await reader.nextFrameOrNull();
      expect(payload, isNull);
    });

    test('连续坏帧达到上限后断开客户端且不创建 session', () async {
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: _FakeSingletonBootstrapPort(),
        exitHandler: (_) {},
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: DesktopSessionReducer(),
        bootstrap: bootstrap,
      );
      addTearDown(() async {
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      await host.ensureStarted();

      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      addTearDown(socket.destroy);
      final Completer<void> socketClosed = Completer<void>();
      final StreamSubscription<List<int>> socketSubscription = socket.listen(
        (_) {},
        onDone: () {
          if (!socketClosed.isCompleted) {
            socketClosed.complete();
          }
        },
      );
      addTearDown(socketSubscription.cancel);
      final DesktopIpcFramer framer = const DesktopIpcFramer();
      // 负载是合法 JSON 字符串但不是对象，应计为坏帧而不能进入消息分发。
      final Uint8List badFrame = framer.encodeString('"bad"');
      socket.add(badFrame);
      socket.add(badFrame);
      socket.add(badFrame);
      await socket.flush();

      await socketClosed.future.timeout(const Duration(seconds: 2));

      expect(coordinator.sessionFor(1024), isNull);
      expect(backend.floatingHost.showCalls, isEmpty);
    });

    test('socket 断开后会清理该连接持有的全部实例', () async {
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: _FakeSingletonBootstrapPort(),
        exitHandler: (_) {},
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: DesktopSessionReducer(),
        bootstrap: bootstrap,
      );
      addTearDown(() async {
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      await host.ensureStarted();

      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      final DesktopIpcFramer framer = const DesktopIpcFramer();
      socket.add(framer.encodeJson(const DesktopHelloMessage().toJson()));
      await socket.flush();
      final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
          .decodeInstanceAck(await _readSingleFrame(socket));

      expect(coordinator.sessionFor(ack.instanceId), isNotNull);

      socket.destroy();
      await waitForCondition(
        () => coordinator.sessionFor(ack.instanceId) == null,
      );

      expect(coordinator.sessionFor(ack.instanceId), isNull);
      expect(backend.floatingHost.destroyCalls, contains(ack.instanceId));
    });

    test('少量 socket 断开重连会逐次释放旧实例且不污染新会话', () async {
      final _FakeWindowBackend backend = _FakeWindowBackend();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: _FakeSingletonBootstrapPort(),
        exitHandler: (_) {},
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: DesktopSessionReducer(),
        bootstrap: bootstrap,
      );
      addTearDown(() async {
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      await host.ensureStarted();
      final DesktopIpcFramer framer = const DesktopIpcFramer();
      final List<int> instanceIds = <int>[];

      for (int reconnectIndex = 0; reconnectIndex < 3; reconnectIndex += 1) {
        final Socket socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          host.port!,
        );
        socket.add(framer.encodeJson(const DesktopHelloMessage().toJson()));
        await socket.flush();
        final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
            .decodeInstanceAck(await _readSingleFrame(socket));
        instanceIds.add(ack.instanceId);
        expect(coordinator.sessionFor(ack.instanceId), isNotNull);

        socket.destroy();
        await waitForCondition(
          () => coordinator.sessionFor(ack.instanceId) == null,
        );
      }

      expect(instanceIds.toSet(), hasLength(3));
      expect(backend.floatingHost.destroyCalls, containsAll(instanceIds));
      for (final int instanceId in instanceIds) {
        expect(coordinator.sessionFor(instanceId), isNull);
      }
    });

    test(
      'live routing 会处理插件 raw create_panel / update_panel_surface / destroy_panel / del_instance',
      () async {
        final _FakeWindowBackend backend = _FakeWindowBackend();
        final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
          reducer: DesktopSessionReducer(),
          sceneStore: DesktopInMemorySceneStore(),
          floatingEffectExecutor: DesktopFloatingEffectExecutor(
            windowBackend: backend,
          ),
          panelEffectExecutor: DesktopPanelEffectExecutor(
            windowBackend: backend,
          ),
          selectorEffectExecutor: DesktopSelectorEffectExecutor(
            windowBackend: backend,
          ),
        );
        final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
          singletonPort: _FakeSingletonBootstrapPort(),
          exitHandler: (_) {},
        );
        final DesktopServiceHost host = DesktopServiceHost(
          coordinator: coordinator,
          reducer: DesktopSessionReducer(),
          bootstrap: bootstrap,
          panelHostBridgeController: DesktopPanelHostBridgeController(
            panelHost: backend.panelHost,
            coordinator: coordinator,
          ),
        );
        addTearDown(() async {
          await host.dispose();
          await coordinator.dispose();
          await bootstrap.dispose();
        });

        await host.ensureStarted();

        final Socket socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          host.port!,
        );
        addTearDown(socket.destroy);
        final DesktopIpcFramer framer = const DesktopIpcFramer();
        socket.add(framer.encodeJson(const DesktopHelloMessage().toJson()));
        await socket.flush();
        final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
            .decodeInstanceAck(await _readSingleFrame(socket));

        socket.add(
          framer.encodeJson(
            DesktopChangMusicMessage(
              instanceId: ack.instanceId,
              title: 'Song',
              artist: 'Artist',
              album: 'Album',
              durationMs: 180000,
              path: r'D:\music\song.flac',
              track: 1,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(<String, Object?>{
            'task': 'create_panel',
            'id': ack.instanceId,
            'panel_id': 9,
            'host_window_id': 456,
          }),
        );
        socket.add(
          framer.encodeJson(<String, Object?>{
            'task': 'update_panel_surface',
            'id': ack.instanceId,
            'panel_id': 9,
            'width': 640,
            'height': 180,
            'size_space': 'host_physical_px',
            'visible': true,
          }),
        );
        socket.add(
          framer.encodeJson(<String, Object?>{
            'task': 'destroy_panel',
            'id': ack.instanceId,
            'panel_id': 9,
          }),
        );
        socket.add(
          framer.encodeJson(<String, Object?>{
            'task': 'del_instance',
            'id': ack.instanceId,
          }),
        );
        await socket.flush();

        await waitForCondition(
          () => coordinator.sessionFor(ack.instanceId) == null,
        );
        await waitForCondition(
          () =>
              backend.panelHost.createCalls.any(
                (({int hostWindowId, int instanceId, int panelId}) call) =>
                    call.instanceId == ack.instanceId && call.panelId == 9,
              ) &&
              backend.panelHost.surfaceCalls.any(
                (
                  ({
                    int instanceId,
                    int panelId,
                    int width,
                    int height,
                    PanelSizeSpace sizeSpace,
                    bool visible,
                  })
                  call,
                ) =>
                    call.instanceId == ack.instanceId &&
                    call.panelId == 9 &&
                    call.width == 640 &&
                    call.height == 180 &&
                    call.visible,
              ) &&
              backend.panelHost.destroyCalls.any(
                (({int instanceId, int panelId}) call) =>
                    call.instanceId == ack.instanceId && call.panelId == 9,
              ),
        );

        expect(coordinator.sessionFor(ack.instanceId), isNull);
        expect(
          backend.panelHost.createCalls,
          contains((instanceId: ack.instanceId, panelId: 9, hostWindowId: 456)),
        );
        expect(
          backend.panelHost.surfaceCalls,
          contains((
            instanceId: ack.instanceId,
            panelId: 9,
            width: 640,
            height: 180,
            sizeSpace: PanelSizeSpace.hostPhysicalPx,
            visible: true,
          )),
        );
        expect(
          backend.panelHost.destroyCalls,
          contains((instanceId: ack.instanceId, panelId: 9)),
        );
        expect(backend.floatingHost.destroyCalls, contains(ack.instanceId));
      },
    );

    test('start 不会等待卡死的浮窗同步', () async {
      final _DelayedApplyFloatingHost floatingHost =
          _DelayedApplyFloatingHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
        singletonPort: _FakeSingletonBootstrapPort(),
        exitHandler: (_) {},
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: DesktopSessionReducer(),
        bootstrap: bootstrap,
      );
      addTearDown(() async {
        await host.dispose();
        await coordinator.dispose();
        await bootstrap.dispose();
      });

      await host.ensureStarted();

      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        host.port!,
      );
      addTearDown(socket.destroy);
      final DesktopIpcFramer framer = const DesktopIpcFramer();
      socket.add(framer.encodeJson(const DesktopHelloMessage().toJson()));
      await socket.flush();
      final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
          .decodeInstanceAck(await _readSingleFrame(socket));

      final Stopwatch stopwatch = Stopwatch()..start();
      socket.add(
        framer.encodeJson(
          DesktopSimpleTaskMessage(
            task: DesktopIpcTask.start,
            instanceId: ack.instanceId,
            playbackTimeMs: 1200,
          ).toJson(),
        ),
      );
      socket.add(
        framer.encodeJson(
          DesktopSimpleTaskMessage(
            task: DesktopIpcTask.sync,
            instanceId: ack.instanceId,
            playbackTimeMs: 1300,
          ).toJson(),
        ),
      );
      await socket.flush();

      await waitForCondition(
        () =>
            coordinator
                .sessionFor(ack.instanceId)
                ?.playbackSync
                .pluginPlaybackTimeMs ==
            1300,
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      floatingHost.completeApply();
    });
  });
}

Future<Map<String, Object?>> _readSingleFrame(Socket socket) async {
  final DesktopIpcFrameBuffer buffer = DesktopIpcFrameBuffer();
  await for (final List<int> chunk in socket) {
    final List<Uint8List> frames = buffer.addChunk(chunk);
    if (frames.isEmpty) {
      continue;
    }
    final Object? payload = jsonDecode(utf8.decode(frames.first));
    return Map<String, Object?>.from(payload! as Map<Object?, Object?>);
  }
  throw StateError('socket closed before first frame received');
}

AppStoragePaths _createTestStoragePaths(Directory root) {
  return AppStoragePaths(
    isWindows: false,
    isLinux: false,
    isMacOS: true,
    windowsKnownFolderResolver: (_) async => root.path,
    linuxConfigHomeResolver: () async => root,
    linuxDataHomeResolver: () async => root,
    linuxCacheHomeResolver: () async => root,
    applicationSupportDirectoryResolver: () async => root,
    applicationCacheDirectoryResolver: () async => root,
    applicationDocumentsDirectoryResolver: () async => root,
    libraryDirectoryResolver: () async => root,
  );
}

final class _RuntimeHostHarness {
  _RuntimeHostHarness._({
    required this.host,
    required this.coordinator,
    required this.bootstrap,
    required this.bootstrapPort,
  });

  factory _RuntimeHostHarness.create({
    DesktopServiceServerSocketBinder? serverSocketBinder,
  }) {
    final DesktopSessionReducer reducer = DesktopSessionReducer();
    final _FakeSingletonBootstrapPort bootstrapPort =
        _FakeSingletonBootstrapPort();
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      singletonPort: bootstrapPort,
      exitHandler: (_) {},
    );
    final _FakeWindowBackend backend = _FakeWindowBackend();
    final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
      reducer: reducer,
      sceneStore: DesktopInMemorySceneStore(),
      floatingEffectExecutor: DesktopFloatingEffectExecutor(
        windowBackend: backend,
      ),
      panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
      selectorEffectExecutor: DesktopSelectorEffectExecutor(
        windowBackend: backend,
      ),
    );
    return _RuntimeHostHarness._(
      host: DesktopServiceHost(
        coordinator: coordinator,
        reducer: reducer,
        bootstrap: bootstrap,
        serverSocketBinder: serverSocketBinder,
      ),
      coordinator: coordinator,
      bootstrap: bootstrap,
      bootstrapPort: bootstrapPort,
    );
  }

  final DesktopServiceHost host;
  final DesktopServiceCoordinator coordinator;
  final DesktopServiceBootstrap bootstrap;
  final _FakeSingletonBootstrapPort bootstrapPort;

  Future<void> dispose() async {
    await host.dispose();
    await coordinator.dispose();
    await bootstrap.dispose();
  }
}

class _FakeSingletonBootstrapPort implements DesktopSingletonBootstrapPort {
  int? servicePort;

  @override
  Future<void> close() async {}

  @override
  Future<String?> request(
    String message, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return null;
  }

  @override
  Future<void> setServicePort(int port) async {
    servicePort = port;
  }

  @override
  Future<DesktopPrimaryClaimResult> claimPrimary({
    required DesktopServiceSingletonRequestHandler onRequest,
  }) async => DesktopPrimaryClaimResult.primary;

  @override
  Future<bool> hasPrimaryInstance() async => true;

  @override
  Future<bool> waitUntilPrimaryAvailable({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    return true;
  }
}

class _FakeWindowBackend implements DesktopWindowBackend {
  _FakeWindowBackend({
    _FakeFloatingHost? floatingHost,
    _FakeSelectorHost? selectorHost,
    _FakePanelHost? panelHost,
  }) : floatingHost = floatingHost ?? _FakeFloatingHost(),
       selectorHost = selectorHost ?? _FakeSelectorHost(),
       panelHost = panelHost ?? _FakePanelHost();

  @override
  final _FakeFloatingHost floatingHost;

  @override
  final _FakeSelectorHost selectorHost;

  @override
  final _FakePanelHost panelHost;
}

class _FakeSelectorHost implements DesktopSelectorWindowHostPort {
  @override
  void setIntentHandler(DesktopSelectorWindowIntentHandler? handler) {}

  @override
  Future<void> publishConfigRevision({required int revision}) async {}

  @override
  Future<void> destroySelectorWindow({required int instanceId}) async {}

  @override
  Future<void> ensureSelectorWindow({required int instanceId}) async {}

  @override
  Future<void> hideSelectorWindow({required int instanceId}) async {}

  @override
  Future<void> refreshSelectorContext({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {}

  @override
  Future<void> showSelectorWindow({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {}
}

class _FakeFloatingHost implements DesktopFloatingWindowHostPort {
  final List<int> showCalls = <int>[];
  final List<int> destroyCalls = <int>[];

  @override
  void setIntentHandler(DesktopFloatingWindowIntentHandler? handler) {}

  @override
  Future<void> destroyFloatingWindow({required int instanceId}) async {
    destroyCalls.add(instanceId);
  }

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    if (snapshot.flags.visible) {
      showCalls.add(instanceId);
    }
  }

  @override
  Future<bool> flushFloatingGeometry({required int instanceId}) async => true;
}

class _DelayedApplyFloatingHost extends _FakeFloatingHost {
  final Completer<void> _completer = Completer<void>();

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    await _completer.future;
    await super.applyFloatingSnapshot(
      instanceId: instanceId,
      snapshot: snapshot,
    );
  }

  void completeApply() => _completer.complete();
}

class _FakePanelHost implements DesktopPanelWindowHostPort {
  final List<({int instanceId, int panelId, int hostWindowId})> createCalls =
      <({int instanceId, int panelId, int hostWindowId})>[];
  final List<({int instanceId, int panelId})> destroyCalls =
      <({int instanceId, int panelId})>[];
  final List<
    ({
      int instanceId,
      int panelId,
      int width,
      int height,
      PanelSizeSpace sizeSpace,
      bool visible,
    })
  >
  surfaceCalls =
      <
        ({
          int instanceId,
          int panelId,
          int width,
          int height,
          PanelSizeSpace sizeSpace,
          bool visible,
        })
      >[];
  @override
  void setIntentHandler(DesktopPanelWindowIntentHandler? handler) {}

  @override
  Future<void> createPanel({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    DesktopPanelWindowSnapshot? initialSnapshot,
    PanelSurfaceUpdate? initialSurface,
  }) async {
    createCalls.add((
      instanceId: instanceId,
      panelId: panelId,
      hostWindowId: hostWindowId,
    ));
  }

  @override
  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {
    destroyCalls.add((instanceId: instanceId, panelId: panelId));
  }

  @override
  Future<void> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {
    surfaceCalls.add((
      instanceId: instanceId,
      panelId: panelId,
      width: update.width,
      height: update.height,
      sizeSpace: update.sizeSpace,
      visible: update.visible,
    ));
  }

  @override
  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  }) async {}
}

final class _DelayedDestroyPanelHost extends _FakePanelHost {
  final Completer<void> _destroyCompleter = Completer<void>();

  void completeDestroy() {
    if (!_destroyCompleter.isCompleted) {
      _destroyCompleter.complete();
    }
  }

  @override
  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {
    await _destroyCompleter.future;
    await super.destroyPanel(instanceId: instanceId, panelId: panelId);
  }
}
