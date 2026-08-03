import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/capability/capability.dart';
import '../../core/config/config.dart';
import '../../core/i18n/i18n.dart';
import '../../shared/ui/theme/app_theme_factory.dart';
import 'app_bootstrap.dart';

part 'app_runtime_providers.g.dart';

/// 全局配置仓储 Provider。
///
/// 这里不能依赖 `app_providers.dart`：普通 app 壳只需要配置、主题和能力，
/// 若反向导入完整业务 Provider，Web 构建会被 cache/sqlite3 等 IO 依赖污染。
final Provider<ConfigRepository> configRepositoryProvider =
    Provider<ConfigRepository>((Ref ref) {
      return AppBootstrap.configRepository;
    });

/// 全局配置流 Provider，统一监听配置热更新。
final StreamProvider<AppConfig> appConfigStreamProvider =
    StreamProvider<AppConfig>((Ref ref) {
      return ref.watch(configRepositoryProvider).watch();
    });

/// 运行期能力开关快照，统一从 Riverpod 树读取。
@Riverpod(keepAlive: true)
AppCapability appCapability(Ref ref) {
  return AppBootstrap.capability;
}

/// 运行期配置快照：
/// 优先消费配置流最新值，未就绪时回退到仓储当前值。
@Riverpod(keepAlive: true)
AppConfig appConfigSnapshot(Ref ref) {
  final ConfigRepository repository = ref.watch(configRepositoryProvider);
  final streamed = ref.watch(appConfigStreamProvider);
  return streamed.maybeWhen(
    data: (AppConfig value) => value,
    orElse: () => repository.current,
  );
}

/// 当前应用 locale：
/// `auto` 跟随系统，显式语言则映射到受支持的 locale。
@Riverpod(keepAlive: true)
Locale? appLocale(Ref ref) {
  final AppConfig config = ref.watch(appConfigSnapshotProvider);
  return config.app.language.explicitLocale;
}

/// 主题模式映射：保持与配置 `app.colorScheme` 一致。
@Riverpod(keepAlive: true)
ThemeMode appThemeMode(Ref ref) {
  final AppConfig config = ref.watch(appConfigSnapshotProvider);
  return switch (config.app.colorScheme) {
    AppColorScheme.light => ThemeMode.light,
    AppColorScheme.dark => ThemeMode.dark,
    AppColorScheme.auto => ThemeMode.system,
  };
}

/// 亮色主题：用于 Light/System(亮色) 分支。
@Riverpod(keepAlive: true)
ThemeData appLightTheme(Ref ref) {
  final AppConfig config = ref.watch(appConfigSnapshotProvider);
  return AppThemeFactory.build(config: config, brightness: Brightness.light);
}

/// 暗色主题：用于 Dark/System(暗色) 分支。
@Riverpod(keepAlive: true)
ThemeData appDarkTheme(Ref ref) {
  final AppConfig config = ref.watch(appConfigSnapshotProvider);
  return AppThemeFactory.build(config: config, brightness: Brightness.dark);
}
