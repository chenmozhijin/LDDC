import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  group('DesktopWindowBackendPorts', () {
    test('会按组合方式暴露 floating/selector/panel 三类 host', () {
      const DesktopNoopFloatingWindowHost floatingHost =
          DesktopNoopFloatingWindowHost();
      const DesktopNoopSelectorWindowHost selectorHost =
          DesktopNoopSelectorWindowHost();
      final _FakePanelHost panelHost = _FakePanelHost();

      final DesktopWindowBackendPorts backend = DesktopWindowBackendPorts(
        floatingHost: floatingHost,
        selectorHost: selectorHost,
        panelHost: panelHost,
      );

      expect(identical(backend.floatingHost, floatingHost), isTrue);
      expect(identical(backend.selectorHost, selectorHost), isTrue);
      expect(identical(backend.panelHost, panelHost), isTrue);
    });
  });
}

class _FakePanelHost implements DesktopPanelWindowHostPort {
  @override
  void setIntentHandler(DesktopPanelWindowIntentHandler? handler) {}

  @override
  Future<void> createPanel({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    DesktopPanelWindowSnapshot? initialSnapshot,
    PanelSurfaceUpdate? initialSurface,
  }) async {}

  @override
  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {}

  @override
  Future<void> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {}

  @override
  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  }) async {}
}
