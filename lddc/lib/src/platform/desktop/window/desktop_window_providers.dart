import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config.dart';
import '../../../core/library_link/library_link.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../service_host/desktop_floating_effect_executor.dart';
import '../service_host/desktop_exit_guard.dart';
import '../service_host/desktop_main_window_navigation.dart';
import '../service_host/desktop_pending_effect_executor.dart';
import '../service_host/desktop_panel_effect_executor.dart';
import '../service_host/desktop_panel_host_bridge.dart';
import '../service_host/desktop_service_coordinator.dart';
import '../service_host/desktop_selector_effect_executor.dart';
import '../service_host/desktop_service_bootstrap.dart';
import '../service_host/desktop_service_runtime_host_stub.dart'
    if (dart.library.io) '../service_host/desktop_service_runtime_host_io.dart';
import '../service_host/desktop_session_reducer.dart';
import '../service_host/desktop_tray_port.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'desktop_panel_window_host.dart';

class DesktopWindowAppDependencies {
  const DesktopWindowAppDependencies({
    required this.configRepository,
    required this.libraryLinkRepository,
    required this.loadLinkedLyrics,
    required this.runAutoFetch,
    required this.resolveAutoSaveDirectory,
    required this.fileSavePersistenceFactory,
    required this.openAssociationManager,
  });

  final ConfigRepository configRepository;
  final LibraryLinkRepository libraryLinkRepository;
  final DesktopLinkedLyricsLoader loadLinkedLyrics;
  final DesktopAutoFetchRunner runAutoFetch;
  final DesktopAutoSaveDirectoryResolver resolveAutoSaveDirectory;
  final LyricsSavePersistencePort Function(String folder)
  fileSavePersistenceFactory;
  final Future<void> Function() openAssociationManager;
}

final Provider<DesktopWindowAppDependencies>
desktopWindowAppDependenciesProvider = Provider<DesktopWindowAppDependencies>((
  Ref ref,
) {
  throw StateError('DesktopWindowAppDependencies 必须由 app 层显式注入');
});

/// 当前窗口角色快照。
///
/// 主窗口与子窗口必须通过同一份启动参数判断自己能否创建其他窗口，
/// 避免子窗口再次递归拉起新的浮窗/选择器实例。
final Provider<DesktopWindowLaunchArguments> desktopWindowLaunchProvider =
    Provider<DesktopWindowLaunchArguments>((Ref ref) {
      final DesktopEmbeddedPanelRuntime embeddedPanelRuntime =
          DesktopEmbeddedPanelRuntime.instance;
      if (embeddedPanelRuntime.isInitialized) {
        return embeddedPanelRuntime.windowLaunch;
      }
      return DesktopSubWindowRuntime.instance.launch;
    });

/// `desktop_multi_window` 抽象口。
final Provider<DesktopMultiWindowPort> desktopMultiWindowPortProvider =
    Provider<DesktopMultiWindowPort>((Ref ref) {
      return const DesktopMultiWindowAdapter();
    });

/// 主窗口侧场景缓存。
final Provider<DesktopSceneStorePort> desktopSceneStoreProvider =
    Provider<DesktopSceneStorePort>((Ref ref) {
      return DesktopInMemorySceneStore();
    });

final Provider<DesktopWindowLifecycleRegistry>
desktopWindowLifecycleRegistryProvider =
    Provider<DesktopWindowLifecycleRegistry>((Ref ref) {
      final DesktopWindowLifecycleRegistryController controller =
          DesktopWindowLifecycleRegistryController();
      // 主 engine 拥有唯一 registry；ProviderScope 释放时同步启动幂等关闭，
      // 避免事件 StreamController 与关闭等待者跨应用生命周期常驻。
      ref.onDispose(() {
        unawaited(controller.dispose());
      });
      return controller;
    });

/// 桌面服务 bootstrap 协调器 Provider。
final Provider<DesktopServiceBootstrap> desktopServiceBootstrapProvider =
    Provider<DesktopServiceBootstrap>((Ref ref) {
      final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap();
      ref.onDispose(() {
        unawaited(bootstrap.dispose());
      });
      return bootstrap;
    });

/// 桌面退出守卫 Provider。
final Provider<DesktopExitGuardPort> desktopExitGuardProvider =
    Provider<DesktopExitGuardPort>((Ref ref) {
      return DesktopExitGuardController(
        lifecycleRegistry: ref.watch(desktopWindowLifecycleRegistryProvider),
      );
    });

final Provider<DesktopTrayPortFactory> desktopTrayPortFactoryProvider =
    Provider<DesktopTrayPortFactory>((Ref ref) {
      return createDesktopTrayPort;
    });

