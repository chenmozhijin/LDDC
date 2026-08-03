import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../service_host/desktop_session_state.dart';
import '../service_host/desktop_window_action_builder.dart';
import 'desktop_projection_host_mapper.dart';

/// 将 LDDC 会话裁剪为共享 Panel 窗口快照。
///
/// 这里只读取宿主配置和 foobar 播放锚点；窗口 DTO、渲染状态和生命周期均由
/// `lddc_desktop_lyrics` 唯一拥有。
DesktopPanelWindowSnapshot buildDesktopPanelWindowSnapshot(
  DesktopSessionState state,
) {
  final runtime = state.lyricsRuntime;
  return DesktopPanelWindowSnapshot(
    session: DesktopPanelSessionSnapshot(
      songId: runtime.song?.id,
      enabledLangs: state.config.selectedLangs,
      playedColors: state.config.playedColors,
      unplayedColors: state.config.unplayedColors,
      fontFamily: state.config.fontFamily,
      fontSize: state.config.panelFontSize,
      showFurigana: state.config.showFurigana,
      refreshRate: state.config.refreshRate,
      visible: true,
      actions: buildDesktopWindowActionSnapshot(state),
    ),
    anchor: DesktopPanelAnchorSnapshot(
      pluginPlaybackTimeMs: state.playbackSync.pluginPlaybackTimeMs,
      pluginSendTimeMs: state.playbackSync.pluginSendTimeMs,
      hostReceivedAtMs: state.playbackSync.hostReceivedAtMs,
      isPlaying: state.playbackSync.isPlaying,
      syncRevision: state.playbackSync.syncRevision,
      eventKind: state.playbackSync.task.toPlaybackEventKind(),
      sceneId: state.playbackSync.sceneId,
      songToken: state.playbackSync.songToken,
    ),
    sceneRef: runtime.sceneRef,
  );
}
