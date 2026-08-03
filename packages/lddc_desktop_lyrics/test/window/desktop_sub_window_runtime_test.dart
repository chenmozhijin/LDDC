import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel windowManagerChannel = MethodChannel('window_manager');
  final DesktopSubWindowRuntime runtime = DesktopSubWindowRuntime.instance;
  final DesktopWindowLifecycleRegistryController lifecycle =
      DesktopWindowLifecycleRegistryController.instance;
  final List<MethodCall> windowManagerCalls = <MethodCall>[];
  bool windowIsMinimized = false;
  bool windowIsAlwaysOnTop = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    runtime.debugResetForTests();
    lifecycle.debugResetForTests();
    windowManagerCalls.clear();
    windowIsMinimized = false;
    windowIsAlwaysOnTop = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (
          MethodCall call,
        ) async {
          windowManagerCalls.add(call);
          if (call.method == 'getId') {
            return 4242;
          }
          if (call.method == 'isMinimized') {
            return windowIsMinimized;
          }
          if (call.method == 'isAlwaysOnTop') {
            return windowIsAlwaysOnTop;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
    runtime.debugResetForTests();
    lifecycle.debugResetForTests();
    debugDefaultTargetPlatformOverride = null;
  });

  test('浮窗配置成功会解除 ready 屏障', () async {
    final _FakeRemoteWindow current = await _initializeFloatingRuntime(
      runtime,
      lifecycle,
    );
    final Future<Object?> ready = current.dispatch(
      DesktopWindowMethodNames.floatingAwaitReady,
    );
    bool completed = false;
    ready.whenComplete(() => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    runtime.markFloatingWindowReady();

    await expectLater(ready, completion(isTrue));
  });

  test('配置失败先于 host 等待时会立即返回明确错误且不产生错误 Future', () async {
    final _FakeRemoteWindow current = await _initializeFloatingRuntime(
      runtime,
      lifecycle,
    );

    runtime.markFloatingWindowConfigurationFailed(
      MissingPluginException('screen_retriever 未注册'),
    );

    await expectLater(
      current.dispatch(DesktopWindowMethodNames.floatingAwaitReady),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('screen_retriever 未注册'),
        ),
      ),
    );
  });

  test('Windows 子窗口先卸载根组件再投递标准关闭', () async {
    bool rootDetached = false;
    final _FakeRemoteWindow current = await _initializeFloatingRuntime(
      runtime,
      lifecycle,
      rootDetachHandler: () async {
        rootDetached = true;
      },
    );

    final Object? result = await current.dispatch('window_close');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(rootDetached, isTrue);
    expect(result, isNull);
    expect(
      windowManagerCalls.map((MethodCall call) => call.method),
      containsAllInOrder(<String>['setPreventClose', 'close']),
    );
  });

  test('Windows 子窗口会等待原生配置调用收口再卸载根组件', () async {
    final Completer<void> configuration = Completer<void>();
    final List<String> events = <String>[];
    final _FakeRemoteWindow current = await _initializeFloatingRuntime(
      runtime,
      lifecycle,
      rootDetachHandler: () async {
        events.add('detach');
      },
      drainHostResources: () async {
        events.add('drain');
      },
    );
    runtime.setPrepareCloseHandler(() async {
      events.add('prepare');
      await configuration.future;
      events.add('prepared');
    });

    final Future<Object?> close = current.dispatch('window_close');
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>['prepare']);
    configuration.complete();
    await expectLater(close, completion(isNull));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(events, <String>['prepare', 'prepared', 'detach', 'drain']);
  });

  testWidgets('浮窗 flags 热更新会应用有边框样式和受支持的鼠标穿透通道', (WidgetTester tester) async {
    final _FakeRemoteWindow current = await _initializeFloatingRuntime(
      runtime,
      lifecycle,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopFloatingWindowShellPage(
          launch: DesktopWindowLaunchArguments(
            role: DesktopWindowRole.floating,
            instanceId: 7,
            hostWindowId: 'main-1',
          ),
        ),
      ),
    );
    await tester.pump();
    windowManagerCalls.clear();

    await current.dispatch(
      DesktopWindowMethodNames.floatingUpdateFlags,
      DesktopWindowPayloadCodec.encodeFloatingFlagsPayload(
        const DesktopFloatingFlagsPayload(
          revision: 1,
          flags: DesktopFloatingWindowFlags(
            frameless: false,
            clickThrough: true,
          ),
        ),
      ),
    );

    final Iterable<String> methods = windowManagerCalls.map(
      (MethodCall call) => call.method,
    );
    expect(methods, contains('setTitleBarStyle'));
    expect(methods, contains('setHasShadow'));
    expect(methods, contains('setIgnoreMouseEvents'));
    // Widget 测试的全局 debug invariant 早于普通 tearDown 执行，因此必须
    // 在用例体结束前恢复平台覆盖，避免把测试平台配置误判为全局状态泄漏。
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('dispose 会解绑方法通道并清空当前窗口缓存', () async {
    final _FakeRemoteWindow current = await _initializeFloatingRuntime(
      runtime,
      lifecycle,
    );

    await runtime.dispose();

    expect(runtime.currentWindowId, isNull);
    expect(runtime.launch.role, DesktopWindowRole.main);
    expect(
      () => current.dispatch(DesktopWindowMethodNames.floatingAwaitReady),
      throwsStateError,
    );
  });

  test('子 engine 启动时会等待官方插件补齐当前窗口通道', () async {
    final DesktopWindowRef ref = lifecycle.registerWindow(
      role: DesktopWindowRole.floating,
      instanceId: 7,
      observedState: DesktopWindowObservedState.creating,
      desiredState: DesktopWindowDesiredState.hidden,
    );
    final _FakeRemoteWindow current = _FakeRemoteWindow(
      windowId: 'floating-7',
      arguments: DesktopWindowLaunchArguments(
        role: DesktopWindowRole.floating,
        instanceId: 7,
        hostWindowId: 'main-1',
        generation: ref.generation,
      ).encode(),
    );
    final _FakeMultiWindowPort port = _FakeMultiWindowPort(
      current,
      unavailableAttempts: 2,
    );

    final DesktopWindowLaunchArguments launch = await runtime.ensureInitialized(
      multiWindowPort: port,
      lifecycleRegistry: lifecycle,
      currentWindowRetryDelay: Duration.zero,
      currentWindowRetryLimit: 3,
    );

    expect(port.currentWindowAttempts, 3);
    expect(launch.role, DesktopWindowRole.floating);
    expect(launch.instanceId, 7);
  });

  test('当前窗口通道超过启动重试上限后保留原始错误', () async {
    final _FakeMultiWindowPort port = _FakeMultiWindowPort(
      _FakeRemoteWindow(windowId: 'floating-7', arguments: null),
      unavailableAttempts: 3,
    );

    await expectLater(
      runtime.ensureInitialized(
        multiWindowPort: port,
        lifecycleRegistry: lifecycle,
        currentWindowRetryDelay: Duration.zero,
        currentWindowRetryLimit: 2,
      ),
      throwsA(
        isA<PlatformException>().having(
          (PlatformException error) => error.code,
          'code',
          'CHANNEL_UNREGISTERED',
        ),
      ),
    );
    expect(port.currentWindowAttempts, 2);
  });

  test('目标窗口已创建但 handler 尚未绑定时会按 NO_HANDLER 有界重试', () async {
    int attempts = 0;

    final int result = await retryDesktopWindowChannel<int>(
      () async {
        attempts += 1;
        if (attempts < 3) {
          throw Exception(
            'WindowChannelException(error, '
            'WindowChannelException(NO_HANDLER, '
            'No method call handler registered for channel test/window))',
          );
        }
        return 42;
      },
      instanceId: 7,
      operation: 'testNoHandlerStartupRace',
      retryDelay: Duration.zero,
      retryLimit: 3,
      operationTimeout: const Duration(seconds: 1),
    );

    expect(result, 42);
    expect(attempts, 3);
    expect(
      isDesktopWindowChannelUnregistered(
        Exception('WindowChannelException(BUSINESS_ERROR, invalid payload)'),
      ),
      isFalse,
    );
  });

  test('选择器配置版本会在启动期排队，并去重重复或倒序通知', () async {
    final _FakeRemoteWindow current = await _initializeSelectorRuntime(
      runtime,
      lifecycle,
    );
    final List<int> appliedRevisions = <int>[];

    await current.dispatch(
      DesktopWindowMethodNames.selectorConfigChanged,
      DesktopWindowPayloadCodec.encodeSelectorConfigRevision(2),
    );
    expect(appliedRevisions, isEmpty);

    await runtime.bindSelectorConfigRefreshHandler((int revision) async {
      appliedRevisions.add(revision);
    });
    await current.dispatch(
      DesktopWindowMethodNames.selectorConfigChanged,
      DesktopWindowPayloadCodec.encodeSelectorConfigRevision(2),
    );
    await current.dispatch(
      DesktopWindowMethodNames.selectorConfigChanged,
      DesktopWindowPayloadCodec.encodeSelectorConfigRevision(1),
    );
    await current.dispatch(
      DesktopWindowMethodNames.selectorConfigChanged,
      DesktopWindowPayloadCodec.encodeSelectorConfigRevision(3),
    );

    expect(appliedRevisions, <int>[2, 3]);
  });

  test('选择器配置刷新失败不会确认版本，同版本通知可重试', () async {
    final _FakeRemoteWindow current = await _initializeSelectorRuntime(
      runtime,
      lifecycle,
    );
    int attempts = 0;
    await runtime.bindSelectorConfigRefreshHandler((int revision) async {
      attempts += 1;
      if (attempts == 1) {
        throw StateError('模拟刷新失败');
      }
    });

    final Map<String, Object?> payload =
        DesktopWindowPayloadCodec.encodeSelectorConfigRevision(4);
    await expectLater(
      current.dispatch(DesktopWindowMethodNames.selectorConfigChanged, payload),
      throwsA(isA<StateError>()),
    );
    await current.dispatch(
      DesktopWindowMethodNames.selectorConfigChanged,
      payload,
    );

    expect(attempts, 2);
  });

  test('Windows 选择器 present 会恢复、显示、短暂置顶并聚焦', () async {
    windowIsMinimized = true;
    final _FakeRemoteWindow current = await _initializeSelectorRuntime(
      runtime,
      lifecycle,
    );
    windowManagerCalls.clear();

    await expectLater(
      current.dispatch(DesktopWindowMethodNames.selectorPresent),
      completion(isTrue),
    );

    expect(
      windowManagerCalls.map((MethodCall call) => call.method),
      containsAllInOrder(<String>[
        'isMinimized',
        'restore',
        'show',
        'isAlwaysOnTop',
        'setAlwaysOnTop',
        'focus',
        'setAlwaysOnTop',
      ]),
    );
    expect(
      windowManagerCalls.where(
        (MethodCall call) => call.method == 'setAlwaysOnTop',
      ),
      hasLength(2),
    );
    expect(
      lifecycle.currentRef(role: DesktopWindowRole.selector, instanceId: 7),
      isNotNull,
    );
  });

  test('非 Windows 选择器 present 只恢复、显示并聚焦，不改置顶属性', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    windowIsMinimized = true;
    windowIsAlwaysOnTop = true;
    final _FakeRemoteWindow current = await _initializeSelectorRuntime(
      runtime,
      lifecycle,
    );
    windowManagerCalls.clear();

    await current.dispatch(DesktopWindowMethodNames.selectorPresent);

    final Iterable<String> methods = windowManagerCalls.map(
      (MethodCall call) => call.method,
    );
    expect(
      methods,
      containsAllInOrder(<String>[
        'isMinimized',
        'restore',
        'show',
        'isAlwaysOnTop',
        'focus',
      ]),
    );
    expect(methods, isNot(contains('setAlwaysOnTop')));
  });
}

