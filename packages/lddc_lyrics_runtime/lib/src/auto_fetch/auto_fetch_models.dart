import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 自动获取歌词请求参数。
class AutoFetchRequest {
  AutoFetchRequest({
    required this.info,
    this.minScore = 55,
    Iterable<Source> sources = const <Source>[Source.qm, Source.kg, Source.ne],
    this.includeSearchResults = false,
    this.timeout = const Duration(seconds: 30),
    this.shouldCancel,
  }) : sources = List<Source>.unmodifiable(sources) {
    if (!minScore.isFinite) {
      throw ArgumentError.value(minScore, 'minScore', '必须是有限数值');
    }
    if (timeout.inMicroseconds <= 0) {
      throw ArgumentError.value(timeout, 'timeout', '必须大于零');
    }
  }

  final SongInfo info;

  /// 最低匹配分数，默认对齐 Python 版的 55 分阈值。
  final double minScore;

  /// 自动匹配来源优先级。构造后不可修改，避免异步执行期间输入发生变化。
  final List<Source> sources;

  final bool includeSearchResults;
  final Duration timeout;

  /// 协作式取消检查。底层网络请求可能无法立即终止，但自动获取会在每个异步
  /// 边界停止消费迟到结果，也不会继续请求后续候选。
  final bool Function()? shouldCancel;
}

/// 自动获取歌词输出。
class AutoFetchResult {
  const AutoFetchResult({
    required this.lyrics,
    required this.matchedSongInfo,
    required this.score,
    this.searchResults,
  });

  final Lyrics lyrics;
  final SongInfo matchedSongInfo;
  final double score;
  final APIResultList<SongInfo>? searchResults;
}

/// 自动获取编排所需的最小歌词网关。
abstract interface class AutoFetchLyricsGateway {
  Future<APIResultList<SongInfo>> searchSongs({
    required Source source,
    required String keyword,
    required SearchType searchType,
  });

  Future<Lyrics> getLyrics(SongInfo info);
}

/// 自动获取被上层协作式取消。
class AutoFetchCancelledException implements Exception {
  const AutoFetchCancelledException();

  @override
  String toString() => '自动获取已取消';
}
