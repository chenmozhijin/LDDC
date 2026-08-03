import 'dart:math' as math;

import '../lyrics_source/lyrics_source.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'auto_fetch_models.dart';

/// 将 [LyricsClient] 适配为自动获取所需的最小网关。
class LyricsApiAutoFetchGateway implements AutoFetchLyricsGateway {
  LyricsApiAutoFetchGateway({required this._lyricsApi});

  final LyricsClient _lyricsApi;

  @override
  Future<APIResultList<SongInfo>> searchSongs({
    required Source source,
    required String keyword,
    required SearchType searchType,
  }) async {
    final APIResultList<SourceAware> result = await _lyricsApi.search(
      source: source,
      keyword: keyword,
      searchType: searchType,
    );
    final List<SongInfo> songs = result.whereType<SongInfo>().toList(
      growable: false,
    );
    if (songs.length == result.length) {
      return APIResultList<SongInfo>(
        songs,
        info: result.info,
        ranges: result.sourceRanges,
        cached: result.cached,
      );
    }

    // 单来源搜索偶尔可能混入歌单等其他结果类型。过滤后重新建立当前页范围，
    // 但继续保留服务端 total，避免自动获取结果进入搜索页后丢失分页能力。
    final int total = math.max(
      songs.length,
      result.sourceRanges[source]?.total ?? songs.length,
    );
    final SourceRange range = songs.isEmpty
        ? SourceRange(start: 0, end: -1, total: total)
        : SourceRange(start: 0, end: songs.length - 1, total: total);
    return APIResultList<SongInfo>(
      songs,
      info: result.info,
      ranges: <Source, SourceRange>{source: range},
      cached: result.cached,
    );
  }

  @override
  Future<Lyrics> getLyrics(SongInfo info) {
    return _lyricsApi.getLyrics(info: info);
  }
}
