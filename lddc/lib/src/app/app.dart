import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/config.dart';
import '../core/i18n/i18n.dart';
import '../core/i18n/l10n/app_localizations.dart';
import '../core/logging/logging.dart';
import 'bootstrap/app_runtime_providers.dart';
import 'shell/app_shell_page.dart';

/// 应用根组件：运行期状态统一从 Riverpod provider 树读取。
class LddcApp extends StatelessWidget {
  const LddcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const LddcRuntimeMaterialApp(home: AppShellPage());
  }
}

/// 使用 Riverpod 运行时配置构建统一的 Material 应用壳。
///
/// 普通窗口和桌面主窗口都需要响应语言、主题与日志级别变化。把这些监听集中在
/// 同一个组件后，各入口只负责选择首页内容，避免新增入口时遗漏本地化或主题配置。
class LddcRuntimeMaterialApp extends ConsumerWidget {
  const LddcRuntimeMaterialApp({required this.home, super.key});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AppConfig>(appConfigSnapshotProvider, (_, AppConfig next) {
      AppLogRuntime.updateLevel(next.app.logLevel);
    });
    final Locale? locale = ref.watch(appLocaleProvider);
    final ThemeMode themeMode = ref.watch(appThemeModeProvider);
    final ThemeData lightTheme = ref.watch(appLightThemeProvider);
    final ThemeData darkTheme = ref.watch(appDarkThemeProvider);

    return LddcMaterialApp(
      locale: locale,
      themeMode: themeMode,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      home: home,
    );
  }
}

/// LDDC 的统一 MaterialApp 配置。
///
/// 桌面歌词浮窗等轻量子窗口不会创建完整 Provider 树，而是直接传入启动快照；
/// 普通应用则由 [LddcRuntimeMaterialApp] 提供实时配置。两条链路最终共用这里的
/// 本地化、主题和调试标记设置，确保窗口之间的基础行为一致。
class LddcMaterialApp extends StatelessWidget {
  const LddcMaterialApp({
    required this.locale,
    required this.themeMode,
    required this.lightTheme,
    required this.darkTheme,
    required this.home,
    super.key,
  });

  final Locale? locale;
  final ThemeMode themeMode;
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (BuildContext context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: home,
    );
  }
}
