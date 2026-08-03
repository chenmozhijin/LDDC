import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel windowManagerChannel = MethodChannel('window_manager');
  final DesktopEmbeddedPanelRuntime runtime =
      DesktopEmbeddedPanelRuntime.instance;
  final List<MethodCall> windowManagerCalls = <MethodCall>[];

  setUp(() {
    windowManagerCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (
          MethodCall call,
        ) async {
          windowManagerCalls.add(call);
          if (call.method == 'getBounds') {
            return <String, double>{
              'x': 20,
              'y': 30,
              'width': 1200,
              'height': 150,
            };
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
    debugDefaultTargetPlatformOverride = null;
    await runtime.dispose();
  });

  test('浮窗样式去重忽略可见性但保留原生样式字段', () {
    const DesktopFloatingWindowFlags hidden = DesktopFloatingWindowFlags();

    expect(
      desktopShellFloatingStyleEquals(
        hidden,
        const DesktopFloatingWindowFlags(visible: true),
      ),
      isTrue,
    );
    expect(
      desktopShellFloatingStyleEquals(
        hidden,
        const DesktopFloatingWindowFlags(opacity: 0.5),
      ),
      isFalse,
    );
  });

  testWidgets('main role 不会在窗口壳中创建子窗口内容', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopWindowShellPage(
          launch: DesktopWindowLaunchArguments.main(),
        ),
      ),
    );

    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.byType(DesktopPanelWindowShellPage), findsNothing);
  });

  testWidgets('Linux 浮窗配置不会调用未实现的窗口通道', (WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: DesktopFloatingWindowShellPage(
            launch: DesktopWindowLaunchArguments(
              role: DesktopWindowRole.floating,
              instanceId: 1,
              initialWindowRect: WindowRect(
                left: 20,
                top: 30,
                width: 1200,
                height: 150,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Iterable<String> methods = windowManagerCalls.map(
        (MethodCall call) => call.method,
      );
      expect(methods, contains('setAsFrameless'));
      expect(methods, isNot(contains('setHasShadow')));
      expect(methods, isNot(contains('setIgnoreMouseEvents')));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    testWidgets('${platform.name} 浮窗配置保留受支持的窗口通道', (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: DesktopFloatingWindowShellPage(
              launch: DesktopWindowLaunchArguments(
                role: DesktopWindowRole.floating,
                instanceId: 1,
                initialWindowRect: WindowRect(
                  left: 20,
                  top: 30,
                  width: 1200,
                  height: 150,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final Iterable<String> methods = windowManagerCalls.map(
          (MethodCall call) => call.method,
        );
        expect(methods, contains('setAsFrameless'));
        expect(methods, contains('setHasShadow'));
        expect(methods, contains('setIgnoreMouseEvents'));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('Panel runtime 原子发布内容并丢弃旧 revision', () async {
    final _FakeEmbeddedPanelChannel channel = _FakeEmbeddedPanelChannel();
    await runtime.ensureInitialized(
      payload: const DesktopEmbeddedPanelLaunchPayload(
        instanceId: 1,
        panelId: 2,
        hostWindowId: 3,
        channelName: 'panel-test',
        generation: 1,
      ),
      channel: channel,
    );
    const DesktopSceneRef sceneRef = DesktopSceneRef(
      sceneId: 'scene-a',
      sceneRevision: 1,
      checksum: 'a',
    );
    final Uint8List sceneBytes = const DesktopLyricsSceneCodec().encode(
      DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.staticText,
        selectedLangs: <String>['orig'],
        langOrder: <String>['orig'],
        durationMs: null,
        staticDisplayLines: <String>['A'],
      ),
    );

    await channel.emit(
      DesktopWindowMethodNames.panelApplyContent,
      DesktopWindowPayloadCodec.encodePanelContentPayload(
        DesktopPanelContentPayload(
          contentRevision: 1,
          session: DesktopPanelSessionSnapshot(songId: 'song-a'),
          sceneRef: sceneRef,
          sceneBytes: sceneBytes,
        ),
      ),
    );
    await channel.emit(
      DesktopWindowMethodNames.panelApplyContent,
      DesktopWindowPayloadCodec.encodePanelContentPayload(
        DesktopPanelContentPayload(
          contentRevision: 2,
          session: DesktopPanelSessionSnapshot(songId: 'song-b'),
          sceneRef: sceneRef,
          sceneBytes: null,
        ),
      ),
    );
    await channel.emit(
      DesktopWindowMethodNames.panelApplyContent,
      DesktopWindowPayloadCodec.encodePanelContentPayload(
        DesktopPanelContentPayload(
          contentRevision: 1,
          session: DesktopPanelSessionSnapshot(songId: 'stale'),
          sceneRef: null,
          sceneBytes: null,
        ),
      ),
    );

    final DesktopPanelContentState content = runtime.panelContent.value!;
    expect(content.snapshot.contentRevision, 2);
    expect(content.snapshot.session.songId, 'song-b');
    expect(content.snapshot.sceneRef?.sceneId, 'scene-a');
    expect(content.sceneDocument?.staticDisplayLines, <String>['A']);
  });

  testWidgets('Panel 页面使用纯黑背景并在物理 viewport 匹配后回传 presentation', (
    WidgetTester tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final _FakeEmbeddedPanelChannel channel = _FakeEmbeddedPanelChannel();
    await runtime.ensureInitialized(
      payload: const DesktopEmbeddedPanelLaunchPayload(
        instanceId: 4,
        panelId: 5,
        hostWindowId: 6,
        channelName: 'panel-widget-test',
        generation: 1,
      ),
      channel: channel,
    );
    final Uint8List sceneBytes = const DesktopLyricsSceneCodec().encode(
      DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.staticText,
        selectedLangs: <String>['orig'],
        langOrder: <String>['orig'],
        durationMs: null,
        staticDisplayLines: <String>['Opaque'],
      ),
    );
    await channel.emit(
      DesktopWindowMethodNames.panelApplyContent,
      DesktopWindowPayloadCodec.encodePanelContentPayload(
        DesktopPanelContentPayload(
          contentRevision: 7,
          session: DesktopPanelSessionSnapshot(songId: 'song'),
          sceneRef: const DesktopSceneRef(
            sceneId: 'scene',
            sceneRevision: 1,
            checksum: 'scene',
          ),
          sceneBytes: sceneBytes,
        ),
      ),
    );
    await channel.emit(
      DesktopWindowMethodNames.panelSurfaceStateSync,
      const DesktopPanelSurfaceState(
        surfaceRevision: 9,
        attached: true,
        visible: false,
        clientSizePx: Size(800, 600),
        dpi: 96,
      ).toPayload(),
    );

    await tester.pumpWidget(
      MaterialApp(home: DesktopWindowShellPage(launch: runtime.windowLaunch)),
    );
    await tester.pump();
    await tester.pump();

    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.black);
    expect(find.byType(DesktopPanelLyricsRenderView), findsOneWidget);
    final List<_Invocation> readyCalls = channel.invocations
        .where(
          (_Invocation value) =>
              value.method == DesktopWindowMethodNames.panelPresentationReady,
        )
        .toList(growable: false);
    expect(readyCalls, hasLength(1));
    final DesktopPanelPresentationReady ready =
        DesktopWindowPayloadCodec.decodePanelPresentationReady(
          readyCalls.single.arguments,
        );
    expect(ready.contentRevision, 7);
    expect(ready.surfaceRevision, 9);
  });

  testWidgets('Panel 右键菜单会把选择歌词动作发送给宿主', (WidgetTester tester) async {
    final _FakeEmbeddedPanelChannel channel = _FakeEmbeddedPanelChannel();
    await runtime.ensureInitialized(
      payload: const DesktopEmbeddedPanelLaunchPayload(
        instanceId: 10,
        panelId: 11,
        hostWindowId: 12,
        channelName: 'panel-menu-test',
        generation: 1,
      ),
      channel: channel,
    );
    await channel.emit(
      DesktopWindowMethodNames.panelApplyContent,
      DesktopWindowPayloadCodec.encodePanelContentPayload(
        DesktopPanelContentPayload(
          contentRevision: 1,
          session: DesktopPanelSessionSnapshot(songId: 'song'),
          sceneRef: null,
          sceneBytes: null,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopWindowShellPage(
          launch: runtime.windowLaunch,
          strings: const DesktopLyricsWindowStrings.zhHans(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byType(DesktopPanelWindowShellPage),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(find.text('选择歌词'), findsOneWidget);
    await tester.tap(find.text('选择歌词'));
    await tester.pumpAndSettle();

    final List<_Invocation> actionCalls = channel.invocations
        .where(
          (_Invocation value) =>
              value.method == DesktopWindowMethodNames.panelActionIntent,
        )
        .toList(growable: false);
    expect(actionCalls, hasLength(1));
    final DesktopPanelWindowIntent? intent =
        DesktopWindowPayloadCodec.decodePanelIntent(
          actionCalls.single.method,
          actionCalls.single.arguments,
        );
    expect(intent, isA<DesktopPanelActionIntent>());
    expect(
      (intent! as DesktopPanelActionIntent).action,
      DesktopWindowActionType.openSelector,
    );
  });

  test('Panel action 会原样返回 host 的失败结果', () async {
    final _FakeEmbeddedPanelChannel channel = _FakeEmbeddedPanelChannel(
      resultForMethod: (String method) =>
          method == DesktopWindowMethodNames.panelActionIntent ? false : true,
    );
    await runtime.ensureInitialized(
      payload: const DesktopEmbeddedPanelLaunchPayload(
        instanceId: 7,
        panelId: 8,
        hostWindowId: 9,
        channelName: 'panel-action-test',
        generation: 1,
      ),
      channel: channel,
    );

    final bool handled = await runtime.notifyPanelAction(
      const DesktopPanelActionIntent(
        instanceId: 7,
        panelId: 8,
        action: DesktopWindowActionType.openSelector,
      ),
    );

    expect(handled, isFalse);
  });
}

typedef _MethodResultResolver = bool Function(String method);

class _FakeEmbeddedPanelChannel implements EmbeddedPanelMethodChannelPort {
  _FakeEmbeddedPanelChannel({this.resultForMethod});

  final _MethodResultResolver? resultForMethod;
  EmbeddedPanelMethodCallHandler? _handler;
  final List<_Invocation> invocations = <_Invocation>[];

  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    invocations.add(_Invocation(method: method, arguments: arguments));
    return (resultForMethod?.call(method) ?? true) as T?;
  }

  @override
  Future<void> setMethodCallHandler(
    EmbeddedPanelMethodCallHandler? handler,
  ) async {
    _handler = handler;
  }

  Future<Object?> emit(String method, Object? arguments) {
    final EmbeddedPanelMethodCallHandler? handler = _handler;
    if (handler == null) {
      throw StateError('embedded panel handler 尚未注册');
    }
    return handler(MethodCall(method, arguments));
  }
}

class _Invocation {
  const _Invocation({required this.method, required this.arguments});

  final String method;
  final Object? arguments;
}
