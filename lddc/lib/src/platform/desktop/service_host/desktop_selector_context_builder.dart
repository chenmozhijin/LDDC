import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'desktop_session_state.dart';

/// 构造桌面歌词选择器上下文，统一关键词与 refresh token 语义。
DesktopSelectorWindowContext buildDesktopSelectorContext({
  required DesktopSessionState state,
  required int refreshToken,
}) {
  return DesktopSelectorWindowContext(
    keyword: buildDesktopSelectorKeyword(state.lyricsRuntime.song),
    lyrics: state.lyricsRuntime.lyrics,
    langs: state.config.selectedLangs,
    offsetMs: state.config.offsetMs,
    refreshToken: refreshToken,
  );
}

/// 构造用于歌词搜索的紧凑关键词。
///
/// 通常使用“歌手 - 标题”；歌手文本远长于标题时只保留标题，避免多人合作名单
/// 稀释搜索关键词。标题缺失时仍保留歌手，使不完整的播放器元数据可以继续搜索。
String? buildDesktopSelectorKeyword(SongInfo? song) {
  if (song == null) {
    return null;
  }
  final String artist = song.artistText.trim();
  final String title = (song.title ?? '').trim();
  if (title.isEmpty) {
    return artist.isEmpty ? null : artist;
  }
  if (artist.isEmpty || artist.length > title.length * 2) {
    return title;
  }
  return '$artist - $title';
}
