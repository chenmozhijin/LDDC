import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../support/search_workflow_test_support.dart';

void main() {
  testWidgets('结果区显示加载状态并在请求完成后渲染可点击歌曲', (WidgetTester tester) async {
    final Completer<APIResultList<SourceAware>> completer =
        Completer<APIResultList<SourceAware>>();
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController(
          lyricsClient: _ScriptedLyricsClient(
            (_, _, _, _, _) => completer.future,
          ),
        );
    addTearDown(controller.dispose);
    controller.setKeyword('demo');
    final Future<void> search = controller.search();
    await _waitUntil(tester, () => controller.state.tableState is AsyncLoading);

    await _pumpPane(tester, controller);
    expect(find.text('正在搜索'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    completer.complete(_result(<SourceAware>[_song('1', 'First Song')]));
    await search;
    int? tappedIndex;
    await _pumpPane(
      tester,
      controller,
      onDesktopRowTap: (int index) async {
        tappedIndex = index;
      },
    );

    expect(find.text('First Song'), findsOneWidget);
    await tester.tap(find.text('First Song'));
    await tester.pump();
    expect(tappedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果区明确显示空结果而不是空白表格', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController(
          lyricsClient: _ScriptedLyricsClient(
            (_, _, _, _, _) async => _result(const <SourceAware>[]),
          ),
        );
    addTearDown(controller.dispose);
    controller.setKeyword('empty');
    await controller.search();

    await _pumpPane(tester, controller);

    expect(find.text('没有找到结果'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('请求失败显示重试与来源详情，弹窗保留来源和错误分类', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController(
          lyricsClient: _ScriptedLyricsClient((_, _, _, _, _) async {
            throw const LddcApiRequestException('synthetic request failure');
          }),
        );
    addTearDown(controller.dispose);
    controller.setKeyword('failure');
    await controller.search();

    await _pumpPane(tester, controller);

    expect(find.text('发生错误'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    await tester.tap(find.text('查看详情'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('搜索错误详情'), findsOneWidget);
    expect(
      find.text(SearchUiStrings.zhHans().sourceLabel(Source.qm)),
      findsOneWidget,
    );
    expect(find.textContaining('请求失败'), findsWidgets);
    expect(find.textContaining('synthetic request failure'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多来源部分失败保留成功歌曲并显示可查看的警告', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController(
          searchSources: const <Source>[Source.qm, Source.kg],
          lyricsClient: _ScriptedLyricsClient((
            Source source,
            _,
            _,
            _,
            _,
          ) async {
            if (source == Source.kg) {
              throw const LddcApiRequestException('KG unavailable');
            }
            return _result(<SourceAware>[_song('1', 'Available Song')]);
          }),
        );
    addTearDown(controller.dispose);
    controller.setKeyword('partial');
    await controller.search();

    expect(controller.state.tableState, isA<AsyncPartial<List<SourceAware>>>());
    await _pumpPane(tester, controller);

    expect(find.text('Available Song'), findsOneWidget);
    expect(find.text('部分来源暂不可用'), findsOneWidget);
    expect(find.byTooltip('查看详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果行分别渲染专辑、歌单和歌词候选的用户元数据', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    addTearDown(controller.dispose);
    final List<SourceAware> rows = <SourceAware>[
      const SongListInfo(
        source: Source.qm,
        type: SongListType.album,
        id: 'album-1',
        title: 'Fixture Album',
        imgUrl: '',
        songCount: 12,
        publishTimeS: 0,
        author: 'Album Artist',
      ),
      const SongListInfo(
        source: Source.kg,
        type: SongListType.songlist,
        id: 'list-1',
        title: 'Fixture Playlist',
        imgUrl: '',
        songCount: null,
        publishTimeS: null,
        author: 'List Author',
      ),
      LyricInfo(
        source: Source.ne,
        songInfo: SongInfo(
          source: Source.ne,
          title: 'Candidate Lyrics',
          artist: SongArtist(<String>['Candidate Artist']),
        ),
        id: 'lyric-1',
        durationMs: 90000,
      ),
    ];
    controller.state = controller.state.copyWith(
      hasSubmittedSearch: true,
      tableState: AsyncSuccess<List<SourceAware>>(data: rows),
    );

    await _pumpPane(tester, controller);

    expect(find.text('Fixture Album'), findsOneWidget);
    expect(find.textContaining('Album Artist'), findsOneWidget);
    expect(find.textContaining('12 首歌曲'), findsOneWidget);
    expect(find.text('Fixture Playlist'), findsOneWidget);
    expect(find.textContaining('List Author'), findsOneWidget);
    expect(find.text('Candidate Lyrics'), findsOneWidget);
    expect(find.textContaining('Candidate Artist'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPane(
  WidgetTester tester,
  SearchWorkflowController controller, {
  Future<void> Function(int index)? onDesktopRowTap,
}) async {
  final AsyncViewState<List<SourceAware>> tableState =
      controller.state.tableState;
  final List<SourceAware> rows = switch (tableState) {
    AsyncSuccess<List<SourceAware>> value => value.data,
    AsyncPartial<List<SourceAware>> value => value.data,
    _ => const <SourceAware>[],
  };
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 600,
          child: SearchResultPane(
            state: controller.state,
            rows: rows,
            controller: controller,
            strings: SearchUiStrings.zhHans(),
            readKeywordText: () => controller.state.keyword,
            isExpanded: true,
            isDesktopPlatform: true,
            canUseAndroidSafListSave: false,
            selectedRowIndex: null,
            onDesktopRowTap: onDesktopRowTap ?? (_) async {},
            onMobileRowTap: (_, _) async {},
            onReturnPath: () {},
            onOpenPreviewSheet: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

SongInfo _song(String id, String title) => SongInfo(
  source: Source.qm,
  id: id,
  title: title,
  artist: SongArtist(<String>['Singer']),
  album: 'Album',
  durationMs: 180000,
);

APIResultList<SourceAware> _result(List<SourceAware> rows) {
  return APIResultList<SourceAware>(
    rows,
    info: SearchInfo(
      source: Source.qm,
      keyword: 'fixture',
      searchType: SearchType.song,
      page: 1,
    ),
    ranges: rows.isEmpty
        ? const <Source, SourceRange>{}
        : <Source, SourceRange>{
            Source.qm: SourceRange(
              start: 0,
              end: rows.length - 1,
              total: rows.length,
            ),
          },
  );
}

Future<void> _waitUntil(WidgetTester tester, bool Function() predicate) async {
  for (int attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 2));
  }
  throw TimeoutException('等待搜索状态超时');
}

final class _ScriptedLyricsClient extends Fake implements LyricsClient {
  _ScriptedLyricsClient(this._search);

  final Future<APIResultList<SourceAware>> Function(
    Source source,
    String keyword,
    SearchType searchType,
    int page,
    RequestCancellationToken? cancellationToken,
  )
  _search;

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) => _search(source, keyword, searchType, page, cancellationToken);
}
