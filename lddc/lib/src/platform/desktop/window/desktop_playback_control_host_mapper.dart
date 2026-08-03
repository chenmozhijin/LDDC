import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../ipc/desktop_ipc.dart';

/// 将 foobar IPC 控制任务裁剪为共享桌面歌词包使用的播放器动作。
///
/// 两个枚举故意保持独立：协议层可以继续兼容 Python 版的 `prev` 拼写，
/// 共享包则不需要感知具体播放器或传输协议。
extension DesktopControlCommandTaskHostMapper on DesktopControlCommandTask {
  DesktopPlaybackControlTask toPlaybackControlTask() {
    return switch (this) {
      DesktopControlCommandTask.play => DesktopPlaybackControlTask.play,
      DesktopControlCommandTask.pause => DesktopPlaybackControlTask.pause,
      DesktopControlCommandTask.stop => DesktopPlaybackControlTask.stop,
      DesktopControlCommandTask.prev => DesktopPlaybackControlTask.previous,
      DesktopControlCommandTask.next => DesktopPlaybackControlTask.next,
    };
  }
}

/// 在宿主真正发送 foobar IPC 命令前恢复为协议枚举。
extension DesktopPlaybackControlTaskHostMapper on DesktopPlaybackControlTask {
  DesktopControlCommandTask toProtocolControlTask() {
    return switch (this) {
      DesktopPlaybackControlTask.play => DesktopControlCommandTask.play,
      DesktopPlaybackControlTask.pause => DesktopControlCommandTask.pause,
      DesktopPlaybackControlTask.stop => DesktopControlCommandTask.stop,
      DesktopPlaybackControlTask.previous => DesktopControlCommandTask.prev,
      DesktopPlaybackControlTask.next => DesktopControlCommandTask.next,
    };
  }
}
