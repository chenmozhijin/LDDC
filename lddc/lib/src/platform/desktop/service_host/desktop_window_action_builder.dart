import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../window/desktop_playback_control_host_mapper.dart';
import 'desktop_session_state.dart';

DesktopWindowActionSnapshot buildDesktopWindowActionSnapshot(
  DesktopSessionState state,
) {
  return DesktopWindowActionSnapshot(
    isInstrumental: state.config.isInstrumental,
    isAutoSearchDisabled: state.config.isAutoSearchDisabled,
    canUnlinkLyrics: _canUnlinkLyrics(state),
    canOpenSelector: state.instanceId != null,
    canShowMainWindow: true,
    canOpenAssociationManager: true,
    availableControlTasks: state.client.availableTasks
        .map((task) => task.toPlaybackControlTask())
        .toSet(),
    clickThroughEnabled: state.uiState.clickThrough,
    floatingVisibilityMode: state.uiState.floatingVisibilityMode,
  );
}

DesktopLyricsInfoBadgeSnapshot buildDesktopLyricsInfoBadgeSnapshot(
  DesktopSessionState state,
) {
  if (state.config.isInstrumental) {
    return const DesktopLyricsInfoBadgeSnapshot(isInstrumental: true);
  }
  final Lyrics? lyrics = state.lyricsRuntime.lyrics;
  if (lyrics == null) {
    return const DesktopLyricsInfoBadgeSnapshot();
  }
  return DesktopLyricsInfoBadgeSnapshot(
    source: lyrics.source,
    lyricsType: lyrics.types['orig'],
    isInstrumental: false,
  );
}

bool _canUnlinkLyrics(DesktopSessionState state) {
  return state.lyricsRuntime.lyricsPath != null ||
      state.lyricsRuntime.lyrics != null ||
      state.config.isInstrumental ||
      state.config.isAutoSearchDisabled;
}
