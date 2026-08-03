import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/files/app_path_opener.dart';

void main() {
  test('桌面平台映射到对应系统打开命令', () async {
    const List<(TargetPlatform, String)> cases = <(TargetPlatform, String)>[
      (TargetPlatform.windows, 'explorer'),
      (TargetPlatform.macOS, 'open'),
      (TargetPlatform.linux, 'xdg-open'),
    ];

    for (final (TargetPlatform platform, String expectedExecutable) in cases) {
      String? executable;
      List<String>? arguments;
      final AppPathOpenerImpl opener = AppPathOpenerImpl(
        platformResolver: () => platform,
        processStarter: (String command, List<String> commandArguments) async {
          executable = command;
          arguments = commandArguments;
        },
      );

      await opener.openDirectory('  /music  ');

      expect(executable, expectedExecutable, reason: '$platform');
      expect(arguments, <String>['/music'], reason: '$platform');
    }
  });

  test('空路径在启动进程前被拒绝', () async {
    int startCount = 0;
    final AppPathOpenerImpl opener = AppPathOpenerImpl(
      platformResolver: () => TargetPlatform.windows,
      processStarter: (_, _) async {
        startCount += 1;
      },
    );

    await expectLater(opener.openFile('   '), throwsArgumentError);

    expect(startCount, 0);
  });

  test('移动平台显式拒绝系统路径打开', () async {
    int startCount = 0;
    final AppPathOpenerImpl opener = AppPathOpenerImpl(
      platformResolver: () => TargetPlatform.android,
      processStarter: (_, _) async {
        startCount += 1;
      },
    );

    await expectLater(opener.openDirectory('/music'), throwsUnsupportedError);

    expect(startCount, 0);
  });
}
