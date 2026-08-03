import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../network/request_cancellation.dart';

/// 歌词候选失败后的自动降级原因。
enum LyricsResolveFallbackReason {
  /// 拉取候选歌词列表失败，回退到直接获取歌词。
  lyricsListFailed,

  /// 候选歌词列表为空，回退到直接获取歌词。
  lyricsListEmpty,
}

/// 歌词解析结果：要么直接得到歌词，要么要求用户选择候选项。
sealed class LyricsResolveResult {
  const LyricsResolveResult();
}

/// 已得到可直接使用的歌词。
final class LyricsResolvedResult extends LyricsResolveResult {
  const LyricsResolvedResult({required this.lyrics, this.fallbackReason});

  final Lyrics lyrics;
  final LyricsResolveFallbackReason? fallbackReason;

  bool get usedFallback => fallbackReason != null;
}

/// 需要用户从候选列表中选择歌词。
final class LyricsSelectionRequiredResult extends LyricsResolveResult {
  const LyricsSelectionRequiredResult({required this.candidates});

  final APIResultList<LyricInfo> candidates;
}

/// 歌词搜索与获取的能力级公共契约。
///
/// 外部控制器只依赖实际使用的方法，既可以接入默认 LyricsApi，也可以在测试或
/// 特殊宿主中提供自己的实现；缓存、重试和来源注册仍由默认实现唯一负责。
abstract interface class LyricsClient {
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  });

  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo);

  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo);

  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  });

  Future<Lyrics> getLyrics({Object? info, String? path, Object? data});
}
