import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart'
    as lyrics_flutter
    show AsyncError;
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/features/search/application/search_workflow_host_mapper.dart';
import 'package:lddc/src/features/search/application/search_workflow_providers.dart';
import 'package:lddc/src/features/search/presentation/search_page.dart';
import 'package:lddc/src/platform/drag_drop/drag_drop_port.dart';
import 'package:lddc/src/shared/ui/components/desktop_page_interaction_scope.dart';

void main() {
  testWidgets('默认结果卡片显示引导态，来源切换与 Tab 自动搜索保持可用', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final _FakeLyricsApi api = _FakeLyricsApi();
    api.setSearchResult(
      source: Source.qm,
      keyword: 'album-keyword',
      searchType: SearchType.album,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[
          SongListInfo(
            source: Source.qm,
            type: SongListType.album,
            id: 'album-1',
            title: 'Album One',
            imgUrl: '',
            songCount: 1,
            publishTimeS: 1700000000,
            author: 'Author',
          ),
        ],
        source: Source.qm,
        keyword: 'album-keyword',
        searchType: SearchType.album,
        page: 1,
        start: 0,
        total: 1,
      ),
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _desktopCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    expect(find.text('输入关键词开始搜索'), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(
      tester.getSize(find.byType(SearchBar)).height,
      lessThanOrEqualTo(48),
    );
    expect(find.byType(Card), findsNWidgets(2));

    await _expectSourceMenuMatchesDescriptors(tester);
    await _selectWideSource(tester, fromLabel: '聚合', toLabel: 'Lrclib');
    expect(find.text('单曲'), findsOneWidget);
    expect(find.text('专辑'), findsNothing);
    expect(find.text('歌单'), findsNothing);

    await _selectWideSource(tester, fromLabel: 'Lrclib', toLabel: 'QQ音乐');
    await _enterSearchKeyword(tester, 'album-keyword');
    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();

    expect(api.searchCalls.length, 1);
    expect(api.searchCalls.single, 'QM|album-keyword|ALBUM|1');
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.textContaining('Album One'), findsOneWidget);
  });

  testWidgets('宽屏分隔条支持拖动键盘调节、最小宽度和页面会话状态', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);
    await tester.pumpAndSettle();

    final Finder splitter = find.byKey(
      const ValueKey<String>('search_workspace_splitter'),
    );
    final Finder resultPane = find.byKey(
      const ValueKey<String>('search_workspace_result_pane'),
    );
    final Finder previewPane = find.byKey(
      const ValueKey<String>('search_workspace_preview_pane'),
    );
    expect(splitter, findsOneWidget);
    final double initialResultWidth = tester.getSize(resultPane).width;
    final double initialPreviewWidth = tester.getSize(previewPane).width;
    expect(
      initialResultWidth / (initialResultWidth + initialPreviewWidth),
      closeTo(0.4, 0.01),
    );

    // 故意在同一帧内连续发送事件，复现高刷新率鼠标快于 Flutter 布局重建的场景。
    // 如果生产代码错误使用 build 时捕获的旧宽度，这里只会保留最后一次 20dp 位移。
    final TestGesture dragGesture = await tester.startGesture(
      tester.getCenter(splitter),
    );
    for (int step = 0; step < 12; step += 1) {
      await dragGesture.moveBy(const Offset(20, 0));
    }
    await dragGesture.up();
    await tester.pump();
    expect(
      tester.getSize(resultPane).width,
      closeTo(initialResultWidth + 240, 2),
    );
    expect(tester.getSize(previewPane).width, lessThan(initialPreviewWidth));

    await tester.tap(splitter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    final double keyboardAdjustedWidth = tester.getSize(resultPane).width;
    expect(keyboardAdjustedWidth, lessThan(initialResultWidth + 240));

    await tester.drag(splitter, const Offset(-3000, 0));
    await tester.pump();
    expect(tester.getSize(resultPane).width, closeTo(320, 1));
    await tester.drag(splitter, const Offset(3000, 0));
    await tester.pump();
    expect(tester.getSize(previewPane).width, closeTo(420, 1));

    tester.view.physicalSize = const Size(900, 900);
    await tester.pump();
    expect(splitter, findsNothing);
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pump();
    expect(splitter, findsOneWidget);
    expect(tester.getSize(previewPane).width, closeTo(420, 1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpSearchPage(tester, container);
    await tester.pump();
    final double rebuiltResultWidth = tester.getSize(resultPane).width;
    final double rebuiltPreviewWidth = tester.getSize(previewPane).width;
    expect(
      rebuiltResultWidth / (rebuiltResultWidth + rebuiltPreviewWidth),
      closeTo(0.4, 0.01),
    );
  });

  testWidgets('宽屏右侧预览面板收口视图控制与导出操作，格式限制通过 SnackBar 提示', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongInfo song = _song(id: 'song-1', title: 'Demo Song');
    api.setSearchResult(
      source: Source.qm,
      keyword: 'demo',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[song],
        source: Source.qm,
        keyword: 'demo',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.resolveBySongId[song.id!] = LyricsResolvedResult(
      lyrics: _lyricsForSong(song, text: '原文A'),
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _desktopCapability(),
      filePicker: _FakeAppFilePicker(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    await _enterSearchKeyword(tester, 'demo');
    await _tapSearchButton(tester);
    await tester.pumpAndSettle();

    final Finder rowCell = find.textContaining('Demo Song');
    await tester.tap(rowCell);
    await tester.pumpAndSettle();

    expect(find.textContaining('原文A'), findsOneWidget);
    expect(find.textContaining('歌词语言 · 原文（逐行）'), findsOneWidget);
    expect(find.textContaining('orig'), findsNothing);
    expect(find.text('翻译歌词'), findsOneWidget);
    expect(find.text('翻译歌词/取消翻译'), findsNothing);
    expect(find.text('歌词预览'), findsOneWidget);
    expect(find.text('视图控制'), findsNothing);
    expect(find.text('导出操作'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is SegmentedButton<String>,
      ),
      findsOneWidget,
    );
    final SegmentedButton<String> languageSegments = tester.widget(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('search_preview_language_segments'),
        ),
        matching: find.byType(SegmentedButton<String>),
      ),
    );
    // 每个分段都包含透明勾图标以稳定宽度，图标数量不能代表选中状态。
    // 直接断言组件的业务选择集，避免布局占位实现变化产生假红。
    expect(languageSegments.selected, <String>{'orig', 'ts'});
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('保存路径'), findsOneWidget);
    expect(find.text('选择保存路径'), findsOneWidget);
    expect(find.text('保存到文件夹'), findsOneWidget);
    expect(find.text('保存到歌曲标签'), findsOneWidget);
    expect(find.text('保存专辑/歌单的歌词'), findsNothing);
    expect(find.textContaining('歌词语言'), findsOneWidget);
    expect(find.textContaining('歌曲ID'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
    expect(
      (tester
                  .getTopLeft(
                    find.byKey(
                      const ValueKey<String>('search_preview_save_path_field'),
                    ),
                  )
                  .dy -
              tester
                  .getTopLeft(
                    find.byKey(
                      const ValueKey<String>('search_preview_format_field'),
                    ),
                  )
                  .dy)
          .abs(),
      lessThanOrEqualTo(12),
    );
    expect(
      (tester
                  .getTopLeft(
                    find.byKey(
                      const ValueKey<String>(
                        'search_preview_language_segments',
                      ),
                    ),
                  )
                  .dy -
              tester
                  .getTopLeft(
                    find.byKey(
                      const ValueKey<String>('search_preview_action_bar'),
                    ),
                  )
                  .dy)
          .abs(),
      lessThanOrEqualTo(12),
    );

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(container.read(searchWorkflowControllerProvider).offsetMs, 100);

    final Finder offsetText = find.text('100');
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(offsetText),
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.pump();
    expect(container.read(searchWorkflowControllerProvider).offsetMs, 200);

    await tester.tap(find.byType(DropdownButtonFormField<LyricsFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SRT').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存到歌曲标签'));
    await tester.pump();
    expect(find.text('歌曲标签中的歌词应为 LRC 格式'), findsOneWidget);

    await container
        .read(searchWorkflowControllerInstanceProvider)
        .toggleTranslation();
    await tester.pumpAndSettle();
    expect(find.text('取消翻译'), findsOneWidget);
    expect(find.textContaining('译文（逐行）'), findsOneWidget);
  });

  testWidgets('搜索页使用非 OpenAI 翻译时显示忙碌文案并禁用重复提交', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final Completer<LyricsData> translation = Completer<LyricsData>();
    final _FakeTranslateApi translateApi = _FakeTranslateApi()
      ..completer = translation;
    final ProviderContainer container = _createContainer(
      translateApi: translateApi,
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);
    final SongInfo song = _song(id: 'page-translate', title: 'Translate');
    await container
        .read(searchWorkflowControllerInstanceProvider)
        .applyExternalPreset(lyrics: _lyricsForSong(song, text: '原文'));
    await tester.pump();

    final Finder translateButton = find.byKey(
      const ValueKey<String>('search_preview_translate_button'),
    );
    await tester.tap(translateButton);
    await tester.pump();

    expect(find.text('翻译中...'), findsOneWidget);
    expect(tester.widget<FilledButton>(translateButton).onPressed, isNull);
    expect(translateApi.callCount, 1);

    translation.complete(<LyricsLine>[
      LyricsLine(
        startMs: 0,
        endMs: 1000,
        words: const <LyricsWord>[
          LyricsWord(startMs: 0, endMs: 1000, text: '翻译'),
        ],
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('取消翻译'), findsOneWidget);
    expect(tester.widget<FilledButton>(translateButton).onPressed, isNotNull);
  });

  testWidgets('桌面快捷键会触发打开文件、打开预览与清空选中', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongInfo song = _song(id: 'shortcut-song', title: 'Shortcut Song');
    api.setSearchResult(
      source: Source.qm,
      keyword: 'shortcut',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[song],
        source: Source.qm,
        keyword: 'shortcut',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.resolveBySongId[song.id!] = LyricsResolvedResult(
      lyrics: _lyricsForSong(song, text: '快捷键预览歌词'),
    );
    final _FakeAppFilePicker picker = _FakeAppFilePicker();
    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _desktopCapability(),
      filePicker: picker,
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    await _invokeShortcut(
      tester,
      const SingleActivator(LogicalKeyboardKey.keyO, control: true),
    );
    expect(picker.audioPickCount, 1);

    await _enterSearchKeyword(tester, 'shortcut');
    await _tapSearchButton(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('search_result_row_0')));
    await tester.pump();
    await _invokeShortcut(
      tester,
      const SingleActivator(LogicalKeyboardKey.escape),
    );
    await tester.pumpAndSettle();
    await _invokeShortcut(
      tester,
      const SingleActivator(LogicalKeyboardKey.enter),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(searchWorkflowControllerProvider).previewPhase,
      SearchPreviewPhase.ready,
    );

    await tester.pump(const Duration(milliseconds: 320));
    await tester.tap(find.byKey(const ValueKey<String>('search_result_row_0')));
    await tester.pump();
    await _invokeShortcut(
      tester,
      const SingleActivator(LogicalKeyboardKey.enter),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(searchWorkflowControllerProvider).previewPhase,
      SearchPreviewPhase.ready,
    );
    expect(find.textContaining('快捷键预览歌词'), findsOneWidget);
  });

  testWidgets('聚合搜索结果显示具体来源名称而不是代号', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final _FakeLyricsApi api = _FakeLyricsApi();
    api.setSearchResult(
      source: Source.qm,
      keyword: 'mix',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[_song(id: 'qm-1', title: 'Song Qm')],
        source: Source.qm,
        keyword: 'mix',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.setSearchResult(
      source: Source.ne,
      keyword: 'mix',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[
          SongInfo(
            source: Source.ne,
            id: 'ne-1',
            title: 'Song Ne',
            artist: SongArtist(<String>['Singer']),
          ),
        ],
        source: Source.ne,
        keyword: 'mix',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 1,
      ),
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      config: _buildConfig(searchSources: <String>['QM', 'NE']),
      capability: _desktopCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    await _enterSearchKeyword(tester, 'mix');
    await _tapSearchButton(tester);
    await tester.pumpAndSettle();

    expect(find.text('QQ音乐'), findsOneWidget);
    expect(find.text('网易云音乐'), findsOneWidget);
    expect(find.text('QM'), findsNothing);
    expect(find.text('NE'), findsNothing);
  });

  testWidgets('部分来源失败只显示一次 SnackBar，详情弹窗可只重试失败来源', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final _FakeLyricsApi api = _FakeLyricsApi();
    api.setSearchResult(
      source: Source.qm,
      keyword: 'partial-error',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[_song(id: 'qm-ok', title: 'QM Result')],
        source: Source.qm,
        keyword: 'partial-error',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.setSearchResult(
      source: Source.kg,
      keyword: 'partial-error',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[
          SongInfo(source: Source.kg, id: 'kg-ok', title: 'KG Result'),
        ],
        source: Source.kg,
        keyword: 'partial-error',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.enqueueSearchError(
      source: Source.kg,
      keyword: 'partial-error',
      searchType: SearchType.song,
      page: 1,
      error: const LddcApiRequestException('KG 服务暂时不可用'),
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      config: _buildConfig(searchSources: <String>['QM', 'KG']),
      capability: _desktopCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    await _enterSearchKeyword(tester, 'partial-error');
    await _tapSearchButton(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('search_notice_searchPartialSourcesFailed'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('部分来源搜索失败'), findsOneWidget);
    expect(find.textContaining('QM Result'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('搜索错误详情'), findsOneWidget);
    expect(find.text('酷狗音乐'), findsOneWidget);
    expect(find.textContaining('KG 服务暂时不可用'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await tester.pumpAndSettle();

    expect(
      api.searchCalls.where((String call) => call.startsWith('QM|')).length,
      1,
    );
    expect(
      api.searchCalls.where((String call) => call.startsWith('KG|')).length,
      2,
    );
    expect(find.textContaining('KG Result'), findsOneWidget);
    expect(
      container.read(searchWorkflowControllerProvider).sourceFailures,
      isEmpty,
    );
  });

  testWidgets('全部来源失败保留持久详情，弹窗重试成功后清除错误状态', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final _FakeLyricsApi api = _FakeLyricsApi();
    for (final Source source in <Source>[Source.qm, Source.kg]) {
      api.setSearchResult(
        source: source,
        keyword: 'all-error',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[
            SongInfo(
              source: source,
              id: '${source.value}-ok',
              title: '${source.value} Result',
            ),
          ],
          source: source,
          keyword: 'all-error',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.enqueueSearchError(
        source: source,
        keyword: 'all-error',
        searchType: SearchType.song,
        page: 1,
        error: LddcApiRequestException('${source.value} 请求失败'),
      );
    }

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      config: _buildConfig(searchSources: <String>['QM', 'KG']),
      capability: _desktopCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    await _enterSearchKeyword(tester, 'all-error');
    await _tapSearchButton(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('search_notice_searchAllSourcesFailed'),
      ),
      findsOneWidget,
    );
    expect(
      container.read(searchWorkflowControllerProvider).tableState,
      isA<lyrics_flutter.AsyncError<List<SourceAware>>>(),
    );
    // SnackBar 消失后，结果区仍持有详情和重试入口。
    ScaffoldMessenger.of(
      tester.element(find.byType(SearchPage)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '查看详情'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('请求失败\nQM 请求失败'), findsOneWidget);
    expect(find.text('请求失败\nKG 请求失败'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await tester.pumpAndSettle();

    expect(
      api.searchCalls.where((String call) => call.startsWith('QM|')).length,
      2,
    );
    expect(
      api.searchCalls.where((String call) => call.startsWith('KG|')).length,
      2,
    );
    expect(
      container.read(searchWorkflowControllerProvider).tableState,
      isA<AsyncSuccess<List<SourceAware>>>(),
    );
    expect(find.text('查看详情'), findsNothing);
  });

  testWidgets('搜索结果默认自动续取，仅在续取失败时显示重试动作', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final _FakeLyricsApi api = _FakeLyricsApi();
    final List<SourceAware> page1 = List<SourceAware>.generate(
      20,
      (int index) => _song(id: 'song-$index', title: 'Song $index'),
    );
    api.setSearchResult(
      source: Source.qm,
      keyword: 'retry',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: page1,
        source: Source.qm,
        keyword: 'retry',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 50,
      ),
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _desktopCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    await _enterSearchKeyword(tester, 'retry');
    await _tapSearchButton(tester);
    await tester.pumpAndSettle();

    final Finder resultList = find.byType(ListView);
    expect(find.text('加载更多'), findsNothing);
    expect(find.text('重试'), findsNothing);
    for (
      int attempt = 0;
      attempt < 6 && find.text('重试').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(resultList, const Offset(0, -420));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('自动续取失败，可重试继续加载剩余结果'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('search_notice_searchLoadMoreFailed')),
      findsOneWidget,
    );
    expect(
      api.searchCalls.where((String call) => call.endsWith('|2')).length,
      1,
    );

    // SnackBar 会覆盖列表底部，先打开并关闭详情，确认完整错误可见的同时
    // 让底部持久重试按钮恢复可点击。
    await tester.tap(find.widgetWithText(SnackBarAction, '查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('搜索错误详情'), findsOneWidget);
    expect(find.textContaining('未配置搜索结果'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    final int loadMoreCallsBeforeRetry = api.searchCalls
        .where((String call) => call.endsWith('|2'))
        .length;
    final OutlinedButton retryButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '重试'),
    );
    // 长列表尾部按钮的回调已经由布局断言覆盖；直接触发回调可避免测试窗口
    // 底部 Scaffold overlay 对命中测试造成平台相关遮挡。
    retryButton.onPressed!();
    await tester.pumpAndSettle();
    expect(
      api.searchCalls.where((String call) => call.endsWith('|2')).length,
      loadMoreCallsBeforeRetry + 1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('专辑结果页标题固定为搜索结果，批量保存入口只在进入曲目页后出现', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongListInfo album = SongListInfo(
      source: Source.qm,
      type: SongListType.album,
      id: 'album-1',
      title: 'Album One',
      imgUrl: '',
      songCount: 1,
      publishTimeS: 1700000000,
      author: 'Author',
    );
    api.setSearchResult(
      source: Source.qm,
      keyword: 'album',
      searchType: SearchType.album,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[album],
        source: Source.qm,
        keyword: 'album',
        searchType: SearchType.album,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.songlistById[album.id] = APIResultList<SongInfo>(
      <SongInfo>[_song(id: 'track-1', title: 'Track One')],
      info: album,
      ranges: <Source, SourceRange>{
        Source.qm: const SourceRange(start: 0, end: 0, total: 1),
      },
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _desktopCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    await _enterSearchKeyword(tester, 'album');
    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();

    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('保存专辑/歌单的歌词'), findsNothing);

    final Finder row = find.textContaining('Album One');
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('保存专辑/歌单的歌词'), findsOneWidget);
  });

  testWidgets('桌面窄宽度下结果表头按钮保持横向排列且不与 Tab 争抢同一行', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongListInfo album = SongListInfo(
      source: Source.qm,
      type: SongListType.album,
      id: 'android-album-1',
      title: 'Android Album',
      imgUrl: '',
      songCount: 1,
      publishTimeS: 1700000000,
      author: 'Author',
    );
    api.setSearchResult(
      source: Source.qm,
      keyword: 'android-album',
      searchType: SearchType.album,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[album],
        source: Source.qm,
        keyword: 'android-album',
        searchType: SearchType.album,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.songlistById[album.id] = APIResultList<SongInfo>(
      <SongInfo>[_song(id: 'android-track-1', title: 'Android Track')],
      info: album,
      ranges: <Source, SourceRange>{
        Source.qm: const SourceRange(start: 0, end: 0, total: 1),
      },
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _desktopCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);
    final SearchWorkflowController controller = container.read(
      searchWorkflowControllerInstanceProvider,
    );
    controller.updateSearchType(SearchType.album);
    controller.setKeyword('android-album');
    await controller.search();
    await controller.openResult(0);
    await tester.pumpAndSettle();

    final Finder tab = find.text('单曲');
    final Finder returnButton = find.text('返回上一层');
    final Finder saveListButton = find.text('保存专辑/歌单的歌词');
    expect(returnButton, findsOneWidget);
    expect(saveListButton, findsOneWidget);
    expect(
      tester.getTopLeft(returnButton).dy,
      greaterThan(tester.getTopLeft(tab).dy),
    );
    expect(
      tester.getTopLeft(returnButton).dy,
      closeTo(tester.getTopLeft(saveListButton).dy, 0.1),
    );
  });

  testWidgets('Android 紧凑布局进入专辑曲目页后继续显示批量保存入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongListInfo album = SongListInfo(
      source: Source.qm,
      type: SongListType.album,
      id: 'mobile-album-1',
      title: 'Mobile Album',
      imgUrl: '',
      songCount: 1,
      publishTimeS: 1700000000,
      author: 'Author',
    );
    api.setSearchResult(
      source: Source.qm,
      keyword: 'mobile-album',
      searchType: SearchType.album,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[album],
        source: Source.qm,
        keyword: 'mobile-album',
        searchType: SearchType.album,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.songlistById[album.id] = APIResultList<SongInfo>(
      <SongInfo>[_song(id: 'mobile-track-1', title: 'Mobile Track')],
      info: album,
      ranges: <Source, SourceRange>{
        Source.qm: const SourceRange(start: 0, end: 0, total: 1),
      },
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _androidCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);
    final SearchWorkflowController controller = container.read(
      searchWorkflowControllerInstanceProvider,
    );
    controller.updateSearchType(SearchType.album);
    controller.setKeyword('mobile-album');
    await controller.search();
    await controller.openResult(0);
    await tester.pumpAndSettle();

    expect(find.text('返回上一层'), findsOneWidget);
    expect(find.text('保存专辑/歌单的歌词'), findsOneWidget);
  });

  testWidgets('Android 真实比例视口进入歌单后清空关键词会显示即时提示', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongListInfo playlist = SongListInfo(
      source: Source.qm,
      type: SongListType.songlist,
      id: 'android-empty-keyword-playlist',
      title: 'Android Playlist',
      imgUrl: '',
      songCount: 1,
      publishTimeS: 1700000000,
      author: 'Author',
    );
    api.setSearchResult(
      source: Source.qm,
      keyword: 'android-playlist',
      searchType: SearchType.songlist,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[playlist],
        source: Source.qm,
        keyword: 'android-playlist',
        searchType: SearchType.songlist,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.songlistById[playlist.id] = APIResultList<SongInfo>(
      <SongInfo>[_song(id: 'android-playlist-track', title: 'Playlist Track')],
      info: playlist,
      ranges: <Source, SourceRange>{
        Source.qm: const SourceRange(start: 0, end: 0, total: 1),
      },
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _androidCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);
    final SearchWorkflowController controller = container.read(
      searchWorkflowControllerInstanceProvider,
    );
    controller.updateSearchType(SearchType.songlist);
    controller.setKeyword('android-playlist');
    await controller.search();
    await controller.openResult(0);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, '');
    await tester.tap(
      find.byKey(const ValueKey<String>('search_toolbar_search_button')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('search_notice_emptyKeyword')),
      findsOneWidget,
    );
    expect(controller.state.isSearching, isFalse);
  });

  testWidgets('iOS 单击结果后自动弹出预览底部抽屉，并同时显示文件与标签保存入口', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongInfo song = _song(id: 'mobile-song', title: 'Mobile Song');
    api.setSearchResult(
      source: Source.qm,
      keyword: 'mobile',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[song],
        source: Source.qm,
        keyword: 'mobile',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.resolveBySongId[song.id!] = LyricsResolvedResult(
      lyrics: _lyricsForSong(song, text: '移动端歌词'),
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _iosCapability(),
      filePicker: _FakeAppFilePicker(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);

    await _enterSearchKeyword(tester, 'mobile');
    await _tapSearchButton(tester);
    await tester.pumpAndSettle();

    expect(find.text('保存到文件'), findsNothing);
    await tester.tap(find.textContaining('Mobile Song'));
    await tester.pumpAndSettle();
    expect(find.text('保存到歌曲标签'), findsOneWidget);
    expect(find.text('保存到文件'), findsOneWidget);
    expect(find.text('保存路径'), findsNothing);
    expect(find.text('保存专辑/歌单的歌词'), findsNothing);
    expect(find.textContaining('移动端歌词'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is SegmentedButton<String>,
      ),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsNothing);

    container
        .read(searchWorkflowControllerInstanceProvider)
        .updateSelectedLangs(<String>{});
    await tester.pumpAndSettle();

    expect(find.text('请至少选择一种歌词语言'), findsOneWidget);
    expect(find.text('请先选择歌曲或歌词条目'), findsNothing);
  });

  testWidgets('iOS 紧凑布局单击专辑结果只进入曲目页，不自动弹出预览抽屉', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongListInfo album = SongListInfo(
      source: Source.qm,
      type: SongListType.album,
      id: 'ios-tap-album-1',
      title: 'Tap Album',
      imgUrl: '',
      songCount: 1,
      publishTimeS: 1700000000,
      author: 'Author',
    );
    api.setSearchResult(
      source: Source.qm,
      keyword: 'ios-tap-album',
      searchType: SearchType.album,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[album],
        source: Source.qm,
        keyword: 'ios-tap-album',
        searchType: SearchType.album,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.songlistById[album.id] = APIResultList<SongInfo>(
      <SongInfo>[_song(id: 'ios-tap-track-1', title: 'Tap Track')],
      info: album,
      ranges: <Source, SourceRange>{
        Source.qm: const SourceRange(start: 0, end: 0, total: 1),
      },
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _iosCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);
    final SearchWorkflowController controller = container.read(
      searchWorkflowControllerInstanceProvider,
    );
    controller.updateSearchType(SearchType.album);
    controller.setKeyword('ios-tap-album');
    await controller.search();
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Tap Album'));
    await tester.pumpAndSettle();

    expect(find.text('返回上一层'), findsOneWidget);
    expect(find.textContaining('Tap Track'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('保存到文件'), findsNothing);
    expect(find.text('保存到歌曲标签'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS 紧凑布局进入专辑曲目页后不显示批量保存入口', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongListInfo album = SongListInfo(
      source: Source.qm,
      type: SongListType.album,
      id: 'ios-album-1',
      title: 'iOS Album',
      imgUrl: '',
      songCount: 1,
      publishTimeS: 1700000000,
      author: 'Author',
    );
    api.setSearchResult(
      source: Source.qm,
      keyword: 'ios-album',
      searchType: SearchType.album,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[album],
        source: Source.qm,
        keyword: 'ios-album',
        searchType: SearchType.album,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.songlistById[album.id] = APIResultList<SongInfo>(
      <SongInfo>[_song(id: 'ios-track-1', title: 'iOS Track')],
      info: album,
      ranges: <Source, SourceRange>{
        Source.qm: const SourceRange(start: 0, end: 0, total: 1),
      },
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _iosCapability(),
    );
    addTearDown(container.dispose);
    await _pumpSearchPage(tester, container);
    final SearchWorkflowController controller = container.read(
      searchWorkflowControllerInstanceProvider,
    );
    controller.updateSearchType(SearchType.album);
    controller.setKeyword('ios-album');
    await controller.search();
    await controller.openResult(0);
    await tester.pumpAndSettle();

    expect(find.text('返回上一层'), findsOneWidget);
    expect(find.text('保存专辑/歌单的歌词'), findsNothing);
  });
}

Future<void> _pumpSearchPage(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SearchPage()),
      ),
    ),
  );
}

void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _enterSearchKeyword(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byType(EditableText).first, keyword);
}

Future<void> _tapSearchButton(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.search).last);
  await tester.pumpAndSettle();
}

Future<void> _selectWideSource(
  WidgetTester tester, {
  required String fromLabel,
  required String toLabel,
}) async {
  await tester.tap(find.text(fromLabel).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(toLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _expectSourceMenuMatchesDescriptors(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('search_toolbar_source_menu')),
  );
  await tester.pumpAndSettle();

  for (final SearchSourceDescriptor descriptor
      in kSearchToolbarSourceDescriptors) {
    expect(
      find.byKey(
        ValueKey<String>(
          'search_toolbar_source_item_${descriptor.source.value}',
        ),
      ),
      findsOneWidget,
    );
  }
  expect(
    find.byKey(
      ValueKey<String>('search_toolbar_source_item_${Source.local.value}'),
    ),
    findsNothing,
  );

  await tester.tap(find.text('聚合').last);
  await tester.pumpAndSettle();
}

ProviderContainer _createContainer({
  _FakeLyricsApi? lyricsApi,
  _FakeTranslateApi? translateApi,
  AppConfig? config,
  AppCapability? capability,
  AppFilePicker? filePicker,
}) {
  final _FixedConfigRepository repository = _FixedConfigRepository(
    config ?? _buildConfig(),
  );
  final AppCapability resolvedCapability = capability ?? _desktopCapability();
  final _FakeLyricsApi resolvedLyricsApi = lyricsApi ?? _FakeLyricsApi();
  final _FakeTranslateApi resolvedTranslateApi =
      translateApi ?? _FakeTranslateApi();
  final AppFilePicker resolvedFilePicker = filePicker ?? _FakeAppFilePicker();
  return ProviderContainer(
    overrides: [
      appCapabilityProvider.overrideWith((ref) => resolvedCapability),
      searchWorkflowDependenciesProvider.overrideWithValue(
        SearchWorkflowDependencies(
          optionsResolver: () => repository.current.toSearchWorkflowOptions(),
          capabilities: resolvedCapability.toSearchWorkflowCapabilities(),
          lyricsApi: resolvedLyricsApi,
          translateApi: resolvedTranslateApi,
          mediaGateway: _FakeLocalMatchMediaGateway(),
          filePicker: resolvedFilePicker,
          dragDropPort: const DragDropPortImpl(),
          androidSafTreePort: _FakeAndroidSafTreePort(),
          batchSaveUseCase: SearchBatchSaveLyricsUseCase(
            lyricsApi: resolvedLyricsApi,
            persistenceFactory: _fakePersistenceFactory,
          ),
          androidSafBatchSaveUseCase: SearchAndroidSafBatchSaveLyricsUseCase(
            lyricsApi: resolvedLyricsApi,
            persistenceFactory: _fakePersistenceFactory,
          ),
          fileSavePersistenceFactory: _fakePersistenceFactory,
          autoFetchUseCase: AutoFetchUseCase(gateway: _NoopAutoFetchGateway()),
        ),
      ),
      configRepositoryProvider.overrideWithValue(repository),
      lyricsApiProvider.overrideWithValue(resolvedLyricsApi),
      translateApiProvider.overrideWithValue(resolvedTranslateApi),
      appFilePickerProvider.overrideWithValue(resolvedFilePicker),
    ],
  );
}

AppConfig _buildConfig({List<String>? searchSources}) {
  final AppConfig base = ConfigDefaults.current;
  return AppConfig(
    schemaVersion: base.schemaVersion,
    search: SearchConfig(sources: searchSources ?? const <String>['QM']),
    lyrics: base.lyrics,
    match: base.match,
    translate: base.translate,
    desktop: base.desktop,
    app: base.app,
    storage: base.storage,
    legacyExtras: base.legacyExtras,
  );
}

AppCapability _desktopCapability() {
  return const AppCapability(
    multiWindow: true,
    desktopPanelDetached: true,
    desktopPanelEmbedded: true,
    systemTray: true,
    globalHotkey: true,
    audioTagWrite: true,
    directoryRecursiveScan: true,
    androidSafTreeAccess: false,
    androidCueTrackResolve: false,
    webFileSystemAccess: false,
    webTaglibWasmReady: false,
  );
}

AppCapability _androidCapability() {
  return const AppCapability(
    multiWindow: false,
    desktopPanelDetached: false,
    desktopPanelEmbedded: false,
    systemTray: false,
    globalHotkey: false,
    audioTagWrite: true,
    directoryRecursiveScan: false,
    androidSafTreeAccess: true,
    androidCueTrackResolve: true,
    webFileSystemAccess: false,
    webTaglibWasmReady: false,
  );
}

AppCapability _iosCapability() {
  return const AppCapability(
    multiWindow: false,
    desktopPanelDetached: false,
    desktopPanelEmbedded: false,
    systemTray: false,
    globalHotkey: false,
    audioTagWrite: true,
    directoryRecursiveScan: false,
    androidSafTreeAccess: false,
    androidCueTrackResolve: false,
    webFileSystemAccess: false,
    webTaglibWasmReady: false,
  );
}

APIResultList<SourceAware> _searchResult({
  required List<SourceAware> items,
  required Source source,
  required String keyword,
  required SearchType searchType,
  required int page,
  required int start,
  required int total,
}) {
  final int end = start + items.length - 1;
  return APIResultList<SourceAware>(
    items,
    info: SearchInfo(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    ),
    ranges: <Source, SourceRange>{
      source: SourceRange(start: start, end: end, total: total),
    },
  );
}

SongInfo _song({required String id, required String title}) {
  return SongInfo(
    source: Source.qm,
    id: id,
    title: title,
    artist: SongArtist(<String>['Singer']),
  );
}

Lyrics _lyricsForSong(SongInfo song, {required String text}) {
  return Lyrics(
    songInfo: song,
    source: song.source,
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 1000, text: text)],
        ),
      ],
    },
  );
}

class _FixedConfigRepository implements ConfigRepository {
  _FixedConfigRepository(this._config);

  final AppConfig _config;

  @override
  AppConfig get current => _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<AppConfig> refreshFromStorage() async => _config;

  @override
  Future<AppConfig> update(Map<String, Object?> patch) async => _config;

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield _config;
    }
  }
}

LyricsSavePersistencePort _fakePersistenceFactory(String target) {
  return _FakeLyricsSavePersistence(target);
}

class _FakeLyricsSavePersistence extends LyricsSavePersistencePort {
  _FakeLyricsSavePersistence(this.target);

  final String target;

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    return '$target/${request.songInfo.title ?? 'lyrics'}';
  }
}

