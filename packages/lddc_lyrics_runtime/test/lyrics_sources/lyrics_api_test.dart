import 'dart:async';

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('LyricsApi', () {
    test('registry 批量注册原子提交，并拒绝覆盖已有 provider', () async {
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final _FakeCloudProvider qm = _FakeCloudProvider(source: Source.qm);
      final _FakeCloudProvider ne = _FakeCloudProvider(source: Source.ne);
      final _FakeCloudProvider duplicateQm = _FakeCloudProvider(
        source: Source.qm,
      );
      final _FakeLocalProvider local = _FakeLocalProvider();
      final _FakeLocalProvider duplicateLocal = _FakeLocalProvider();
      registry.registerCloudProvider(qm);
      registry.registerLocalProvider(local);

      expect(
        () => registry.registerCloudProviders(<LyricsCloudSourceProvider>[
          ne,
          duplicateQm,
        ]),
        throwsA(isA<LddcApiParamsException>()),
      );
      expect(
        () => registry.registerLocalProvider(duplicateLocal),
        throwsA(isA<LddcApiParamsException>()),
      );

      expect(registry.requireCloudProvider(Source.qm), same(qm));
      expect(registry.hasCloudProvider(Source.ne), isFalse);
      expect(registry.localProvider, same(local));
      await registry.close();
      expect(qm.closeCalls, 1);
      expect(ne.closeCalls, 0);
      expect(duplicateQm.closeCalls, 0);
      expect(local.closeCalls, 1);
      expect(duplicateLocal.closeCalls, 0);
    });

    test('registry.close 同步摘除资源、并发幂等并拒绝关闭后注册', () async {
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final Completer<void> closeGate = Completer<void>();
      final _FakeCloudProvider cloud = _FakeCloudProvider(
        source: Source.qm,
        closeGate: closeGate,
      );
      final _FakeLocalProvider local = _FakeLocalProvider();
      registry.registerCloudProvider(cloud);
      registry.registerLocalProvider(local);

      final Future<void> firstClose = registry.close();
      final Future<void> secondClose = registry.close();

      expect(secondClose, same(firstClose));
      expect(registry.cloudProviders, isEmpty);
      expect(registry.localProvider, isNull);
      expect(
        () => registry.registerCloudProvider(
          _FakeCloudProvider(source: Source.ne),
        ),
        throwsStateError,
      );
      closeGate.complete();
      await Future.wait(<Future<void>>[firstClose, secondClose]);
      expect(cloud.closeCalls, 1);
      expect(local.closeCalls, 1);
    });

    test('registry.close 隔离单个关闭失败并继续释放其余资源', () async {
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final _FakeCloudProvider failed = _FakeCloudProvider(
        source: Source.qm,
        closeError: StateError('close failed'),
      );
      final _FakeCloudProvider healthy = _FakeCloudProvider(source: Source.ne);
      registry.registerCloudProviders(<LyricsCloudSourceProvider>[
        failed,
        healthy,
      ]);

      await expectLater(registry.close(), throwsStateError);

      expect(failed.closeCalls, 1);
      expect(healthy.closeCalls, 1);
      expect(registry.cloudProviders, isEmpty);
    });

    test('本地歌词不依赖缓存数据库初始化', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(
          executorFactory: () async => throw StateError('cache unavailable'),
        ),
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry()
        ..registerLocalProvider(_FakeLocalProvider());
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);

      final Lyrics lyrics = await api.getLyrics(data: '[00:00.00]local');

      expect(lyrics.source, Source.local);
      await registry.close();
      await cache.dispose();
    });

    test('云端请求只重试超时，非超时错误直接保留', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final _FakeCloudProvider timeoutThenSuccess = _FakeCloudProvider(
        source: Source.qm,
        searchTimeoutsBeforeSuccess: 2,
      );
      final _FakeCloudProvider failed = _FakeCloudProvider(
        source: Source.ne,
        searchError: StateError('boom'),
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry()
        ..registerCloudProviders(<LyricsCloudSourceProvider>[
          timeoutThenSuccess,
          failed,
        ]);
      final LyricsApi api = LyricsApi(
        registry: registry,
        cache: cache,
        requestBudget: const NetworkRequestBudget(
          timeout: Duration(seconds: 1),
          retryCount: 3,
        ),
      );

      final APIResultList<SourceAware> result = await api.search(
        source: Source.qm,
        keyword: 'retry',
        searchType: SearchType.song,
      );
      expect(result, hasLength(1));
      expect(timeoutThenSuccess.searchCalls, 3);
      await expectLater(
        () => api.search(
          source: Source.ne,
          keyword: 'failed',
          searchType: SearchType.song,
        ),
        throwsStateError,
      );
      expect(failed.searchCalls, 1);
      await registry.close();
      await cache.dispose();
    });

    test('search/getSonglist/getLyricslist 命中缓存后 cached=true', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final _FakeCloudProvider cloud = _FakeCloudProvider(source: Source.qm);
      final _FakeLocalProvider local = _FakeLocalProvider();
      registry.registerCloudProvider(cloud);
      registry.registerLocalProvider(local);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);

      final APIResultList<SourceAware> searchFirst = await api.search(
        source: Source.qm,
        keyword: 'abc',
        searchType: SearchType.song,
        page: 1,
      );
      final APIResultList<SourceAware> searchSecond = await api.search(
        source: Source.qm,
        keyword: 'abc',
        searchType: SearchType.song,
        page: 1,
      );
      expect(searchFirst.cached, isFalse);
      expect(searchSecond.cached, isTrue);
      expect(cloud.searchCalls, 1);

      const SongListInfo songListInfo = SongListInfo(
        source: Source.qm,
        type: SongListType.album,
        id: 'album-id',
        title: 'album',
        imgUrl: '',
        songCount: 1,
        publishTimeS: null,
        author: '',
      );
      final APIResultList<SongInfo> songlistFirst = await api.getSonglist(
        songListInfo,
      );
      final APIResultList<SongInfo> songlistSecond = await api.getSonglist(
        songListInfo,
      );
      expect(songlistFirst.cached, isFalse);
      expect(songlistSecond.cached, isTrue);
      expect(cloud.songlistCalls, 1);

      const SongInfo songInfo = SongInfo(
        source: Source.qm,
        id: 'song-id',
        title: 'song',
      );
      final APIResultList<LyricInfo> lyricslistFirst = await api.getLyricslist(
        songInfo,
      );
      final APIResultList<LyricInfo> lyricslistSecond = await api.getLyricslist(
        songInfo,
      );
      expect(lyricslistFirst.cached, isFalse);
      expect(lyricslistSecond.cached, isTrue);
      expect(cloud.lyricslistCalls, 1);
      await registry.close();
      await cache.dispose();
    });

    test('相同缓存键的并发请求复用同一个网络 Future', () async {
      final CacheFacade cache = CacheFacade(store: _InMemoryCacheStore());
      final Completer<void> searchStarted = Completer<void>();
      final Completer<void> searchGate = Completer<void>();
      final _FakeCloudProvider cloud = _FakeCloudProvider(
        source: Source.qm,
        searchStarted: searchStarted,
        searchGate: searchGate,
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry()
        ..registerCloudProvider(cloud);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);

      final Future<APIResultList<SourceAware>> first = api.search(
        source: Source.qm,
        keyword: 'same-key',
        searchType: SearchType.song,
      );
      final Future<APIResultList<SourceAware>> second = api.search(
        source: Source.qm,
        keyword: 'same-key',
        searchType: SearchType.song,
      );
      await searchStarted.future;

      expect(cloud.searchCalls, 1);
      searchGate.complete();
      final List<APIResultList<SourceAware>> results = await Future.wait(
        <Future<APIResultList<SourceAware>>>[first, second],
      );
      expect(
        results.every((APIResultList<SourceAware> item) => !item.cached),
        isTrue,
      );
      expect(cloud.searchCalls, 1);
      await registry.close();
      await cache.dispose();
    });

    test('取消一个缓存 waiter 不会中止仍在使用的共享请求', () async {
      final CacheFacade cache = CacheFacade(store: _InMemoryCacheStore());
      final Completer<void> searchStarted = Completer<void>();
      final Completer<void> searchGate = Completer<void>();
      final _FakeCloudProvider cloud = _FakeCloudProvider(
        source: Source.qm,
        searchStarted: searchStarted,
        searchGate: searchGate,
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry()
        ..registerCloudProvider(cloud);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);
      final RequestCancellationToken firstToken = RequestCancellationToken();
      final RequestCancellationToken secondToken = RequestCancellationToken();

      final Future<APIResultList<SourceAware>> first = api.search(
        source: Source.qm,
        keyword: 'shared-cancel',
        searchType: SearchType.song,
        cancellationToken: firstToken,
      );
      final Future<APIResultList<SourceAware>> second = api.search(
        source: Source.qm,
        keyword: 'shared-cancel',
        searchType: SearchType.song,
        cancellationToken: secondToken,
      );
      await searchStarted.future;
      firstToken.cancel();

      await expectLater(first, throwsA(isA<RequestCancelledException>()));
      expect(cloud.searchCalls, 1);
      searchGate.complete();
      await second;

      firstToken.dispose();
      secondToken.dispose();
      await registry.close();
      await cache.dispose();
    });

    test('损坏缓存只修复当前条目，并支持原始字符串 info', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final _FakeCloudProvider cloud = _FakeCloudProvider(
        source: Source.qm,
        searchInfo: 'opaque-info',
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry()
        ..registerCloudProvider(cloud);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);
      final String damagedKey = CacheFacade.buildCacheKey(
        functionIdentifier: 'LDDC.core.api.lyrics.search',
        args: <Object?>[Source.qm.value, 'damaged', SearchType.song.value, 1],
      );
      const String retainedKey = 'retained-entry';
      await cache.set('lyrics_api.search', damagedKey, <String, Object?>{
        'ranges': <String, Object?>{},
        'items': 'not-a-list',
        'info': null,
      });
      await cache.set('lyrics_api.search', retainedKey, <String, Object?>{
        'sentinel': true,
      });

      final APIResultList<SourceAware> result = await api.search(
        source: Source.qm,
        keyword: 'damaged',
        searchType: SearchType.song,
      );

      expect(result.cached, isFalse);
      expect(result.info, 'opaque-info');
      expect(cloud.searchCalls, 1);
      expect(
        await cache.get('lyrics_api.search', retainedKey),
        <String, Object?>{'sentinel': true},
      );
      await registry.close();
      await cache.dispose();
    });

    test('getLyrics 参数校验、本地不缓存、云端缓存与未找到分支', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final _FakeCloudProvider qm = _FakeCloudProvider(source: Source.qm);
      final _FakeCloudProvider ne = _FakeCloudProvider(
        source: Source.ne,
        returnEmptyLyrics: true,
      );
      final _FakeLocalProvider local = _FakeLocalProvider();
      registry.registerCloudProviders(<LyricsCloudSourceProvider>[qm, ne]);
      registry.registerLocalProvider(local);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);

      await expectLater(
        () => api.getLyrics(),
        throwsA(isA<LddcApiParamsException>()),
      );

      final Lyrics localFirst = await api.getLyrics(
        path: 'C:/demo.lrc',
        data: '[00:00.00]hi',
      );
      final Lyrics localSecond = await api.getLyrics(
        path: 'C:/demo.lrc',
        data: '[00:00.00]hi',
      );
      expect(localFirst.cached, isFalse);
      expect(localSecond.cached, isFalse);
      expect(local.calls, 2);

      const SongInfo qmSong = SongInfo(source: Source.qm, id: 'q1', title: 'q');
      final Lyrics cloudFirst = await api.getLyrics(info: qmSong);
      final Lyrics cloudSecond = await api.getLyrics(info: qmSong);
      expect(cloudFirst.cached, isFalse);
      expect(cloudSecond.cached, isTrue);
      expect(qm.lyricsCalls, 1);

      const SongInfo neSong = SongInfo(source: Source.ne, id: 'n1', title: 'n');
      await expectLater(
        () => api.getLyrics(info: neSong),
        throwsA(isA<LddcLyricsNotFoundException>()),
      );
      await expectLater(
        () => api.getLyrics(info: neSong),
        throwsA(isA<LddcLyricsNotFoundException>()),
      );
      expect(ne.lyricsCalls, 2);

      await registry.close();
      await cache.dispose();
    });

    test('LyricInfo 的 cached 展示状态不分裂歌词缓存键', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final _FakeCloudProvider cloud = _FakeCloudProvider(source: Source.qm);
      final LyricsSourceRegistry registry = LyricsSourceRegistry()
        ..registerCloudProvider(cloud);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);
      final LyricInfo info = LyricInfo(
        source: Source.qm,
        songInfo: const SongInfo(
          source: Source.qm,
          id: 'song-id',
          title: 'song',
        ),
        id: 'lyric-id',
        accessKey: 'access-key',
      );

      final Lyrics first = await api.getLyrics(info: info);
      final Lyrics second = await api.getLyrics(
        info: info.copyWith(cached: true),
      );

      expect(first.cached, isFalse);
      expect(second.cached, isTrue);
      expect(cloud.lyricsCalls, 1);
      await registry.close();
      await cache.dispose();
    });

    test('getLyricslist 对不支持候选列表的来源抛出 not supported', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final _FakeCloudProvider qm = _FakeCloudProvider(
        source: Source.qm,
        supportsLyricsList: false,
      );
      final _FakeLocalProvider local = _FakeLocalProvider();
      registry.registerCloudProvider(qm);
      registry.registerLocalProvider(local);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);

      await expectLater(
        () => api.getLyricslist(
          const SongInfo(source: Source.qm, id: 'song-1', title: 'song'),
        ),
        throwsA(isA<LddcApiNotSupportedException>()),
      );
      expect(qm.lyricslistCalls, 0);

      await registry.close();
      await cache.dispose();
    });

    test('resolveSongLyrics 在手动模式返回候选列表', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final _FakeCloudProvider kg = _FakeCloudProvider(
        source: Source.kg,
        supportsLyricsList: true,
      );
      final _FakeLocalProvider local = _FakeLocalProvider();
      registry.registerCloudProvider(kg);
      registry.registerLocalProvider(local);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);

      final LyricsResolveResult result = await api.resolveSongLyrics(
        songInfo: const SongInfo(source: Source.kg, id: 'song-kg', title: 'kg'),
        autoSelect: false,
      );

      expect(result, isA<LyricsSelectionRequiredResult>());
      final LyricsSelectionRequiredResult selection =
          result as LyricsSelectionRequiredResult;
      expect(selection.candidates.length, 1);
      expect(kg.lyricslistCalls, 1);
      expect(kg.lyricsCalls, 0);

      await registry.close();
      await cache.dispose();
    });

    test('resolveSongLyrics 在候选列表失败时自动降级到 getLyrics', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final _FakeCloudProvider kg = _FakeCloudProvider(
        source: Source.kg,
        supportsLyricsList: true,
        throwOnLyricsList: true,
      );
      final _FakeLocalProvider local = _FakeLocalProvider();
      registry.registerCloudProvider(kg);
      registry.registerLocalProvider(local);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);

      final LyricsResolveResult result = await api.resolveSongLyrics(
        songInfo: const SongInfo(source: Source.kg, id: 'song-kg', title: 'kg'),
        autoSelect: false,
      );

      expect(result, isA<LyricsResolvedResult>());
      final LyricsResolvedResult resolved = result as LyricsResolvedResult;
      expect(
        resolved.fallbackReason,
        LyricsResolveFallbackReason.lyricsListFailed,
      );
      expect(resolved.lyrics.source, Source.kg);
      expect(kg.lyricslistCalls, 1);
      expect(kg.lyricsCalls, 1);

      await registry.close();
      await cache.dispose();
    });

    test('resolveSongLyrics 在候选列表为空时自动降级到 getLyrics', () async {
      final CacheFacade cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      final LyricsSourceRegistry registry = LyricsSourceRegistry();
      final _FakeCloudProvider kg = _FakeCloudProvider(
        source: Source.kg,
        supportsLyricsList: true,
        returnEmptyLyricsList: true,
      );
      final _FakeLocalProvider local = _FakeLocalProvider();
      registry.registerCloudProvider(kg);
      registry.registerLocalProvider(local);
      final LyricsApi api = LyricsApi(registry: registry, cache: cache);

      final LyricsResolveResult result = await api.resolveSongLyrics(
        songInfo: const SongInfo(source: Source.kg, id: 'song-kg', title: 'kg'),
        autoSelect: false,
      );

      expect(result, isA<LyricsResolvedResult>());
      final LyricsResolvedResult resolved = result as LyricsResolvedResult;
      expect(
        resolved.fallbackReason,
        LyricsResolveFallbackReason.lyricsListEmpty,
      );
      expect(resolved.lyrics.source, Source.kg);
      expect(kg.lyricslistCalls, 1);
      expect(kg.lyricsCalls, 1);

      await registry.close();
      await cache.dispose();
    });
  });
}

