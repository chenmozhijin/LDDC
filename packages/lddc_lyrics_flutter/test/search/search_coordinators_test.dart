import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_flutter/src/search/search_preview_coordinator.dart';
import 'package:lddc_lyrics_flutter/src/search/search_query_coordinator.dart';
import 'package:lddc_lyrics_flutter/src/search/search_save_coordinator.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  group('SearchQueryCoordinator', () {
    test('按搜索类型过滤聚合来源并去重', () {
      final SearchQueryCoordinator coordinator = SearchQueryCoordinator(
        lyricsClient: _RecordingLyricsClient(),
      );

      final List<Source> sources = coordinator.resolveSources(
        selectedSource: Source.multi,
        searchType: SearchType.album,
        configuredSources: const <Source>[
          Source.multi,
          Source.local,
          Source.qm,
          Source.lrclib,
          Source.qm,
        ],
      );

      expect(sources, const <Source>[Source.qm]);
      expect(() => sources.add(Source.ne), throwsUnsupportedError);
    });

    test('首屏并发查询保留成功结果并隔离单来源失败', () async {
      final _RecordingLyricsClient client = _RecordingLyricsClient(
        failedSources: const <Source>{Source.kg},
      );
      final SearchQueryCoordinator coordinator = SearchQueryCoordinator(
        lyricsClient: client,
      );

      final List<SearchSourceQueryResult> results = await coordinator
          .searchFirstPage(
            sources: const <Source>[Source.qm, Source.kg],
            keyword: 'demo',
            searchType: SearchType.song,
          );

      expect(results, hasLength(2));
      expect(results.first.result?.single.source, Source.qm);
      expect(results.first.error, isNull);
      expect(results.last.result, isNull);
      expect(results.last.error, contains('KG'));
      expect(client.calls.map((_SearchCall call) => call.page), <int>[1, 1]);
    });

    test('首屏来源逐个完成时立即发布快源结果', () async {
      final _DelayedLyricsClient client = _DelayedLyricsClient(
        gates: <Source, Completer<void>>{
          Source.qm: Completer<void>(),
          Source.kg: Completer<void>(),
        },
      );
      final SearchQueryCoordinator coordinator = SearchQueryCoordinator(
        lyricsClient: client,
      );
      final List<SearchSourceQueryResult> events = <SearchSourceQueryResult>[];
      final Future<List<SearchSourceQueryResult>> pending = coordinator
          .searchFirstPage(
            sources: const <Source>[Source.qm, Source.kg],
            keyword: 'partial',
            searchType: SearchType.song,
            onResult: events.add,
          );
      await client.started[Source.qm]!.future;
      await client.started[Source.kg]!.future;

      client.gates[Source.qm]!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single.source, Source.qm);

      client.gates[Source.kg]!.complete();
      final List<SearchSourceQueryResult> results = await pending;
      expect(results, hasLength(2));
      expect(
        events.map((SearchSourceQueryResult value) => value.source),
        <Source>[Source.qm, Source.kg],
      );
    });

    test('单来源达到 deadline 时只返回 timeout 结果', () async {
      final SearchQueryCoordinator coordinator = SearchQueryCoordinator(
        lyricsClient: _NeverCompletingLyricsClient(),
        sourceDeadline: const Duration(milliseconds: 20),
      );
      final Stopwatch stopwatch = Stopwatch()..start();
      final List<SearchSourceQueryResult> events = <SearchSourceQueryResult>[];

      final List<SearchSourceQueryResult> results = await coordinator
          .searchFirstPage(
            sources: const <Source>[Source.qm],
            keyword: 'timeout',
            searchType: SearchType.song,
            onResult: events.add,
          );
      stopwatch.stop();

      expect(results.single.status, SearchSourceQueryStatus.timeout);
      expect(events.single.status, SearchSourceQueryStatus.timeout);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('非整页结果继续加载时向上取整且不重复当前页', () async {
      final _RecordingLyricsClient client = _RecordingLyricsClient();
      final SearchQueryCoordinator coordinator = SearchQueryCoordinator(
        lyricsClient: client,
      );
      final APIResultList<SourceAware> current = APIResultList<SourceAware>(
        List<SourceAware>.generate(
          25,
          (int index) => _song(id: '$index', source: Source.qm),
        ),
        info: SearchInfo(
          source: Source.qm,
          keyword: 'paged',
          searchType: SearchType.song,
          page: 2,
        ),
        ranges: const <Source, SourceRange>{
          Source.qm: SourceRange(start: 0, end: 24, total: 60),
        },
      );

      await coordinator.loadMore(current);

      expect(client.calls.single.page, 3);
      expect(client.calls.single.keyword, 'paged');
    });
  });

  group('SearchPreviewCoordinator', () {
    test('生成空态投影并保持翻译增删只返回新歌词快照', () async {
      final _RecordingTranslationClient client = _RecordingTranslationClient(
        _lyricsData('译文'),
      );
      final SearchPreviewCoordinator coordinator = SearchPreviewCoordinator(
        translationClient: client,
      );
      final Lyrics lyrics = _lyrics(text: '原文');

      final SearchPreviewProjection emptyProjection = coordinator
          .buildProjection(
            lyrics: lyrics,
            selectedLangs: const <String>[],
            lyricsFormat: LyricsFormat.lineByLineLrc,
            offsetMs: 0,
            convertOptions: LyricsConvertOptions(),
          );
      final Lyrics translated = await coordinator.translate(lyrics: lyrics);
      final Lyrics restored = coordinator.removeTranslation(translated);

      expect(emptyProjection.emptyReason, SearchPreviewEmptyReason.noLanguage);
      expect(emptyProjection.previewText, isEmpty);
      expect(client.lastLyrics, same(lyrics));
      expect(translated.data['LDDC_ts']?.single.text, '译文');
      expect(lyrics.data.containsKey('LDDC_ts'), isFalse);
      expect(restored.data.containsKey('LDDC_ts'), isFalse);
      expect(translated.data.containsKey('LDDC_ts'), isTrue);
    });
  });

  group('SearchSaveCoordinator', () {
    test('预览保存失败原样返回且不会吞掉持久化异常', () async {
      final _CoordinatorFixture fixture = _CoordinatorFixture(
        previewPersistence: _RecordingPersistence(
          error: StateError('disk full'),
        ),
      );

      await expectLater(
        fixture.coordinator.savePreviewToDirectory(
          folder: 'C:/lyrics',
          fileNameFormat: '%<title>',
          lyrics: _lyrics(text: '原文'),
          langs: const <String>['orig'],
          lyricsFormat: LyricsFormat.lineByLineLrc,
          text: '原文',
        ),
        throwsStateError,
      );
    });

    test('桌面与 Android 批处理都转发取消令牌和各自保存目标', () async {
      final _CoordinatorFixture fixture = _CoordinatorFixture();
      final SearchBatchSaveCancellationToken desktopToken =
          SearchBatchSaveCancellationToken()..cancel();
      final SearchBatchSaveCancellationToken androidToken =
          SearchBatchSaveCancellationToken()..cancel();

      final SearchBatchSaveResult desktop = await fixture.coordinator.saveBatch(
        songs: <SongInfo>[_song(id: 'desktop')],
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.lineByLineLrc,
        saveFolder: 'C:/lyrics',
        options: _batchOptions(),
        cancellationToken: desktopToken,
      );
      final SearchBatchSaveResult android = await fixture.coordinator
          .saveAndroidBatch(
            songs: <SongInfo>[_song(id: 'android')],
            langs: const <String>['orig'],
            lyricsFormat: LyricsFormat.lineByLineLrc,
            treeUri: 'content://tree/lyrics',
            options: _batchOptions(),
            cancellationToken: androidToken,
          );

      expect(desktop.cancelled, isTrue);
      expect(android.cancelled, isTrue);
      expect(fixture.batchTargets, <String>[
        'C:/lyrics',
        'content://tree/lyrics',
      ]);
      expect(fixture.lyricsClient.getLyricsCalls, 0);
    });
  });
}

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

