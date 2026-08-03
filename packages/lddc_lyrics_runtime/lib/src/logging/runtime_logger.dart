/// 共享歌词运行时日志级别。
enum LddcRuntimeLogLevel { trace, debug, info, warning, error }

typedef LddcRuntimeLogCallback =
    void Function(
      String scope,
      LddcRuntimeLogLevel level,
      String message,
      Map<String, Object?> fields,
    );

/// 可注入的轻量日志端口。
///
/// 默认实例不产生输出，宿主可把记录映射到自己的日志系统。
final class LddcRuntimeLogger {
  const LddcRuntimeLogger({this.callback, this.scope = 'lddc-runtime'});

  final LddcRuntimeLogCallback? callback;
  final String scope;

  LddcRuntimeLogger child(String childScope) {
    return LddcRuntimeLogger(callback: callback, scope: '$scope/$childScope');
  }

  void debug(String message, {Map<String, Object?> fields = const {}}) {
    callback?.call(scope, LddcRuntimeLogLevel.debug, message, fields);
  }

  void info(String message, {Map<String, Object?> fields = const {}}) {
    callback?.call(scope, LddcRuntimeLogLevel.info, message, fields);
  }

  void warning(String message, {Map<String, Object?> fields = const {}}) {
    callback?.call(scope, LddcRuntimeLogLevel.warning, message, fields);
  }

  void error(String message, {Map<String, Object?> fields = const {}}) {
    callback?.call(scope, LddcRuntimeLogLevel.error, message, fields);
  }
}