Future<_FakeRemoteWindow> _initializeFloatingRuntime(
  DesktopSubWindowRuntime runtime,
  DesktopWindowLifecycleRegistryController lifecycle, {
  DesktopSubWindowRootDetachHandler? rootDetachHandler,
  DesktopSubWindowHostResourceDrainHandler? drainHostResources,
}) async {
  final DesktopWindowRef ref = lifecycle.registerWindow(
    role: DesktopWindowRole.floating,
    instanceId: 7,
    observedState: DesktopWindowObservedState.creating,
    desiredState: DesktopWindowDesiredState.hidden,
  );
  final _FakeRemoteWindow current = _FakeRemoteWindow(
    windowId: 'floating-7',
    arguments: DesktopWindowLaunchArguments(
      role: DesktopWindowRole.floating,
      instanceId: 7,
      hostWindowId: 'main-1',
      generation: ref.generation,
    ).encode(),
  );
  await runtime.ensureInitialized(
    multiWindowPort: _FakeMultiWindowPort(current),
    lifecycleRegistry: lifecycle,
    rootDetachHandler: rootDetachHandler,
    drainHostResources: drainHostResources,
  );
  return current;
}

Future<_FakeRemoteWindow> _initializeSelectorRuntime(
  DesktopSubWindowRuntime runtime,
  DesktopWindowLifecycleRegistryController lifecycle,
) async {
  final DesktopWindowRef ref = lifecycle.registerWindow(
    role: DesktopWindowRole.selector,
    instanceId: 7,
    observedState: DesktopWindowObservedState.creating,
    desiredState: DesktopWindowDesiredState.hidden,
  );
  final _FakeRemoteWindow current = _FakeRemoteWindow(
    windowId: 'selector-7',
    arguments: DesktopWindowLaunchArguments(
      role: DesktopWindowRole.selector,
      instanceId: 7,
      hostWindowId: 'main-1',
      generation: ref.generation,
    ).encode(),
  );
  await runtime.ensureInitialized(
    multiWindowPort: _FakeMultiWindowPort(current),
    lifecycleRegistry: lifecycle,
  );
  return current;
}

