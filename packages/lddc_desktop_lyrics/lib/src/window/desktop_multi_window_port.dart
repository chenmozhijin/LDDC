import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import 'desktop_window_launch.dart';

typedef DesktopRemoteWindowMethodHandler =
    Future<Object?> Function(String method, Object? arguments);

/// 判断 `desktop_multi_window` 的目标窗口通道是否尚未完成注册。
///
/// Windows 子 engine 会先创建目标窗口，再由 Dart 入口绑定 method handler，
/// 两者存在很短的初始化竞态。插件版本分别使用 `CHANNEL_UNREGISTERED` 或
/// `NO_HANDLER` 表达这两个启动阶段；只对带有明确“handler 未注册”语义的错误
/// 做有界重试，避免把窗口已销毁、参数错误或业务异常误判为“稍后可恢复”。
bool isDesktopWindowChannelUnregistered(Object error) {
  final String message = error.toString();
  if (!message.contains('WindowChannelException')) {
    return false;
  }
  return message.contains('CHANNEL_UNREGISTERED') ||
      (message.contains('NO_HANDLER') &&
          message.contains('No method call handler registered'));
}

/// 远端窗口控制口。
abstract interface class DesktopRemoteWindowPort {
  String get windowId;

  Object? get arguments;

  Future<void> show();

  Future<void> hide();

  Future<Object?> invokeMethod(String method, [Object? arguments]);

  Future<void> setMethodHandler(DesktopRemoteWindowMethodHandler? handler);

  /// 请求关闭并在原生窗口从 multi-window registry 移除后完成。
  Future<void> requestClose();

  Future<void> setTitle(String title);
}

/// `desktop_multi_window` 公共抽象口，便于宿主和消费者在测试中使用 fake。
abstract interface class DesktopMultiWindowPort {
  Future<DesktopRemoteWindowPort> currentWindow();

  Future<DesktopRemoteWindowPort> fromWindowId(String windowId);

  Future<DesktopRemoteWindowPort> createWindow({
    required DesktopWindowLaunchArguments arguments,
  });
}

/// 默认的 `desktop_multi_window` 适配器。
class DesktopMultiWindowAdapter implements DesktopMultiWindowPort {
  const DesktopMultiWindowAdapter();

  @override
  Future<DesktopRemoteWindowPort> createWindow({
    required DesktopWindowLaunchArguments arguments,
  }) async {
    final WindowController controller = await WindowController.create(
      WindowConfiguration(hiddenAtLaunch: true, arguments: arguments.encode()),
    );
    return _DesktopWindowControllerAdapter(controller);
  }

  @override
  Future<DesktopRemoteWindowPort> currentWindow() async {
    final WindowController controller =
        await WindowController.fromCurrentEngine();
    return _DesktopWindowControllerAdapter(controller);
  }

  @override
  Future<DesktopRemoteWindowPort> fromWindowId(String windowId) async {
    final WindowController controller = WindowController.fromWindowId(windowId);
    return _DesktopWindowControllerAdapter(controller);
  }
}

class _DesktopWindowControllerAdapter implements DesktopRemoteWindowPort {
  const _DesktopWindowControllerAdapter(this._controller);

  final WindowController _controller;

  @override
  Object? get arguments => _controller.arguments;

  @override
  String get windowId => _controller.windowId;

  @override
  Future<void> hide() => _controller.hide();

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) {
    return _controller.invokeMethod(method, arguments);
  }

  @override
  Future<void> setMethodHandler(DesktopRemoteWindowMethodHandler? handler) {
    return _controller.setWindowMethodHandler(
      handler == null
          ? null
          : (MethodCall call) {
              return handler(call.method, call.arguments);
            },
    );
  }

  @override
  Future<void> requestClose() async {
    await _controller.invokeMethod('window_close');
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final List<WindowController> windows = await WindowController.getAll();
      if (!windows.any(
        (WindowController window) => window.windowId == _controller.windowId,
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw TimeoutException(
      '子窗口关闭后仍留在 multi-window registry: ${_controller.windowId}',
    );
  }

  @override
  Future<void> setTitle(String title) =>
      _controller.invokeMethod('window_set_title', title);

  @override
  Future<void> show() => _controller.show();
}
