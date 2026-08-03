import 'package:flutter_test/flutter_test.dart';

import 'package:lddc/src/platform/desktop/service_host/desktop_service_launch_arguments.dart';

void main() {
  group('DesktopServiceLaunchArguments', () {
    test('只解析Python版兼容 public CLI', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '--get-service-port',
            '--not-show',
          ]);

      expect(args.getServicePort, isTrue);
      expect(args.notShow, isTrue);
      expect(args.parseError, isNull);
    });

    test('未知参数会返回解析错误', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '--foo',
            '--get-service-port',
            '--bar=baz',
          ]);

      expect(args.getServicePort, isTrue);
      expect(args.parseError, '未知桌面服务参数：--foo');
      expect(args.hasParseError, isTrue);
    });

    test('无参数时不产生解析错误', () {
      const DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments();

      expect(args.getServicePort, isFalse);
      expect(args.notShow, isFalse);
      expect(args.parseError, isNull);
      expect(args.hasParseError, isFalse);
    });
  });
}