class _FakeCloudProvider
    implements LyricsCloudSourceProvider, ClosableLyricsSourceProvider {
  _FakeCloudProvider({
    required this.source,
    this.supportsLyricsList = true,
    this.returnEmptyLyrics = false,
    this.returnEmptyLyricsList = false,
    this.throwOnLyricsList = false,
    this.searchTimeoutsBeforeSuccess = 0,
    this.searchError,
    this.searchInfo,
    this.searchStarted,
    this.searchGate,
    this.closeGate,
    this.closeError,
  });

  @override
  final Source source;
  @override
  final bool supportsLyricsList;
  final bool returnEmptyLyrics;
  final bool returnEmptyLyricsList;
  final bool throwOnLyricsList;
  final int searchTimeoutsBeforeSuccess;
  final Object? searchError;
  final Object? searchInfo;
  final Completer<void>? searchStarted;
  final Completer<void>? searchGate;
  final Completer<void>? closeGate;
  final Object? closeError;

  int searchCalls = 0;
  int songlistCalls = 0;
  int lyricslistCalls = 0;
  int lyricsCalls = 0;
  int closeCalls = 0;

  @override
  Set<SearchType> get supportedSearchTypes => source.supportedSearchTypes;

  @override
  Future<void> close() async {
    closeCalls += 1;
    final Completer<void>? gate = closeGate;
    if (gate != null) {
      await gate.future;
    }
    final Object? error = closeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<APIResultList<SourceAware>> search({
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    searchCalls += 1;
    final Completer<void>? started = searchStarted;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final Completer<void>? gate = searchGate;
    if (gate != null) {
      await gate.future;
    }
    if (searchCalls <= searchTimeoutsBeforeSuccess) {
      throw TimeoutException('timeout-$searchCalls');
    }
    final Object? error = searchError;
    if (error != null) {
      throw error;
    }
    return APIResultList<SourceAware>(
      <SourceAware>[
        SongInfo(source: source, id: '$keyword-$page', title: keyword),
      ],
      info:
          searchInfo ??
          SearchInfo(
            source: source,
            keyword: keyword,
            searchType: searchType,
            page: page,
          ),
      ranges: const SourceRange(start: 0, end: 0, total: 1),
    );
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    songlistCalls += 1;
    return APIResultList<SongInfo>(
      <SongInfo>[
        SongInfo(
          source: source,
          id: '${songListInfo.id}-song',
          title: 'song-from-list',
        ),
      ],
      info: songListInfo,
      ranges: const SourceRange(start: 0, end: 0, total: 1),
    );
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    lyricslistCalls += 1;
    if (throwOnLyricsList) {
      throw const LddcApiRequestException('候选歌词列表请求失败');
    }
    if (returnEmptyLyricsList) {
      return APIResultList<LyricInfo>(
        <LyricInfo>[],
        info: songInfo,
        ranges: const SourceRange(start: 0, end: -1, total: 0),
      );
    }
    return APIResultList<LyricInfo>(
      <LyricInfo>[
        LyricInfo(
          source: source,
          songInfo: songInfo,
          id: 'lyric-${songInfo.id ?? 'x'}',
          accessKey: 'ak',
        ),
      ],
      info: songInfo,
      ranges: const SourceRange(start: 0, end: 0, total: 1),
    );
  }

  @override
  Future<Lyrics> getLyrics(Object info) async {
    lyricsCalls += 1;
    final SongInfo songInfo = switch (info) {
      SongInfo value => value,
      LyricInfo value => value.songInfo,
      _ => SongInfo(source: source),
    };
    if (returnEmptyLyrics) {
      return Lyrics(songInfo: songInfo, source: source);
    }
    return Lyrics(
      songInfo: songInfo,
      source: source,
      data: <String, LyricsData>{
        'orig': <LyricsLine>[
          LyricsLine(
            startMs: 0,
            endMs: 1000,
            words: const <LyricsWord>[
              LyricsWord(startMs: 0, endMs: 1000, text: 'hello'),
            ],
          ),
        ],
      },
      types: const <String, LyricsType>{'orig': LyricsType.verbatim},
    );
  }
}

class _FakeLocalProvider
    implements LyricsLocalSourceProvider, ClosableLyricsSourceProvider {
  int calls = 0;
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  Future<Lyrics> getLyrics(LocalLyricsRequest request) async {
    calls += 1;
    final SongInfo songInfo =
        request.info?.songInfo ?? const SongInfo(source: Source.local);
    return Lyrics(
      songInfo: songInfo,
      source: Source.local,
      data: <String, LyricsData>{
        'orig': <LyricsLine>[
          LyricsLine(
            startMs: 0,
            endMs: 1000,
            words: const <LyricsWord>[
              LyricsWord(startMs: 0, endMs: 1000, text: 'local'),
            ],
          ),
        ],
      },
      types: const <String, LyricsType>{'orig': LyricsType.verbatim},
    );
  }
}

/// 不依赖 sqlite3 native asset 的最小缓存存储。
///
/// 这两个 single-flight 测试验证的是 LyricsApi 的 waiter 所有权，不是 SQLite
/// 事务。使用进程内实现可以把测试失败准确归因到请求共享逻辑，避免开发机缺少
/// native asset 时把 provider gate 误报成超时。
final class _InMemoryCacheStore implements CacheStore {
  final Map<String, CacheStoreEntry> _entries = <String, CacheStoreEntry>{};
  bool _disposed = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> ensureNamespaceVersion(
    String namespace,
    int cacheVersion,
  ) async {}

  @override
  Future<CacheStoreEntry?> getEntry(String namespace, String key) async {
    _checkOpen();
    final String composite = _key(namespace, key);
    final CacheStoreEntry? entry = _entries[composite];
    if (entry?.expiresAtMs != null &&
        entry!.expiresAtMs! <= DateTime.now().millisecondsSinceEpoch) {
      _entries.remove(composite);
      return null;
    }
    return entry;
  }

  @override
  Future<Object?> get(String namespace, String key) async {
    return (await getEntry(namespace, key))?.value;
  }

  @override
  Future<void> set(
    String namespace,
    String key,
    Object? value, {
    Duration? ttl,
  }) async {
    _checkOpen();
    _entries[_key(namespace, key)] = CacheStoreEntry(
      value: value,
      expiresAtMs: _expiresAt(ttl),
    );
  }

  @override
  Future<Object?> updateAtomically(
    String namespace,
    String key,
    Object? Function(Object? current) update, {
    Duration? ttl,
  }) async {
    final Object? value = update((await getEntry(namespace, key))?.value);
    await set(namespace, key, value, ttl: ttl);
    return value;
  }

  @override
  Future<void> remove(String namespace, String key) async {
    _checkOpen();
    _entries.remove(_key(namespace, key));
  }

  @override
  Future<void> clearNamespace(String namespace) async {
    _checkOpen();
    _entries.removeWhere((String key, CacheStoreEntry _) {
      return key.startsWith('$namespace\u0000');
    });
  }

  @override
  Future<void> clearAll() async {
    _checkOpen();
    _entries.clear();
  }

  @override
  Future<CacheStats> stats({String? namespace}) async {
    final int count = namespace == null
        ? _entries.length
        : _entries.keys
              .where((String key) => key.startsWith('$namespace\u0000'))
              .length;
    return CacheStats(
      namespace: namespace,
      entryCount: count,
      sizeBytes: 0,
      hits: 0,
      misses: 0,
      writes: count,
      removals: 0,
      expired: 0,
      versionResets: 0,
    );
  }

  @override
  Stream<CacheStats> watchStats({String? namespace, bool emitCurrent = true}) {
    if (!emitCurrent) {
      return const Stream<CacheStats>.empty();
    }
    return Stream<CacheStats>.fromFuture(stats(namespace: namespace));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _entries.clear();
  }

  void _checkOpen() {
    if (_disposed) {
      throw StateError('测试缓存已释放');
    }
  }

  static String _key(String namespace, String key) => '$namespace\u0000$key';

  static int? _expiresAt(Duration? ttl) {
    if (ttl == null) {
      return null;
    }
    return DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds;
  }
}