final class _RecordingLyricsClient extends Fake implements LyricsClient {
  _RecordingLyricsClient({this.failedSources = const <Source>{}});

  final Set<Source> failedSources;
  final List<_SearchCall> calls = <_SearchCall>[];
  int getLyricsCalls = 0;

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
    if (failedSources.contains(source)) {
      throw Exception('source unavailable');
    }
    return APIResultList<SourceAware>(
      <SourceAware>[_song(id: '${source.value}-$page', source: source)],
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
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    getLyricsCalls += 1;
    return _lyrics(text: 'batch');
  }
}

final class _DelayedLyricsClient extends Fake implements LyricsClient {
  _DelayedLyricsClient({required this.gates})
    : started = <Source, Completer<void>>{
        for (final Source source in gates.keys) source: Completer<void>(),
      };

  final Map<Source, Completer<void>> gates;
  final Map<Source, Completer<void>> started;

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    started[source]!.complete();
    await gates[source]!.future;
    return APIResultList<SourceAware>(
      <SourceAware>[_song(id: source.value, source: source)],
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
}

final class _NeverCompletingLyricsClient extends Fake implements LyricsClient {
  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) => Completer<APIResultList<SourceAware>>().future;
}

final class _RecordingTranslationClient extends Fake
    implements TranslationClient {
  _RecordingTranslationClient(this.result);

  final LyricsData result;
  Lyrics? lastLyrics;

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) async {
    lastLyrics = lyrics;
    return result;
  }
}

