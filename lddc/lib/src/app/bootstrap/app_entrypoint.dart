import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import 'app_bootstrap.dart';

Future<void> runAppEntrypoint(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppBootstrap.ensureCorePortsRegistered();
  await AppBootstrap.ensureInitialized();
  runApp(const ProviderScope(child: LddcApp()));
}

Future<void> runPanelEmbeddedEntrypoint(List<String> args) {
  throw UnsupportedError('当前平台不支持桌面歌词 embedded panel 入口');
}

Future<void> runHiddenDesktopServiceEntrypoint({required List<String> args}) {
  throw UnsupportedError('当前平台不支持桌面歌词隐藏服务入口');
}
