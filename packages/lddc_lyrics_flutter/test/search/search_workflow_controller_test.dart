import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  test('公开能力契约可直接驱动搜索控制器，不依赖宿主 Provider', () async {
    final _FakeLyricsClient lyricsClient = _FakeLyricsClient();
    LyricsSavePersistencePort persistenceFactory(String _) =>
        _UnusedLyricsSavePersistence();
    final SearchWorkflowController controller = SearchWorkflowController(
      dependencies: SearchWorkflowDependencies(
        optionsResolver: () => SearchWorkflowOptions(
          defaultSaveDirectory: '',
          fileNameFormat: '%<artist> - %<title>',
          id3Version: Id3Version.v23,
          autoSelect: true,
          translationSource: TranslateSource.bing,
          searchSources: const <Source>[Source.lrclib],
          convertOptions: LyricsConvertOptions(),
          skipInstrumental: true,
        ),
        capabilities: const SearchWorkflowCapabilities(
          multiWindow: false,
          androidSafTreeAccess: false,
          audioTagWrite: false,
        ),
        lyricsApi: lyricsClient,
        translateApi: const _FakeTranslationClient(),
        mediaGateway: _UnusedMediaGateway(),
        filePicker: _UnusedFilePicker(),
        dragDropPort: const UnsupportedDragDropPort(),
        androidSafTreePort: _UnusedAndroidSafTreePort(),
        batchSaveUseCase: SearchBatchSaveLyricsUseCase(
          lyricsApi: lyricsClient,
          persistenceFactory: persistenceFactory,
        ),
        androidSafBatchSaveUseCase: SearchAndroidSafBatchSaveLyricsUseCase(
          lyricsApi: lyricsClient,
          persistenceFactory: persistenceFactory,
        ),
        fileSavePersistenceFactory: persistenceFactory,
        autoFetchUseCase: AutoFetchUseCase(
          gateway: _UnusedAutoFetchLyricsGateway(),
        ),
      ),
    );
    addTearDown(controller.dispose);

    final List<SearchWorkflowState> states = <SearchWorkflowState>[];
    final subscription = controller.states.listen(states.add);
    addTearDown(subscription.cancel);

    controller.setKeyword('independent package');
    await controller.search();

    expect(lyricsClient.searchCalls, 1);
    expect(lyricsClient.lastSource, Source.lrclib);
    expect(controller.state.tableState, isA<AsyncSuccess<List<SourceAware>>>());
    expect(controller.state.currentPathResult?.single, isA<SongInfo>());
    expect(
      states.any((SearchWorkflowState state) => state.hasSubmittedSearch),
      isTrue,
    );
    expect(controller.diagnostics.searchBatchStartedCount, 1);
    expect(controller.diagnostics.searchBatchSettledCount, 1);
    expect(controller.diagnostics.sourceRequestStartedCount, 1);
    expect(controller.diagnostics.sourceRequestSettledCount, 1);

    // dispose 必须幂等，外部消费者无需了解 ChangeNotifier 的内部订阅。
    controller.dispose();
    controller.dispose();
  });

  test('部分来源失败会保留结构化详情，且只重试失败来源', () async {
    bool failKgOnce = true;
    final _ScriptedLyricsClient lyricsClient = _ScriptedLyricsClient(
      responder:
          (
            Source source,
            String keyword,
            SearchType searchType,
            int page,
            RequestCancellationToken? cancellationToken,
          ) async {
            if (source == Source.kg && failKgOnce) {
              failKgOnce = false;
              throw const LddcApiRequestException('KG 暂时不可用');
            }
            return _searchResult(
              source: source,
              keyword: keyword,
              searchType: searchType,
              page: page,
            );
          },
    );
    final SearchWorkflowController controller = _createController(
      lyricsClient,
      searchSources: const <Source>[Source.qm, Source.kg],
    );
    addTearDown(controller.dispose);

    controller.setKeyword('partial');
    await controller.search();

    expect(controller.state.tableState, isA<AsyncPartial<List<SourceAware>>>());
    expect(controller.state.sourceFailures, hasLength(1));
    expect(controller.state.sourceFailures.single.source, Source.kg);
    expect(
      controller.state.sourceFailures.single.kind,
      SearchSourceFailureKind.request,
    );
    expect(
      controller.state.notice?.code,
      SearchNoticeCode.searchPartialSourcesFailed,
    );

    await controller.retryFailedSources();

    expect(
      lyricsClient.calls.where((_SearchCall call) => call.source == Source.qm),
      hasLength(1),
    );
    expect(
      lyricsClient.calls.where((_SearchCall call) => call.source == Source.kg),
      hasLength(2),
    );
    expect(controller.state.sourceFailures, isEmpty);
    expect(controller.state.tableState, isA<AsyncSuccess<List<SourceAware>>>());
  });

  test('快速外部预设只执行活动批次和最后一个 pending 批次', () async {
    final _ScriptedLyricsClient lyricsClient = _ScriptedLyricsClient(
      responder:
          (
            Source source,
            String keyword,
            SearchType searchType,
            int page,
            RequestCancellationToken? cancellationToken,
          ) async {
            if (keyword == 'active') {
              // 活动请求必须等到令牌取消后才结束，用来证明控制器不会在旧 Future
              // 释放前启动新批次，也不会让连续 preset 形成无界并发。
              await cancellationToken!.whenCancelled;
              cancellationToken.throwIfCancelled();
            }
            return _searchResult(
              source: source,
              keyword: keyword,
              searchType: searchType,
              page: page,
            );
          },
    );
    final SearchWorkflowController controller = _createController(
      lyricsClient,
      searchSources: const <Source>[Source.qm],
    );
    addTearDown(controller.dispose);

    final List<Future<void>> requests = <Future<void>>[
      controller.applyExternalPreset(keyword: 'active', triggerSearch: true),
    ];
    await _waitUntil(() => lyricsClient.calls.isNotEmpty);

    for (int index = 1; index <= 19; index += 1) {
      requests.add(
        controller.applyExternalPreset(
          keyword: 'pending-$index',
          triggerSearch: true,
        ),
      );
    }
    await Future.wait(requests);

    expect(lyricsClient.calls.map((_SearchCall call) => call.keyword), <String>[
      'active',
      'pending-19',
    ]);
    expect(lyricsClient.maxActiveCalls, 1);
    expect(controller.state.keyword, 'pending-19');
    expect(controller.state.isSearching, isFalse);
  });

  test('dispose 会取消 debounce、pending 和活动搜索且不再启动请求', () async {
    final _ScriptedLyricsClient debounceClient = _ScriptedLyricsClient();
    final SearchWorkflowController debounceController = _createController(
      debounceClient,
      searchSources: const <Source>[Source.qm],
    );
    final Future<void> pendingPreset = debounceController.applyExternalPreset(
      keyword: 'dispose-before-debounce',
      triggerSearch: true,
    );

    debounceController.dispose();
    await pendingPreset;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(debounceClient.calls, isEmpty);

    final _ScriptedLyricsClient activeClient = _ScriptedLyricsClient(
      responder:
          (
            Source source,
            String keyword,
            SearchType searchType,
            int page,
            RequestCancellationToken? cancellationToken,
          ) async {
            await cancellationToken!.whenCancelled;
            cancellationToken.throwIfCancelled();
            throw StateError('取消后不应继续执行');
          },
    );
    final SearchWorkflowController activeController = _createController(
      activeClient,
      searchSources: const <Source>[Source.qm],
    );
    final Future<void> activePreset = activeController.applyExternalPreset(
      keyword: 'dispose-active',
      triggerSearch: true,
    );
    await _waitUntil(() => activeClient.calls.isNotEmpty);

    activeController.dispose();
    await activePreset;
    expect(activeClient.activeCalls, 0);
    expect(activeClient.calls, hasLength(1));
  });

  test('迟到的旧 preset 歌词不能覆盖最新外部歌词', () async {
    final Completer<void> oldSearchGate = Completer<void>();
    final _ScriptedLyricsClient lyricsClient = _ScriptedLyricsClient(
      responder:
          (
            Source source,
            String keyword,
            SearchType searchType,
            int page,
            RequestCancellationToken? cancellationToken,
          ) async {
            if (keyword == 'old') {
              await oldSearchGate.future;
            }
            return _searchResult(
              source: source,
              keyword: keyword,
              searchType: searchType,
              page: page,
            );
          },
    );
    final SearchWorkflowController controller = _createController(
      lyricsClient,
      searchSources: const <Source>[Source.qm],
    );
    addTearDown(controller.dispose);
    final Lyrics oldLyrics = _lyrics('old lyrics');
    final Lyrics latestLyrics = _lyrics('latest lyrics');

    final Future<void> oldPreset = controller.applyExternalPreset(
      keyword: 'old',
      lyrics: oldLyrics,
      triggerSearch: true,
    );
    await _waitUntil(() => lyricsClient.calls.isNotEmpty);
    await controller.applyExternalPreset(
      keyword: 'latest',
      lyrics: latestLyrics,
    );
    oldSearchGate.complete();
    await oldPreset;

    expect(controller.state.currentLyrics, same(latestLyrics));
    expect(controller.state.keyword, 'latest');
  });

  test('关键词使搜索 epoch 失效后仍会清除 searching 并保留已发布结果', () async {
    final Completer<void> slowSource = Completer<void>();
    final _ScriptedLyricsClient lyricsClient = _ScriptedLyricsClient(
      responder:
          (
            Source source,
            String keyword,
            SearchType searchType,
            int page,
            RequestCancellationToken? cancellationToken,
          ) async {
            if (source == Source.kg) {
              await slowSource.future;
            }
            return _searchResult(
              source: source,
              keyword: keyword,
              searchType: searchType,
              page: page,
              total: 1,
            );
          },
    );
    final SearchWorkflowController controller = _createController(
      lyricsClient,
      searchSources: const <Source>[Source.qm, Source.kg],
    );
    addTearDown(controller.dispose);
    controller.setKeyword('old keyword');

    final Future<void> search = controller.search();
    await _waitUntil(
      () => controller.state.tableState is AsyncPartial<List<SourceAware>>,
    );
    controller.setKeyword('new keyword');
    slowSource.complete();
    await search;

    expect(controller.state.keyword, 'new keyword');
    expect(controller.state.isSearching, isFalse);
    expect(controller.state.tableState, isA<AsyncSuccess<List<SourceAware>>>());
    expect(controller.diagnostics.isIdle, isTrue);
  });

  test('已取消搜索后同关键词 refresh 不会留下 searching 状态', () async {
    final _ScriptedLyricsClient lyricsClient = _ScriptedLyricsClient(
      responder:
          (
            Source source,
            String keyword,
            SearchType searchType,
            int page,
            RequestCancellationToken? cancellationToken,
          ) async => _searchResult(
            source: source,
            keyword: keyword,
            searchType: searchType,
            page: page,
            total: 1,
          ),
    );
    final SearchWorkflowController controller = _createController(
      lyricsClient,
      searchSources: const <Source>[Source.qm],
    );
    addTearDown(controller.dispose);

    // 模拟窗口 refresh：同一关键词只更新外部上下文，不启动第二个搜索。
    controller.state = controller.state.copyWith(
      keyword: 'same keyword',
      isSearching: true,
      tableState: const AsyncLoading<List<SourceAware>>(
        message: SearchTableStatusMessageCode.searching,
      ),
    );
    await controller.applyExternalPreset(
      keyword: 'same keyword',
      offsetMs: 20,
      triggerSearch: false,
    );

    expect(controller.state.isSearching, isFalse);
    expect(lyricsClient.calls, isEmpty);
  });

  test('首屏和分页逐源发布时冻结下一页并保持来源范围连续', () async {
    final Completer<void> slowFirstPage = Completer<void>();
    final Completer<void> slowSecondPage = Completer<void>();
    final _ScriptedLyricsClient lyricsClient = _ScriptedLyricsClient(
      responder:
          (
            Source source,
            String keyword,
            SearchType searchType,
            int page,
            RequestCancellationToken? cancellationToken,
          ) async {
            if (source == Source.kg && page == 1) {
              await slowFirstPage.future;
            }
            if (source == Source.kg && page == 2) {
              await slowSecondPage.future;
            }
            return _searchResult(
              source: source,
              keyword: keyword,
              searchType: searchType,
              page: page,
              total: 2,
            );
          },
    );
    final SearchWorkflowController controller = _createController(
      lyricsClient,
      searchSources: const <Source>[Source.qm, Source.kg],
    );
    addTearDown(controller.dispose);
    controller.setKeyword('paged');

    final Future<void> firstPage = controller.search();
    await _waitUntil(
      () =>
          controller.state.tableState is AsyncPartial<List<SourceAware>> &&
          controller.state.currentPathResult?.length == 1,
    );
    expect(controller.state.isSearching, isTrue);
    expect(controller.state.canLoadMore, isFalse);
    await controller.loadMore();
    expect(
      lyricsClient.calls.where((_SearchCall call) => call.page == 2),
      isEmpty,
    );

    slowFirstPage.complete();
    await firstPage;
    expect(controller.state.isSearching, isFalse);
    expect(controller.state.canLoadMore, isTrue);

    final Future<void> secondPage = controller.loadMore();
    await _waitUntil(
      () =>
          controller.state.isLoadingMore &&
          controller.state.currentPathResult?.length == 3,
    );
    expect(controller.state.canLoadMore, isFalse);
    await controller.loadMore();
    expect(
      lyricsClient.calls.where((_SearchCall call) => call.page == 2),
      hasLength(2),
    );

    slowSecondPage.complete();
    await secondPage;
    final APIResultList<SourceAware> result =
        controller.state.currentPathResult!;
    expect(result, hasLength(4));
    expect(result.more, isEmpty);
    expect(result.sourceRanges[Source.qm]?.toList(), <int>[0, 1, 2]);
    expect(result.sourceRanges[Source.kg]?.toList(), <int>[0, 1, 2]);
    expect(controller.state.isLoadingMore, isFalse);
    expect(controller.state.canLoadMore, isFalse);
  });

  test('加载更多失败后的失败源重试保持原分页，不重复请求成功来源', () async {
    bool failKgPageTwoOnce = true;
    final _ScriptedLyricsClient lyricsClient = _ScriptedLyricsClient(
      responder:
          (
            Source source,
            String keyword,
            SearchType searchType,
            int page,
            RequestCancellationToken? cancellationToken,
          ) async {
            if (source == Source.kg && page == 2 && failKgPageTwoOnce) {
              failKgPageTwoOnce = false;
              throw const LddcApiRequestException('KG 第二页暂时不可用');
            }
            return _searchResult(
              source: source,
              keyword: keyword,
              searchType: searchType,
              page: page,
              total: 2,
            );
          },
    );
    final SearchWorkflowController controller = _createController(
      lyricsClient,
      searchSources: const <Source>[Source.qm, Source.kg],
    );
    addTearDown(controller.dispose);
    controller.setKeyword('paged-retry');

    await controller.search();
    await controller.loadMore();

    expect(controller.state.sourceFailures, hasLength(1));
    expect(controller.state.sourceFailures.single.source, Source.kg);
    expect(
      controller.state.notice?.code,
      SearchNoticeCode.searchLoadMoreFailed,
    );
    expect(controller.state.currentPathResult, hasLength(3));

    await controller.retryFailedSources();

    expect(
      lyricsClient.calls
          .where(
            (_SearchCall call) => call.source == Source.qm && call.page == 2,
          )
          .length,
      1,
    );
    expect(
      lyricsClient.calls
          .where(
            (_SearchCall call) => call.source == Source.kg && call.page == 2,
          )
          .length,
      2,
    );
    expect(
      lyricsClient.calls.where((_SearchCall call) => call.page == 1).length,
      2,
    );
    expect(controller.state.sourceFailures, isEmpty);
    expect(controller.state.currentPathResult, hasLength(4));
    expect(controller.state.tableState, isA<AsyncSuccess<List<SourceAware>>>());
  });
}

