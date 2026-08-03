/// 桌面歌词包使用的日志级别。
enum DesktopLyricsLogLevel { trace, debug, info, warning, error }

typedef DesktopLyricsLogCallback =
    void Function(
      String scope,
      DesktopLyricsLogLevel level,
      String message,
      Map<String, Object?> fields,
    );

/// 可由宿主注入的轻量日志端口。
///
/// 桌面歌词包只负责产生结构化诊断，不读取宿主日志目录、配置或文件句柄。
/// 默认实例不输出；宿主可通过 [callback] 接入自己的日志运行时。
final class DesktopLyricsLogger {
  const DesktopLyricsLogger({this.callback, this.scope = 'desktop-lyrics'});

  final DesktopLyricsLogCallback? callback;
  final String scope;

  DesktopLyricsLogger child(String childScope) {
    return DesktopLyricsLogger(callback: callback, scope: '$scope/$childScope');
  }

  void debug(String message, {Map<String, Object?> fields = const {}}) {
    callback?.call(scope, DesktopLyricsLogLevel.debug, message, fields);
  }

  void info(String message, {Map<String, Object?> fields = const {}}) {
    callback?.call(scope, DesktopLyricsLogLevel.info, message, fields);
  }

  void warning(String message, {Map<String, Object?> fields = const {}}) {
    callback?.call(scope, DesktopLyricsLogLevel.warning, message, fields);
  }

  void error(String message, {Map<String, Object?> fields = const {}}) {
    callback?.call(scope, DesktopLyricsLogLevel.error, message, fields);
  }
}
