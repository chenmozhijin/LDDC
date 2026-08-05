import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/logging/logging.dart';
import 'desktop_service_bootstrap.dart';
import 'desktop_exit_guard.dart';
import 'desktop_service_coordinator.dart';
import 'desktop_tray_controller.dart';
import 'desktop_main_window_raise_result.dart';
import 'desktop_main_window_raise_stub.dart'
    if (dart.library.io) 'desktop_main_window_raise_io.dart'
    as main_window_raise;
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import '../window/desktop_window_providers.dart';

final AppLogger _mainWindowLogger = AppLogger.scope('main-window');

/// 主窗口桌面服务绑定页。
///
/// 职责：
/// - 主窗口首次构建后绑定主实例唤起处理；
/// - 在三类桌面平台的后台服务模式下保持主窗口隐藏；
/// - 处理桌面歌词插件或托盘转发过来的 `show` 请求。
class DesktopMainWindowHostPage extends ConsumerStatefulWidget {
  const DesktopMainWindowHostPage({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DesktopMainWindowHostPage> createState() =>
      _DesktopMainWindowHostPageState();
}

class _DesktopMainWindowHostPageState
    extends ConsumerState<DesktopMainWindowHostPage>
    with WindowListener {
  static const DesktopExitGuardWindowRef _mainWindowRef =
      DesktopExitGuardWindowRef.main();

  bool _initialized = false;
  bool _disposed = false;
  bool _forceCloseInFlight = false;
  bool _mainWindowVisible = false;
  late final DesktopExitGuardPort _exitGuard;
  late final DesktopWindowLifecycleRegistry _lifecycleRegistry;
  DesktopWindowRef? _mainWindowLifecycleRef;
  DesktopServiceBootstrap? _bootstrap;
  DesktopServiceCoordinator? _coordinator;
  DesktopTrayController? _trayController;
  DesktopTrayLabels? _trayLabels;
  StreamSubscription<DesktopServiceNotice>? _serviceNoticeSubscription;

  @override
  void initState() {
    super.initState();
    _exitGuard = ref.read(desktopExitGuardProvider);
    _lifecycleRegistry = ref.read(desktopWindowLifecycleRegistryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeDesktopServiceHost());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    if (!kIsWeb) {
      windowManager.removeListener(this);
    }
    _exitGuard
      ..bindMainWindowVisibilityProbe(null)
      ..bindAliveInstanceGetter(null)
      ..registerExitHandler(null)
      ..setMainWindowOwnership(DesktopMainWindowOwnershipState.hidden);
    final DesktopWindowRef? lifecycleRef = _mainWindowLifecycleRef;
    if (lifecycleRef != null) {
      _lifecycleRegistry.markClosed(
        lifecycleRef,
        reason: 'main-window-host-dispose',
      );
    }
    _bootstrap?.detachShowHandler();
    final DesktopTrayController? trayController = _trayController;
    if (trayController != null) {
      unawaited(trayController.dispose());
    }
    unawaited(_serviceNoticeSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final DesktopTrayLabels labels = _buildTrayLabels();
    if (_trayLabels == labels) {
      return;
    }
    _trayLabels = labels;
    final DesktopTrayController? controller = _trayController;
    if (controller != null) {
      unawaited(controller.updateLabels(labels));
    }
  }

  Future<void> _initializeDesktopServiceHost() async {
    if (_initialized || _disposed || kIsWeb) {
      return;
    }
    _initialized = true;
    final DesktopServiceBootstrap bootstrap = ref.read(
      desktopServiceBootstrapProvider,
    );
    _bootstrap = bootstrap;
    if (!bootstrap.isPrimaryInstance) {
      return;
    }
    final coordinator = ref.read(desktopServiceCoordinatorProvider);
    _coordinator = coordinator;
    await windowManager.ensureInitialized();
    if (_disposed || !mounted) {
      return;
    }
    _serviceNoticeSubscription = coordinator.notices.listen(
      _handleServiceNotice,
    );
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    if (_disposed || !mounted) {
      return;
    }
    _bindMainWindowLifecycle();
    _exitGuard.bindAliveInstanceGetter(() => coordinator.sessions.isNotEmpty);
    _exitGuard.registerExitHandler(_forceCloseApplication);
    _exitGuard.bindMainWindowVisibilityProbe(windowManager.isVisible);
    await bootstrap.attachShowHandler(_showMainWindow);
    if (_disposed || !mounted) {
      bootstrap.detachShowHandler();
      return;
    }
    await _initializeTrayController(coordinator);
    if (_disposed || !mounted) {
      return;
    }
    _mainWindowLogger.info(
      'show handler attached, shouldStartHidden=${bootstrap.shouldStartHidden}',
    );
    final bool shouldStartHidden = bootstrap.shouldStartHidden;
    if (shouldStartHidden && defaultTargetPlatform != TargetPlatform.windows) {
      // Windows runner 会在创建原生窗口前识别 `--not-show`，不需要重复隐藏。
      // macOS/Linux runner 没有对应的启动参数入口；如果这里只更新逻辑状态，
      // 原生窗口仍然可见，退出守卫也会拒绝在最后一个歌词实例删除后退出。
      // 在 window_manager 初始化完成后显式隐藏，可让三平台遵循同一后台服务契约。
      await windowManager.hide();
      if (_disposed || !mounted) {
        return;
      }
    }
    _setMainWindowOwnership(
      shouldStartHidden
          ? DesktopMainWindowOwnershipState.hidden
          : DesktopMainWindowOwnershipState.visible,
      reason: 'main-window-initialized',
    );
  }

  Future<void> _initializeTrayController(
    DesktopServiceCoordinator coordinator,
  ) async {
    final DesktopTrayController controller = DesktopTrayController(
      trayPortFactory: ref.read(desktopTrayPortFactoryProvider),
      sessionSnapshots: coordinator.sessionSnapshots,
      runWindowAction: coordinator.runWindowAction,
      exitApplication: _forceCloseApplication,
      iconAsset: _resolveTrayIconAsset(),
      labels: _trayLabels ?? _buildTrayLabels(),
    );
    _trayController = controller;
    await controller.initialize(initialSessions: coordinator.sessions);
    if (_disposed) {
      await controller.dispose();
    }
  }

  Future<void> _showMainWindow() async {
    if (_disposed) {
      return;
    }
    _mainWindowLogger.info('show request received');
    _setMainWindowOwnership(
      DesktopMainWindowOwnershipState.showing,
      reason: 'main-window-showing',
    );
    try {
      final bool minimized = await windowManager.isMinimized();
      if (_disposed) {
        return;
      }
      _mainWindowLogger.info('show request minimized=$minimized');
      if (minimized) {
        _setMainWindowOwnership(
          DesktopMainWindowOwnershipState.restoring,
          reason: 'main-window-restoring',
        );
        await windowManager.restore();
        if (_disposed) {
          return;
        }
        _mainWindowLogger.info('window restored from minimized');
      }
      await windowManager.show();
      if (_disposed) {
        return;
      }
      _setMainWindowOwnership(
        DesktopMainWindowOwnershipState.visible,
        reason: 'main-window-show',
      );
      await windowManager.focus();
      _mainWindowLogger.info('window focused');
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final DesktopMainWindowRaiseResult raiseResult = await main_window_raise
            .raiseDesktopMainWindowToFront();
        final Map<String, Object?> fields = raiseResult.toLogFields();
        if (raiseResult.raised) {
          _mainWindowLogger.info('foreground pulse applied', fields: fields);
        } else {
          _mainWindowLogger.warning(
            'foreground pulse incomplete',
            fields: fields,
          );
        }
      }
      _mainWindowLogger.info('show request handled');
    } on Object catch (error, stackTrace) {
      _mainWindowLogger.error(
        'show request failed error=$error stack=$stackTrace',
      );
      await _correctMainWindowOwnershipAfterShowFailure();
    }
  }

  @override
  Future<void> onWindowClose() async {
    if (_forceCloseInFlight) {
      return;
    }
    final DesktopExitGuardCloseAction action = _exitGuard
        .handleWindowCloseRequest(window: _mainWindowRef);
    _mainWindowLogger.info(
      'onWindowClose resolved action=${action.name}'
      ' forceCloseInFlight=$_forceCloseInFlight',
    );
    if (action == DesktopExitGuardCloseAction.exitApp) {
      await _forceCloseApplication();
      return;
    }
    await windowManager.hide();
    _setMainWindowOwnership(
      DesktopMainWindowOwnershipState.hidden,
      reason: 'main-window-hide',
    );
  }

  Future<void> _forceCloseApplication() async {
    if (_forceCloseInFlight) {
      return;
    }
    final DesktopWindowRef? lifecycleRef = _mainWindowLifecycleRef;
    if (lifecycleRef == null || !_lifecycleRegistry.isMainWindowReachable()) {
      _mainWindowLogger.info(
        'forceCloseApplication skipped reason=main-window-unreachable',
      );
      return;
    }
    _forceCloseInFlight = true;
    _mainWindowLogger.info('forceCloseApplication begin');
    try {
      final bool geometryFlushed =
          await _coordinator?.flushFloatingGeometryForApplicationExit() ?? true;
      if (!geometryFlushed) {
        _mainWindowLogger.warning(
          'forceCloseApplication geometry flush was not fully confirmed',
        );
      }
      _setMainWindowOwnership(
        DesktopMainWindowOwnershipState.closingForExit,
        reason: 'main-window-force-close',
      );
      _lifecycleRegistry.markCommandIssued(
        lifecycleRef,
        observedState: DesktopWindowObservedState.closing,
        desiredState: DesktopWindowDesiredState.absent,
        reason: 'main-window-force-close',
      );
      await windowManager.setPreventClose(false);
      _mainWindowLogger.info(
        'forceCloseApplication setPreventClose(false) done',
      );
      // macOS 需要允许隐藏主窗口长期承载桌面歌词服务，因此 AppDelegate 不再依赖
      // “最后窗口关闭后自动退出”。bootstrap.dispose() 会幂等撤销 endpoint、关闭
      // singleton 控制端并释放锁；完成后再显式销毁应用，避免新客户端连接退出中的服务。
      await _bootstrap?.dispose();
      await windowManager.destroy();
      _lifecycleRegistry.markClosed(
        lifecycleRef,
        reason: 'main-window-destroy-returned',
      );
      _mainWindowLogger.info(
        'forceCloseApplication windowManager.destroy() returned',
      );
    } finally {
      _forceCloseInFlight = false;
      _mainWindowLogger.info('forceCloseApplication end');
    }
  }

  String _resolveTrayIconAsset() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return 'assets/tray_icon.ico';
    }
    return 'assets/tray_icon.png';
  }

