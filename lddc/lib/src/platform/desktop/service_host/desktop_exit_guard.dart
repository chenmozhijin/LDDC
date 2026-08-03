import 'dart:async';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

/// 退出守卫登记的窗口角色。
enum DesktopExitGuardWindowRole { main, floating, selector, panel }

/// 退出守卫使用的窗口标识。
final class DesktopExitGuardWindowRef {
  const DesktopExitGuardWindowRef({
    required this.role,
    this.instanceId,
    this.panelId,
  });

  const DesktopExitGuardWindowRef.main()
    : role = DesktopExitGuardWindowRole.main,
      instanceId = null,
      panelId = null;

  final DesktopExitGuardWindowRole role;
  final int? instanceId;
  final int? panelId;

  String get key => switch (role) {
    DesktopExitGuardWindowRole.main => 'main',
    DesktopExitGuardWindowRole.floating => 'floating/${instanceId ?? '-'}',
    DesktopExitGuardWindowRole.selector => 'selector/${instanceId ?? '-'}',
    DesktopExitGuardWindowRole.panel =>
      'panel/${instanceId ?? '-'}/${panelId ?? '-'}',
  };
}

/// 窗口关闭请求的处理结果。
enum DesktopExitGuardCloseAction { hideWindow, exitApp }

/// 主窗口对应用生命周期的所有权状态。
enum DesktopMainWindowOwnershipState {
  showing,
  visible,
  minimized,
  maximized,
  restoring,
  hidden,
  closingForExit;

  bool get holdsApplication => switch (this) {
    showing || visible || minimized || maximized || restoring => true,
    hidden || closingForExit => false,
  };
}

/// 桌面退出守卫抽象。
abstract interface class DesktopExitGuardPort {
  bool get hasAliveInstances;

  bool hasAnyVisibleWindow({DesktopExitGuardWindowRef? excludeWindow});

  void bindAliveInstanceGetter(bool Function()? getter);

  void registerExitHandler(Future<void> Function()? handler);

  void bindMainWindowVisibilityProbe(Future<bool> Function()? probe);

  void setMainWindowOwnership(DesktopMainWindowOwnershipState state);

  DesktopExitGuardCloseAction handleWindowCloseRequest({
    required DesktopExitGuardWindowRef window,
  });

  Future<void> handleWindowClosed({required DesktopExitGuardWindowRef window});

  Future<void> handleInstanceLifecycleChanged();
}

/// 无副作用退出守卫。
final class DesktopNoopExitGuard implements DesktopExitGuardPort {
  const DesktopNoopExitGuard();

  @override
  bool get hasAliveInstances => false;

  @override
  bool hasAnyVisibleWindow({DesktopExitGuardWindowRef? excludeWindow}) => false;

  @override
  void bindAliveInstanceGetter(bool Function()? getter) {}

  @override
  DesktopExitGuardCloseAction handleWindowCloseRequest({
    required DesktopExitGuardWindowRef window,
  }) {
    return DesktopExitGuardCloseAction.hideWindow;
  }

  @override
  Future<void> handleInstanceLifecycleChanged() async {}

  @override
  Future<void> handleWindowClosed({
    required DesktopExitGuardWindowRef window,
  }) async {}

  @override
  void registerExitHandler(Future<void> Function()? handler) {}

  @override
  void bindMainWindowVisibilityProbe(Future<bool> Function()? probe) {}

  @override
  void setMainWindowOwnership(DesktopMainWindowOwnershipState state) {}
}

/// Python版 `ExitManager` 等价的桌面退出守卫。
final class DesktopExitGuardController implements DesktopExitGuardPort {
  DesktopExitGuardController({
    DesktopWindowLifecycleRegistry? lifecycleRegistry,
  }) : _lifecycleRegistry =
           lifecycleRegistry ??
           DesktopWindowLifecycleRegistryController.instance;

  bool Function()? _aliveInstanceGetter;
  Future<void> Function()? _exitHandler;
  final DesktopWindowLifecycleRegistry _lifecycleRegistry;
  bool _exitInFlight = false;
  Future<bool> Function()? _mainWindowVisibilityProbe;
  DesktopMainWindowOwnershipState _mainWindowOwnership =
      DesktopMainWindowOwnershipState.hidden;

  @override
  bool get hasAliveInstances => _aliveInstanceGetter?.call() ?? false;

  @override
  bool hasAnyVisibleWindow({DesktopExitGuardWindowRef? excludeWindow}) {
    final DesktopWindowRef? excludedRef = excludeWindow == null
        ? null
        : _lookupWindowRef(excludeWindow);
    return _lifecycleRegistry.hasVisibleWindow(excludeRef: excludedRef);
  }

  @override
  void bindAliveInstanceGetter(bool Function()? getter) {
    _aliveInstanceGetter = getter;
  }

