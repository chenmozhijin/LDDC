import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../ipc/desktop_ipc.dart';

/// 将 LDDC/foobar 协议事件映射为共享包的播放器事件。
extension DesktopIpcTaskProjectionMapper on DesktopIpcTask? {
  DesktopPlaybackEventKind toPlaybackEventKind() {
    return switch (this) {
      DesktopIpcTask.start => DesktopPlaybackEventKind.start,
      DesktopIpcTask.pause => DesktopPlaybackEventKind.pause,
      DesktopIpcTask.proceed => DesktopPlaybackEventKind.resume,
      DesktopIpcTask.stop => DesktopPlaybackEventKind.stop,
      DesktopIpcTask.sync => DesktopPlaybackEventKind.sync,
      DesktopIpcTask.changMusic => DesktopPlaybackEventKind.trackChanged,
      _ => DesktopPlaybackEventKind.other,
    };
  }
}
