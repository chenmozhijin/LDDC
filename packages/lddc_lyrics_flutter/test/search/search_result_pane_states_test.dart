import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('结果行不再显示序号列，标题按可用宽度单行省略', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    addTearDown(controller.dispose);
    final List<SourceAware> rows = <SourceAware>[
      _song('1', '很长的歌曲标题需要按可用宽度省略而不是换行显示'),
      _song('2', 'Second Song'),
      _song('3', 'Third Song'),
    ];
    controller.state = controller.state.copyWith(
      hasSubmittedSearch: true,
      tableState: AsyncSuccess<List<SourceAware>>(data: rows),
    );

    await _pumpPane(
      tester,
      controller,
      width: _narrowPaneWidth,
      bordered: false,
    );

    // 序号列已删除：01/02/03 不应出现在任何一行里。
    expect(find.text('01'), findsNothing);
    expect(find.text('03'), findsNothing);
    // 时长仍按自然宽度右对齐显示（不再占用固定 88dp 元数据框）。
    expect(find.text('03:00'), findsNWidgets(rows.length));

    // 窄屏下标题列必须拿到足够宽度：封面 50 + 间距 12 + 行内边距 28 之后，
    // 标题减去时长与间距仍有 ~200dp（修复前 360dp 屏只剩十几 dp）。
    final RenderParagraph titleParagraph = tester.renderObject<RenderParagraph>(
      find.text('很长的歌曲标题需要按可用宽度省略而不是换行显示'),
    );
    expect(titleParagraph.size.width, greaterThanOrEqualTo(190));
    expect(titleParagraph.didExceedMaxLines, isTrue, reason: '超长标题应按单行省略');

    // 常见的艺术家·专辑文案必须完整可读，不能因为被挤压而省略。
    final RenderParagraph subtitleParagraph = tester
        .renderObject<RenderParagraph>(find.text('Singer · Album').first);
    expect(subtitleParagraph.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏结果区不包卡片，分栏布局仍保留卡片边界', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    addTearDown(controller.dispose);
    controller.state = controller.state.copyWith(
      hasSubmittedSearch: true,
      tableState: AsyncSuccess<List<SourceAware>>(
        data: <SourceAware>[_song('1', 'First Song')],
      ),
    );

    await _pumpPane(
      tester,
      controller,
      width: _narrowPaneWidth,
      bordered: false,
    );
    expect(find.byType(Card), findsNothing);
    expect(find.text('First Song'), findsOneWidget);

    await _pumpPane(tester, controller, bordered: true);
    expect(find.byType(Card), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多来源结果行用行内徽标标注来源且不重复来源文案', (WidgetTester tester) async {
    // 走真实搜索流程拿到多来源结果集，避免手写 ranges 破坏 APIResultList 的取值范围约束。
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
            return _sourceResult(source, <SourceAware>[
              _song('1', 'First Song', source: source),
            ]);
          }),
        );
    addTearDown(controller.dispose);
    controller.setKeyword('fixture');
    await controller.search();
    expect(controller.state.currentPathResult?.sources.length, 2);

    await _pumpPane(
      tester,
      controller,
      width: _narrowPaneWidth,
      bordered: false,
    );

    final SearchUiStrings strings = SearchUiStrings.zhHans();
    // 每行一个来源徽标，且第二行不再重复同一句来源文案。
    expect(find.text(strings.sourceLabel(Source.qm)), findsOneWidget);
    expect(find.text(strings.sourceLabel(Source.kg)), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(2));
    expect(find.text('Singer · Album'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

/// 窄屏手机（360dp）宽度，用于验证结果行在移动端的可用宽度。
const double _narrowPaneWidth = 360;

Future<void> _pumpPane(
  WidgetTester tester,
  SearchWorkflowController controller, {
  Future<void> Function(int index)? onDesktopRowTap,
  double width = 900,
  bool bordered = true,
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
          width: width,
          height: 600,
          child: SearchResultPane(
            state: controller.state,
            rows: rows,
            controller: controller,
            strings: SearchUiStrings.zhHans(),
            readKeywordText: () => controller.state.keyword,
            isExpanded: true,
            bordered: bordered,
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

SongInfo _song(String id, String title, {Source source = Source.qm}) =>
    SongInfo(
      source: source,
      id: id,
      title: title,
      artist: SongArtist(<String>['Singer']),
      album: 'Album',
      durationMs: 180000,
    );

/// 构造指定来源的单来源结果，供多来源搜索脚本客户端使用。
APIResultList<SourceAware> _sourceResult(
  Source source,
  List<SourceAware> rows,
) {
  return APIResultList<SourceAware>(
    rows,
    info: SearchInfo(
      source: source,
      keyword: 'fixture',
      searchType: SearchType.song,
      page: 1,
    ),
    ranges: rows.isEmpty
        ? const <Source, SourceRange>{}
        : <Source, SourceRange>{
            source: SourceRange(
              start: 0,
              end: rows.length - 1,
              total: rows.length,
            ),
          },
  );
}

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
