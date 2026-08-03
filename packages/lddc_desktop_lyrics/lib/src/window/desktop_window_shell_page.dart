import 'dart:async';

import 'package:flutter/material.dart';
import '../logging/desktop_lyrics_logger.dart';

import 'desktop_floating_window_shell_page.dart';
import 'desktop_panel_window_shell_page.dart';
import 'desktop_selector_window_shell_page.dart';
import 'desktop_window_backend.dart';
import 'desktop_window_launch.dart';
import 'desktop_window_strings.dart';

typedef DesktopSelectorWindowContentBuilder =
    Widget Function(
      BuildContext context,
      DesktopSelectorWindowContentBuildData data,
    );

class DesktopSelectorWindowContentBuildData {
  const DesktopSelectorWindowContentBuildData({
    required this.instanceId,
    required this.contextSnapshot,
    required this.onLyricsSelected,
  });

  final int instanceId;
  final DesktopSelectorWindowContext? contextSnapshot;
  final Future<bool> Function(DesktopSelectorLyricsSelectedIntent intent)
  onLyricsSelected;
}

/// 桌面多窗口壳层入口。
class DesktopWindowShellPage extends StatelessWidget {
  const DesktopWindowShellPage({
    required this.launch,
    this.nowMsFactory,
    this.selectorContentBuilder,
    this.strings = const DesktopLyricsWindowStrings.zhHans(),
    this.logger = const DesktopLyricsLogger(),
    super.key,
  });

  final DesktopWindowLaunchArguments launch;
  final int Function()? nowMsFactory;
  final DesktopSelectorWindowContentBuilder? selectorContentBuilder;
  final DesktopLyricsWindowStrings strings;
  final DesktopLyricsLogger logger;

  @override
  Widget build(BuildContext context) {
    return switch (launch.role) {
      DesktopWindowRole.floating => DesktopFloatingWindowShellPage(
        launch: launch,
        nowMsFactory: nowMsFactory,
        strings: strings,
        logger: logger,
      ),
      DesktopWindowRole.panel => DesktopPanelWindowShellPage(
        launch: launch,
        nowMsFactory: nowMsFactory,
        strings: strings,
        logger: logger,
      ),
      DesktopWindowRole.selector => DesktopSelectorWindowShellPage(
        launch: launch,
        contentBuilder: selectorContentBuilder,
      ),
      DesktopWindowRole.main => const SizedBox.shrink(),
    };
  }
}