typedef _SearchResponder =
    Future<APIResultList<SourceAware>> Function(
      Source source,
      String keyword,
      SearchType searchType,
      int page,
      RequestCancellationToken? cancellationToken,
    );

final class _SearchCall {
  const _SearchCall({
    required this.source,
    required this.keyword,
    required this.searchType,
    required this.page,
  });

  final Source source;
  final String keyword;
  final SearchType searchType;
  final int page;
}

final class _ScriptedLyricsClient extends Fake implements LyricsClient {
  _ScriptedLyricsClient({this.responder});

  final _SearchResponder? responder;
  final List<_SearchCall> calls = <_SearchCall>[];
  int activeCalls = 0;
  int maxActiveCalls = 0;

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    calls.add(
      _SearchCall(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: page,
      ),
    );
    activeCalls += 1;
    if (activeCalls > maxActiveCalls) {
      maxActiveCalls = activeCalls;
    }
    try {
      final _SearchResponder? responseBuilder = responder;
      if (responseBuilder != null) {
        return await responseBuilder(
          source,
          keyword,
          searchType,
          page,
          cancellationToken,
        );
      }
      return _searchResult(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: page,
      );
    } finally {
      activeCalls -= 1;
    }
  }
}

SearchWorkflowController _createController(
  LyricsClient lyricsClient, {
  required List<Source> searchSources,
}) {
  LyricsSavePersistencePort persistenceFactory(String _) =>
      _UnusedLyricsSavePersistence();
  return SearchWorkflowController(
    dependencies: SearchWorkflowDependencies(
      optionsResolver: () => SearchWorkflowOptions(
        defaultSaveDirectory: '',
        fileNameFormat: '%<artist> - %<title>',
        id3Version: Id3Version.v23,
        autoSelect: true,
        translationSource: TranslateSource.bing,
        searchSources: searchSources,
        convertOptions: LyricsConvertOptions(),
        skipInstrumental: true,
      ),
      capabilities: const SearchWorkflowCapabilities(
        multiWindow: false,
        androidSafTreeAccess: false,
        audioTagWrite: false,
      ),
      lyricsApi: lyricsClient,
      translateApi: const _FakeTranslationClient(),
      mediaGateway: _UnusedMediaGateway(),
      filePicker: _UnusedFilePicker(),
      dragDropPort: const UnsupportedDragDropPort(),
      androidSafTreePort: _UnusedAndroidSafTreePort(),
      batchSaveUseCase: SearchBatchSaveLyricsUseCase(
        lyricsApi: lyricsClient,
        persistenceFactory: persistenceFactory,
      ),
      androidSafBatchSaveUseCase: SearchAndroidSafBatchSaveLyricsUseCase(
        lyricsApi: lyricsClient,
        persistenceFactory: persistenceFactory,
      ),
      fileSavePersistenceFactory: persistenceFactory,
      autoFetchUseCase: AutoFetchUseCase(
        gateway: _UnusedAutoFetchLyricsGateway(),
      ),
    ),
  );
}

