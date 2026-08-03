import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'auto_fetch_models.dart';

const TextSimilarity _textSimilarity = TextSimilarity();
const ArtistParser _artistParser = ArtistParser();
const TitleScorer _titleScorer = TitleScorer();

const int _maxLyricsAttemptsPerSource = 3;

/// 自动匹配编排：对齐Python版 `core/auto_fetch.py::auto_fetch`。
class AutoFetchUseCase {
  const AutoFetchUseCase({required this._gateway});

  final AutoFetchLyricsGateway _gateway;

  Future<AutoFetchResult> execute(AutoFetchRequest request) async {
    final _AutoFetchRunGuard guard = _AutoFetchRunGuard(request.shouldCancel);
    guard.throwIfCancelled();
    return _executeCore(request, guard).timeout(
      request.timeout,
      onTimeout: () {
        guard.cancel();
        throw TimeoutException('自动获取超时');
      },
    );
  }

  Future<AutoFetchResult> _executeCore(
    AutoFetchRequest request,
    _AutoFetchRunGuard guard,
  ) async {
    guard.throwIfCancelled();
    final _Keywords keywords = _buildKeywords(request.info);
    final List<Source> sources = _normalizeSources(request.sources);
    if (sources.isEmpty) {
      throw const LddcApiParamsException('自动获取歌词来源不能为空');
    }

    final List<Future<_SourceAttemptOutcome>> attempts =
        <Future<_SourceAttemptOutcome>>[
          for (
            int sourcePriority = 0;
            sourcePriority < sources.length;
            sourcePriority++
          )
            _attemptSource(
              source: sources[sourcePriority],
              sourcePriority: sourcePriority,
              info: request.info,
              keywords: keywords,
              minScore: request.minScore,
              collectSearchResults: request.includeSearchResults,
              guard: guard,
            ),
        ];
    final List<_SourceAttemptOutcome> outcomes = await Future.wait(
      attempts,
      eagerError: true,
    );
    guard.throwIfCancelled();

    final Map<SongInfo, _AutoFetchCandidateRecord> records =
        <SongInfo, _AutoFetchCandidateRecord>{};
    final List<APIResultList<SongInfo>> searchResultSets =
        <APIResultList<SongInfo>>[];
    final List<AppFailureCause> errors = <AppFailureCause>[];
    for (final _SourceAttemptOutcome outcome in outcomes) {
      for (final MapEntry<SongInfo, _AutoFetchCandidateRecord> entry
          in outcome.records.entries) {
        final _AutoFetchCandidateRecord? existing = records[entry.key];
        if (existing == null || entry.value.state.rank < existing.state.rank) {
          records[entry.key] = entry.value;
        }
      }
      searchResultSets.addAll(outcome.searchResultSets);
      errors.addAll(outcome.errors);
    }

    _MatchedLyricsCandidate? selected = _selectUsableCandidate(
      records: records,
    );
    selected ??= _selectInstrumentalFallback(
      localInfo: request.info,
      records: records,
      minScore: request.minScore,
    );
    if (selected == null) {
      _throwOnNoLyrics(errors);
    }

    return AutoFetchResult(
      lyrics: selected!.lyrics,
      matchedSongInfo: selected.songInfo,
      score: selected.score,
      searchResults: request.includeSearchResults
          ? _mergeSearchResults(
              primarySong: selected.songInfo,
              sources: sources,
              keyword: keywords.primaryKeyword,
              searchResultSets: searchResultSets,
              records: records,
            )
          : null,
    );
  }

  _Keywords _buildKeywords(SongInfo info) {
    final String title = (info.title ?? '').trim();
    final String artistTitle = info.artistTitle();
    final bool hasArtist = info.artist?.isNotEmpty ?? false;
    if (title.isNotEmpty) {
      return _Keywords(
        primaryKeyword: hasArtist && artistTitle.isNotEmpty
            ? artistTitle
            : title,
        primaryType: hasArtist && artistTitle.isNotEmpty
            ? _KeywordType.artistTitle
            : _KeywordType.title,
        titleKeyword: title,
      );
    }

    final String? songPath = info.path;
    if (songPath != null && songPath.trim().isNotEmpty) {
      final String fileName = path.basenameWithoutExtension(songPath);
      if (fileName.trim().isNotEmpty) {
        return _Keywords(
          primaryKeyword: fileName,
          primaryType: _KeywordType.fileName,
          titleKeyword: null,
        );
      }
    }
    throw const LddcNotEnoughInfoException('没有足够的信息用于搜索');
  }

