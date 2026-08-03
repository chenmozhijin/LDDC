import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/capability/capability.dart';
import '../../../core/config/config.dart';

part 'settings_page_dependencies.g.dart';

typedef SettingsConfigUpdater =
    Future<AppConfig> Function(Map<String, Object?> patch);

typedef SettingsDirectoryPicker =
    Future<String?> Function({String? initialDirectory});

typedef SettingsDiagnosticsLogger =
    void Function({
      required String action,
      required Object error,
      required StackTrace stackTrace,
      required Map<String, Object?> fields,
    });

class SettingsPageDependencies {
  const SettingsPageDependencies({
    required this.config,
    required this.capability,
    required this.updateConfig,
    required this.pickDirectory,
    required this.openAssociationManager,
    required this.openLogDirectory,
    required this.clearCache,
    required this.logFailure,
  });

  final AppConfig config;
  final AppCapability capability;
  final SettingsConfigUpdater updateConfig;
  final SettingsDirectoryPicker pickDirectory;
  final Future<void> Function() openAssociationManager;
  final Future<void> Function() openLogDirectory;
  final Future<void> Function() clearCache;
  final SettingsDiagnosticsLogger logFailure;
}

/// Settings 是可复用的功能页，不能直接读取 app 层或平台层 Provider。
/// 真实文件选择、导航和缓存清理由 app 层在页面外部注入；测试也必须显式注入，
/// 这样缺少运行时能力时会尽早失败，而不是在用户操作时才暴露空实现。
// Riverpod 3.4 会在运行时校验 scoped provider 的传递依赖。这里交给生成器声明
// scope 元数据，控制器才能显式引用该依赖，同时继续保留原有 Provider 名称和覆盖方式。
@Riverpod(dependencies: [])
SettingsPageDependencies settingsPageDependencies(Ref ref) {
  throw StateError('SettingsPageDependencies 必须由 app 层或测试显式注入');
}
