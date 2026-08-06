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

    test('AppKit 的 XCTest 宿主参数和 NO 值不参与 CLI 解析', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '-NSTreatUnknownArgumentsAsOpen',
            'NO',
            '--not-show',
          ]);

      expect(args.notShow, isTrue);
      expect(args.parseError, isNull);
    });

    test('AppKit 的 ApplePersistenceIgnoreState YES/NO 值不参与 CLI 解析', () {
      for (final String value in <String>['YES', 'NO']) {
        final DesktopServiceLaunchArguments args =
            DesktopServiceLaunchArguments.parse(<String>[
              '-ApplePersistenceIgnoreState',
              value,
              '--not-show',
            ]);

        expect(args.notShow, isTrue, reason: value);
        expect(args.parseError, isNull, reason: value);
      }
    });

    test('两个 AppKit 宿主参数可以同时出现', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '-NSTreatUnknownArgumentsAsOpen',
            'YES',
            '-ApplePersistenceIgnoreState',
            'NO',
            '--get-service-port',
          ]);

      expect(args.getServicePort, isTrue);
      expect(args.parseError, isNull);
    });

    test('ApplePersistenceIgnoreState 缺失值不会吞掉后续 LDDC 参数', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '-ApplePersistenceIgnoreState',
            '--not-show',
          ]);

      expect(args.notShow, isTrue);
      expect(
        args.parseError,
        contains('未知桌面服务参数：-ApplePersistenceIgnoreState'),
      );
    });

    test('ApplePersistenceIgnoreState 非法值仍然严格失败', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '-ApplePersistenceIgnoreState',
            'maybe',
          ]);

      expect(args.parseError, '未知桌面服务参数：-ApplePersistenceIgnoreState');
    });

    test('AppKit 的 XCTest 宿主参数接受 YES 值', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '-NSTreatUnknownArgumentsAsOpen',
            'YES',
            '--get-service-port',
          ]);

      expect(args.getServicePort, isTrue);
      expect(args.parseError, isNull);
    });

    test('AppKit 宿主参数缺少值时不吞掉后续 LDDC 参数', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '-NSTreatUnknownArgumentsAsOpen',
            '--not-show',
          ]);

      expect(args.notShow, isTrue);
      expect(args.parseError, isNull);
    });

    test('AppKit 宿主参数后的非布尔值仍严格报错', () {
      final DesktopServiceLaunchArguments args =
          DesktopServiceLaunchArguments.parse(<String>[
            '-NSTreatUnknownArgumentsAsOpen',
            'MAYBE',
            '--not-show',
          ]);

      expect(args.notShow, isTrue);
      expect(args.parseError, '未知桌面服务参数：MAYBE');
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
