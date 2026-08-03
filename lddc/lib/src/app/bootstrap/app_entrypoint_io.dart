import 'package:flutter/material.dart';

import '../../../panel_embedded_main.dart' as panel_embedded_main;
import '../../platform/desktop/service_host/desktop_service_bootstrap.dart';
import '../../platform/desktop/service_host/desktop_service_launch_arguments.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'app_bootstrap.dart';
import 'desktop_service_entrypoint_runner.dart';

Future<void> runPanelEmbeddedEntrypoint(List<String> args) {
  return panel_embedded_main.runPanelEmbeddedMain(args);
}

Future<void> runAppEntrypoint(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppBootstrap.ensureCorePortsRegistered();

  final bool isDesktopSubWindow =
      DesktopWindowLaunchArguments.isDesktopMultiWindowEntrypoint(args);
  final DesktopServiceLaunchArguments serviceLaunch = isDesktopSubWindow
      // `desktop_multi_window` 子 engine 的原始 argv 形如
      // `multi_window <windowId> <payload>`。这不是 service CLI 参数；若走严格
      // 解析会在浮窗创建过程中退出子 engine，Windows release 下可能进一步触发
      // flutter_windows.dll 原生崩溃。
      ? const DesktopServiceLaunchArguments()
      : DesktopServiceLaunchArguments.parse(args);
  final DesktopServiceEntrypointRunner runner =
      DesktopServiceEntrypointRunner();
  if (await runner.exitOnArgumentError(serviceLaunch)) {
    return;
  }
  final DesktopServiceStartupMode startupMode = isDesktopSubWindow
      ? DesktopServiceStartupMode.mainWindow
      : serviceLaunch.getServicePort
      ? DesktopServiceStartupMode.servicePortCli
      : serviceLaunch.notShow
      ? DesktopServiceStartupMode.hiddenService
      : DesktopServiceStartupMode.mainWindow;

  switch (startupMode) {
    case DesktopServiceStartupMode.servicePortCli:
      await runDesktopServicePortCliEntrypoint(
        args: args,
        serviceLaunch: serviceLaunch,
        serviceBootstrap: DesktopServiceBootstrap(),
      );
    case DesktopServiceStartupMode.hiddenService:
      await runner.runHiddenService(args: args, serviceLaunch: serviceLaunch);
    case DesktopServiceStartupMode.mainWindow:
      await runner.runMainWindow(args: args, serviceLaunch: serviceLaunch);
  }
}

Future<void> runHiddenDesktopServiceEntrypoint({
  required List<String> args,
}) async {
  final DesktopServiceLaunchArguments serviceLaunch =
      DesktopServiceLaunchArguments.parse(args);
  final DesktopServiceEntrypointRunner runner =
      DesktopServiceEntrypointRunner();
  if (await runner.exitOnArgumentError(serviceLaunch)) {
    return;
  }
  await runner.runHiddenService(args: args, serviceLaunch: serviceLaunch);
}

Future<bool> runDesktopServicePortCliEntrypoint({
  required List<String> args,
  required DesktopServiceLaunchArguments serviceLaunch,
  required DesktopServiceBootstrap serviceBootstrap,
}) {
  return DesktopServiceEntrypointRunner().runServicePortCli(
    args: args,
    serviceLaunch: serviceLaunch,
    serviceBootstrap: serviceBootstrap,
  );
}
