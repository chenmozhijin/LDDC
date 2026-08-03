import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/platform/desktop/window/windows_desktop_panel_host_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'lddc/windows_desktop_panel_host',
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('createPanel 透传唯一 embedded 创建字段并解码精简 surface', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          received = call;
          return <String, Object?>{
            'surfaceRevision': 1,
            'attached': true,
            'visible': false,
            'clientWidthPx': 941,
            'clientHeightPx': 906,
            'dpi': 144,
          };
        });
    final WindowsDesktopPanelHostAdapter adapter =
        WindowsDesktopPanelHostAdapter();

    final DesktopPanelSurfaceState surface = await adapter.createPanel(
      request: const DesktopPanelCreateRequest(
        instanceId: 11,
        panelId: 3,
        hostWindowId: 4096,
        channelName: 'lddc.panel.runtime/11/3/1',
        generation: 1,
        initialSurface: PanelSurfaceUpdate(
          width: 941,
          height: 906,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      ),
    );

    expect(received?.method, 'createPanel');
    final Map<Object?, Object?> arguments = Map<Object?, Object?>.from(
      received?.arguments as Map<Object?, Object?>,
    );
    expect(arguments.remove('ownerToken'), isA<int>());
    expect(arguments, <String, Object?>{
      'instanceId': 11,
      'panelId': 3,
      'hostWindowId': 4096,
      'channelName': 'lddc.panel.runtime/11/3/1',
      'generation': 1,
      'requestedWidth': 941,
      'requestedHeight': 906,
      'requestedSizeSpace': 'hostPhysicalPx',
      'requestedVisible': true,
    });
    expect(surface.surfaceRevision, 1);
    expect(surface.clientSizePx, const Size(941, 906));
    expect(surface.dpi, 144);
  });

  test('surface_unready 会转换为明确的 pending 异常', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'surface_unready');
        });
    final WindowsDesktopPanelHostAdapter adapter =
        WindowsDesktopPanelHostAdapter();

    expect(
      () => adapter.createPanel(
        request: const DesktopPanelCreateRequest(
          instanceId: 1,
          panelId: 2,
          hostWindowId: 3,
          channelName: 'panel',
          generation: 1,
        ),
      ),
      throwsA(isA<DesktopPanelSurfaceUnavailable>()),
    );
  });

  test('更新、显隐和销毁复用同一 owner token', () async {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'updatePanelSurface') {
            return <String, Object?>{
              'surfaceRevision': 2,
              'attached': true,
              'visible': false,
              'clientWidthPx': 640,
              'clientHeightPx': 320,
              'dpi': 96,
            };
          }
          return true;
        });
    final WindowsDesktopPanelHostAdapter adapter =
        WindowsDesktopPanelHostAdapter();

    final DesktopPanelSurfaceState surface = await adapter.updatePanelSurface(
      instanceId: 13,
      panelId: 8,
      update: const PanelSurfaceUpdate(
        width: 640,
        height: 320,
        sizeSpace: PanelSizeSpace.hostPhysicalPx,
        visible: true,
      ),
    );
    await adapter.setPanelVisibility(instanceId: 13, panelId: 8, visible: true);
    await adapter.destroyPanel(instanceId: 13, panelId: 8);

    expect(calls.map((MethodCall call) => call.method), <String>[
      'updatePanelSurface',
      'setPanelVisibility',
      'destroyPanel',
    ]);
    final List<Object?> ownerTokens = calls
        .map(
          (MethodCall call) =>
              (call.arguments as Map<Object?, Object?>)['ownerToken'],
        )
        .toList(growable: false);
    expect(ownerTokens.toSet(), hasLength(1));
    expect(surface.clientSizePx, const Size(640, 320));
  });
}