class _FakeAndroidSafTreePort implements AndroidSafTreePort {
  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    return AndroidSafWriteDocumentResult(
      uri: '$treeUri/$displayName',
      displayName: displayName,
    );
  }

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    return AndroidSafTreePage(
      entries: const <AndroidSafTreeEntry>[],
      nextOffset: null,
    );
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() async {
    return const <AndroidSafPersistedTree>[];
  }

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) async {
    return const AndroidSafTreeToken(uri: 'content://tree/test');
  }

  @override
  Future<void> persistTreePermission(String uri) async {}
}

class _FakeLocalMatchMediaGateway implements LocalMatchMediaGateway {
  @override
  Future<bool> hasLyricsTag(String songPath) async => false;

  @override
  Future<int?> readAudioDurationMs(String audioPath) async => null;

  @override
  Future<String?> readAudioLyricsText({
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    return null;
  }

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async {
    return <SongInfo>[
      SongInfo(source: Source.local, path: audioPath, title: 'Local'),
    ];
  }

  @override
  Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {}
}

class _NoopAutoFetchGateway implements AutoFetchLyricsGateway {
  @override
  Future<Lyrics> getLyrics(SongInfo info) {
    throw UnsupportedError('测试场景不支持自动获取歌词');
  }

  @override
  Future<APIResultList<SongInfo>> searchSongs({
    required Source source,
    required String keyword,
    required SearchType searchType,
  }) {
    throw UnsupportedError('测试场景不支持自动搜索歌曲');
  }
}

class _FakeLyricsApi implements LyricsClient {
  final Map<String, APIResultList<SourceAware>> _searchResults =
      <String, APIResultList<SourceAware>>{};
  final Map<String, List<Object>> _searchErrors = <String, List<Object>>{};
  final Map<String, LyricsResolveResult> resolveBySongId =
      <String, LyricsResolveResult>{};
  final Map<String?, APIResultList<SongInfo>> songlistById =
      <String?, APIResultList<SongInfo>>{};
  final List<String> searchCalls = <String>[];