  DesktopTrayLabels _buildTrayLabels() {
    final l10n = context.l10n;
    return (
      showMainWindow: l10n.desktopWindowActionShowMainWindow,
      currentTarget: l10n.desktopTrayCurrentTarget,
      noSelection: l10n.desktopTrayNoSelection,
      targetInstance: l10n.desktopTrayTargetInstance,
      instance: l10n.desktopTrayInstance,
      selectLyrics: l10n.desktopWindowActionSelectLyrics,
      markInstrumental: l10n.desktopWindowActionMarkInstrumental,
      disableAutoSearch: l10n.desktopWindowActionDisableAutoSearch,
      unlinkLyrics: l10n.desktopWindowActionUnlinkLyrics,
      clickThrough: l10n.desktopWindowActionClickThrough,
      toggleFloating: l10n.desktopWindowActionToggleFloating,
      associationManager: l10n.desktopWindowActionAssociationManager,
      exit: l10n.desktopTrayExit,
    );
  }

  void _bindMainWindowLifecycle() {
    final DesktopWindowRef lifecycleRef = _lifecycleRegistry.ensureMainWindow();
    _mainWindowLifecycleRef = lifecycleRef;
    unawaited(_attachMainWindowId(lifecycleRef));
  }

  void _setMainWindowOwnership(
    DesktopMainWindowOwnershipState state, {
    required String reason,
  }) {
    if (_disposed) {
      return;
    }
    _mainWindowVisible = switch (state) {
      DesktopMainWindowOwnershipState.showing ||
      DesktopMainWindowOwnershipState.visible ||
      DesktopMainWindowOwnershipState.maximized ||
      DesktopMainWindowOwnershipState.restoring => true,
      DesktopMainWindowOwnershipState.minimized ||
      DesktopMainWindowOwnershipState.hidden ||
      DesktopMainWindowOwnershipState.closingForExit => false,
    };
    _exitGuard.setMainWindowOwnership(state);
    final DesktopWindowRef? lifecycleRef = _mainWindowLifecycleRef;
    if (lifecycleRef == null) {
      return;
    }
    _lifecycleRegistry.upsertObserved(
      lifecycleRef,
      state.holdsApplication
          ? DesktopWindowObservedState.visible
          : state == DesktopMainWindowOwnershipState.closingForExit
          ? DesktopWindowObservedState.closing
          : DesktopWindowObservedState.ready,
      reason: reason,
    );
  }