class _FakeMultiWindowPort implements DesktopMultiWindowPort {
  _FakeMultiWindowPort(this.current, {this.unavailableAttempts = 0});

  final _FakeRemoteWindow current;
  final int unavailableAttempts;
  int currentWindowAttempts = 0;

  @override
  Future<DesktopRemoteWindowPort> currentWindow() async {
    currentWindowAttempts += 1;
    if (currentWindowAttempts <= unavailableAttempts) {
      throw PlatformException(
        code: 'CHANNEL_UNREGISTERED',
        message: 'WindowChannelException: Channel not accessible',
      );
    }
    return current;
  }

  @override
  Future<DesktopRemoteWindowPort> createWindow({
    required DesktopWindowLaunchArguments arguments,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<DesktopRemoteWindowPort> fromWindowId(String windowId) {
    throw UnimplementedError();
  }
}

class _FakeRemoteWindow implements DesktopRemoteWindowPort {
  _FakeRemoteWindow({required this.windowId, required this.arguments});

  @override
  final String windowId;

  @override
  final Object? arguments;

  DesktopRemoteWindowMethodHandler? _handler;

  Future<Object?> dispatch(String method, [Object? arguments]) {
    final DesktopRemoteWindowMethodHandler? handler = _handler;
    if (handler == null) {
      throw StateError('子窗口方法处理器尚未注册');
    }
    return handler(method, arguments);
  }

  @override
  Future<void> setMethodHandler(
    DesktopRemoteWindowMethodHandler? handler,
  ) async {
    _handler = handler;
  }

  @override
  Future<void> hide() async {}

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async =>
      null;

  @override
  Future<void> requestClose() async {}

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> show() async {}
}