  List<Source> _normalizeSources(List<Source> raw) {
    return <Source>{
      for (final Source source in raw)
        if (source != Source.local && source != Source.multi) source,
    }.toList(growable: false);
  }

  Future<_SourceAttemptOutcome> _attemptSource({
    required Source source,
    required int sourcePriority,
    required SongInfo info,
    required _Keywords keywords,
    required double minScore,
    required bool collectSearchResults,
    required _AutoFetchRunGuard guard,
  }) async {
    guard.throwIfCancelled();
    final _SourceAttemptOutcome outcome = _SourceAttemptOutcome();
    final bool primaryOutcome = await _attemptKeyword(
      source: source,
      sourcePriority: sourcePriority,
      info: info,
      keyword: keywords.primaryKeyword,
      keywordType: keywords.primaryType,
      minScore: minScore,
      outcome: outcome,
      collectSearchResults: collectSearchResults,
      guard: guard,
    );
    guard.throwIfCancelled();
    if (primaryOutcome) {
      return outcome;
    }

    if (keywords.primaryType == _KeywordType.artistTitle &&
        (keywords.titleKeyword?.isNotEmpty ?? false)) {
      await _attemptKeyword(
        source: source,
        sourcePriority: sourcePriority,
        info: info,
        keyword: keywords.titleKeyword!,
        keywordType: _KeywordType.title,
        minScore: minScore,
        outcome: outcome,
        collectSearchResults: collectSearchResults,
        guard: guard,
      );
    }
    return outcome;
  }

  Future<bool> _attemptKeyword({
    required Source source,
    required int sourcePriority,
    required SongInfo info,
    required String keyword,
    required _KeywordType keywordType,
    required double minScore,
    required _SourceAttemptOutcome outcome,
    required bool collectSearchResults,
    required _AutoFetchRunGuard guard,
  }) async {
    guard.throwIfCancelled();
    late final APIResultList<SongInfo> results;
    try {
      results = await _gateway.searchSongs(
        source: source,
        keyword: keyword,
        searchType: SearchType.song,
      );
      guard.throwIfCancelled();
    } on AutoFetchCancelledException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      outcome.errors.add(
        AppFailureCause(
          error: error,
          stackTrace: stackTrace,
          source: source.value,
          stage: 'search',
        ),
      );
      return false;
    }
    if (collectSearchResults && results.isNotEmpty) {
      outcome.searchResultSets.add(results);
    }

    final List<_ScoredSongCandidate> scored = _scoreCandidates(
      localInfo: info,
      searchResults: results,
      keywordType: keywordType,
      fileNameKeyword: keywordType == _KeywordType.fileName ? keyword : null,
      resultIndexOffset: outcome.resultCount,
    );
    outcome.resultCount += results.length;
    if (scored.isEmpty) {
      return false;
    }

    // 需要展示搜索结果时保留全部真实分数；默认路径只保留超过阈值的候选。
    // 两种路径都只有超过阈值的候选会消耗歌词请求额度。
    for (final _ScoredSongCandidate candidate in scored) {
      if (!collectSearchResults && candidate.score <= minScore) {
        continue;
      }
      final _AutoFetchCandidateRecord record = outcome.records.putIfAbsent(
        candidate.songInfo,
        () => _AutoFetchCandidateRecord(
          songInfo: candidate.songInfo,
          score: candidate.score,
          relation: candidate.relation,
          sourcePriority: sourcePriority,
          resultIndex: candidate.resultIndex,
          titleInstrumentalEvidence: candidate.titleInstrumentalEvidence,
          languageInstrumentalEvidence:
              candidate.songInfo.language == Language.instrumental,
        ),
      );

      // 版本冲突保留在结果列表，但不请求歌词，也不占同源三次额度。
      if (record.relation == SongVariantRelation.conflict) {
        record.state = _CandidateState.conflict;
      }
    }

