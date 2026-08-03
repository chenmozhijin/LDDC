import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/logging/logging.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'desktop_main_window_raise_result.dart';
import 'desktop_main_window_raise_stub.dart'
    if (dart.library.io) 'desktop_main_window_raise_io.dart'
    as main_window_raise;

final AppLogger _mainWindowNavigationLogger = AppLogger.scope(
  'main-window-navigation',
);

abstract interface class DesktopMainWindowNavigationPort {
  Future<bool> showMainWindow();

  Future<bool> openAssociationManager();
}

class DesktopNoopMainWindowNavigationPort
    implements DesktopMainWindowNavigationPort {
  const DesktopNoopMainWindowNavigationPort();

  @override
  Future<bool> openAssociationManager() async => false;

  @override
  Future<bool> showMainWindow() async => false;
}

class DesktopMainWindowNavigationController
    implements DesktopMainWindowNavigationPort {
  DesktopMainWindowNavigationController({
    required Future<void> Function() openAssociationManager,
    DesktopWindowLifecycleRegistry? lifecycleRegistry,
  }) : _openAssociationManager = openAssociationManager,
       _lifecycleRegistry =
           lifecycleRegistry ??
           DesktopWindowLifecycleRegistryController.instance;

  final Future<void> Function() _openAssociationManager;
  final DesktopWindowLifecycleRegistry _lifecycleRegistry;

  @override
  Future<bool> showMainWindow() {
    return _raiseMainWindow(reason: 'show-main-window');
  }

  @override
  Future<bool> openAssociationManager() async {
    try {
      await _openAssociationManager();
    } on Object catch (error, stackTrace) {
      // 路由回调可能包含异步页面装配；失败时必须留在动作返回值边界内，
      // 否则托盘或子窗口发起的未等待调用会形成未捕获异步异常。
      _mainWindowNavigationLogger.error(
        'open association manager failed error=$error stack=$stackTrace',
      );
      return false;
    }
    return _raiseMainWindow(reason: 'open-association-manager');
  }

  Future<bool> _raiseMainWindow({required String reason}) async {
    _mainWindowNavigationLogger.info('raise main window begin reason=$reason');
    if (!_lifecycleRegistry.isMainWindowReachable()) {
      _mainWindowNavigationLogger.warning(
        'raise main window skipped reason=$reason mainWindowReachable=false',
      );
      return false;
    }
    try {
      await windowManager.ensureInitialized();
      _mainWindowNavigationLogger.info(
        'window manager initialized reason=$reason',
      );
      final bool minimized = await windowManager.isMinimized();
      _mainWindowNavigationLogger.info(
        'main window minimized=$minimized reason=$reason',
      );
      if (minimized) {
        await windowManager.restore();
        _mainWindowNavigationLogger.info('main window restored reason=$reason');
      }
      await windowManager.show();
      _mainWindowNavigationLogger.info('main window shown reason=$reason');
      await windowManager.focus();
      _mainWindowNavigationLogger.info('main window focused reason=$reason');
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final DesktopMainWindowRaiseResult raiseResult = await main_window_raise
            .raiseDesktopMainWindowToFront();
        final Map<String, Object?> fields = <String, Object?>{
          'reason': reason,
          ...raiseResult.toLogFields(),
        };
        if (raiseResult.raised) {
          _mainWindowNavigationLogger.info(
            'main window foreground raise completed',
            fields: fields,
          );
        } else {
          _mainWindowNavigationLogger.warning(
            'main window foreground raise incomplete',
            fields: fields,
          );
        }
      }
      _mainWindowNavigationLogger.info('raise main window end reason=$reason');
      return true;
    } on Object catch (error, stackTrace) {
      _mainWindowNavigationLogger.error(
        'raise main window failed reason=$reason error=$error stack=$stackTrace',
      );
      return false;
    }
  }
}