/// 桌面窗口后端统一装配入口。
///
/// 规则：
/// - 只有桌面主窗口角色会创建真实浮窗/选择器 host；
/// - 子窗口角色与非桌面平台统一回退到 noop host；
/// - 面板仅在 Windows 主窗口角色启用 embedded panel 原生宿主。
final Provider<DesktopWindowBackend>
desktopWindowBackendProvider = Provider<DesktopWindowBackend>((Ref ref) {
  final DesktopWindowLaunchArguments launch = ref.watch(
    desktopWindowLaunchProvider,
  );
  final DesktopMultiWindowPort multiWindowPort = ref.watch(
    desktopMultiWindowPortProvider,
  );
  final DesktopSceneStorePort sceneStore = ref.watch(desktopSceneStoreProvider);
  final bool useRealAppOwnedWindows =
      _supportsDesktopAppOwnedWindows() &&
      launch.role == DesktopWindowRole.main;
  final DesktopMultiWindowHostIntentRouter intentRouter =
      DesktopMultiWindowHostIntentRouter(multiWindowPort: multiWindowPort);
  ref.onDispose(intentRouter.dispose);
  final DesktopFloatingWindowHostPort floatingHost = useRealAppOwnedWindows
      ? DesktopMultiWindowFloatingWindowHost(
          sceneStore: sceneStore,
          multiWindowPort: multiWindowPort,
          lifecycleRegistry: ref.watch(desktopWindowLifecycleRegistryProvider),
          intentRouter: intentRouter,
        )
      : const DesktopNoopFloatingWindowHost();
  final DesktopSelectorWindowHostPort selectorHost = useRealAppOwnedWindows
      ? DesktopMultiWindowSelectorWindowHost(
          multiWindowPort: multiWindowPort,
          lifecycleRegistry: ref.watch(desktopWindowLifecycleRegistryProvider),
          intentRouter: intentRouter,
        )
      : const DesktopNoopSelectorWindowHost();
  if (floatingHost case final DesktopMultiWindowFloatingWindowHost host) {
    ref.onDispose(host.dispose);
  }
  if (selectorHost case final DesktopMultiWindowSelectorWindowHost host) {
    ref.onDispose(host.dispose);
  }
  final DesktopPanelWindowHostPort panelHost =
      _supportsWindowsEmbeddedPanel() && launch.role == DesktopWindowRole.main
      ? WindowsEmbeddedPanelWindowHost(
          sceneStore: sceneStore,
          lifecycleRegistry: ref.watch(desktopWindowLifecycleRegistryProvider),
        )
      : const DesktopNoopPanelWindowHost();
  if (panelHost case final WindowsEmbeddedPanelWindowHost host) {
    ref.onDispose(host.dispose);
  }
  return DesktopWindowBackendPorts(
    floatingHost: floatingHost,
    selectorHost: selectorHost,
    panelHost: panelHost,
  );
});

/// 面板 effect 执行器 Provider。
final Provider<DesktopPanelEffectExecutor> desktopPanelEffectExecutorProvider =
    Provider<DesktopPanelEffectExecutor>((Ref ref) {
      return DesktopPanelEffectExecutor(
        windowBackend: ref.watch(desktopWindowBackendProvider),
      );
    });

/// 选择器 effect 执行器 Provider。
final Provider<DesktopSelectorEffectExecutor>
desktopSelectorEffectExecutorProvider = Provider<DesktopSelectorEffectExecutor>(
  (Ref ref) {
    return DesktopSelectorEffectExecutor(
      windowBackend: ref.watch(desktopWindowBackendProvider),
    );
  },
);

/// 浮窗状态同步执行器 Provider。
final Provider<DesktopFloatingEffectExecutor>
desktopFloatingEffectExecutorProvider = Provider<DesktopFloatingEffectExecutor>(
  (Ref ref) {
    return DesktopFloatingEffectExecutor(
      windowBackend: ref.watch(desktopWindowBackendProvider),
    );
  },
);

