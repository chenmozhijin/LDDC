import 'desktop_lyrics_projection_runtime.dart';
import '../window/desktop_panel_host.dart';
import '../window/desktop_window_backend.dart';

/// 将浮窗会话快照裁剪为投影运行时真正需要的样式字段。
extension DesktopFloatingProjectionStyleMapper
    on DesktopFloatingSessionSnapshot {
  DesktopLyricsProjectionStyle toProjectionStyle() {
    return DesktopLyricsProjectionStyle(
      enabledLangs: enabledLangs,
      showFurigana: showFurigana,
    );
  }
}

/// 将 Panel 会话快照裁剪为投影运行时真正需要的样式字段。
extension DesktopPanelProjectionStyleMapper on DesktopPanelSessionSnapshot {
  DesktopLyricsProjectionStyle toProjectionStyle() {
    return DesktopLyricsProjectionStyle(
      enabledLangs: enabledLangs,
      showFurigana: showFurigana,
    );
  }
}

/// 将浮窗播放锚点转换为播放器无关的投影同步事件。
extension DesktopFloatingPlaybackAnchorMapper on DesktopFloatingAnchorSnapshot {
  DesktopLyricsPlaybackSyncEvent toProjectionSyncEvent() {
    return DesktopLyricsPlaybackSyncEvent(
      pluginPlaybackTimeMs: pluginPlaybackTimeMs,
      pluginSendTimeMs: pluginSendTimeMs,
      hostReceivedAtMs: hostReceivedAtMs,
      isPlaying: isPlaying,
      syncRevision: syncRevision,
      task: eventKind,
      sceneId: sceneId,
      songToken: songToken,
    );
  }
}

/// 将 Panel 播放锚点转换为播放器无关的投影同步事件。
extension DesktopPanelPlaybackAnchorMapper on DesktopPanelAnchorSnapshot {
  DesktopLyricsPlaybackSyncEvent toProjectionSyncEvent() {
    return DesktopLyricsPlaybackSyncEvent(
      pluginPlaybackTimeMs: pluginPlaybackTimeMs,
      pluginSendTimeMs: pluginSendTimeMs,
      hostReceivedAtMs: hostReceivedAtMs,
      isPlaying: isPlaying,
      syncRevision: syncRevision,
      task: eventKind,
      sceneId: sceneId,
      songToken: songToken,
    );
  }
}
