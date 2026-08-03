import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../support/search_workflow_test_support.dart';

void main() {
  test('自动获取成功会原子更新候选列表、预览和成功通知', () async {
    final SongInfo localSong = SongInfo(
      source: Source.local,
      path: 'fixture.mp3',
      title: 'Demo',
      artist: SongArtist(<String>['Singer']),
    );
    final SongInfo matchedSong = SongInfo(
      source: Source.kg,
      id: 'kg-demo',
      title: 'Demo',
      artist: SongArtist(<String>['Singer']),
    );
    final SongInfo secondarySong = SongInfo(
      source: Source.qm,
      id: 'qm-demo',
      title: 'Demo',
      artist: SongArtist(<String>['Singer']),
    );
    final _ScriptedAutoFetchUseCase useCase = _ScriptedAutoFetchUseCase(
      (AutoFetchRequest request) async => AutoFetchResult(
        lyrics: _lyrics(matchedSong),
        matchedSongInfo: matchedSong,
        score: 95,
        searchResults: APIResultList<SongInfo>(
          <SongInfo>[matchedSong, secondarySong],
          info: SearchInfo(
            source: Source.qm,
            keyword: 'Singer - Demo',
            searchType: SearchType.song,
            page: 1,
          ),
          ranges: const <Source, SourceRange>{
            Source.kg: SourceRange(start: 0, end: 0, total: 1),
            Source.qm: SourceRange(start: 0, end: 0, total: 1),
          },
          preserveOrder: true,
        ),
      ),
    );
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController(
          autoFetchUseCase: useCase,
          searchSources: const <Source>[Source.qm, Source.ne],
        );
    addTearDown(controller.dispose);

    await controller.autoFetchFromSongInfo(localSong);

    expect(useCase.lastRequest?.info, same(localSong));
    expect(useCase.lastRequest?.sources, <Source>[Source.qm, Source.ne]);
    expect(useCase.lastRequest?.includeSearchResults, isTrue);
    expect(controller.state.keyword, 'Singer - Demo');
    expect(controller.state.tableState, isA<AsyncSuccess<List<SourceAware>>>());
    expect(controller.state.currentPathResult, hasLength(2));
    expect(controller.state.previewPhase, SearchPreviewPhase.ready);
    expect(controller.state.previewText, contains('auto fetched line'));
    expect(controller.state.notice?.code, SearchNoticeCode.autoFetchSucceeded);
  });

  test('自动获取失败会清空临时预览并发布结构化失败通知', () async {
    final _ScriptedAutoFetchUseCase useCase = _ScriptedAutoFetchUseCase(
      (_) async => throw Exception('synthetic auto-fetch failure'),
    );
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController(autoFetchUseCase: useCase);
    addTearDown(controller.dispose);
    final SongInfo localSong = SongInfo(
      source: Source.local,
      title: 'Broken',
      artist: SongArtist(<String>['Singer']),
    );

    await controller.autoFetchFromSongInfo(localSong);

    expect(controller.state.tableState, isA<AsyncError<List<SourceAware>>>());
    expect(controller.state.currentLyrics, isNull);
    expect(controller.state.previewPhase, SearchPreviewPhase.idle);
    expect(controller.state.previewText, isEmpty);
    expect(controller.state.notice?.code, SearchNoticeCode.autoFetchFailed);
    expect(
      controller.state.notice?.detail,
      contains('synthetic auto-fetch failure'),
    );
  });
}

Lyrics _lyrics(SongInfo song) {
  return Lyrics(
    songInfo: song,
    source: song.source,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: const <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: 'auto fetched line'),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}

final class _ScriptedAutoFetchUseCase extends AutoFetchUseCase {
  _ScriptedAutoFetchUseCase(this._execute)
    : super(gateway: _UnusedAutoFetchGateway());

  final Future<AutoFetchResult> Function(AutoFetchRequest request) _execute;
  AutoFetchRequest? lastRequest;

  @override
  Future<AutoFetchResult> execute(AutoFetchRequest request) {
    lastRequest = request;
    return _execute(request);
  }
}

final class _UnusedAutoFetchGateway extends Fake
    implements AutoFetchLyricsGateway {}
