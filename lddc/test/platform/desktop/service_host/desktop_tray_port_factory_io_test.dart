import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_tray_port_factory_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel trayManagerChannel = MethodChannel('tray_manager');

  testWidgets('Windows 托盘初始化会把 ico 路径交给 tray_manager', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final List<MethodCall> trayCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      trayManagerChannel,
      (MethodCall call) async {
        trayCalls.add(call);
        return true;
      },
    );
    final TrayManagerDesktopTrayPort port = TrayManagerDesktopTrayPort();

    try {
      await port.initialize(iconAsset: 'assets/tray_icon.ico', toolTip: 'LDDC');

      final MethodCall setIconCall = trayCalls.firstWhere(
        (MethodCall call) => call.method == 'setIcon',
      );
      final Map<Object?, Object?> arguments =
          setIconCall.arguments! as Map<Object?, Object?>;
      expect(arguments['iconPath'], isA<String>());
      final String iconPath = arguments['iconPath'] as String;
      expect(iconPath, contains('flutter_assets'));
      expect(iconPath.replaceAll('\\', '/'), endsWith('assets/tray_icon.ico'));
    } finally {
      await port.dispose();
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        trayManagerChannel,
        null,
      );
    }
  });
}
