import 'dart:async';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'desktop_service_launch_arguments.dart';

/// Web/非 IO 环境下的桌面服务引导占位实现。
class DesktopServiceEntrypointResult {
  const DesktopServiceEntrypointResult._({
    required this.shouldRunApp,
    required this.exitCode,
    this.stdoutLine,
    this.stderrLine,
  });

  const DesktopServiceEntrypointResult.continueApp()
    : this._(shouldRunApp: true, exitCode: 0);

  const DesktopServiceEntrypointResult.exit({
    required int exitCode,
    String? stdoutLine,
    String? stderrLine,
  }) : this._(
         shouldRunApp: false,
         exitCode: exitCode,
         stdoutLine: stdoutLine,
         stderrLine: stderrLine,
       );

  final bool shouldRunApp;
  final int exitCode;
  final String? stdoutLine;
  final String? stderrLine;
}

/// 非 IO 环境直接透传，不接管启动。
class DesktopServiceBootstrap {
  const DesktopServiceBootstrap();

  bool get isPrimaryInstance => false;

  bool get shouldStartHidden => false;

  Future<void> attachShowHandler(Future<void> Function() handler) async {}

  void detachShowHandler() {}

  Future<DesktopServiceEntrypointResult> prepareEntrypoint({
    required DesktopWindowLaunchArguments windowLaunch,
    required DesktopServiceLaunchArguments launchArguments,
  }) async {
    return const DesktopServiceEntrypointResult.continueApp();
  }

  Future<bool> finalizeEntrypoint(DesktopServiceEntrypointResult result) async {
    return result.shouldRunApp;
  }

  Future<void> registerServicePort(int port) async {}

  Future<void> dispose() async {}
}