    for (final _ScoredSongCandidate candidate in scored) {
      if (candidate.score <= minScore) {
        continue;
      }
      final _AutoFetchCandidateRecord record =
          outcome.records[candidate.songInfo]!;
      if (record.state != _CandidateState.untried ||
          outcome.lyricsAttempts >= _maxLyricsAttemptsPerSource) {
        continue;
      }
      outcome.lyricsAttempts += 1;

      try {
        guard.throwIfCancelled();
        final Lyrics lyrics = await _gateway.getLyrics(candidate.songInfo);
        guard.throwIfCancelled();
        if (lyrics.isEmpty) {
          record.state = _CandidateState.empty;
          continue;
        }
        if (lyrics.isInstrumental()) {
          record
            ..state = _CandidateState.instrumental
            ..lyricsInstrumentalEvidence = true;
          continue;
        }
        record
          ..state = _CandidateState.usable
          ..lyrics = lyrics;
        return true;
      } on AutoFetchCancelledException {
        rethrow;
      } on Exception catch (error, stackTrace) {
        record.state = _CandidateState.failed;
        outcome.errors.add(
          AppFailureCause(
            error: error,
            stackTrace: stackTrace,
            source: source.value,
            stage: 'lyrics',
          ),
        );
        // 单个候选失败不代表该来源失败，继续检查后续候选。
        continue;
      }
    }
    return false;
  }

  List<_ScoredSongCandidate> _scoreCandidates({
    required SongInfo localInfo,
    required APIResultList<SongInfo> searchResults,
    required _KeywordType keywordType,
    required String? fileNameKeyword,
    required int resultIndexOffset,
  }) {
    final List<_ScoredSongCandidate> candidates = <_ScoredSongCandidate>[];
    final String localTitle = _localVariantTitle(localInfo);
    for (int index = 0; index < searchResults.length; index += 1) {
      final SongInfo remoteSong = searchResults[index];
      final double score = _isDurationMismatch(localInfo, remoteSong)
          ? 0
          : switch (keywordType) {
              _KeywordType.fileName => _calculateFileNameScore(
                fileNameKeyword ?? '',
                remoteSong,
              ),
              _KeywordType.artistTitle || _KeywordType.title =>
                _calculateSongInfoScore(localInfo, remoteSong),
            };
      final String remoteTitle = remoteSong.fullTitle;
      final SongTitleVariant remoteVariant = _titleScorer.analyzeVariant(
        remoteTitle,
      );
      candidates.add(
        _ScoredSongCandidate(
          songInfo: remoteSong,
          score: score,
          relation: _titleScorer.classifyVariant(localTitle, remoteTitle),
          resultIndex: resultIndexOffset + index,
          titleInstrumentalEvidence: remoteVariant.isInstrumental,
        ),
      );
    }
    candidates.sort((_ScoredSongCandidate left, _ScoredSongCandidate right) {
      final int scoreOrder = right.score.compareTo(left.score);
      return scoreOrder != 0
          ? scoreOrder
          : left.resultIndex.compareTo(right.resultIndex);
    });
    return candidates;
  }

  String _localVariantTitle(SongInfo info) {
    final String fullTitle = info.fullTitle.trim();
    if (fullTitle.isNotEmpty) {
      return fullTitle;
    }
    final String? songPath = info.path;
    return songPath == null ? '' : path.basenameWithoutExtension(songPath);
  }

  bool _isDurationMismatch(SongInfo localInfo, SongInfo remoteSong) {
    final int? localDuration = localInfo.durationMs;
    if (localDuration == null) {
      return false;
    }
    final int remoteDuration = remoteSong.durationMs ?? -8;
    return (localDuration - remoteDuration).abs() > 4000;
  }

  double _calculateSongInfoScore(SongInfo localInfo, SongInfo remoteSong) {
    final double titleScore = _titleScorer.calculateScore(
      localInfo.title ?? '',
      remoteSong.title ?? '',
    );
    final double? albumScore =
        localInfo.album != null && remoteSong.album != null
        ? (_textSimilarity.textDifference(
                localInfo.album!.toLowerCase(),
                remoteSong.album!.toLowerCase(),
              ) *
              100)
        : null;
    final double? artistScore =
        localInfo.artist != null && remoteSong.artist != null
        ? _artistParser.calculateScore(
            localInfo.artist!.toString(),
            remoteSong.artist!.toString(),
          )
        : null;

    double score;
    if (artistScore != null) {
      if (albumScore != null) {
        score = math.max(
          titleScore * 0.5 + artistScore * 0.5,
          titleScore * 0.5 + artistScore * 0.35 + albumScore * 0.15,
        );
      } else {
        score = titleScore * 0.5 + artistScore * 0.5;
      }
    } else if (albumScore != null) {
      score = math.max(titleScore * 0.7 + albumScore * 0.3, titleScore * 0.8);
    } else {
      score = titleScore;
    }
    if (titleScore < 30) {
      score = math.max(0, score - 35);
    }
    return score;
  }

  double _calculateFileNameScore(String fileNameKeyword, SongInfo remoteSong) {
    final String title = remoteSong.title ?? '';
    final String artist = remoteSong.artist?.toString() ?? '';
    final double s1 =
        _textSimilarity.textDifference(fileNameKeyword, title) * 100;
    final double s2 =
        _textSimilarity.textDifference(fileNameKeyword, '$artist - $title') *
        100;
    final double s3 =
        _textSimilarity.textDifference(fileNameKeyword, '$title - $artist') *
        100;
    return math.max(s1, math.max(s2, s3));
  }

  _MatchedLyricsCandidate? _selectInstrumentalFallback({
    required SongInfo localInfo,
    required Map<SongInfo, _AutoFetchCandidateRecord> records,
    required double minScore,
  }) {
    final bool localIsInstrumental = _titleScorer
        .analyzeVariant(_localVariantTitle(localInfo))
        .isInstrumental;
    final double inferenceScore = math.max(minScore, 85);
    final List<_AutoFetchCandidateRecord> eligible = records.values.where((
      _AutoFetchCandidateRecord record,
    ) {
      if (record.score < inferenceScore ||
          record.relation == SongVariantRelation.conflict ||
          !record.hasInstrumentalEvidence) {
        return false;
      }
      if (record.relation == SongVariantRelation.compatible) {
        return true;
      }
      // 本地明确 Inst.、远端标题省略版本词时，必须再有 language 或歌词内容
      // 证据才允许反推，不能只凭标题缺失信息。
      return localIsInstrumental &&
          record.relation == SongVariantRelation.unknown &&
          (record.languageInstrumentalEvidence ||
              record.lyricsInstrumentalEvidence);
    }).toList();
    if (eligible.isEmpty) {
      return null;
    }
    eligible.sort((
      _AutoFetchCandidateRecord left,
      _AutoFetchCandidateRecord right,
    ) {
      final int scoreOrder = right.score.compareTo(left.score);
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      final int sourceOrder = left.sourcePriority.compareTo(
        right.sourcePriority,
      );
      return sourceOrder != 0
          ? sourceOrder
          : left.resultIndex.compareTo(right.resultIndex);
    });
    final _AutoFetchCandidateRecord selected = eligible.first;
    return _MatchedLyricsCandidate(
      songInfo: selected.songInfo,
      lyrics: Lyrics.instrumental(
        songInfo: selected.songInfo,
        source: selected.songInfo.source,
      ),
      score: selected.score,
    );
  }

  void _throwOnNoLyrics(List<AppFailureCause> errors) {
    final List<AppFailureCause> nonNotFound = errors
        .where(
          (AppFailureCause cause) =>
              cause.error is! LddcLyricsNotFoundException,
        )
        .toList(growable: false);
    if (nonNotFound.isEmpty) {
      throw const LddcLyricsNotFoundException('没有找到符合要求的歌曲');
    }

    final bool allNetwork = nonNotFound.every(
      (AppFailureCause cause) => _isLikelyNetworkError(cause.error),
    );
    if (allNetwork) {
      final AppFailureCause first = nonNotFound.first;
      throw LddcLyricsRequestException(
        '网络请求失败',
        cause: first.error,
        stackTrace: first.stackTrace,
        context: <String, Object?>{'failureCount': nonNotFound.length},
      );
    }
    throw LddcAutoFetchUnknownException('自动获取时发生未知错误', causes: errors);
  }

  bool _isLikelyNetworkError(Object error) {
    if (error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is TimeoutException) {
      return true;
    }
    if (error is LddcApiRequestException) {
      return true;
    }
    return false;
  }

  _MatchedLyricsCandidate? _selectUsableCandidate({
    required Map<SongInfo, _AutoFetchCandidateRecord> records,
  }) {
    final List<_AutoFetchCandidateRecord> usable = records.values
        .where(
          (_AutoFetchCandidateRecord record) =>
              record.state == _CandidateState.usable &&
              record.relation != SongVariantRelation.conflict &&
              record.lyrics != null,
        )
        .toList();
    if (usable.isEmpty) {
      return null;
    }
    final double highest = usable
        .map((_AutoFetchCandidateRecord record) => record.score)
        .reduce(math.max);
    final List<_AutoFetchCandidateRecord> window = usable
        .where(
          (_AutoFetchCandidateRecord record) => highest - record.score <= 15,
        )
        .toList();
    window.sort((
      _AutoFetchCandidateRecord left,
      _AutoFetchCandidateRecord right,
    ) {
      final int qualityOrder = _lyricsQualityRank(
        right.lyrics!,
      ).compareTo(_lyricsQualityRank(left.lyrics!));
      if (qualityOrder != 0) {
        return qualityOrder;
      }
      final int scoreOrder = right.score.compareTo(left.score);
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      final int sourceOrder = left.sourcePriority.compareTo(
        right.sourcePriority,
      );
      return sourceOrder != 0
          ? sourceOrder
          : left.resultIndex.compareTo(right.resultIndex);
    });
    final _AutoFetchCandidateRecord selected = window.first;
    return _MatchedLyricsCandidate(
      songInfo: selected.songInfo,
      lyrics: selected.lyrics!,
      score: selected.score,
    );
  }

  int _lyricsQualityRank(Lyrics lyrics) {
    final bool verbatim = lyrics.types['orig'] == LyricsType.verbatim;
    final bool translation = lyrics.data.containsKey('ts');
    final bool romanization = lyrics.data.containsKey('roma');
    if (verbatim && translation && romanization) {
      return 7;
    }
    if (verbatim && translation) {
      return 6;
    }
    if (translation && romanization) {
      return 5;
    }
    if (translation) {
      return 4;
    }
    if (verbatim && romanization) {
      return 3;
    }
    if (verbatim) {
      return 2;
    }
    return romanization ? 1 : 0;
  }

  APIResultList<SongInfo>? _mergeSearchResults({
    required SongInfo primarySong,
    required List<Source> sources,
    required String keyword,
    required List<APIResultList<SongInfo>> searchResultSets,
    required Map<SongInfo, _AutoFetchCandidateRecord> records,
  }) {
    if (searchResultSets.isEmpty) {
      return null;
    }
    final List<SongInfo> songs = <SongInfo>[];
    final Map<SongInfo, int> encounterOrder = <SongInfo, int>{};
    for (final APIResultList<SongInfo> resultSet in searchResultSets) {
      for (final SongInfo song in resultSet) {
        if (!encounterOrder.containsKey(song)) {
          encounterOrder[song] = encounterOrder.length;
          songs.add(song);
        }
      }
    }
    final Map<Source, int> sourcePriority = <Source, int>{
      for (int index = 0; index < sources.length; index += 1)
        sources[index]: index,
    };
    songs.sort((SongInfo left, SongInfo right) {
      if (left == primarySong) {
        return right == primarySong ? 0 : -1;
      }
      if (right == primarySong) {
        return 1;
      }
      final _AutoFetchCandidateRecord? leftRecord = records[left];
      final _AutoFetchCandidateRecord? rightRecord = records[right];
      final int bucketOrder = _resultBucket(
        leftRecord,
      ).compareTo(_resultBucket(rightRecord));
      if (bucketOrder != 0) {
        return bucketOrder;
      }
      final int relationOrder = _relationPriority(
        leftRecord,
      ).compareTo(_relationPriority(rightRecord));
      if (relationOrder != 0) {
        return relationOrder;
      }
      final int qualityOrder = _recordLyricsQuality(
        rightRecord,
      ).compareTo(_recordLyricsQuality(leftRecord));
      if (qualityOrder != 0) {
        return qualityOrder;
      }
      final int scoreOrder = (rightRecord?.score ?? 0).compareTo(
        leftRecord?.score ?? 0,
      );
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      final int leftSource = sourcePriority[left.source] ?? sources.length;
      final int rightSource = sourcePriority[right.source] ?? sources.length;
      final int sourceOrder = leftSource.compareTo(rightSource);
      return sourceOrder != 0
          ? sourceOrder
          : encounterOrder[left]!.compareTo(encounterOrder[right]!);
    });

    final List<Source> resultSources = <Source>[];
    for (final SongInfo song in songs) {
      if (!resultSources.contains(song.source)) {
        resultSources.add(song.source);
      }
    }
    return APIResultList<SongInfo>(
      songs,
      info: SearchInfo(
        source: resultSources,
        keyword: keyword,
        searchType: SearchType.song,
        page: null,
      ),
      ranges: _buildRangesForOrderedResults(songs, searchResultSets),
      cached: searchResultSets.every(
        (APIResultList<SongInfo> result) => result.cached,
      ),
      preserveOrder: true,
    );
  }

  int _resultBucket(_AutoFetchCandidateRecord? record) {
    if (record != null) {
      return switch (record.state) {
        _CandidateState.usable => 0,
        _CandidateState.untried => 1,
        _CandidateState.failed ||
        _CandidateState.empty ||
        _CandidateState.instrumental => 2,
        _CandidateState.conflict => 3,
      };
    }
    return 1;
  }

  int _relationPriority(_AutoFetchCandidateRecord? record) {
    return record?.relation == SongVariantRelation.compatible ? 0 : 1;
  }

  int _recordLyricsQuality(_AutoFetchCandidateRecord? record) {
    final Lyrics? lyrics = record?.lyrics;
    return lyrics == null ? -1 : _lyricsQualityRank(lyrics);
  }

  Map<Source, SourceRange> _buildRangesForOrderedResults(
    List<SongInfo> songs,
    List<APIResultList<SongInfo>> resultSets,
  ) {
    final Map<Source, int> counts = <Source, int>{};
    for (final SongInfo song in songs) {
      counts[song.source] = (counts[song.source] ?? 0) + 1;
    }
    final Map<Source, int> totals = <Source, int>{};
    for (final APIResultList<SongInfo> resultSet in resultSets) {
      for (final MapEntry<Source, SourceRange> entry
          in resultSet.sourceRanges.entries) {
        totals[entry.key] = math.max(totals[entry.key] ?? 0, entry.value.total);
      }
    }
    return <Source, SourceRange>{
      for (final MapEntry<Source, int> entry in counts.entries)
        entry.key: SourceRange(
          start: 0,
          end: entry.value - 1,
          total: math.max(entry.value, totals[entry.key] ?? 0),
        ),
    };
  }
}

