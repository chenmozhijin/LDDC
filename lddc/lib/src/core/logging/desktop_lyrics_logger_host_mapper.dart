import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import 'app_logger.dart';

/// 将桌面歌词包的轻量日志端口绑定到 LDDC 文件日志运行时。
///
/// 映射只存在于宿主侧，桌面包不会读取 LDDC 配置、日志目录或文件句柄。
extension DesktopLyricsLoggerHostMapper on AppLogger {
  DesktopLyricsLogger toDesktopLyricsLogger() {
    return DesktopLyricsLogger(
      scope: scopeName,
      callback:
          (
            String _,
            DesktopLyricsLogLevel level,
            String message,
            Map<String, Object?> fields,
          ) {
            switch (level) {
              case DesktopLyricsLogLevel.trace:
                trace(message, fields: fields);
              case DesktopLyricsLogLevel.debug:
                debug(message, fields: fields);
              case DesktopLyricsLogLevel.info:
                info(message, fields: fields);
              case DesktopLyricsLogLevel.warning:
                warning(message, fields: fields);
              case DesktopLyricsLogLevel.error:
                error(message, fields: fields);
            }
          },
    );
  }
}