APIResultList<SourceAware> _searchResult({
  required Source source,
  required String keyword,
  required SearchType searchType,
  required int page,
  int total = 1,
}) {
  final int start = page - 1;
  return APIResultList<SourceAware>(
    <SourceAware>[
      SongInfo(
        source: source,
        id: '${source.value}-$page',
        title: '${source.value} result $page',
      ),
    ],
    info: SearchInfo(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    ),
    ranges: <Source, SourceRange>{
      source: SourceRange(start: start, end: start, total: total),
    },
  );
}

Lyrics _lyrics(String text) {
  final SongInfo song = SongInfo(source: Source.qm, id: text, title: text);
  return Lyrics(
    songInfo: song,
    source: Source.qm,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 1000, text: text)],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed > const Duration(seconds: 2)) {
      throw TimeoutException('等待测试状态超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

final class _FakeLyricsClient implements LyricsClient {
  int searchCalls = 0;
  Source? lastSource;

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    searchCalls += 1;
    lastSource = source;
    return APIResultList<SourceAware>(
      <SourceAware>[
        SongInfo(source: source, id: 'result-1', title: 'Package Result'),
      ],
      info: SearchInfo(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: page,
      ),
      ranges: <Source, SourceRange>{
        source: const SourceRange(start: 0, end: 0, total: 1),
      },
    );
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) {
    throw UnsupportedError('本测试不会获取歌词');
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) {
    throw UnsupportedError('本测试不会获取歌词候选');
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) {
    throw UnsupportedError('本测试不会获取歌单');
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) {
    throw UnsupportedError('本测试不会解析歌曲歌词');
  }
}

final class _FakeTranslationClient implements TranslationClient {
  const _FakeTranslationClient();

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {}

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) {
    throw UnsupportedError('本测试不会翻译歌词');
  }
}

final class _UnusedMediaGateway extends Fake
    implements LocalMatchMediaGateway {}

final class _UnusedFilePicker extends Fake implements AppFilePicker {}

final class _UnusedAndroidSafTreePort extends Fake
    implements AndroidSafTreePort {}

final class _UnusedLyricsSavePersistence extends Fake
    implements LyricsSavePersistencePort {}

final class _UnusedAutoFetchLyricsGateway extends Fake
    implements AutoFetchLyricsGateway {}