enum _KeywordType { artistTitle, title, fileName }

class _Keywords {
  const _Keywords({
    required this.primaryKeyword,
    required this.primaryType,
    required this.titleKeyword,
  });

  final String primaryKeyword;
  final _KeywordType primaryType;
  final String? titleKeyword;
}

class _SourceAttemptOutcome {
  final Map<SongInfo, _AutoFetchCandidateRecord> records =
      <SongInfo, _AutoFetchCandidateRecord>{};
  final List<APIResultList<SongInfo>> searchResultSets =
      <APIResultList<SongInfo>>[];
  final List<AppFailureCause> errors = <AppFailureCause>[];
  int lyricsAttempts = 0;
  int resultCount = 0;
}

enum _CandidateState {
  usable(0),
  instrumental(1),
  empty(2),
  failed(3),
  untried(4),
  conflict(5);

  const _CandidateState(this.rank);

  final int rank;
}

class _AutoFetchCandidateRecord {
  _AutoFetchCandidateRecord({
    required this.songInfo,
    required this.score,
    required this.relation,
    required this.sourcePriority,
    required this.resultIndex,
    required this.titleInstrumentalEvidence,
    required this.languageInstrumentalEvidence,
  });

  final SongInfo songInfo;
  final double score;
  final SongVariantRelation relation;
  final int sourcePriority;
  final int resultIndex;
  final bool titleInstrumentalEvidence;
  final bool languageInstrumentalEvidence;
  bool lyricsInstrumentalEvidence = false;
  _CandidateState state = _CandidateState.untried;
  Lyrics? lyrics;

