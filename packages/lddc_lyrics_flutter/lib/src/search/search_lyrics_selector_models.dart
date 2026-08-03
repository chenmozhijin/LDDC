import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

typedef SearchLyricsSelectorPickLocalLyricsPath = Future<String?> Function();
typedef SearchLyricsSelectorLoadLocalLyrics =
    Future<Lyrics> Function(String path);

class SearchLyricsSelectorInitialState {
  const SearchLyricsSelectorInitialState({
    this.keyword,
    this.lyrics,
    required this.langs,
    required this.offsetMs,
    this.refreshRevision = 0,
  });

  final String? keyword;
  final Lyrics? lyrics;
  final List<String> langs;
  final int offsetMs;
  final int refreshRevision;
}

class SearchLyricsSelectorResult {
  const SearchLyricsSelectorResult({
    required this.lyrics,
    this.path,
    this.langs,
    this.offsetMs = 0,
    this.isInstrumental = false,
  });

  final Lyrics lyrics;
  final String? path;
  final List<String>? langs;
  final int offsetMs;
  final bool isInstrumental;
}

class SearchLyricsSelectorDependencies {
  const SearchLyricsSelectorDependencies({
    required this.pickLocalLyricsPath,
    required this.loadLocalLyrics,
  });

  final SearchLyricsSelectorPickLocalLyricsPath pickLocalLyricsPath;
  final SearchLyricsSelectorLoadLocalLyrics loadLocalLyrics;
}
