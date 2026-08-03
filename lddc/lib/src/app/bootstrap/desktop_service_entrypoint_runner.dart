import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import '../../app/bootstrap/app_bootstrap.dart';
import '../../app/bootstrap/app_providers.dart';
import '../../app/desktop/desktop_app.dart';
import '../../app/shell/app_shell_providers.dart';
import '../../app/shell/app_shell_route.dart';
import '../../core/logging/logging.dart';
import '../../core/resource/async_disposal_tracker.dart';
import '../../core/storage/app_storage_paths_port.dart';
import '../../infra/storage/file_lyrics_save_persistence.dart';
import '../../platform/desktop/service_host/desktop_service_bootstrap.dart';
import '../../platform/desktop/service_host/desktop_service_launch_arguments.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import '../../platform/desktop/window/desktop_window_providers.dart';
import 'owned_provider_container_scope.dart';

enum DesktopServiceStartupMode { mainWindow, hiddenService, servicePortCli }

class DesktopServiceEntrypointRunner {
  DesktopServiceEntrypointRunner({AppLogger? logger})
    : _logger = logger ?? AppLogger.scope('desktop-service-entrypoint');

  final AppLogger _logger;

  Future<void> runMainWindow({
    required List<String> args,
    required DesktopServiceLaunchArguments serviceLaunch,
  }) async {
    _logger.info(
      'args received',
      fields: <String, Object?>{'args': args.join(' ')},
    );

    final DesktopWindowLaunchArguments launch = await DesktopSubWindowRuntime
        .instance
        .ensureInitialized(
          logger: _logger.toDesktopLyricsLogger(),
          drainHostResources: () async {
            // 子窗口根组件卸载后，等待 Provider/数据库任务和日志文件句柄全部
            // 释放，再允许 native 销毁 engine，避免晚到回调访问失效 messenger。
            await AsyncDisposalTracker.drain();
            await AppLogRuntime.dispose();
          },
        );
    await AppLogRuntime.initialize(
      role: launch.role.name,
      instanceId: launch.instanceId,
      panelId: launch.panelId,
    );
    _logger.info(
      'window launch ready',
      fields: <String, Object?>{
        'role': launch.role.name,
        'instance': launch.instanceId,
        'panel': launch.panelId,
      },
    );
    _rejectUnsupportedPanelMainEntrypoint(launch);

    final DesktopServiceBootstrap serviceBootstrap = DesktopServiceBootstrap();
    final bool shouldRunApp = await _prepareAndFinalize(
      serviceBootstrap: serviceBootstrap,
      windowLaunch: launch,
      launchArguments: serviceLaunch,
    );
    if (!shouldRunApp) {
      await AppLogRuntime.flush();
      return;
    }

    if (_shouldUseLightweightSubWindowApp(launch.role)) {
      await AppBootstrap.ensureInitialized();
      AppLogRuntime.updateLevel(AppBootstrap.config.app.logLevel);
      _logger.info('launch lightweight sub window app');
      runApp(
        ProviderScope(
          child: LddcLightweightDesktopSubWindowApp(
            windowLaunch: launch,
            config: AppBootstrap.config,
          ),
        ),
      );
      return;
    }

    if (launch.role == DesktopWindowRole.selector) {
      // 选择器需要搜索相关 provider，但它仍是可销毁的子 engine。使用受控
      // ProviderScope 让 Riverpod 在 widget 树卸载时先释放订阅、客户端和
      // native 资源；UncontrolledProviderScope 不拥有外部 container，会把
      // 清理拖到 isolate teardown，Windows 多 engine 下会触发悬空回调。
      // selector 与浮窗一样是独立 engine，必须在创建 provider 树前加载宿主配置
      // 和 core storage ports。测试 fake 会直接注入配置，无法覆盖真实子 engine
      // 未初始化时的默认配置/路径问题；缺少这一步会表现为自动搜索和手动搜索
      // 都没有有效来源或请求链。
      await AppBootstrap.ensureInitialized();
      try {
        await DesktopSubWindowRuntime.instance.bindSelectorConfigRefreshHandler(
          (int _) async {
            await AppBootstrap.configRepository.refreshFromStorage();
          },
        );
      } on Object catch (error, stackTrace) {
        // 启动竞态中的刷新失败不能丢弃已经加载成功的旧配置；runtime 会保留
        // 未应用版本，后续配置通知或再次显示窗口时继续重试。
        _logger.warning(
          'selector config refresh deferred',
          fields: <String, Object?>{
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        );
      }
      AppLogRuntime.updateLevel(
        AppBootstrap.configRepository.current.app.logLevel,
      );
      _logger.info('launch owned selector sub window app');
      runApp(
        ProviderScope(
          overrides: _desktopProviderOverrides(serviceBootstrap),
          child: LddcDesktopApp(windowLaunch: launch),
        ),
      );
      return;
    }

    final ProviderContainer container = _createDesktopProviderContainer(
      serviceBootstrap,
    );
    await _runAppWithOwnedContainer(
      container: container,
      prepare: () async {
        _logger.info(
          'check service host bootstrap',
          fields: <String, Object?>{
            'role': launch.role.name,
            'isPrimary': serviceBootstrap.isPrimaryInstance,
          },
        );
        if (launch.role == DesktopWindowRole.main &&
            serviceBootstrap.isPrimaryInstance) {
          _logger.info('start desktop service host');
          await container.read(desktopServiceHostProvider).ensureStarted();
          _logger.info('desktop service host started');
          return;
        }
        _logger.info(
          'skip desktop service host bootstrap',
          fields: <String, Object?>{
            'role': launch.role.name,
            'isPrimary': serviceBootstrap.isPrimaryInstance,
          },
        );
      },
      child: LddcDesktopApp(windowLaunch: launch),
    );
  }

  Future<void> runHiddenService({
    required List<String> args,
    required DesktopServiceLaunchArguments serviceLaunch,
  }) async {
    // fb2k 冷启动依赖本入口快速发布端口。这里先启动 TCP host，
    // 再加载完整配置，避免慢磁盘或平台目录解析挡住插件连接。
    const DesktopWindowLaunchArguments launch =
        DesktopWindowLaunchArguments.main();
    await AppLogRuntime.initialize(role: launch.role.name);
    _logger.info(
      'args received',
      fields: <String, Object?>{'args': args.join(' ')},
    );

    final DesktopServiceBootstrap serviceBootstrap = DesktopServiceBootstrap();
    final bool shouldRunApp = await _prepareAndFinalize(
      serviceBootstrap: serviceBootstrap,
      windowLaunch: launch,
      launchArguments: serviceLaunch,
    );
    if (!shouldRunApp) {
      await AppLogRuntime.flush();
      return;
    }

    final ProviderContainer container = _createDesktopProviderContainer(
      serviceBootstrap,
    );
    await _runAppWithOwnedContainer(
      container: container,
      prepare: () async {
        _logger.info('start hidden desktop service host');
        await container.read(desktopServiceHostProvider).ensureStarted();
        _logger.info('hidden desktop service host started');

        await AppBootstrap.ensureInitialized();
        AppLogRuntime.updateLevel(AppBootstrap.config.app.logLevel);
        _logger.info('AppBootstrap.ensureInitialized completed');
      },
      child: const LddcDesktopApp(windowLaunch: launch),
    );
  }

  Future<void> _runAppWithOwnedContainer({
    required ProviderContainer container,
    required Future<void> Function() prepare,
    required Widget child,
  }) async {
    try {
      await prepare();
      runApp(OwnedProviderContainerScope(container: container, child: child));
    } catch (_) {
      // Widget 树尚未接管容器时发生启动异常，必须在重新抛出前同步释放。
      container.dispose();
      rethrow;
    }
  }

  Future<bool> runServicePortCli({
    required List<String> args,
    required DesktopServiceLaunchArguments serviceLaunch,
    required DesktopServiceBootstrap serviceBootstrap,
  }) async {
    // `--get-service-port` 的 stdout 是插件协议输入，不能在这里初始化完整 UI。
    const DesktopWindowLaunchArguments launch =
        DesktopWindowLaunchArguments.main();
    await AppLogRuntime.initialize(role: launch.role.name);
    _logger.info(
      'args received',
      fields: <String, Object?>{'args': args.join(' ')},
    );
    _logger.info('run lightweight service port cli entrypoint');
    final DesktopServiceEntrypointResult bootstrapResult =
        await serviceBootstrap.prepareEntrypoint(
          windowLaunch: launch,
          launchArguments: serviceLaunch,
        );
    _logger.info(
      'prepareEntrypoint completed',
      fields: <String, Object?>{
        'shouldRunApp': bootstrapResult.shouldRunApp,
        'isPrimary': serviceBootstrap.isPrimaryInstance,
        'shouldStartHidden': serviceBootstrap.shouldStartHidden,
      },
    );
    await AppLogRuntime.flush();
    return serviceBootstrap.finalizeEntrypoint(bootstrapResult);
  }

  Future<bool> exitOnArgumentError(DesktopServiceLaunchArguments launch) async {
    final String? parseError = launch.parseError;
    if (parseError == null) {
      return false;
    }
    // CLI 参数错误必须显式失败，避免拼写错误被当作普通启动参数吞掉。
    final DesktopServiceEntrypointResult result =
        DesktopServiceEntrypointResult.exit(
          exitCode: 2,
          stderrLine: parseError,
        );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap();
    await bootstrap.finalizeEntrypoint(result);
    await AppLogRuntime.flush();
    return true;
  }

  Future<bool> _prepareAndFinalize({
    required DesktopServiceBootstrap serviceBootstrap,
    required DesktopWindowLaunchArguments windowLaunch,
    required DesktopServiceLaunchArguments launchArguments,
  }) async {
    final DesktopServiceEntrypointResult bootstrapResult =
        await serviceBootstrap.prepareEntrypoint(
          windowLaunch: windowLaunch,
          launchArguments: launchArguments,
        );
    _logger.info(
      'prepareEntrypoint completed',
      fields: <String, Object?>{
        'shouldRunApp': bootstrapResult.shouldRunApp,
        'isPrimary': serviceBootstrap.isPrimaryInstance,
        'shouldStartHidden': serviceBootstrap.shouldStartHidden,
      },
    );

    final bool shouldRunApp = await serviceBootstrap.finalizeEntrypoint(
      bootstrapResult,
    );
    _logger.info(
      'finalizeEntrypoint completed',
      fields: <String, Object?>{'shouldRunApp': shouldRunApp},
    );
    return shouldRunApp;
  }
}

bool _shouldUseLightweightSubWindowApp(DesktopWindowRole role) {
  return switch (role) {
    DesktopWindowRole.floating => true,
    DesktopWindowRole.main ||
    DesktopWindowRole.panel ||
    DesktopWindowRole.selector => false,
  };
}

ProviderContainer _createDesktopProviderContainer(
  DesktopServiceBootstrap serviceBootstrap,
) {
  return ProviderContainer(
    overrides: _desktopProviderOverrides(serviceBootstrap),
  );
}

List<Override> _desktopProviderOverrides(
  DesktopServiceBootstrap serviceBootstrap,
) {
  return <Override>[
    desktopServiceBootstrapProvider.overrideWithValue(serviceBootstrap),
    desktopWindowAppDependenciesProvider.overrideWith(
      _buildDesktopWindowAppDependencies,
    ),
  ];
}

DesktopWindowAppDependencies _buildDesktopWindowAppDependencies(Ref ref) {
  return DesktopWindowAppDependencies(
    configRepository: ref.watch(configRepositoryProvider),
    libraryLinkRepository: ref.watch(libraryLinkRepositoryProvider),
    loadLinkedLyrics: (String lyricsPath) {
      return ref.read(lyricsApiProvider).getLyrics(path: lyricsPath);
    },
    runAutoFetch: ref.read(autoFetchUseCaseProvider).execute,
    resolveAutoSaveDirectory: () async {
      // 自动保存目录属于宿主组合根的路径策略；platform executor 只接收回调，
      // 不再自行读取全局路径注册表或创建 infra 实现。
      final Directory dataDirectory = await AppStoragePathsRegistry.current
          .resolveDataDirectory();
      return Directory(
        '${dataDirectory.path}${Platform.pathSeparator}auto_save',
      );
    },
    fileSavePersistenceFactory: (String folder) {
      return FileLyricsSavePersistence(folder: folder);
    },
    openAssociationManager: () async {
      ref.read(appShellRouteListenableProvider).value =
          AppShellRoute.associationManager;
    },
  );
}

void _rejectUnsupportedPanelMainEntrypoint(
  DesktopWindowLaunchArguments launch,
) {
  if (launch.role != DesktopWindowRole.panel) {
    return;
  }
  AppLogger.scope('desktop-service-entrypoint').info(
    'unsupported panel main entrypoint rejected',
    fields: <String, Object?>{
      'role': launch.role.name,
      'instance': launch.instanceId,
      'panel': launch.panelId,
      'hostWindowId': launch.hostWindowId,
      'generation': launch.generation,
    },
  );
  throw StateError(
    'panel 不再允许通过 desktop_multi_window 子窗口入口启动；'
    '请改用 panel_embedded_main / embedded panel child-engine 链路。',
  );
}
