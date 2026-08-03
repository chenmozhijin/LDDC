import 'package:flutter/material.dart';

import '../../core/config/config.dart';
import '../../core/i18n/i18n.dart';
import '../../core/logging/logging.dart';
import '../../platform/desktop/service_host/desktop_main_window_host_page.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import '../../platform/desktop/window/desktop_window_strings_host_mapper.dart';
import '../../shared/ui/theme/app_theme_factory.dart';
import '../app.dart';
import '../shell/app_shell_page.dart';
import 'desktop_selector_window_content.dart';

/// 桌面主窗口与多窗口应用壳。
///
/// 普通 `LddcApp` 不能直接 import 桌面窗口/service 模块，否则 Web 构建会把
/// sqlite3、desktop_multi_window 等桌面链路静态拉进来。桌面入口统一使用本组件，
/// 移动/Web 入口只保留纯应用 shell。
class LddcDesktopApp extends StatelessWidget {
  const LddcDesktopApp({
    this.windowLaunch = const DesktopWindowLaunchArguments.main(),
    super.key,
  });

  final DesktopWindowLaunchArguments windowLaunch;

  @override
  Widget build(BuildContext context) {
    return LddcRuntimeMaterialApp(
      home: switch (windowLaunch.role) {
        DesktopWindowRole.main => const DesktopMainWindowHostPage(
          child: AppShellPage(),
        ),
        DesktopWindowRole.floating ||
        DesktopWindowRole.panel ||
        DesktopWindowRole.selector => _LddcDesktopWindowShellPage(
          launch: windowLaunch,
        ),
      },
    );
  }
}

/// 轻量桌面子窗口应用。
///
/// 仅供浮窗与 panel 使用，避免子窗口为纯渲染场景拉起完整的 Riverpod
/// provider 树，降低 debug 多引擎常驻内存。
class LddcLightweightDesktopSubWindowApp extends StatelessWidget {
  const LddcLightweightDesktopSubWindowApp({
    required this.windowLaunch,
    required this.config,
    super.key,
  });

  final DesktopWindowLaunchArguments windowLaunch;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    AppLogRuntime.updateLevel(config.app.logLevel);
    final Locale? locale = config.app.language.explicitLocale;
    final ThemeMode themeMode = switch (config.app.colorScheme) {
      AppColorScheme.light => ThemeMode.light,
      AppColorScheme.dark => ThemeMode.dark,
      AppColorScheme.auto => ThemeMode.system,
    };
    return LddcMaterialApp(
      locale: locale,
      themeMode: themeMode,
      lightTheme: AppThemeFactory.build(
        config: config,
        brightness: Brightness.light,
      ),
      darkTheme: AppThemeFactory.build(
        config: config,
        brightness: Brightness.dark,
      ),
      home: _LddcDesktopWindowShellPage(launch: windowLaunch),
    );
  }
}

/// 把 LDDC 的本地化和文件日志装配到通用桌面歌词窗口壳。
class _LddcDesktopWindowShellPage extends StatelessWidget {
  const _LddcDesktopWindowShellPage({required this.launch});

  final DesktopWindowLaunchArguments launch;

  @override
  Widget build(BuildContext context) {
    return DesktopWindowShellPage(
      launch: launch,
      strings: context.l10n.toDesktopLyricsWindowStrings(),
      logger: AppLogger.scope('desktop-window-shell').toDesktopLyricsLogger(),
      selectorContentBuilder: _buildDesktopSelectorWindowContent,
    );
  }
}

Widget _buildDesktopSelectorWindowContent(
  BuildContext context,
  DesktopSelectorWindowContentBuildData data,
) {
  return DesktopSelectorWindowContent(
    instanceId: data.instanceId,
    contextSnapshot: data.contextSnapshot,
    onLyricsSelected: data.onLyricsSelected,
  );
}