  void setSearchResult({
    required Source source,
    required String keyword,
    required SearchType searchType,
    required int page,
    required APIResultList<SourceAware> result,
  }) {
    _searchResults['${source.value}|$keyword|${searchType.value}|$page'] =
        result;
  }

  void enqueueSearchError({
    required Source source,
    required String keyword,
    required SearchType searchType,
    required int page,
    required Object error,
  }) {
    final String key = '${source.value}|$keyword|${searchType.value}|$page';
    _searchErrors.putIfAbsent(key, () => <Object>[]).add(error);
  }

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    final String key = '${source.value}|$keyword|${searchType.value}|$page';
    searchCalls.add(key);
    final List<Object>? errors = _searchErrors[key];
    if (errors != null && errors.isNotEmpty) {
      throw errors.removeAt(0);
    }
    final APIResultList<SourceAware>? result = _searchResults[key];
    if (result == null) {
      throw Exception('未配置搜索结果');
    }
    return result;
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    final LyricsResolveResult? result = resolveBySongId[songInfo.id ?? ''];
    if (result == null) {
      throw StateError('未配置候选结果');
    }
    return result;
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    final APIResultList<SongInfo>? result = songlistById[songListInfo.id];
    if (result == null) {
      throw StateError('未配置歌单结果');
    }
    return result;
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw UnsupportedError('SearchPage 测试场景不支持候选歌词列表');
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    throw const LddcLyricsNotFoundException('没有找到歌词');
  }
}