  bool get hasInstrumentalEvidence =>
      titleInstrumentalEvidence ||
      languageInstrumentalEvidence ||
      lyricsInstrumentalEvidence;
}

class _ScoredSongCandidate {
  const _ScoredSongCandidate({
    required this.songInfo,
    required this.score,
    required this.relation,
    required this.resultIndex,
    required this.titleInstrumentalEvidence,
  });

  final SongInfo songInfo;
  final double score;
  final SongVariantRelation relation;
  final int resultIndex;
  final bool titleInstrumentalEvidence;
}

class _MatchedLyricsCandidate {
  const _MatchedLyricsCandidate({
    required this.songInfo,
    required this.lyrics,
    required this.score,
  });

  final SongInfo songInfo;
  final Lyrics lyrics;
  final double score;
}

/// 单次 execute 的取消状态。
///
/// 外部取消回调负责表达用户取消；[cancel] 由超时分支调用。两者都统一转换为
/// [AutoFetchCancelledException]，使迟到的搜索或歌词结果在内部立即停止继续编排。
class _AutoFetchRunGuard {
  _AutoFetchRunGuard(this._shouldCancel);

  final bool Function()? _shouldCancel;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
  }

  void throwIfCancelled() {
    if (_cancelled || (_shouldCancel?.call() ?? false)) {
      throw const AutoFetchCancelledException();
    }
  }
}
