import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../cache/cache.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../network/request_budget.dart';
import '../network/request_cancellation.dart';
import 'lyrics_client.dart';
import 'lyrics_source_provider.dart';
import 'lyrics_source_registry.dart';

/// 歌词 API 聚合门面，对齐Python版 `core/api/lyrics/__init__.py`。
class LyricsApi implements LyricsClient {
  LyricsApi({
    required this._registry,
    required this._cache,
    this._requestBudget = kDefaultLyricsRequestBudget,
  });

  static const Duration _cacheTtl = Duration(seconds: 14400);

  final LyricsSourceRegistry _registry;
  final CacheFacade _cache;
  final NetworkRequestBudget _requestBudget;
  final Map<String, _SharedInflightCall> _inflightCacheCalls =
      <String, _SharedInflightCall>{};

  /// 搜索歌曲/专辑/歌单（仅云端源）。
  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    final LyricsCloudSourceProvider provider = _requireCloudProvider(source);
    if (!provider.supportedSearchTypes.contains(searchType)) {
      throw LddcApiParamsException('不支持的搜索类型: ${searchType.value}');
    }

    return _cachedCall<APIResultList<SourceAware>>(
      functionIdentifier: 'LDDC.core.api.lyrics.search',
      policy: const CachePolicy(namespace: 'lyrics_api.search', ttl: _cacheTtl),
      args: <Object?>[source.value, keyword, searchType.value, page],
      loader: () async {
        final APIResultList<SourceAware> result =
            await _retryRequest<APIResultList<SourceAware>>(
              () => provider.search(
                keyword: keyword,
                searchType: searchType,
                page: page,
                cancellationToken: RequestCancellationToken.current,
              ),
              cancellationToken: RequestCancellationToken.current,
            );
        return _encodeSourceAwareResult(result);
      },
      decoder: (Map<String, Object?> payload, bool cached) {
        return _decodeSourceAwareResult(payload).copyWith(cached: cached);
      },
      cancellationToken: cancellationToken,
    );
  }

  /// 获取歌单/专辑歌曲列表。
  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    final LyricsCloudSourceProvider provider = _requireCloudProvider(
      songListInfo.source,
    );
    return _cachedCall<APIResultList<SongInfo>>(
      functionIdentifier: 'LDDC.core.api.lyrics.get_songlist',
      policy: const CachePolicy(
        namespace: 'lyrics_api.get_songlist',
        ttl: _cacheTtl,
      ),
      args: <Object?>[songListInfo.toMap()],
      loader: () async {
        final APIResultList<SongInfo> result =
            await _retryRequest<APIResultList<SongInfo>>(
              () => provider.getSonglist(songListInfo),
            );
        return _encodeSongInfoResult(result);
      },
      decoder: (Map<String, Object?> payload, bool cached) {
        return _decodeSongInfoResult(payload).copyWith(cached: cached);
      },
    );
  }

  /// 获取歌曲歌词列表。
  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    final LyricsCloudSourceProvider provider = _requireCloudProvider(
      songInfo.source,
    );
    if (!provider.supportsLyricsList) {
      throw LddcApiNotSupportedException(
        '来源 ${songInfo.source.value} 不支持歌词候选列表',
      );
    }
    return _cachedCall<APIResultList<LyricInfo>>(
      functionIdentifier: 'LDDC.core.api.lyrics.get_lyricslist',
      policy: const CachePolicy(
        namespace: 'lyrics_api.get_lyricslist',
        ttl: _cacheTtl,
      ),
      args: <Object?>[songInfo.toMap()],
      loader: () async {
        final APIResultList<LyricInfo> result =
            await _retryRequest<APIResultList<LyricInfo>>(
              () => provider.getLyricslist(songInfo),
            );
        return _encodeLyricInfoResult(result);
      },
      decoder: (Map<String, Object?> payload, bool cached) {
        return _decodeLyricInfoResult(payload).copyWith(cached: cached);
      },
    );
  }

  /// 按 `autoSelect` 策略解析歌曲歌词。
  ///
  /// 语义对齐Python版搜索页策略：
  /// - `autoSelect=true`：直接获取最佳歌词。
  /// - `autoSelect=false` 且来源支持候选：先请求候选列表，返回“需用户选择”结果。
  /// - 候选列表请求失败或为空：自动回退到直接获取最佳歌词。
  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    final LyricsCloudSourceProvider provider = _requireCloudProvider(
      songInfo.source,
    );

    if (autoSelect || !provider.supportsLyricsList) {
      final Lyrics lyrics = await getLyrics(info: songInfo);
      return LyricsResolvedResult(lyrics: lyrics);
    }

    try {
      final APIResultList<LyricInfo> candidates = await getLyricslist(songInfo);
      if (candidates.isNotEmpty) {
        return LyricsSelectionRequiredResult(candidates: candidates);
      }
      final Lyrics lyrics = await getLyrics(info: songInfo);
      return LyricsResolvedResult(
        lyrics: lyrics,
        fallbackReason: LyricsResolveFallbackReason.lyricsListEmpty,
      );
    } on LddcApiRequestException {
      final Lyrics lyrics = await getLyrics(info: songInfo);
      return LyricsResolvedResult(
        lyrics: lyrics,
        fallbackReason: LyricsResolveFallbackReason.lyricsListFailed,
      );
    } on LddcApiNotSupportedException {
      final Lyrics lyrics = await getLyrics(info: songInfo);
      return LyricsResolvedResult(
        lyrics: lyrics,
        fallbackReason: LyricsResolveFallbackReason.lyricsListFailed,
      );
    } on LddcLyricsNotFoundException {
      final Lyrics lyrics = await getLyrics(info: songInfo);
      return LyricsResolvedResult(
        lyrics: lyrics,
        fallbackReason: LyricsResolveFallbackReason.lyricsListFailed,
      );
    }
  }

  /// 获取歌词内容。
  ///
  /// 语义对齐Python版：
  /// - 本地分支不走缓存
  /// - 云端分支走缓存并回写 `cached` 标记
  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    if (info == null && path == null && data == null) {
      throw const LddcApiParamsException('info/path/data 不能同时为空');
    }

    final Uint8List? inputData = _normalizeInputData(data);
    final Source? source = _resolveSource(info);
    if (info == null || source == Source.local) {
      final Lyrics lyrics = await _getLocalLyrics(
        info: info,
        path: path,
        data: inputData,
      );
      if (lyrics.isEmpty) {
        throw const LddcLyricsNotFoundException('没有找到歌词');
      }
      return lyrics.copyWith(cached: false);
    }

    if (info is! SongInfo && info is! LyricInfo) {
      throw const LddcApiParamsException('info 类型必须为 SongInfo 或 LyricInfo');
    }

    final LyricsCloudSourceProvider provider = _requireCloudProvider(source!);
    return _cachedCall<Lyrics>(
      functionIdentifier: 'LDDC.core.api.lyrics.get_lyrics',
      policy: const CachePolicy(
        namespace: 'lyrics_api.get_lyrics',
        ttl: _cacheTtl,
      ),
      args: <Object?>[_buildLyricsCacheIdentity(info)],
      loader: () async {
        final Lyrics lyrics = await _retryRequest<Lyrics>(
          () => provider.getLyrics(info),
        );
        if (lyrics.isEmpty) {
          throw const LddcLyricsNotFoundException('没有找到歌词');
        }
        return _encodeLyrics(lyrics);
      },
      decoder: (Map<String, Object?> payload, bool cached) {
        final Lyrics lyrics = _decodeLyrics(payload).copyWith(cached: cached);
        if (lyrics.isEmpty) {
          throw const FormatException('缓存中的歌词内容为空');
        }
        return lyrics;
      },
    );
  }

  Future<Lyrics> _getLocalLyrics({
    required Object? info,
    required String? path,
    required Uint8List? data,
  }) async {
    if (info != null && info is! SongInfo && info is! LyricInfo) {
      throw const LddcApiParamsException('本地 info 类型必须为 SongInfo 或 LyricInfo');
    }
    if (info is SongInfo) {
      throw const LddcApiParamsException('LocalAPI 不支持 SongInfo');
    }

    LyricInfo? lyricInfo = info as LyricInfo?;
    if (lyricInfo != null) {
      lyricInfo = lyricInfo.copyWith(
        path: path ?? lyricInfo.path,
        data: data ?? lyricInfo.data,
      );
    } else {
      lyricInfo = LyricInfo(
        source: Source.local,
        songInfo: const SongInfo(source: Source.local),
        path: path,
        data: data,
      );
    }

    if ((lyricInfo.path == null || lyricInfo.path!.isEmpty) &&
        lyricInfo.data == null) {
      throw const LddcApiParamsException('没有任何文件路径和数据');
    }

    final LyricsLocalSourceProvider provider = _registry.requireLocalProvider();
    return provider.getLyrics(
      LocalLyricsRequest(
        info: lyricInfo,
        path: lyricInfo.path,
        data: lyricInfo.data,
      ),
    );
  }

  LyricsCloudSourceProvider _requireCloudProvider(Source source) {
    if (source == Source.local || source == Source.multi) {
      throw LddcApiParamsException('不支持的歌词源: ${source.value}');
    }
    return _registry.requireCloudProvider(source);
  }

  Future<T> _cachedCall<T>({
    required String functionIdentifier,
    required CachePolicy policy,
    required List<Object?> args,
    required Future<Map<String, Object?>> Function() loader,
    required T Function(Map<String, Object?> payload, bool cached) decoder,
    RequestCancellationToken? cancellationToken,
  }) async {
    final String cacheKey = CacheFacade.buildCacheKey(
      functionIdentifier: functionIdentifier,
      args: args,
      typed: policy.typed,
      ignoreArgs: policy.ignoreArgs,
    );
    final String inflightKey = <Object?>[
      policy.namespace,
      policy.cacheVersion,
      cacheKey,
    ].join('\u0000');
    _SharedInflightCall? sharedCall = _inflightCacheCalls[inflightKey];
    if (sharedCall == null) {
      final RequestCancellationToken sharedToken = RequestCancellationToken();
      final Future<T> call = RequestCancellationToken.runWith<T>(
        sharedToken,
        () => _performCachedCall<T>(
          functionIdentifier: functionIdentifier,
          policy: policy,
          args: args,
          cacheKey: cacheKey,
          loader: () async {
            sharedToken.throwIfCancelled();
            final Map<String, Object?> value = await loader();
            // 所有 waiter 都取消后不能再把已经过时的响应写入缓存。
            sharedToken.throwIfCancelled();
            return value;
          },
          decoder: decoder,
        ),
      );
      final Future<Object?> erasedCall = call.then<Object?>((T value) => value);
      sharedCall = _SharedInflightCall(
        future: erasedCall,
        cancellationToken: sharedToken,
      );
      _inflightCacheCalls[inflightKey] = sharedCall;
      final _SharedInflightCall capturedCall = sharedCall;
      erasedCall.then<void>(
        (_) => _finishInflightCall(inflightKey, capturedCall),
        onError: (Object _, StackTrace _) {
          _finishInflightCall(inflightKey, capturedCall);
        },
      );
    }

    // 每个调用方单独登记 waiter。取消一个调用方只结束自己的等待；只有最后
    // 一个 waiter 离开时才取消底层共享请求，避免误伤其他页面的同 key 搜索。
    return _awaitInflightCall<T>(sharedCall, cancellationToken);
  }

  Future<T> _awaitInflightCall<T>(
    _SharedInflightCall call,
    RequestCancellationToken? cancellationToken,
  ) async {
    call.waiterCount += 1;
    try {
      if (cancellationToken == null) {
        return (await call.future) as T;
      }
      cancellationToken.throwIfCancelled();
      final Object? value = await Future.any<Object?>(<Future<Object?>>[
        call.future,
        cancellationToken.whenCancelled.then<Object?>((_) {
          throw const RequestCancelledException();
        }),
      ]);
      return value as T;
    } finally {
      call.waiterCount -= 1;
      if (call.waiterCount == 0 && !call.finished) {
        call.cancellationToken.cancel();
      }
    }
  }

  void _finishInflightCall(String key, _SharedInflightCall call) {
    call.finished = true;
    call.cancellationToken.dispose();
    if (identical(_inflightCacheCalls[key], call)) {
      _inflightCacheCalls.remove(key);
    }
  }

  Future<T> _performCachedCall<T>({
    required String functionIdentifier,
    required CachePolicy policy,
    required List<Object?> args,
    required String cacheKey,
    required Future<Map<String, Object?>> Function() loader,
    required T Function(Map<String, Object?> payload, bool cached) decoder,
  }) async {
    final CachedCallResult<Object?> first = await _cache
        .cachedCallWithStatus<Object?>(
          functionIdentifier: functionIdentifier,
          policy: policy,
          args: args,
          loader: loader,
        );
    try {
      return decoder(_requireMap(first.value, '缓存根对象'), first.cached);
    } catch (error, stackTrace) {
      if (!first.cached) {
        throw LddcApiRequestException(
          '歌词源返回的数据无法写入缓存模型',
          cause: error,
          stackTrace: stackTrace,
        );
      }
    }

    // 只删除当前损坏条目，其他搜索词或歌曲的有效缓存不应被连带清空。单飞表保证
    // 同一 LyricsApi 实例内只有一个修复请求，修复后最多回源一次，不使用递归重试。
    await _cache.remove(
      policy.namespace,
      cacheKey,
      cacheVersion: policy.cacheVersion,
    );
    final CachedCallResult<Object?> repaired = await _cache
        .cachedCallWithStatus<Object?>(
          functionIdentifier: functionIdentifier,
          policy: policy,
          args: args,
          loader: loader,
        );
    try {
      return decoder(_requireMap(repaired.value, '缓存根对象'), repaired.cached);
    } catch (error, stackTrace) {
      throw LddcApiRequestException(
        '歌词缓存数据结构异常',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<T> _retryRequest<T>(
    Future<T> Function() action, {
    RequestCancellationToken? cancellationToken,
  }) async {
    final RequestCancellationToken? token =
        cancellationToken ?? RequestCancellationToken.current;
    try {
      return await retryTimedOutRequest<T>(() async {
        token?.throwIfCancelled();
        final T value = await action();
        token?.throwIfCancelled();
        return value;
      }, maxAttempts: _requestBudget.retryCount);
    } on RequestCancelledException {
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      throw LddcApiRequestException(
        '请求超时: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Source? _resolveSource(Object? info) {
    return switch (info) {
      SongInfo value => value.source,
      LyricInfo value => value.source,
      _ => null,
    };
  }

  static Uint8List? _normalizeInputData(Object? data) {
    if (data == null) {
      return null;
    }
    if (data is Uint8List) {
      return Uint8List.fromList(data);
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    if (data is String) {
      return Uint8List.fromList(utf8.encode(data));
    }
    throw const LddcApiParamsException('无效的本地歌词数据类型');
  }

  static Map<String, Object?> _buildLyricsCacheIdentity(Object info) {
    if (info is LyricInfo) {
      // cached 只描述对象来自缓存还是网络，不属于远端歌词身份；把它放进 key 会让
      // 同一个候选在首次结果与缓存结果之间生成两个缓存条目。
      return info.toMap()..remove('cached');
    }
    if (info is SongInfo) {
      return info.toMap();
    }
    throw const LddcApiParamsException('info 类型必须为 SongInfo 或 LyricInfo');
  }

  Map<String, Object?> _encodeApiResultListBase<T extends SourceAware>({
    required APIResultList<T> result,
    required Map<String, Object?> Function(T item) encodeItem,
  }) {
    final Map<String, Object?> ranges = <String, Object?>{};
    result.sourceRanges.forEach((Source source, SourceRange range) {
      ranges[source.value] = range.toList();
    });
    return <String, Object?>{
      'ranges': ranges,
      'items': result
          .map<Map<String, Object?>>(encodeItem)
          .toList(growable: false),
      'info': _encodeInfo(result.info),
    };
  }

  APIResultList<T> _decodeApiResultListBase<T extends SourceAware>({
    required Map<String, Object?> payload,
    required T Function(Map<String, Object?> item) decodeItem,
  }) {
    final List<Object?> rawItems = _requireList(payload['items'], 'items');
    final List<T> items = rawItems
        .map((Object? item) => decodeItem(_requireMap(item, 'items[]')))
        .toList(growable: false);

    final Map<Source, SourceRange> ranges = <Source, SourceRange>{};
    final Map<String, Object?> rawRanges = _requireMap(
      payload['ranges'],
      'ranges',
    );
    rawRanges.forEach((String key, Object? value) {
      if (value is List<Object?>) {
        ranges[Source.fromValue(key)] = SourceRange.fromList(value);
        return;
      }
      throw ArgumentError.value(value, 'ranges[$key]', 'invalid range payload');
    });

    return APIResultList<T>(
      items,
      ranges: ranges,
      info: _decodeInfo(payload['info']),
    );
  }

  Map<String, Object?> _encodeSourceAwareItem(SourceAware item) {
    if (item is SongInfo) {
      return <String, Object?>{'kind': 'song_info', 'value': item.toMap()};
    }
    if (item is SongListInfo) {
      return <String, Object?>{'kind': 'song_list_info', 'value': item.toMap()};
    }
    if (item is LyricInfo) {
      return <String, Object?>{'kind': 'lyric_info', 'value': item.toMap()};
    }
    throw ArgumentError.value(item, 'item', '不支持的搜索结果类型');
  }

  SourceAware _decodeSourceAwareItem(Map<String, Object?> payload) {
    final String kind = payload['kind']?.toString() ?? '';
    final Map<String, Object?> value = _requireMap(
      payload['value'],
      '搜索结果 value',
    );
    switch (kind) {
      case 'song_info':
        return SongInfo.fromMap(value);
      case 'song_list_info':
        return SongListInfo.fromMap(value);
      case 'lyric_info':
        return LyricInfo.fromMap(value);
      default:
        throw ArgumentError.value(kind, 'kind', '不支持的搜索结果类型');
    }
  }

  Map<String, Object?> _encodeSourceAwareResult(
    APIResultList<SourceAware> result,
  ) {
    return _encodeApiResultListBase<SourceAware>(
      result: result,
      encodeItem: _encodeSourceAwareItem,
    );
  }

  APIResultList<SourceAware> _decodeSourceAwareResult(
    Map<String, Object?> payload,
  ) {
    return _decodeApiResultListBase<SourceAware>(
      payload: payload,
      decodeItem: _decodeSourceAwareItem,
    );
  }

  Map<String, Object?> _encodeSongInfoResult(APIResultList<SongInfo> result) {
    return _encodeApiResultListBase<SongInfo>(
      result: result,
      encodeItem: (SongInfo item) => item.toMap(),
    );
  }

  APIResultList<SongInfo> _decodeSongInfoResult(Map<String, Object?> payload) {
    return _decodeApiResultListBase<SongInfo>(
      payload: payload,
      decodeItem: SongInfo.fromMap,
    );
  }

  Map<String, Object?> _encodeLyricInfoResult(APIResultList<LyricInfo> result) {
    return _encodeApiResultListBase<LyricInfo>(
      result: result,
      encodeItem: (LyricInfo item) => item.toMap(),
    );
  }

  APIResultList<LyricInfo> _decodeLyricInfoResult(
    Map<String, Object?> payload,
  ) {
    return _decodeApiResultListBase<LyricInfo>(
      payload: payload,
      decodeItem: LyricInfo.fromMap,
    );
  }

  Object? _encodeInfo(Object? info) {
    if (info == null) {
      return null;
    }
    if (info is SearchInfo) {
      return <String, Object?>{'kind': 'search_info', 'value': info.toMap()};
    }
    if (info is SongListInfo) {
      return <String, Object?>{'kind': 'song_list_info', 'value': info.toMap()};
    }
    if (info is SongInfo) {
      return <String, Object?>{'kind': 'song_info', 'value': info.toMap()};
    }
    if (info is LyricInfo) {
      return <String, Object?>{'kind': 'lyric_info', 'value': info.toMap()};
    }
    return <String, Object?>{'kind': 'raw', 'value': info.toString()};
  }

  Object? _decodeInfo(Object? payload) {
    if (payload == null) {
      return null;
    }
    final Map<String, Object?> map = _requireMap(payload, 'info');
    final String kind = map['kind']?.toString() ?? '';
    switch (kind) {
      case 'search_info':
        return SearchInfo.fromMap(_requireMap(map['value'], 'info.value'));
      case 'song_list_info':
        return SongListInfo.fromMap(_requireMap(map['value'], 'info.value'));
      case 'song_info':
        return SongInfo.fromMap(_requireMap(map['value'], 'info.value'));
      case 'lyric_info':
        return LyricInfo.fromMap(_requireMap(map['value'], 'info.value'));
      case 'raw':
        return map['value']?.toString();
      default:
        throw FormatException('不支持的 info 类型: $kind');
    }
  }

  Map<String, Object?> _encodeLyrics(Lyrics lyrics) {
    return <String, Object?>{
      'songInfo': lyrics.songInfo.toMap(),
      'source': lyrics.source.value,
      'data': _encodeLyricsData(lyrics.data),
      'types': lyrics.types.map(
        (String key, LyricsType value) =>
            MapEntry<String, Object?>(key, value.value),
      ),
      'tags': Map<String, Object?>.from(lyrics.tags),
      'id': lyrics.id,
      'accessKey': lyrics.accessKey,
      'durationMs': lyrics.durationMs,
      'creator': lyrics.creator,
      'score': lyrics.score,
      'path': lyrics.path,
    };
  }

  Lyrics _decodeLyrics(Map<String, Object?> payload) {
    final Map<String, Object?> rawData = _requireMap(payload['data'], 'data');
    final Map<String, LyricsData> data = <String, LyricsData>{};
    rawData.forEach((String lang, Object? value) {
      final List<Object?> lines = _requireList(value, 'data.$lang');
      data[lang] = lines.map(_decodeLyricsLine).toList(growable: false);
    });

    final Map<String, LyricsType> types = <String, LyricsType>{};
    final Map<String, Object?> rawTypes = _requireMap(
      payload['types'],
      'types',
    );
    rawTypes.forEach((String lang, Object? value) {
      types[lang] = LyricsType.fromValue(value);
    });

    final Map<String, String> tags = <String, String>{};
    final Map<String, Object?> rawTags = _requireMap(payload['tags'], 'tags');
    rawTags.forEach((String key, Object? value) {
      tags[key] = value?.toString() ?? '';
    });

    final Object? source = payload['source'];
    if (source == null) {
      throw const FormatException('source 字段缺失');
    }
    return Lyrics(
      songInfo: SongInfo.fromMap(_requireMap(payload['songInfo'], 'songInfo')),
      source: Source.fromValue(source),
      data: data,
      types: types,
      tags: tags,
      id: payload['id']?.toString(),
      accessKey: payload['accessKey']?.toString(),
      durationMs: _parseInt(payload['durationMs']),
      creator: payload['creator']?.toString(),
      score: _parseInt(payload['score']),
      path: payload['path']?.toString(),
    );
  }

  Map<String, Object?> _encodeLyricsData(Map<String, LyricsData> data) {
    final Map<String, Object?> encoded = <String, Object?>{};
    data.forEach((String key, LyricsData lines) {
      encoded[key] = lines
          .map<Map<String, Object?>>(
            (LyricsLine line) => _encodeLyricsLine(line),
          )
          .toList(growable: false);
    });
    return encoded;
  }

  Map<String, Object?> _encodeLyricsLine(LyricsLine line) {
    return <String, Object?>{
      'startMs': line.startMs,
      'endMs': line.endMs,
      'words': line.words
          .map<Map<String, Object?>>(
            (LyricsWord word) => <String, Object?>{
              'startMs': word.startMs,
              'endMs': word.endMs,
              'text': word.text,
            },
          )
          .toList(growable: false),
    };
  }

  LyricsLine _decodeLyricsLine(Object? payload) {
    final Map<String, Object?> map = _requireMap(payload, '歌词行');
    final List<Object?> wordsRaw = _requireList(map['words'], '歌词行 words');
    final List<LyricsWord> words = wordsRaw
        .map((Object? item) {
          final Map<String, Object?> word = _requireMap(item, '歌词字');
          return LyricsWord(
            startMs: _parseInt(word['startMs']),
            endMs: _parseInt(word['endMs']),
            text: word['text']?.toString() ?? '',
          );
        })
        .toList(growable: false);
    return LyricsLine(
      startMs: _parseInt(map['startMs']),
      endMs: _parseInt(map['endMs']),
      words: words,
    );
  }

  static Map<String, Object?> _requireMap(Object? value, String field) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      final Map<String, Object?> normalized = <String, Object?>{};
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final Object? key = entry.key;
        if (key is! String) {
          throw FormatException('$field 包含非字符串键');
        }
        normalized[key] = entry.value;
      }
      return normalized;
    }
    throw FormatException('$field 必须是对象');
  }

  static List<Object?> _requireList(Object? value, String field) {
    if (value is List<Object?>) {
      return value;
    }
    throw FormatException('$field 必须是数组');
  }

  static int? _parseInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

/// 同一缓存键的共享请求及其调用方所有权。
final class _SharedInflightCall {
  _SharedInflightCall({required this.future, required this.cancellationToken});

  final Future<Object?> future;
  final RequestCancellationToken cancellationToken;
  int waiterCount = 0;
  bool finished = false;
}
