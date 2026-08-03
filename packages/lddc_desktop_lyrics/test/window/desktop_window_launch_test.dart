import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  group('DesktopWindowLaunchArguments', () {
    test('空参数会回退为 main 角色', () {
      expect(
        DesktopWindowLaunchArguments.decode(null).role,
        DesktopWindowRole.main,
      );
      expect(
        DesktopWindowLaunchArguments.decode('').role,
        DesktopWindowRole.main,
      );
    });

    test('可往返编码 floating 角色与 hostWindowId', () {
      const DesktopWindowLaunchArguments arguments =
          DesktopWindowLaunchArguments(
            role: DesktopWindowRole.floating,
            instanceId: 42,
            hostWindowId: '7',
            initialWindowRect: WindowRect(
              left: 120,
              top: 240,
              width: 900,
              height: 180,
            ),
          );

      final DesktopWindowLaunchArguments decoded =
          DesktopWindowLaunchArguments.decode(arguments.encode());

      expect(decoded.role, DesktopWindowRole.floating);
      expect(decoded.instanceId, 42);
      expect(decoded.hostWindowId, '7');
      expect(decoded.initialWindowRect?.left, 120);
      expect(decoded.initialWindowRect?.top, 240);
      expect(decoded.initialWindowRect?.width, 900);
      expect(decoded.initialWindowRect?.height, 180);
    });

    test('非法首次窗口矩形会被拒绝', () {
      final DesktopWindowLaunchArguments decoded =
          DesktopWindowLaunchArguments.decode(<String, Object?>{
            'role': 'floating',
            'instanceId': 1,
            'initialWindowRect': <double>[10, 20, -1, 100],
          });

      expect(decoded.initialWindowRect, isNull);
    });

    test('普通子窗口参数损坏时回退 main 而不是抛异常', () {
      expect(
        DesktopWindowLaunchArguments.decode('{broken-json').role,
        DesktopWindowRole.main,
      );
      expect(
        DesktopWindowLaunchArguments.decode(<String>['floating']).role,
        DesktopWindowRole.main,
      );
      expect(
        DesktopWindowLaunchArguments.decode(
          '{"role":"unknown","instanceId":"9"}',
        ).role,
        DesktopWindowRole.main,
      );
    });

    test('识别 desktop_multi_window 子 engine 原始 argv', () {
      expect(
        DesktopWindowLaunchArguments.isDesktopMultiWindowEntrypoint(<String>[
          'multi_window',
          'window-1',
          '{"role":"floating"}',
        ]),
        isTrue,
      );
      expect(
        DesktopWindowLaunchArguments.isDesktopMultiWindowEntrypoint(<String>[
          '--get-service-port',
        ]),
        isFalse,
      );
    });
  });
}