class _FakeTranslateApi implements TranslationClient {
  Completer<LyricsData>? completer;
  int callCount = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {}

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) async {
    callCount += 1;
    final Completer<LyricsData>? currentCompleter = completer;
    if (currentCompleter != null) {
      return currentCompleter.future;
    }
    return <LyricsLine>[
      LyricsLine(
        startMs: 0,
        endMs: 1000,
        words: const <LyricsWord>[
          LyricsWord(startMs: 0, endMs: 1000, text: '翻译'),
        ],
      ),
    ];
  }
}

class _FakeAppFilePicker implements AppFilePicker {
  int audioPickCount = 0;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async => null;

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async => null;

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async => const <PickedFileHandle>[];

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({
    String? initialDirectory,
  }) async {
    audioPickCount += 1;
    return null;
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) async => file;

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) async {}

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    return null;
  }
}

Future<void> _invokeShortcut(
  WidgetTester tester,
  ShortcutActivator activator,
) async {
  for (final Element element
      in find.byType(DesktopPageInteractionScope).evaluate()) {
    final DesktopPageInteractionScope scope =
        element.widget as DesktopPageInteractionScope;
    final VoidCallback? callback = scope.shortcuts[activator];
    if (callback == null) {
      continue;
    }
    callback();
    await tester.pumpAndSettle();
    return;
  }
  fail('未找到快捷键绑定：$activator');
}