  Future<void> _correctMainWindowOwnershipAfterShowFailure() async {
    try {
      final bool visible = await windowManager.isVisible();
      _setMainWindowOwnership(
        visible
            ? DesktopMainWindowOwnershipState.visible
            : DesktopMainWindowOwnershipState.hidden,
        reason: 'main-window-show-failure-probe',
      );
    } on Object {
      // 无法确认系统状态时继续保留 showing 所有权，避免误退应用。
    }
  }

  @override
  void onWindowFocus() {
    _setMainWindowOwnership(
      DesktopMainWindowOwnershipState.visible,
      reason: 'main-window-focus',
    );
  }

  @override
  void onWindowMinimize() {
    _setMainWindowOwnership(
      DesktopMainWindowOwnershipState.minimized,
      reason: 'main-window-minimized',
    );
  }

  @override
  void onWindowMaximize() {
    _setMainWindowOwnership(
      DesktopMainWindowOwnershipState.maximized,
      reason: 'main-window-maximized',
    );
  }

  @override
  void onWindowRestore() {
    _setMainWindowOwnership(
      DesktopMainWindowOwnershipState.visible,
      reason: 'main-window-restored',
    );
  }

  void _handleServiceNotice(DesktopServiceNotice notice) {
    if (!mounted || !_mainWindowVisible) {
      return;
    }
    final String message = switch (notice) {
      DesktopClientDisconnectedNotice() =>
        context.l10n.desktopWindowClientDisconnected,
    };
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  Future<void> _attachMainWindowId(DesktopWindowRef lifecycleRef) async {
    try {
      final DesktopRemoteWindowPort currentWindow = await ref
          .read(desktopMultiWindowPortProvider)
          .currentWindow();
      if (_disposed) {
        return;
      }
      _lifecycleRegistry.attachWindowId(
        lifecycleRef,
        currentWindow.windowId,
        reason: 'main-window-bound',
      );
    } on Object catch (error, stackTrace) {
      _mainWindowLogger.info(
        'bind main lifecycle failed error=$error stack=$stackTrace',
      );
    }
  }
}
