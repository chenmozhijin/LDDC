import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lddc/src/app/bootstrap/app_bootstrap.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc/src/app/desktop/desktop_app.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/logging/logging.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_bootstrap.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/platform/desktop/window/desktop_window_providers.dart';

/// integration test 启动参数。
class LddcIntegrationLaunchOptions {
  const LddcIntegrationLaunchOptions({
    this.configRepository,
    this.capability,
    this.windowLaunch = const DesktopWindowLaunchArguments.main(),
    this.serviceBootstrap,
    this.startDesktopServiceHost = false,
    this.overrides = const [],
  });

  final ConfigRepository? configRepository;
  final AppCapability? capability;
  final DesktopWindowLaunchArguments windowLaunch;
  final DesktopServiceBootstrap? serviceBootstrap;
  final bool startDesktopServiceHost;
  final List<Object> overrides;
}

/// integration test 启动句柄。
class LddcIntegrationLaunchHandle {
  LddcIntegrationLaunchHandle({
    required this.container,
    required this.serviceBootstrap,
    required this.windowLaunch,
  });

  final ProviderContainer container;
  final DesktopServiceBootstrap serviceBootstrap;
  final DesktopWindowLaunchArguments windowLaunch;

  Widget buildApp() {
    return UncontrolledProviderScope(
      container: container,
      child: LddcDesktopApp(windowLaunch: windowLaunch),
    );
  }

  Future<void> dispose() async {
    await serviceBootstrap.dispose();
    container.dispose();
    await AppBootstrap.disposeForTest();
  }
}

/// 启动完整 app，供 integration test 复用。
Future<LddcIntegrationLaunchHandle> launchLddcForIntegrationTest({
  LddcIntegrationLaunchOptions options = const LddcIntegrationLaunchOptions(),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppBootstrap.resetForTest();
  await AppBootstrap.ensureInitialized(
    configRepository: options.configRepository,
    capabilityOverride: options.capability,
  );
  // 日志文件路径依赖 AppBootstrap 注册的 AppStoragePathsPort，测试启动时必须
  // 先完成 bootstrap，再初始化日志，否则离线 integration 会在首帧前失败。
  await AppLogRuntime.initialize(
    role: options.windowLaunch.role.name,
    instanceId: options.windowLaunch.instanceId,
    panelId: options.windowLaunch.panelId,
  );

  final DesktopServiceBootstrap serviceBootstrap =
      options.serviceBootstrap ?? DesktopServiceBootstrap();
  final List<Object> overrides = <Object>[
    desktopServiceBootstrapProvider.overrideWithValue(serviceBootstrap),
    if (options.configRepository != null)
      configRepositoryProvider.overrideWithValue(options.configRepository!),
    if (options.capability != null)
      appCapabilityProvider.overrideWith((ref) => options.capability!),
    ...options.overrides,
  ];
  final ProviderContainer container = ProviderContainer(
    overrides: overrides.cast(),
  );

  if (options.startDesktopServiceHost &&
      options.windowLaunch.role == DesktopWindowRole.main &&
      serviceBootstrap.isPrimaryInstance) {
    await container.read(desktopServiceHostProvider).ensureStarted();
  }

  return LddcIntegrationLaunchHandle(
    container: container,
    serviceBootstrap: serviceBootstrap,
    windowLaunch: options.windowLaunch,
  );
}