/// 桌面主机挂起 effect 执行器 Provider。
final Provider<DesktopPendingEffectExecutor>
desktopPendingEffectExecutorProvider = Provider<DesktopPendingEffectExecutor>((
  Ref ref,
) {
  return DesktopPendingEffectExecutor(
    libraryLinkRepository: ref.watch(
      desktopWindowAppDependenciesProvider.select(
        (DesktopWindowAppDependencies dependencies) =>
            dependencies.libraryLinkRepository,
      ),
    ),
    loadLinkedLyrics: ref.watch(
      desktopWindowAppDependenciesProvider.select(
        (DesktopWindowAppDependencies dependencies) =>
            dependencies.loadLinkedLyrics,
      ),
    ),
    runAutoFetch: ref.watch(
      desktopWindowAppDependenciesProvider.select(
        (DesktopWindowAppDependencies dependencies) =>
            dependencies.runAutoFetch,
      ),
    ),
    resolveAutoSaveDirectory: ref.watch(
      desktopWindowAppDependenciesProvider.select(
        (DesktopWindowAppDependencies dependencies) =>
            dependencies.resolveAutoSaveDirectory,
      ),
    ),
    fileSavePersistenceFactory: ref.watch(
      desktopWindowAppDependenciesProvider.select(
        (DesktopWindowAppDependencies dependencies) =>
            dependencies.fileSavePersistenceFactory,
      ),
    ),
  );
});

final Provider<DesktopMainWindowNavigationPort>
desktopMainWindowNavigationProvider = Provider<DesktopMainWindowNavigationPort>(
  (Ref ref) {
    return DesktopMainWindowNavigationController(
      openAssociationManager: ref.watch(
        desktopWindowAppDependenciesProvider.select(
          (DesktopWindowAppDependencies dependencies) =>
              dependencies.openAssociationManager,
        ),
      ),
      lifecycleRegistry: ref.watch(desktopWindowLifecycleRegistryProvider),
    );
  },
);

/// 桌面歌词 reducer Provider。
final Provider<DesktopSessionReducer> desktopSessionReducerProvider =
    Provider<DesktopSessionReducer>((Ref ref) {
      final DesktopSessionReducerConfig config =
          DesktopSessionReducerConfig.fromAppConfig(
            ref
                .read(desktopWindowAppDependenciesProvider)
                .configRepository
                .current,
          );
      return DesktopSessionReducer(config: config);
    });

/// 桌面主机最小协调层 Provider。
final Provider<DesktopServiceCoordinator>
desktopServiceCoordinatorProvider = Provider<DesktopServiceCoordinator>((
  Ref ref,
) {
  final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
    reducer: ref.watch(desktopSessionReducerProvider),
    sceneStore: ref.watch(desktopSceneStoreProvider),
    floatingEffectExecutor: ref.watch(desktopFloatingEffectExecutorProvider),
    panelEffectExecutor: ref.watch(desktopPanelEffectExecutorProvider),
    selectorEffectExecutor: ref.watch(desktopSelectorEffectExecutorProvider),
    mainWindowNavigationPort: ref.watch(desktopMainWindowNavigationProvider),
    pendingEffectExecutor: ref.watch(desktopPendingEffectExecutorProvider),
    exitGuard: ref.watch(desktopExitGuardProvider),
    lifecycleRegistry: ref.watch(desktopWindowLifecycleRegistryProvider),
  );
  coordinator.bindSelectorIntents();
  coordinator.bindFloatingIntents(
    repository: ref.read(desktopWindowAppDependenciesProvider).configRepository,
  );
  coordinator.installPanelIntentHandlers();
  coordinator.bindPendingEffects();
  coordinator.bindConfigWatch(
    repository: ref.read(desktopWindowAppDependenciesProvider).configRepository,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final Provider<DesktopPanelHostBridgeController>
desktopPanelHostBridgeControllerProvider =
    Provider<DesktopPanelHostBridgeController>((Ref ref) {
      final DesktopPanelHostBridgeController controller =
          DesktopPanelHostBridgeController(
            panelHost: ref.watch(desktopWindowBackendProvider).panelHost,
            coordinator: ref.watch(desktopServiceCoordinatorProvider),
          );
      ref.onDispose(() {
        unawaited(controller.dispose());
      });
      return controller;
    });

/// 真实桌面服务宿主 Provider。
final Provider<DesktopServiceHost> desktopServiceHostProvider =
    Provider<DesktopServiceHost>((Ref ref) {
      final DesktopServiceCoordinator coordinator = ref.watch(
        desktopServiceCoordinatorProvider,
      );
      final DesktopServiceHost host = DesktopServiceHost(
        coordinator: coordinator,
        reducer: ref.watch(desktopSessionReducerProvider),
        bootstrap: ref.watch(desktopServiceBootstrapProvider),
        panelHostBridgeController: ref.watch(
          desktopPanelHostBridgeControllerProvider,
        ),
      );
      coordinator.attachControlCommandSender(host.sendControlCommand);
      ref.onDispose(host.dispose);
      return host;
    });

bool _supportsDesktopAppOwnedWindows() {
  if (kIsWeb) {
    return false;
  }
  return <TargetPlatform>{
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  }.contains(defaultTargetPlatform);
}

bool _supportsWindowsEmbeddedPanel() {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.windows;
}
