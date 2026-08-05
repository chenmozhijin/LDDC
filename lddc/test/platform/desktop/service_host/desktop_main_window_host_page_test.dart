import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_exit_guard.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_floating_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_main_window_host_page.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_panel_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_selector_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_bootstrap.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_coordinator.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_session_reducer.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_session_state.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_tray_port.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/platform/desktop/window/desktop_window_providers.dart';

import '../../../support/desktop_service_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel windowManagerChannel = MethodChannel('window_manager');

  group('DesktopMainWindowHostPage', () {
    testWidgets('关闭主窗口时若仍有实例则只隐藏不退出', (WidgetTester tester) async {
      final List<String> calls = <String>[];
      _installWindowManagerMock(tester, windowManagerChannel, calls: calls);
      final DesktopExitGuardController exitGuard = DesktopExitGuardController();
      final DesktopServiceCoordinator coordinator = _buildCoordinator(
        exitGuard: exitGuard,
      );
      coordinator.upsertSession(_session(instanceId: 1));
      final _FakeBootstrap bootstrap = _FakeBootstrap();
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      addTearDown(coordinator.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopExitGuardProvider.overrideWithValue(exitGuard),
            desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
            desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
            desktopTrayPortFactoryProvider.overrideWithValue(trayFactory.call),
          ],
          child: _localizedHostApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      final dynamic state = tester.state(
        find.byType(DesktopMainWindowHostPage),
      );
      await state.onWindowClose();
      await tester.pump();

      expect(calls, contains('hide'));
      expect(calls, isNot(contains('destroy')));
      expect(trayFactory.createdPorts, hasLength(1));
      expect(trayFactory.lastPort.initializeCalls, 1);
    });

    testWidgets('主窗口已隐藏时，最后一个实例退出会触发整程序退出', (WidgetTester tester) async {
      final List<String> calls = <String>[];
      _installWindowManagerMock(tester, windowManagerChannel, calls: calls);
      final DesktopExitGuardController exitGuard = DesktopExitGuardController();
      final DesktopServiceCoordinator coordinator = _buildCoordinator(
        exitGuard: exitGuard,
      );
      coordinator.upsertSession(_session(instanceId: 2));
      final _FakeBootstrap bootstrap = _FakeBootstrap();
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      addTearDown(coordinator.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopExitGuardProvider.overrideWithValue(exitGuard),
            desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
            desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
            desktopTrayPortFactoryProvider.overrideWithValue(trayFactory.call),
          ],
          child: _localizedHostApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      final dynamic state = tester.state(
        find.byType(DesktopMainWindowHostPage),
      );
      await state.onWindowClose();
      await tester.pump();
      calls.clear();

      await coordinator.removeSession(2);
      await tester.pump();
      await tester.pump();

      expect(
        calls.any((String call) => call.contains('setPreventClose')),
        isTrue,
      );
      expect(bootstrap.disposeCalls, 1);
      expect(calls, contains('destroy'));
      expect(trayFactory.createdPorts, hasLength(1));
      expect(trayFactory.lastPort.initializeCalls, 1);
      expect(trayFactory.lastPort.disposeCalls, 1);
    });

    testWidgets('最后一个实例退出时会等待浮窗销毁完成后再关闭主窗口', (WidgetTester tester) async {
      final List<String> calls = <String>[];
      _installWindowManagerMock(tester, windowManagerChannel, calls: calls);
      final DesktopExitGuardController exitGuard = DesktopExitGuardController();
      final _DelayedDestroyFloatingHost floatingHost =
          _DelayedDestroyFloatingHost();
      final DesktopServiceCoordinator coordinator = _buildCoordinator(
        exitGuard: exitGuard,
        backend: DesktopWindowBackendPorts(
          floatingHost: floatingHost,
          selectorHost: const DesktopNoopSelectorWindowHost(),
          panelHost: const DesktopNoopPanelWindowHost(),
        ),
      );
      coordinator.upsertSession(_session(instanceId: 5));
      final _FakeBootstrap bootstrap = _FakeBootstrap();
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      addTearDown(coordinator.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopExitGuardProvider.overrideWithValue(exitGuard),
            desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
            desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
            desktopTrayPortFactoryProvider.overrideWithValue(trayFactory.call),
          ],
          child: _localizedHostApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      final dynamic state = tester.state(
        find.byType(DesktopMainWindowHostPage),
      );
      await state.onWindowClose();
      await tester.pump();
      calls.clear();

      bool removeFinished = false;
      final Future<void> removeFuture = coordinator.removeSession(5).then((_) {
        removeFinished = true;
      });

      await tester.pump();
      await waitForCondition(() => floatingHost.destroyCalls.contains(5));
      await tester.pump();

      expect(removeFinished, isFalse);
      expect(calls, isNot(contains('destroy')));

      floatingHost.completeDestroy(instanceId: 5);
      await removeFuture;
      await tester.pump();
      await tester.pump();

      expect(removeFinished, isTrue);
      expect(bootstrap.disposeCalls, 1);
      expect(calls, contains('destroy'));
      expect(trayFactory.lastPort.disposeCalls, 1);
    });

    testWidgets('无实例启动时不会初始化 tray，收到首个实例后才创建', (WidgetTester tester) async {
      final List<String> calls = <String>[];
      _installWindowManagerMock(tester, windowManagerChannel, calls: calls);
      final DesktopExitGuardController exitGuard = DesktopExitGuardController();
      final DesktopServiceCoordinator coordinator = _buildCoordinator(
        exitGuard: exitGuard,
      );
      final _FakeBootstrap bootstrap = _FakeBootstrap();
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      addTearDown(coordinator.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopExitGuardProvider.overrideWithValue(exitGuard),
            desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
            desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
            desktopTrayPortFactoryProvider.overrideWithValue(trayFactory.call),
          ],
          child: _localizedHostApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(trayFactory.createdPorts, isEmpty);

      coordinator.upsertSession(_session(instanceId: 3));
      await tester.pump();
      await tester.pump();

      expect(trayFactory.createdPorts, hasLength(1));
      expect(trayFactory.lastPort.initializeCalls, 1);

      await coordinator.removeSession(3);
      await tester.pump();
      await tester.pump();

      expect(trayFactory.lastPort.disposeCalls, 1);
    });

    testWidgets('非 primary 主窗口不会创建 tray', (WidgetTester tester) async {
      final List<String> calls = <String>[];
      _installWindowManagerMock(tester, windowManagerChannel, calls: calls);
      final DesktopExitGuardController exitGuard = DesktopExitGuardController();
      final DesktopServiceCoordinator coordinator = _buildCoordinator(
        exitGuard: exitGuard,
      );
      coordinator.upsertSession(_session(instanceId: 4));
      final _FakeBootstrap bootstrap = _FakeBootstrap(isPrimaryInstance: false);
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      addTearDown(coordinator.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopExitGuardProvider.overrideWithValue(exitGuard),
            desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
            desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
            desktopTrayPortFactoryProvider.overrideWithValue(trayFactory.call),
          ],
          child: _localizedHostApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(trayFactory.createdPorts, isEmpty);
    });

    testWidgets('页面在异步初始化期间销毁后不会补挂 handler 或 tray', (
      WidgetTester tester,
    ) async {
      final List<String> calls = <String>[];
      final Completer<void> ensureInitializedGate = Completer<void>();
      _installWindowManagerMock(
        tester,
        windowManagerChannel,
        calls: calls,
        ensureInitializedGate: ensureInitializedGate,
      );
      final DesktopExitGuardController exitGuard = DesktopExitGuardController();
      final DesktopServiceCoordinator coordinator = _buildCoordinator(
        exitGuard: exitGuard,
      )..upsertSession(_session(instanceId: 8));
      final _FakeBootstrap bootstrap = _FakeBootstrap();
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      addTearDown(coordinator.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopExitGuardProvider.overrideWithValue(exitGuard),
            desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
            desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
            desktopTrayPortFactoryProvider.overrideWithValue(trayFactory.call),
          ],
          child: _localizedHostApp(),
        ),
      );
      await tester.pump();
      expect(calls, contains('ensureInitialized'));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      ensureInitializedGate.complete();
      await tester.pump();
      await tester.pump();

      expect(bootstrap.attachedShowHandler, isNull);
      expect(trayFactory.createdPorts, isEmpty);
      expect(calls, isNot(contains('setPreventClose:true')));
    });

    testWidgets('Windows 隐藏启动只同步隐藏状态，不额外调用 hide', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      final List<String> calls = <String>[];
      _installWindowManagerMock(tester, windowManagerChannel, calls: calls);
      final DesktopWindowLifecycleRegistryController lifecycleRegistry =
          DesktopWindowLifecycleRegistryController.instance;
      lifecycleRegistry.debugResetForTests();
      final DesktopExitGuardController exitGuard = DesktopExitGuardController(
        lifecycleRegistry: lifecycleRegistry,
      );
      final DesktopServiceCoordinator coordinator = _buildCoordinator(
        exitGuard: exitGuard,
      );
      final _FakeBootstrap bootstrap = _FakeBootstrap(shouldStartHidden: true);
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      addTearDown(coordinator.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
        lifecycleRegistry.debugResetForTests();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopExitGuardProvider.overrideWithValue(exitGuard),
            desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
            desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
            desktopTrayPortFactoryProvider.overrideWithValue(trayFactory.call),
            desktopWindowLifecycleRegistryProvider.overrideWithValue(
              lifecycleRegistry,
            ),
          ],
          child: _localizedHostApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      final DesktopWindowRef mainRef = lifecycleRegistry.ensureMainWindow();
      final DesktopWindowLifecycleSnapshot? snapshot = lifecycleRegistry
          .snapshotForRef(mainRef);
      expect(snapshot?.observedState, DesktopWindowObservedState.ready);
      expect(snapshot?.desiredState, DesktopWindowDesiredState.hidden);
      expect(calls, isNot(contains('hide')));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('macOS 和 Linux 隐藏启动会同步隐藏原生主窗口', (WidgetTester tester) async {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final List<String> calls = <String>[];
        _installWindowManagerMock(tester, windowManagerChannel, calls: calls);
        final DesktopWindowLifecycleRegistryController lifecycleRegistry =
            DesktopWindowLifecycleRegistryController.instance;
        lifecycleRegistry.debugResetForTests();
        final DesktopExitGuardController exitGuard = DesktopExitGuardController(
          lifecycleRegistry: lifecycleRegistry,
        );
        final DesktopServiceCoordinator coordinator = _buildCoordinator(
          exitGuard: exitGuard,
        );
        final _FakeBootstrap bootstrap = _FakeBootstrap(
          shouldStartHidden: true,
        );
        final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              desktopExitGuardProvider.overrideWithValue(exitGuard),
              desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
              desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
              desktopTrayPortFactoryProvider.overrideWithValue(
                trayFactory.call,
              ),
              desktopWindowLifecycleRegistryProvider.overrideWithValue(
                lifecycleRegistry,
              ),
            ],
            child: _localizedHostApp(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(calls, contains('hide'), reason: '${platform.name} 必须隐藏原生窗口');
        final DesktopWindowRef mainRef = lifecycleRegistry.ensureMainWindow();
        final DesktopWindowLifecycleSnapshot? snapshot = lifecycleRegistry
            .snapshotForRef(mainRef);
        expect(snapshot?.desiredState, DesktopWindowDesiredState.hidden);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await coordinator.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
        lifecycleRegistry.debugResetForTests();
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('show handler 中 window_manager 失败不会冒泡', (
      WidgetTester tester,
    ) async {
      final List<String> calls = <String>[];
      _installWindowManagerMock(
        tester,
        windowManagerChannel,
        calls: calls,
        failingMethods: <String>{'show'},
      );
      final DesktopExitGuardController exitGuard = DesktopExitGuardController();
      final DesktopServiceCoordinator coordinator = _buildCoordinator(
        exitGuard: exitGuard,
      );
      final _FakeBootstrap bootstrap = _FakeBootstrap();
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      addTearDown(coordinator.dispose);
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          windowManagerChannel,
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            desktopExitGuardProvider.overrideWithValue(exitGuard),
            desktopServiceCoordinatorProvider.overrideWithValue(coordinator),
            desktopServiceBootstrapProvider.overrideWithValue(bootstrap),
            desktopTrayPortFactoryProvider.overrideWithValue(trayFactory.call),
          ],
          child: _localizedHostApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      await bootstrap.attachedShowHandler?.call();
      await tester.pump();

      expect(calls, contains('show'));
      expect(calls, isNot(contains('focus')));
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _localizedHostApp() {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const DesktopMainWindowHostPage(child: SizedBox.shrink()),
  );
}

DesktopServiceCoordinator _buildCoordinator({
  required DesktopExitGuardPort exitGuard,
  DesktopWindowBackend? backend,
}) {
  final DesktopWindowBackend resolvedBackend =
      backend ??
      const DesktopWindowBackendPorts(
        floatingHost: DesktopNoopFloatingWindowHost(),
        selectorHost: DesktopNoopSelectorWindowHost(),
        panelHost: DesktopNoopPanelWindowHost(),
      );
  return DesktopServiceCoordinator(
    reducer: DesktopSessionReducer(),
    sceneStore: DesktopInMemorySceneStore(),
    floatingEffectExecutor: DesktopFloatingEffectExecutor(
      windowBackend: resolvedBackend,
    ),
    panelEffectExecutor: DesktopPanelEffectExecutor(
      windowBackend: resolvedBackend,
    ),
    selectorEffectExecutor: DesktopSelectorEffectExecutor(
      windowBackend: resolvedBackend,
    ),
    exitGuard: exitGuard,
  );
}

DesktopSessionState _session({required int instanceId}) {
  return DesktopSessionState.initial().copyWith(
    instanceId: instanceId,
    lyricsRuntime: DesktopLyricsRuntimeState(
      song: SongInfo(
        source: Source.local,
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
        album: 'Album',
        durationMs: 180000,
        id: '$instanceId',
      ),
    ),
  );
}

void _installWindowManagerMock(
  WidgetTester tester,
  MethodChannel channel, {
  required List<String> calls,
  Set<String> failingMethods = const <String>{},
  Completer<void>? ensureInitializedGate,
}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    MethodCall call,
  ) async {
    if (failingMethods.contains(call.method)) {
      calls.add(call.method);
      throw PlatformException(code: 'TEST_FAILURE', message: call.method);
    }
    switch (call.method) {
      case 'setPreventClose':
        calls.add('setPreventClose:${call.arguments}');
        return null;
      case 'hide':
      case 'close':
      case 'destroy':
      case 'show':
      case 'focus':
        calls.add(call.method);
        return null;
      case 'ensureInitialized':
        calls.add(call.method);
        await ensureInitializedGate?.future;
        return null;
      case 'getId':
        calls.add(call.method);
        return 0;
      case 'isMinimized':
      case 'isVisible':
        return false;
      default:
        return null;
    }
  });
}

class _FakeBootstrap extends DesktopServiceBootstrap {
  _FakeBootstrap({
    this.isPrimaryInstance = true,
    this.shouldStartHidden = false,
  });
  Future<void> Function()? attachedShowHandler;
  int disposeCalls = 0;

  @override
  final bool isPrimaryInstance;

  @override
  final bool shouldStartHidden;

  @override
  Future<void> attachShowHandler(Future<void> Function() handler) async {
    attachedShowHandler = handler;
  }

  @override
  void detachShowHandler() {
    attachedShowHandler = null;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

class _FakeTrayPort implements DesktopTrayPort {
  int initializeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  Future<void> initialize({required String iconAsset, String? toolTip}) async {
    initializeCalls += 1;
  }

  @override
  void setOnPrimaryAction(VoidCallback? onPrimaryAction) {}

  @override
  void setOnSecondaryAction(VoidCallback? onSecondaryAction) {}

  @override
  void setOnMenuItemSelected(ValueChanged<String>? onSelected) {}

  @override
  Future<void> showContextMenu() async {}

  @override
  Future<Rect?> getBounds() async => null;

  @override
  Future<void> updateMenu(List<DesktopTrayMenuEntry> entries) async {}
}

class _FakeTrayPortFactory {
  final List<_FakeTrayPort> createdPorts = <_FakeTrayPort>[];

  _FakeTrayPort get lastPort => createdPorts.last;

  DesktopTrayPort call() {
    final _FakeTrayPort port = _FakeTrayPort();
    createdPorts.add(port);
    return port;
  }
}

class _DelayedDestroyFloatingHost extends DesktopNoopFloatingWindowHost {
  final List<int> destroyCalls = <int>[];
  final Map<int, Completer<void>> _destroyCompleters = <int, Completer<void>>{};

  @override
  Future<void> destroyFloatingWindow({required int instanceId}) {
    destroyCalls.add(instanceId);
    return (_destroyCompleters[instanceId] ??= Completer<void>()).future;
  }

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {}

  @override
  Future<bool> flushFloatingGeometry({required int instanceId}) async => true;

  void completeDestroy({required int instanceId}) {
    final Completer<void> completer = _destroyCompleters[instanceId] ??=
        Completer<void>();
    if (!completer.isCompleted) {
      completer.complete();
    }
  }
}
