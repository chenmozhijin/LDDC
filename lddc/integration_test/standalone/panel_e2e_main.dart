import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:lddc/panel_embedded_main.dart';

import '../support/embedded_panel_e2e.dart';

Future<void> main(List<String> args) => panelE2EMain(args);

@pragma('vm:entry-point')
Future<void> panelE2EMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final int exitCode = await runEmbeddedPanelE2E(args);
  exit(exitCode);
}

/// E2E 构建仍使用生产入口名，原生宿主无需携带任何测试专用协议字段。
@pragma('vm:entry-point')
Future<void> panelEmbeddedMain(List<String> args) {
  return runPanelEmbeddedMain(args);
}
