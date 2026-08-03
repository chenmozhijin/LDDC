import 'desktop_service_bootstrap.dart';
import 'desktop_service_coordinator.dart';
import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'desktop_panel_host_bridge.dart';
import 'desktop_session_reducer.dart';

class DesktopServiceHost {
  const DesktopServiceHost({
    required DesktopServiceCoordinator coordinator,
    required DesktopSessionReducer reducer,
    required DesktopServiceBootstrap bootstrap,
    DesktopPanelHostBridgeController? panelHostBridgeController,
  });

  int? get port => null;

  bool get isRunning => false;

  Future<bool> sendControlCommand({
    required int instanceId,
    required DesktopControlCommandTask task,
  }) async => false;

  Future<void> ensureStarted() async {}

  Future<void> dispose() async {}
}
