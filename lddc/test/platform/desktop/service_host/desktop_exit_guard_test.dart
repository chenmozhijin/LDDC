import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_exit_guard.dart';

void main() {
  group('DesktopExitGuardController', () {
    test('有存活实例时关闭主窗口只返回隐藏动作', () {
      final DesktopExitGuardController guard = DesktopExitGuardController();
      guard.bindAliveInstanceGetter(() => true);

      final DesktopExitGuardCloseAction action = guard.handleWindowCloseRequest(
        window: const DesktopExitGuardWindowRef.main(),
      );

      expect(action, DesktopExitGuardCloseAction.hideWindow);
    });

    test('无实例且无可见独立窗口时关闭主窗口会请求退出', () {
      final DesktopExitGuardController guard = DesktopExitGuardController();
      guard.bindAliveInstanceGetter(() => false);

      final DesktopExitGuardCloseAction action = guard.handleWindowCloseRequest(
        window: const DesktopExitGuardWindowRef.main(),
      );

      expect(action, DesktopExitGuardCloseAction.exitApp);
    });

    test('实例退出后若已无实例且无独立窗口会触发退出', () async {
      final DesktopExitGuardController guard = DesktopExitGuardController();
      int exitCalls = 0;
      guard.bindAliveInstanceGetter(() => false);
      guard.registerExitHandler(() async {
        exitCalls += 1;
      });

      await guard.handleInstanceLifecycleChanged();

      expect(exitCalls, 1);
    });

    test('实例退出后若主窗口仍显示则不会退出', () async {
      final DesktopExitGuardController guard = DesktopExitGuardController();
      int exitCalls = 0;
      guard.bindAliveInstanceGetter(() => false);
      guard.registerExitHandler(() async {
        exitCalls += 1;
      });
      guard.setMainWindowOwnership(DesktopMainWindowOwnershipState.visible);

      await guard.handleInstanceLifecycleChanged();

      expect(exitCalls, 0);
    });

    test('实例退出后主窗口最小化仍持有应用', () async {
      final DesktopExitGuardController guard = DesktopExitGuardController();
      int exitCalls = 0;
      guard.bindAliveInstanceGetter(() => false);
      guard.registerExitHandler(() async {
        exitCalls += 1;
      });
      guard.setMainWindowOwnership(DesktopMainWindowOwnershipState.minimized);

      await guard.handleInstanceLifecycleChanged();

      expect(exitCalls, 0);
    });

    test('实例退出后主窗口正在显示或恢复时仍持有应用', () async {
      for (final DesktopMainWindowOwnershipState state
          in <DesktopMainWindowOwnershipState>[
            DesktopMainWindowOwnershipState.showing,
            DesktopMainWindowOwnershipState.restoring,
            DesktopMainWindowOwnershipState.maximized,
          ]) {
        final DesktopExitGuardController guard = DesktopExitGuardController();
        int exitCalls = 0;
        guard.bindAliveInstanceGetter(() => false);
        guard.registerExitHandler(() async {
          exitCalls += 1;
        });
        guard.setMainWindowOwnership(state);

        await guard.handleInstanceLifecycleChanged();

        expect(exitCalls, 0, reason: state.name);
      }
    });

    test('显式 hidden 但系统仍可见时 probe 会阻止退出', () async {
      final DesktopExitGuardController guard = DesktopExitGuardController();
      int exitCalls = 0;
      guard.bindAliveInstanceGetter(() => false);
      guard.registerExitHandler(() async {
        exitCalls += 1;
      });
      guard.bindMainWindowVisibilityProbe(() async => true);
      guard.setMainWindowOwnership(DesktopMainWindowOwnershipState.hidden);

      await guard.handleInstanceLifecycleChanged();

      expect(exitCalls, 0);
    });

    test('并发生命周期复检只会执行一次退出 handler', () async {
      final DesktopExitGuardController guard = DesktopExitGuardController();
      final Completer<bool> visibilityProbe = Completer<bool>();
      int exitCalls = 0;
      guard.bindAliveInstanceGetter(() => false);
      guard.registerExitHandler(() async {
        exitCalls += 1;
      });
      guard.bindMainWindowVisibilityProbe(() => visibilityProbe.future);
      guard.setMainWindowOwnership(DesktopMainWindowOwnershipState.hidden);

      final Future<void> first = guard.handleInstanceLifecycleChanged();
      final Future<void> second = guard.handleInstanceLifecycleChanged();
      visibilityProbe.complete(false);
      await Future.wait(<Future<void>>[first, second]);

      expect(exitCalls, 1);
    });

    test('允许解除实例 getter 与退出 handler 引用', () async {
      final DesktopExitGuardController guard = DesktopExitGuardController();
      int exitCalls = 0;
      guard.bindAliveInstanceGetter(() => true);
      guard.registerExitHandler(() async {
        exitCalls += 1;
      });

      guard.bindAliveInstanceGetter(null);
      guard.registerExitHandler(null);
      await guard.handleInstanceLifecycleChanged();

      expect(guard.hasAliveInstances, isFalse);
      expect(exitCalls, 0);
    });
  });
}
