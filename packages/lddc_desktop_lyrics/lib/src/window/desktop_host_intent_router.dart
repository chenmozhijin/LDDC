import 'desktop_multi_window_port.dart';

typedef DesktopHostIntentHandler = Future<Object?> Function(Object? arguments);

/// 主窗口 method handler 复用路由。
///
/// `desktop_multi_window` 的当前 engine 只允许注册一个 handler，因此主窗口
/// 必须按 method 统一分派。每个 method 只允许一个处理器，确保调用方拿到的
/// 返回值来自真正执行业务动作的唯一链路。
class DesktopMultiWindowHostIntentRouter {
  DesktopMultiWindowHostIntentRouter({DesktopMultiWindowPort? multiWindowPort})
    : _multiWindowPort = multiWindowPort ?? const DesktopMultiWindowAdapter();

  final DesktopMultiWindowPort _multiWindowPort;
  final Map<String, DesktopHostIntentHandler> _handlers =
      <String, DesktopHostIntentHandler>{};
  DesktopRemoteWindowPort? _boundWindow;
  bool _bound = false;

  void registerHandler(String method, DesktopHostIntentHandler handler) {
    final DesktopHostIntentHandler? existing = _handlers[method];
    if (existing != null && !identical(existing, handler)) {
      throw StateError('桌面主窗口 method 已注册: $method');
    }
    _handlers[method] = handler;
  }

  void unregisterHandler(String method, DesktopHostIntentHandler handler) {
    if (identical(_handlers[method], handler)) {
      _handlers.remove(method);
    }
  }

  Future<void> ensureBound() async {
    if (_bound) {
      return;
    }
    final DesktopRemoteWindowPort currentWindow = await _multiWindowPort
        .currentWindow();
    await currentWindow.setMethodHandler((String method, Object? arguments) {
      final DesktopHostIntentHandler? handler = _handlers[method];
      if (handler == null) {
        return Future<Object?>.value(null);
      }
      return handler(arguments);
    });
    _boundWindow = currentWindow;
    _bound = true;
  }

  Future<void> dispose() async {
    _handlers.clear();
    final DesktopRemoteWindowPort? window = _boundWindow;
    _boundWindow = null;
    _bound = false;
    await window?.setMethodHandler(null);
  }
}