  @override
  void registerExitHandler(Future<void> Function()? handler) {
    _exitHandler = handler;
  }

  @override
  void bindMainWindowVisibilityProbe(Future<bool> Function()? probe) {
    _mainWindowVisibilityProbe = probe;
  }

  @override
  void setMainWindowOwnership(DesktopMainWindowOwnershipState state) {
    _mainWindowOwnership = state;
    final DesktopWindowRef ref = _ensureWindowRef(
      const DesktopExitGuardWindowRef.main(),
    );
    final bool holdsApplication = state.holdsApplication;
    _lifecycleRegistry.setDesired(
      ref,
      state == DesktopMainWindowOwnershipState.closingForExit
          ? DesktopWindowDesiredState.absent
          : holdsApplication
          ? DesktopWindowDesiredState.visible
          : DesktopWindowDesiredState.hidden,
      reason: 'exit-guard-main-${state.name}',
    );
    _lifecycleRegistry.upsertObserved(
      ref,
      state == DesktopMainWindowOwnershipState.closingForExit
          ? DesktopWindowObservedState.closing
          : holdsApplication
          ? DesktopWindowObservedState.visible
          : DesktopWindowObservedState.ready,
      reason: 'exit-guard-main-${state.name}',
    );
  }

  @override
  DesktopExitGuardCloseAction handleWindowCloseRequest({
    required DesktopExitGuardWindowRef window,
  }) {
    return _shouldExit(excludeWindow: window)
        ? DesktopExitGuardCloseAction.exitApp
        : DesktopExitGuardCloseAction.hideWindow;
  }

  @override
  Future<void> handleWindowClosed({
    required DesktopExitGuardWindowRef window,
  }) async {
    final DesktopWindowRef ref = _ensureWindowRef(window);
    _lifecycleRegistry.markClosed(ref, reason: 'exit-guard-window-closed');
    await _maybeExit();
  }

  @override
  Future<void> handleInstanceLifecycleChanged() async {
    await _maybeExit();
  }

  bool _shouldExit({DesktopExitGuardWindowRef? excludeWindow}) {
    return !hasAliveInstances &&
        !hasAnyVisibleWindow(excludeWindow: excludeWindow);
  }

  Future<void> _maybeExit() async {
    if (_exitInFlight || _mainWindowOwnership.holdsApplication) {
      return;
    }
    // 可见性 probe 与退出 handler 都可能让出事件循环，因此从检查开始就占用
    // 同一 in-flight 标记，避免两个生命周期事件同时通过前置条件并重复退出。
    _exitInFlight = true;
    try {
      if (_mainWindowOwnership == DesktopMainWindowOwnershipState.hidden) {
        final Future<bool> Function()? probe = _mainWindowVisibilityProbe;
        if (probe != null) {
          try {
            if (await probe()) {
              setMainWindowOwnership(DesktopMainWindowOwnershipState.visible);
              return;
            }
          } on Object {
            // probe 失败时保留显式 ownership；只有明确 hidden 才继续既有退出判断。
          }
        }
      }
      if (!_shouldExit()) {
        return;
      }
      final Future<void> Function()? exitHandler = _exitHandler;
      if (exitHandler == null) {
        return;
      }
      await exitHandler();
    } finally {
      _exitInFlight = false;
    }
  }

  DesktopWindowRef _ensureWindowRef(DesktopExitGuardWindowRef window) {
    if (window.role == DesktopExitGuardWindowRole.main) {
      return _lifecycleRegistry.ensureMainWindow();
    }
    return _lookupWindowRef(window) ??
        _lifecycleRegistry.registerWindow(
          role: _mapRole(window.role),
          instanceId: window.instanceId,
          panelId: window.panelId,
          observedState: DesktopWindowObservedState.creating,
          desiredState: DesktopWindowDesiredState.hidden,
        );
  }

  DesktopWindowRef? _lookupWindowRef(DesktopExitGuardWindowRef window) {
    if (window.role == DesktopExitGuardWindowRole.main) {
      return _lifecycleRegistry.currentRef(role: DesktopWindowRole.main);
    }
    return _lifecycleRegistry.currentRef(
      role: _mapRole(window.role),
      instanceId: window.instanceId,
      panelId: window.panelId,
    );
  }

  DesktopWindowRole _mapRole(DesktopExitGuardWindowRole role) {
    return switch (role) {
      DesktopExitGuardWindowRole.main => DesktopWindowRole.main,
      DesktopExitGuardWindowRole.floating => DesktopWindowRole.floating,
      DesktopExitGuardWindowRole.selector => DesktopWindowRole.selector,
      DesktopExitGuardWindowRole.panel => DesktopWindowRole.panel,
    };
  }
}
