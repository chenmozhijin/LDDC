import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/desktop_service_host_exports.dart';

void main() {
  final DesktopWindowLifecycleRegistryController lifecycle =
      DesktopWindowLifecycleRegistryController.instance;

  setUp(lifecycle.debugResetForTests);
  tearDown(lifecycle.debugResetForTests);

  group('DesktopMultiWindowFloatingWindowHost', () {
    test('初始几何就绪前不会发送内容或显示浮窗', () async {
      final Completer<Object?> ready = Completer<Object?>();
      final _FakeDesktopRemoteWindow mainWindow = _FakeDesktopRemoteWindow(
        windowId: '2',
      );
      final _FakeDesktopRemoteWindow floatingWindow = _FakeDesktopRemoteWindow(
        windowId: '10',
        resultForMethod: (String method, Object? arguments) {
          if (method == DesktopWindowMethodNames.floatingAwaitReady) {
            return ready.future;
          }
          return true;
        },
      );
      final DesktopMultiWindowFloatingWindowHost host =
          DesktopMultiWindowFloatingWindowHost(
            sceneStore: DesktopInMemorySceneStore(),
            multiWindowPort: _FakeDesktopMultiWindowPort(
              currentWindowRef: mainWindow,
              createdWindows: <_FakeDesktopRemoteWindow>[floatingWindow],
            ),
          );

      final Future<void> apply = host.applyFloatingSnapshot(
        instanceId: 7,
        snapshot: DesktopFloatingWindowSnapshot(
          session: DesktopFloatingSessionSnapshot(),
          initialWindowRect: const WindowRect(
            left: 120,
            top: 240,
            width: 900,
            height: 180,
          ),
          flags: const DesktopFloatingWindowFlags(visible: true),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        floatingWindow.invocations.map((_Invocation value) => value.method),
        <String>[DesktopWindowMethodNames.floatingAwaitReady],
      );
      expect(floatingWindow.showCount, 0);

      ready.complete(true);
      await apply;

      expect(
        floatingWindow.invocations.map((_Invocation value) => value.method),
        containsAllInOrder(<String>[
          DesktopWindowMethodNames.floatingAwaitReady,
          DesktopWindowMethodNames.floatingApplyContent,
          DesktopWindowMethodNames.floatingUpdateFlags,
        ]),
      );
      expect(floatingWindow.showCount, 0);
    });

    test('原子发送内容，锚点保持独立高频消息', () async {
      final _FakeDesktopRemoteWindow mainWindow = _FakeDesktopRemoteWindow(
        windowId: '3',
      );
      final _FakeDesktopRemoteWindow floatingWindow = _FakeDesktopRemoteWindow(
        windowId: '11',
      );
      final _FakeDesktopMultiWindowPort port = _FakeDesktopMultiWindowPort(
        currentWindowRef: mainWindow,
        createdWindows: <_FakeDesktopRemoteWindow>[floatingWindow],
      );
      final DesktopInMemorySceneStore sceneStore = DesktopInMemorySceneStore();
      const DesktopSceneRef sceneRef = DesktopSceneRef(
        sceneId: '8:1',
        sceneRevision: 1,
        checksum: 'abcd',
      );
      final Uint8List bytes = const DesktopLyricsSceneCodec().encode(
        DesktopLyricsSceneDocument(
          mode: DesktopLyricsSceneMode.staticText,
          selectedLangs: <String>['orig'],
          langOrder: <String>['orig'],
          durationMs: null,
          staticDisplayLines: <String>['欢迎使用'],
        ),
      );
      sceneStore.putScene(
        sceneRef.sceneId,
        bytes,
        revision: sceneRef.sceneRevision,
        checksum: sceneRef.checksum,
      );
      final DesktopMultiWindowFloatingWindowHost host =
          DesktopMultiWindowFloatingWindowHost(
            sceneStore: sceneStore,
            multiWindowPort: port,
          );

      await host.applyFloatingSnapshot(
        instanceId: 8,
        snapshot: DesktopFloatingWindowSnapshot(
          session: DesktopFloatingSessionSnapshot(songTitle: 'Scene'),
          initialWindowRect: const WindowRect(
            left: 120,
            top: 240,
            width: 900,
            height: 180,
          ),
          sceneRef: sceneRef,
          anchor: const DesktopFloatingAnchorSnapshot(
            syncRevision: 3,
            sceneId: '8:1',
            songToken: 'song-8',
          ),
          flags: const DesktopFloatingWindowFlags(visible: true),
        ),
      );

      expect(port.createdArguments.single.role, DesktopWindowRole.floating);
      expect(port.createdArguments.single.initialWindowRect?.left, 120);
      expect(port.createdArguments.single.initialWindowRect?.top, 240);
      expect(
        floatingWindow.invocations.map((_Invocation value) => value.method),
        <String>[
          DesktopWindowMethodNames.floatingAwaitReady,
          DesktopWindowMethodNames.floatingApplyContent,
          DesktopWindowMethodNames.floatingSyncAnchor,
          DesktopWindowMethodNames.floatingUpdateFlags,
        ],
      );
      expect(floatingWindow.showCount, 0);
      final _Invocation contentInvocation = floatingWindow.invocations
          .firstWhere(
            (_Invocation value) =>
                value.method == DesktopWindowMethodNames.floatingApplyContent,
          );
      final Map<Object?, Object?> contentMap =
          contentInvocation.arguments! as Map<Object?, Object?>;
      final Map<Object?, Object?> sessionMap =
          contentMap['session']! as Map<Object?, Object?>;
      expect(sessionMap.containsKey('windowRect'), isFalse);
      final DesktopFloatingContentPayload payload =
          DesktopWindowPayloadCodec.decodeFloatingContentPayload(
            contentInvocation.arguments,
          );
      expect(payload.sceneRef?.sceneId, sceneRef.sceneId);
      expect(payload.sceneBytes, isNotEmpty);
    });

    test('主窗口 intent handler 返回真实结果', () async {
      final _FakeDesktopRemoteWindow mainWindow = _FakeDesktopRemoteWindow(
        windowId: '15',
      );
      final _FakeDesktopRemoteWindow floatingWindow = _FakeDesktopRemoteWindow(
        windowId: '25',
      );
      final DesktopMultiWindowFloatingWindowHost host =
          DesktopMultiWindowFloatingWindowHost(
            sceneStore: DesktopInMemorySceneStore(),
            multiWindowPort: _FakeDesktopMultiWindowPort(
              currentWindowRef: mainWindow,
              createdWindows: <_FakeDesktopRemoteWindow>[floatingWindow],
            ),
          );
      await host.applyFloatingSnapshot(
        instanceId: 12,
        snapshot: DesktopFloatingWindowSnapshot(
          session: DesktopFloatingSessionSnapshot(),
          flags: const DesktopFloatingWindowFlags(),
        ),
      );
      host.setIntentHandler((DesktopFloatingWindowIntent intent) async => true);

      final Object? handled = await mainWindow.emit(
        DesktopWindowMethodNames.floatingMetricsCommittedIntent,
        DesktopWindowPayloadCodec.encodeFloatingMetricsCommittedIntent(
          const DesktopFloatingMetricsCommittedIntent(
            instanceId: 12,
            windowRect: WindowRect(left: 1, top: 2, width: 480, height: 160),
            fontSize: 26,
          ),
        ),
      );

      expect(handled, isTrue);
    });
  });

  group('WindowsEmbeddedPanelWindowHost', () {
    test('拒绝非正数通道超时', () {
      expect(
        () => WindowsEmbeddedPanelWindowHost(
          sceneStore: DesktopInMemorySceneStore(),
          lifecycleRegistry: lifecycle,
          panelShellPort: _FakeEmbeddedPanelShellPort(),
          channelOperationTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('session 与 scene 原子发送，anchor 保持独立', () async {
      final DesktopInMemorySceneStore sceneStore = DesktopInMemorySceneStore();
      const DesktopSceneRef sceneRef = DesktopSceneRef(
        sceneId: '1:2',
        sceneRevision: 2,
        checksum: 'panel123',
      );
      sceneStore.putScene(
        sceneRef.sceneId,
        const DesktopLyricsSceneCodec().encode(
          DesktopLyricsSceneDocument(
            mode: DesktopLyricsSceneMode.staticText,
            selectedLangs: <String>['orig'],
            langOrder: <String>['orig'],
            durationMs: null,
            staticDisplayLines: <String>['欢迎使用'],
          ),
        ),
        revision: sceneRef.sceneRevision,
        checksum: sceneRef.checksum,
      );
      final _PanelHarness harness = _PanelHarness(
        lifecycle: lifecycle,
        sceneStore: sceneStore,
      );
      addTearDown(harness.host.dispose);

      await harness.host.createPanel(
        instanceId: 1,
        panelId: 7,
        hostWindowId: 2048,
        initialSurface: const PanelSurfaceUpdate(
          width: 640,
          height: 360,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: false,
        ),
        initialSnapshot: DesktopPanelWindowSnapshot(
          session: DesktopPanelSessionSnapshot(refreshRate: 90),
          anchor: const DesktopPanelAnchorSnapshot(
            syncRevision: 4,
            sceneId: '1:2',
            songToken: 'song-1',
          ),
          sceneRef: sceneRef,
        ),
      );

      final _FakeEmbeddedPanelMethodChannel channel = harness.channel;
      expect(
        channel.invocations.map((_ChannelInvocation value) => value.method),
        <String>[
          DesktopWindowMethodNames.panelSurfaceStateSync,
          DesktopWindowMethodNames.panelApplyContent,
          DesktopWindowMethodNames.panelSyncAnchor,
        ],
      );
      final DesktopPanelContentPayload payload =
          DesktopWindowPayloadCodec.decodePanelContentPayload(
            channel.invocations[1].arguments,
          );
      expect(payload.contentRevision, 1);
      expect(payload.sceneRef?.sceneId, '1:2');
      expect(payload.sceneBytes, isNotEmpty);
    });

    test('Panel action 使用唯一异步 handler 并返回真实结果', () async {
      final _PanelHarness harness = _PanelHarness(lifecycle: lifecycle);
      addTearDown(harness.host.dispose);
      await harness.host.createPanel(
        instanceId: 2,
        panelId: 9,
        hostWindowId: 3001,
      );
      DesktopPanelWindowIntent? received;
      harness.host.setIntentHandler((DesktopPanelWindowIntent intent) async {
        received = intent;
        return true;
      });

      final Object? handled = await harness.channel.emit(
        DesktopWindowMethodNames.panelActionIntent,
        DesktopWindowPayloadCodec.encodePanelActionIntent(
          const DesktopPanelActionIntent(
            instanceId: 2,
            panelId: 9,
            action: DesktopWindowActionType.openSelector,
          ),
        ),
      );

      expect(handled, isTrue);
      expect(received, isA<DesktopPanelActionIntent>());
    });

    test('hidden 到 visible 只接受匹配 content/surface revision 的帧', () async {
      final _PanelHarness harness = _PanelHarness(lifecycle: lifecycle);
      addTearDown(harness.host.dispose);
      await harness.host.createPanel(
        instanceId: 3,
        panelId: 4,
        hostWindowId: 4001,
        initialSurface: const PanelSurfaceUpdate(
          width: 640,
          height: 360,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: false,
        ),
      );
      harness.shell.nextSurfaceRevision = 2;
      bool completed = false;
      final Future<void> update = harness.host
          .updatePanelSurface(
            instanceId: 3,
            panelId: 4,
            update: const PanelSurfaceUpdate(
              width: 800,
              height: 450,
              sizeSpace: PanelSizeSpace.hostPhysicalPx,
              visible: true,
            ),
          )
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      await harness.channel.emit(
        DesktopWindowMethodNames.panelPresentationReady,
        DesktopWindowPayloadCodec.encodePanelPresentationReady(
          const DesktopPanelPresentationReady(
            contentRevision: 0,
            surfaceRevision: 1,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(harness.shell.visibilityRequests, isEmpty);

      await harness.channel.emit(
        DesktopWindowMethodNames.panelPresentationReady,
        DesktopWindowPayloadCodec.encodePanelPresentationReady(
          const DesktopPanelPresentationReady(
            contentRevision: 0,
            surfaceRevision: 2,
          ),
        ),
      );
      await update;

      expect(harness.shell.visibilityRequests, <bool>[true]);
    });

    test('runtime 未就绪时销毁原生对象且不注册半成品', () async {
      final _FakeEmbeddedPanelShellPort shell = _FakeEmbeddedPanelShellPort(
        emitRuntimeReady: false,
      );
      final Map<String, _FakeEmbeddedPanelMethodChannel> channels =
          <String, _FakeEmbeddedPanelMethodChannel>{};
      final WindowsEmbeddedPanelWindowHost host =
          WindowsEmbeddedPanelWindowHost(
            sceneStore: DesktopInMemorySceneStore(),
            lifecycleRegistry: lifecycle,
            panelShellPort: shell,
            channelOperationTimeout: const Duration(milliseconds: 20),
            channelFactory: (String name) {
              final _FakeEmbeddedPanelMethodChannel channel =
                  _FakeEmbeddedPanelMethodChannel();
              channels[name] = channel;
              shell.channels = channels;
              return channel;
            },
          );
      addTearDown(host.dispose);

      await expectLater(
        host.createPanel(instanceId: 6, panelId: 3, hostWindowId: 7001),
        throwsA(isA<TimeoutException>()),
      );

      expect(shell.destroyRequests, <({int instanceId, int panelId})>[
        (instanceId: 6, panelId: 3),
      ]);
      expect(channels.values.single.hasHandler, isFalse);
    });

    test('并发 dispose 会等待同一个原生销毁 Future', () async {
      final Completer<void> destroyGate = Completer<void>();
      final _FakeEmbeddedPanelShellPort shell = _FakeEmbeddedPanelShellPort()
        ..destroyCompleter = destroyGate;
      final _PanelHarness harness = _PanelHarness(
        lifecycle: lifecycle,
        panelShell: shell,
      );
      addTearDown(() async {
        if (!destroyGate.isCompleted) {
          destroyGate.complete();
        }
        await harness.host.dispose();
      });
      await harness.host.createPanel(
        instanceId: 7,
        panelId: 5,
        hostWindowId: 7002,
      );

      final Future<void> firstDispose = harness.host.dispose();
      await _pumpUntil(() => shell.destroyRequests.isNotEmpty);
      final Future<void> secondDispose = harness.host.dispose();

      expect(identical(firstDispose, secondDispose), isTrue);
      expect(shell.disposed, isFalse);
      expect(harness.channel.hasHandler, isFalse);

      destroyGate.complete();
      await Future.wait(<Future<void>>[firstDispose, secondDispose]);
      expect(shell.disposed, isTrue);
    });
  });

  group('DesktopMultiWindowSelectorWindowHost', () {
    test('配置版本不创建窗口，并向隐藏窗口广播且在显示前重放', () async {
      final _FakeDesktopRemoteWindow mainWindow = _FakeDesktopRemoteWindow(
        windowId: 'config-main',
      );
      final _FakeDesktopRemoteWindow selectorWindow = _FakeDesktopRemoteWindow(
        windowId: 'config-selector',
      );
      final _FakeDesktopMultiWindowPort port = _FakeDesktopMultiWindowPort(
        currentWindowRef: mainWindow,
        createdWindows: <_FakeDesktopRemoteWindow>[selectorWindow],
      );
      final DesktopMultiWindowSelectorWindowHost host =
          DesktopMultiWindowSelectorWindowHost(multiWindowPort: port);
      addTearDown(host.dispose);

      await host.publishConfigRevision(revision: 1);
      expect(port.createdArguments, isEmpty);

      await host.showSelectorWindow(
        instanceId: 9,
        context: DesktopSelectorWindowContext(
          keyword: 'config',
          langs: <String>['orig'],
          offsetMs: 0,
        ),
      );
      await host.hideSelectorWindow(instanceId: 9);
      await host.publishConfigRevision(revision: 2);
      final int invocationCountAfterRevision2 =
          selectorWindow.invocations.length;
      await host.publishConfigRevision(revision: 2);
      expect(
        selectorWindow.invocations,
        hasLength(invocationCountAfterRevision2),
      );

      await host.showSelectorWindow(
        instanceId: 9,
        context: DesktopSelectorWindowContext(
          keyword: 'config-again',
          langs: <String>['orig'],
          offsetMs: 0,
        ),
      );

      final List<_Invocation> configInvocations = selectorWindow.invocations
          .where(
            (_Invocation invocation) =>
                invocation.method ==
                DesktopWindowMethodNames.selectorConfigChanged,
          )
          .toList(growable: false);
      expect(configInvocations, hasLength(3));
      expect(
        configInvocations
            .map(
              (_Invocation invocation) =>
                  DesktopWindowPayloadCodec.decodeSelectorConfigRevision(
                    invocation.arguments,
                  ),
            )
            .toList(growable: false),
        <int>[1, 2, 2],
      );
      expect(port.createdArguments, hasLength(1));
    });

    test('显示、刷新及 intent 回传使用同一窗口', () async {
      final _FakeDesktopRemoteWindow mainWindow = _FakeDesktopRemoteWindow(
        windowId: '5',
      );
      final _FakeDesktopRemoteWindow selectorWindow = _FakeDesktopRemoteWindow(
        windowId: '21',
      );
      final _FakeDesktopMultiWindowPort port = _FakeDesktopMultiWindowPort(
        currentWindowRef: mainWindow,
        createdWindows: <_FakeDesktopRemoteWindow>[selectorWindow],
      );
      final DesktopMultiWindowSelectorWindowHost host =
          DesktopMultiWindowSelectorWindowHost(multiWindowPort: port);

      await host.showSelectorWindow(
        instanceId: 9,
        context: DesktopSelectorWindowContext(
          keyword: 'keyword',
          langs: <String>['orig'],
          offsetMs: 120,
        ),
      );
      await host.refreshSelectorContext(
        instanceId: 9,
        context: DesktopSelectorWindowContext(
          keyword: 'keyword-2',
          langs: <String>['orig', 'ts'],
          offsetMs: 240,
        ),
      );
      host.setIntentHandler((DesktopSelectorWindowIntent intent) async => true);
      final Object? handled = await mainWindow.emit(
        DesktopWindowMethodNames.selectorHiddenIntent,
        DesktopWindowPayloadCodec.encodeSelectorHiddenIntent(9),
      );

      expect(port.createdArguments.single.role, DesktopWindowRole.selector);
      // show/restore/focus 统一由子窗口 present 协议完成，宿主不再制造重复 show。
      expect(selectorWindow.showCount, 0);
      expect(selectorWindow.invocations, hasLength(3));
      expect(
        selectorWindow.invocations.map(
          (_Invocation invocation) => invocation.method,
        ),
        contains(DesktopWindowMethodNames.selectorPresent),
      );
      expect(handled, isTrue);
    });

    test('同一实例长驻显隐只创建一个浮窗和一个选择器 engine', () async {
      final _FakeDesktopRemoteWindow mainWindow = _FakeDesktopRemoteWindow(
        windowId: 'resident-main',
      );
      final _FakeDesktopRemoteWindow floatingWindow = _FakeDesktopRemoteWindow(
        windowId: 'resident-floating',
      );
      final _FakeDesktopRemoteWindow selectorWindow = _FakeDesktopRemoteWindow(
        windowId: 'resident-selector',
      );
      final _FakeDesktopMultiWindowPort floatingPort =
          _FakeDesktopMultiWindowPort(
            currentWindowRef: mainWindow,
            createdWindows: <_FakeDesktopRemoteWindow>[floatingWindow],
          );
      final _FakeDesktopMultiWindowPort selectorPort =
          _FakeDesktopMultiWindowPort(
            currentWindowRef: mainWindow,
            createdWindows: <_FakeDesktopRemoteWindow>[selectorWindow],
          );
      final DesktopMultiWindowFloatingWindowHost floatingHost =
          DesktopMultiWindowFloatingWindowHost(
            sceneStore: DesktopInMemorySceneStore(),
            lifecycleRegistry: lifecycle,
            multiWindowPort: floatingPort,
          );
      final DesktopMultiWindowSelectorWindowHost selectorHost =
          DesktopMultiWindowSelectorWindowHost(
            lifecycleRegistry: lifecycle,
            multiWindowPort: selectorPort,
          );
      addTearDown(floatingHost.dispose);
      addTearDown(selectorHost.dispose);

      for (int index = 0; index < 20; index += 1) {
        await floatingHost.applyFloatingSnapshot(
          instanceId: 77,
          snapshot: DesktopFloatingWindowSnapshot(
            session: DesktopFloatingSessionSnapshot(
              songId: 'resident',
              songTitle: 'Resident $index',
              hasStaticDisplay: true,
            ),
            flags: DesktopFloatingWindowFlags(visible: index.isEven),
          ),
        );
        await selectorHost.showSelectorWindow(
          instanceId: 77,
          context: DesktopSelectorWindowContext(
            keyword: 'Resident $index',
            langs: const <String>['orig'],
            offsetMs: index,
            refreshToken: index + 1,
          ),
        );
        await selectorHost.hideSelectorWindow(instanceId: 77);
      }

      expect(floatingPort.createdArguments, hasLength(1));
      expect(selectorPort.createdArguments, hasLength(1));
      expect(selectorWindow.showCount, 0);
      expect(
        selectorWindow.invocations
            .where(
              (_Invocation invocation) =>
                  invocation.method == DesktopWindowMethodNames.selectorPresent,
            )
            .length,
        20,
      );
      expect(selectorWindow.hideCount, 20);
      expect(
        lifecycle
            .currentRef(role: DesktopWindowRole.floating, instanceId: 77)
            ?.generation,
        1,
      );
      expect(
        lifecycle
            .currentRef(role: DesktopWindowRole.selector, instanceId: 77)
            ?.generation,
        1,
      );

      await selectorHost.destroySelectorWindow(instanceId: 77);
      await floatingHost.destroyFloatingWindow(instanceId: 77);

      expect(
        lifecycle.currentRef(role: DesktopWindowRole.floating, instanceId: 77),
        isNull,
      );
      expect(
        lifecycle.currentRef(role: DesktopWindowRole.selector, instanceId: 77),
        isNull,
      );
      expect(floatingWindow.requestCloseCount, 1);
      expect(selectorWindow.requestCloseCount, 1);
    });
  });
}

class _PanelHarness {
  _PanelHarness({
    required DesktopWindowLifecycleRegistry lifecycle,
    DesktopSceneStorePort? sceneStore,
    _FakeEmbeddedPanelShellPort? panelShell,
  }) : shell = panelShell ?? _FakeEmbeddedPanelShellPort() {
    host = WindowsEmbeddedPanelWindowHost(
      sceneStore: sceneStore ?? DesktopInMemorySceneStore(),
      lifecycleRegistry: lifecycle,
      panelShellPort: shell,
      channelFactory: (String name) {
        final _FakeEmbeddedPanelMethodChannel created =
            _FakeEmbeddedPanelMethodChannel();
        shell.channels[name] = created;
        return created;
      },
    );
  }

  final _FakeEmbeddedPanelShellPort shell;
  late final WindowsEmbeddedPanelWindowHost host;

  _FakeEmbeddedPanelMethodChannel get channel => shell.channels.values.single;
}

class _FakeEmbeddedPanelShellPort implements DesktopWindowsPanelShellPort {
  _FakeEmbeddedPanelShellPort({this.emitRuntimeReady = true});

  final bool emitRuntimeReady;
  Map<String, _FakeEmbeddedPanelMethodChannel> channels =
      <String, _FakeEmbeddedPanelMethodChannel>{};
  final List<DesktopPanelCreateRequest> createRequests =
      <DesktopPanelCreateRequest>[];
  final List<({int instanceId, int panelId})> destroyRequests =
      <({int instanceId, int panelId})>[];
  final List<bool> visibilityRequests = <bool>[];
  Completer<void>? destroyCompleter;
  int nextSurfaceRevision = 1;
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }

  @override
  Future<DesktopPanelSurfaceState> createPanel({
    required DesktopPanelCreateRequest request,
  }) async {
    createRequests.add(request);
    if (emitRuntimeReady) {
      await channels[request.channelName]!
          .emit(DesktopWindowMethodNames.panelRuntimeReady, <String, Object?>{
            'instanceId': request.instanceId,
            'panelId': request.panelId,
            'generation': request.generation,
          });
    }
    return const DesktopPanelSurfaceState(
      surfaceRevision: 1,
      attached: true,
      visible: false,
      clientSizePx: Size(640, 360),
      dpi: 96,
    );
  }

  @override
  Future<DesktopPanelSurfaceState> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {
    return DesktopPanelSurfaceState(
      surfaceRevision: nextSurfaceRevision,
      attached: true,
      visible: false,
      clientSizePx: Size(update.width.toDouble(), update.height.toDouble()),
      dpi: 96,
    );
  }

  @override
  Future<void> setPanelVisibility({
    required int instanceId,
    required int panelId,
    required bool visible,
  }) async {
    visibilityRequests.add(visible);
  }

  @override
  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {
    destroyRequests.add((instanceId: instanceId, panelId: panelId));
    await destroyCompleter?.future;
  }
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeEmbeddedPanelMethodChannel
    implements EmbeddedPanelMethodChannelPort {
  EmbeddedPanelMethodCallHandler? _handler;
  final List<_ChannelInvocation> invocations = <_ChannelInvocation>[];

  bool get hasHandler => _handler != null;

  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    invocations.add(_ChannelInvocation(method: method, arguments: arguments));
    return null;
  }

  @override
  Future<void> setMethodCallHandler(
    EmbeddedPanelMethodCallHandler? handler,
  ) async {
    _handler = handler;
  }

  Future<Object?> emit(String method, Object? arguments) {
    final EmbeddedPanelMethodCallHandler? handler = _handler;
    return handler == null
        ? Future<Object?>.value(null)
        : handler(MethodCall(method, arguments));
  }
}

class _ChannelInvocation {
  const _ChannelInvocation({required this.method, required this.arguments});

  final String method;
  final Object? arguments;
}

class _FakeDesktopMultiWindowPort implements DesktopMultiWindowPort {
  _FakeDesktopMultiWindowPort({
    required this.currentWindowRef,
    required List<_FakeDesktopRemoteWindow> createdWindows,
  }) : _createdWindows = Queue<_FakeDesktopRemoteWindow>.of(createdWindows);

  final _FakeDesktopRemoteWindow currentWindowRef;
  final Queue<_FakeDesktopRemoteWindow> _createdWindows;
  final List<DesktopWindowLaunchArguments> createdArguments =
      <DesktopWindowLaunchArguments>[];

  @override
  Future<DesktopRemoteWindowPort> createWindow({
    required DesktopWindowLaunchArguments arguments,
  }) async {
    createdArguments.add(arguments);
    return _createdWindows.removeFirst();
  }

  @override
  Future<DesktopRemoteWindowPort> currentWindow() async => currentWindowRef;

  @override
  Future<DesktopRemoteWindowPort> fromWindowId(String windowId) async {
    if (windowId == currentWindowRef.windowId) {
      return currentWindowRef;
    }
    throw StateError('未知窗口: $windowId');
  }
}

class _FakeDesktopRemoteWindow implements DesktopRemoteWindowPort {
  _FakeDesktopRemoteWindow({required this.windowId, this.resultForMethod});

  @override
  Object? get arguments => null;

  @override
  final String windowId;
  final FutureOr<Object?> Function(String method, Object? arguments)?
  resultForMethod;
  DesktopRemoteWindowMethodHandler? _handler;
  int showCount = 0;
  int hideCount = 0;
  int requestCloseCount = 0;
  final List<_Invocation> invocations = <_Invocation>[];

  Future<Object?> emit(String method, Object? arguments) {
    final DesktopRemoteWindowMethodHandler? handler = _handler;
    return handler == null
        ? Future<Object?>.value(null)
        : handler(method, arguments);
  }

  @override
  Future<void> requestClose() async {
    requestCloseCount += 1;
  }

  @override
  Future<void> hide() async {
    hideCount += 1;
  }

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async {
    invocations.add(_Invocation(method: method, arguments: arguments));
    return await resultForMethod?.call(method, arguments) ?? true;
  }

  @override
  Future<void> setMethodHandler(
    DesktopRemoteWindowMethodHandler? handler,
  ) async {
    _handler = handler;
  }

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> show() async {
    showCount += 1;
  }
}

class _Invocation {
  const _Invocation({required this.method, required this.arguments});

  final String method;
  final Object? arguments;
}