final class _CoordinatorFixture {
  _CoordinatorFixture({_RecordingPersistence? previewPersistence})
    : lyricsClient = _RecordingLyricsClient(),
      previewPersistence = previewPersistence ?? _RecordingPersistence() {
    coordinator = SearchSaveCoordinator(
      filePicker: _UnusedFilePicker(),
      mediaGateway: _UnusedMediaGateway(),
      fileSaveFactory: (_) => this.previewPersistence,
      batchSaveUseCase: SearchBatchSaveLyricsUseCase(
        lyricsApi: lyricsClient,
        persistenceFactory: (String target) {
          batchTargets.add(target);
          return _RecordingPersistence();
        },
      ),
      androidBatchSaveUseCase: SearchAndroidSafBatchSaveLyricsUseCase(
        lyricsApi: lyricsClient,
        persistenceFactory: (String target) {
          batchTargets.add(target);
          return _RecordingPersistence();
        },
      ),
    );
  }

  final _RecordingLyricsClient lyricsClient;
  final _RecordingPersistence previewPersistence;
  final List<String> batchTargets = <String>[];
  late final SearchSaveCoordinator coordinator;
}

final class _RecordingPersistence extends LyricsSavePersistencePort {
  _RecordingPersistence({this.error});

  final Object? error;

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    final Object? failure = error;
    if (failure != null) {
      throw failure;
    }
    return request.resolvedFileNameFormat;
  }
}

final class _UnusedFilePicker extends Fake implements AppFilePicker {}

final class _UnusedMediaGateway extends Fake
    implements LocalMatchMediaGateway {}

SearchBatchSaveOptions _batchOptions() {
  return SearchBatchSaveOptions(
    fileNameFormat: '%<title>',
    skipInstrumental: false,
    convertOptions: LyricsConvertOptions(),
  );
}

SongInfo _song({required String id, Source source = Source.qm}) {
  return SongInfo(
    source: source,
    id: id,
    title: 'Song $id',
    artist: SongArtist(<String>['Singer']),
    path: 'C:/music/$id.mp3',
  );
}

Lyrics _lyrics({required String text}) {
  final SongInfo song = _song(id: 'lyrics');
  return Lyrics(
    songInfo: song,
    source: song.source,
    data: <String, LyricsData>{'orig': _lyricsData(text)},
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}

LyricsData _lyricsData(String text) {
  return <LyricsLine>[
    LyricsLine(
      startMs: 0,
      endMs: 1000,
      words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 1000, text: text)],
    ),
  ];
}
