import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/search/application/search_ui_host_mapper.dart';
import 'package:lddc/src/features/search/application/search_workflow_host_mapper.dart';
import 'package:lddc/src/features/search/application/search_workflow_providers.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  testWidgets('歌词选择器显示预设歌词，隐藏保存动作并回传 feature 结果', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final SongInfo song = _song(id: 'selector-song', title: 'Selector Song');
    final Lyrics lyrics = _lyricsForSong(song, text: '选择器预设歌词');
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    SearchLyricsSelectorResult? selectedResult;

    await _pumpSelectorPage(
      tester,
      container,
      initialState: SearchLyricsSelectorInitialState(
        keyword: 'Selector Song',
        lyrics: lyrics,
        langs: const <String>['orig', 'ts'],
        offsetMs: 120,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (SearchLyricsSelectorResult result) async {
        selectedResult = result;
        return true;
      },
    );
    await tester.pumpAndSettle();

    final Finder splitter = find.byKey(
      const ValueKey<String>('search_workspace_splitter'),
    );
    final Finder resultPane = find.byKey(
      const ValueKey<String>('search_workspace_result_pane'),
    );
    final double resultWidth = tester.getSize(resultPane).width;
    expect(splitter, findsOneWidget);
    await tester.drag(splitter, const Offset(180, 0));
    await tester.pump();
    expect(tester.getSize(resultPane).width, greaterThan(resultWidth));

    expect(find.textContaining('选择器预设歌词'), findsOneWidget);
    expect(find.text('翻译歌词'), findsOneWidget);
    expect(find.text('翻译歌词/取消翻译'), findsNothing);
    expect(find.text('保存到文件夹'), findsNothing);
    expect(find.text('保存到歌曲标签'), findsNothing);
    expect(find.text('选择保存路径'), findsNothing);
    expect(find.text('保存专辑/歌单的歌词'), findsNothing);

    await tester.tap(find.text('选定歌词'));
    await tester.pump();

    expect(selectedResult, isNotNull);
    expect(selectedResult!.lyrics, lyrics);
    expect(selectedResult!.langs, const <String>['orig', 'ts']);
    expect(selectedResult!.offsetMs, 120);
  });

  testWidgets('歌词选择器使用非 OpenAI 翻译时显示忙碌文案并禁用重复提交', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final Completer<LyricsData> translation = Completer<LyricsData>();
    final _FakeTranslateApi translateApi = _FakeTranslateApi()
      ..completer = translation;
    final ProviderContainer container = _createContainer(
      translateApi: translateApi,
    );
    addTearDown(container.dispose);
    final SongInfo song = _song(id: 'selector-translate', title: 'Translate');

    await _pumpSelectorPage(
      tester,
      container,
      initialState: SearchLyricsSelectorInitialState(
        keyword: 'Translate',
        lyrics: _lyricsForSong(song, text: '原文'),
        langs: const <String>['orig', 'ts'],
        offsetMs: 0,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pumpAndSettle();

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

  testWidgets('打开本地歌词失败时只显示业务错误提示', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);

    await _pumpSelectorPage(
      tester,
      container,
      initialState: const SearchLyricsSelectorInitialState(
        keyword: 'Local Song',
        langs: <String>['orig'],
        offsetMs: 0,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => r'D:\lyrics\broken.lrc',
        loadLocalLyrics: (String path) async {
          throw Exception('broken lyrics');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开本地歌词'));
    await tester.pump();

    expect(find.textContaining('打开本地歌词失败'), findsOneWidget);
    expect(find.textContaining('broken lyrics'), findsOneWidget);
  });

  testWidgets('文件选择插件失败会被页面接住，打开动作忙碌期间不会重入', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    final Completer<String?> picker = Completer<String?>();
    int pickerCalls = 0;

    await _pumpSelectorPage(
      tester,
      container,
      initialState: null,
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () {
          pickerCalls += 1;
          return picker.future;
        },
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pump();

    final Finder openButton = find.byKey(
      const ValueKey<String>('selector_open_local_button'),
    );
    await tester.tap(openButton);
    await tester.pump();
    expect(pickerCalls, 1);
    expect(tester.widget<OutlinedButton>(openButton).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(openButton);
    expect(pickerCalls, 1);
    picker.completeError(MissingPluginException('file_selector'));
    await tester.pumpAndSettle();

    expect(find.textContaining('打开本地歌词失败'), findsOneWidget);
    expect(find.textContaining('file_selector'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(openButton).onPressed, isNotNull);
  });

  testWidgets('提交歌词期间按钮防重入且一次操作只发送一次意图', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    final SongInfo song = _song(id: 'submit-once', title: 'Submit Once');
    final Completer<bool> submit = Completer<bool>();
    int submitCalls = 0;

    await _pumpSelectorPage(
      tester,
      container,
      initialState: SearchLyricsSelectorInitialState(
        lyrics: _lyricsForSong(song, text: '只提交一次'),
        langs: const <String>['orig'],
        offsetMs: 0,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) {
        submitCalls += 1;
        return submit.future;
      },
    );
    await tester.pumpAndSettle();

    final Finder selectButton = find.byKey(
      const ValueKey<String>('selector_select_lyrics_button'),
    );
    await tester.tap(selectButton);
    await tester.pump();
    expect(submitCalls, 1);
    expect(tester.widget<FilledButton>(selectButton).onPressed, isNull);

    await tester.tap(selectButton);
    expect(submitCalls, 1);
    submit.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('选择器初始关键词和搜索按钮都会真正启动搜索', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    final _FakeLyricsApi lyricsApi =
        container.read(lyricsApiProvider) as _FakeLyricsApi;
    final SearchWorkflowController controller = container.read(
      searchWorkflowControllerInstanceProvider,
    );
    controller.updateSearchType(SearchType.album);

    await _pumpSelectorPage(
      tester,
      container,
      initialState: const SearchLyricsSelectorInitialState(
        keyword: 'Auto Song',
        langs: <String>['orig'],
        offsetMs: 0,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(lyricsApi.searchCalls, greaterThanOrEqualTo(1));
    expect(lyricsApi.keywords, contains('Auto Song'));
    expect(lyricsApi.searchTypes, contains(SearchType.song));
    final TabBar tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(controller.state.selectedSearchType, SearchType.song);
    expect(
      tabBar.controller?.index,
      controller.state.availableSearchTypes.indexOf(SearchType.song),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('search_toolbar_search_bar')),
      'Manual Song',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('search_toolbar_search_button')),
    );
    await tester.pumpAndSettle();

    expect(lyricsApi.searchCalls, greaterThanOrEqualTo(2));
    expect(lyricsApi.keywords, contains('Manual Song'));
  });

  testWidgets('560x480 紧凑选择器单击歌曲后以底部弹层显示实时预览', (WidgetTester tester) async {
    _useCompactSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    final _FakeLyricsApi lyricsApi =
        container.read(lyricsApiProvider) as _FakeLyricsApi;
    final SongInfo song = _song(id: 'compact-song', title: 'Compact Song');
    lyricsApi.searchResult = APIResultList<SourceAware>(
      <SourceAware>[song],
      info: SearchInfo(
        source: Source.qm,
        keyword: 'Compact Song',
        searchType: SearchType.song,
        page: 1,
      ),
      ranges: const <Source, SourceRange>{
        Source.qm: SourceRange(start: 0, end: 0, total: 1),
      },
    );
    lyricsApi.resolveBySongId[song.id!] = LyricsResolvedResult(
      lyrics: _lyricsForSong(song, text: '紧凑窗口预览歌词'),
    );

    await _pumpSelectorPage(
      tester,
      container,
      initialState: const SearchLyricsSelectorInitialState(
        keyword: 'Compact Song',
        langs: <String>['orig'],
        offsetMs: 0,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPreviewPane), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('search_result_row_0')));
    await tester.pumpAndSettle();

    expect(lyricsApi.resolveCalls, 1);
    expect(find.byType(SearchPreviewPane), findsOneWidget);
    expect(find.textContaining('紧凑窗口预览歌词'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('selector_sheet_select_lyrics_button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽选择器单击结果立即打开歌曲预览', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    final _FakeLyricsApi lyricsApi =
        container.read(lyricsApiProvider) as _FakeLyricsApi;
    final SongInfo song = _song(id: 'wide-song', title: 'Wide Song');
    lyricsApi.searchResult = APIResultList<SourceAware>(
      <SourceAware>[song],
      info: SearchInfo(
        source: Source.qm,
        keyword: 'Wide Song',
        searchType: SearchType.song,
        page: 1,
      ),
      ranges: const <Source, SourceRange>{
        Source.qm: SourceRange(start: 0, end: 0, total: 1),
      },
    );
    lyricsApi.resolveBySongId[song.id!] = LyricsResolvedResult(
      lyrics: _lyricsForSong(song, text: '宽窗口单击歌词'),
    );

    await _pumpSelectorPage(
      tester,
      container,
      initialState: const SearchLyricsSelectorInitialState(
        keyword: 'Wide Song',
        langs: <String>['orig'],
        offsetMs: 0,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    final Finder row = find.byKey(
      const ValueKey<String>('search_result_row_0'),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(lyricsApi.resolveCalls, 1);
    expect(find.textContaining('宽窗口单击歌词'), findsOneWidget);
  });

  testWidgets('紧凑选择器单击歌单进入曲目，候选歌词加载后才显示预览弹层', (WidgetTester tester) async {
    _useCompactSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    final _FakeLyricsApi lyricsApi =
        container.read(lyricsApiProvider) as _FakeLyricsApi;
    const SongListInfo playlist = SongListInfo(
      source: Source.qm,
      type: SongListType.songlist,
      id: 'compact-playlist',
      title: 'Compact Playlist',
      imgUrl: '',
      songCount: 1,
      publishTimeS: null,
      author: 'Tester',
    );
    final SongInfo song = _song(id: 'candidate-song', title: 'Candidate Song');
    final LyricInfo candidate = LyricInfo(
      source: Source.qm,
      songInfo: song,
      id: 'candidate-lyric',
    );
    lyricsApi.searchResult = APIResultList<SourceAware>(
      <SourceAware>[playlist],
      info: SearchInfo(
        source: Source.qm,
        keyword: 'Compact Playlist',
        searchType: SearchType.song,
        page: 1,
      ),
      ranges: const <Source, SourceRange>{
        Source.qm: SourceRange(start: 0, end: 0, total: 1),
      },
    );
    lyricsApi.songlistById[playlist.id] = APIResultList<SongInfo>(
      <SongInfo>[song],
      info: playlist,
      ranges: const <Source, SourceRange>{
        Source.qm: SourceRange(start: 0, end: 0, total: 1),
      },
    );
    lyricsApi.resolveBySongId[song.id!] = LyricsSelectionRequiredResult(
      candidates: APIResultList<LyricInfo>(
        <LyricInfo>[candidate],
        info: song,
        ranges: const <Source, SourceRange>{
          Source.qm: SourceRange(start: 0, end: 0, total: 1),
        },
      ),
    );
    lyricsApi.lyricsById[candidate.id!] = _lyricsForSong(song, text: '候选歌词预览');

    await _pumpSelectorPage(
      tester,
      container,
      initialState: const SearchLyricsSelectorInitialState(
        keyword: 'Compact Playlist',
        langs: <String>['orig'],
        offsetMs: 0,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    final Finder row = find.byKey(
      const ValueKey<String>('search_result_row_0'),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(lyricsApi.songlistCalls, 1);
    expect(find.text('Candidate Song'), findsOneWidget);
    expect(find.byType(SearchPreviewPane), findsNothing);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(lyricsApi.resolveCalls, 1);
    expect(find.byType(SearchPreviewPane), findsNothing);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(lyricsApi.lyricsCalls, 1);
    expect(find.byType(SearchPreviewPane), findsOneWidget);
    expect(find.textContaining('候选歌词预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择器先以空上下文创建再收到窗口 payload 时仍会自动搜索', (WidgetTester tester) async {
    _useLargeSurface(tester);
    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    final _FakeLyricsApi lyricsApi =
        container.read(lyricsApiProvider) as _FakeLyricsApi;

    await _pumpSelectorPage(
      tester,
      container,
      initialState: null,
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pump();

    await _pumpSelectorPage(
      tester,
      container,
      initialState: const SearchLyricsSelectorInitialState(
        keyword: 'Late Context Song',
        langs: <String>['orig'],
        offsetMs: 0,
        refreshRevision: 1,
      ),
      dependencies: SearchLyricsSelectorDependencies(
        pickLocalLyricsPath: () async => null,
        loadLocalLyrics: (String path) async {
          throw StateError('测试不应加载本地歌词');
        },
      ),
      onLyricsSelected: (_) async => true,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(lyricsApi.searchCalls, greaterThan(0));
    expect(lyricsApi.keywords, contains('Late Context Song'));
  });
}

Future<void> _pumpSelectorPage(
  WidgetTester tester,
  ProviderContainer container, {
  required SearchLyricsSelectorInitialState? initialState,
  required SearchLyricsSelectorDependencies dependencies,
  required Future<bool> Function(SearchLyricsSelectorResult result)
  onLyricsSelected,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => SearchLyricsSelectorPage(
            controller: container.read(
              searchWorkflowControllerInstanceProvider,
            ),
            strings: AppLocalizations.of(context).toSearchUiStrings(),
            initialState: initialState,
            dependencies: dependencies,
            onLyricsSelected: onLyricsSelected,
          ),
        ),
      ),
    ),
  );
}

ProviderContainer _createContainer({_FakeTranslateApi? translateApi}) {
  final _FixedConfigRepository repository = _FixedConfigRepository(
    ConfigDefaults.current,
  );
  final _FakeLyricsApi lyricsApi = _FakeLyricsApi();
  final _FakeTranslateApi resolvedTranslateApi =
      translateApi ?? _FakeTranslateApi();
  final AppCapability capability = _desktopCapability();
  return ProviderContainer(
    overrides: [
      searchWorkflowDependenciesProvider.overrideWithValue(
        SearchWorkflowDependencies(
          optionsResolver: () => repository.current.toSearchWorkflowOptions(),
          capabilities: capability.toSearchWorkflowCapabilities(),
          lyricsApi: lyricsApi,
          translateApi: resolvedTranslateApi,
          mediaGateway: _FakeLocalMatchMediaGateway(),
          filePicker: _FakeAppFilePicker(),
          dragDropPort: _FakeDragDropPort(),
          androidSafTreePort: _FakeAndroidSafTreePort(),
          batchSaveUseCase: SearchBatchSaveLyricsUseCase(
            lyricsApi: lyricsApi,
            persistenceFactory: _fakePersistenceFactory,
          ),
          androidSafBatchSaveUseCase: SearchAndroidSafBatchSaveLyricsUseCase(
            lyricsApi: lyricsApi,
            persistenceFactory: _fakePersistenceFactory,
          ),
          fileSavePersistenceFactory: _fakePersistenceFactory,
          autoFetchUseCase: AutoFetchUseCase(gateway: _NoopAutoFetchGateway()),
        ),
      ),
      configRepositoryProvider.overrideWithValue(repository),
      lyricsApiProvider.overrideWithValue(lyricsApi),
      translateApiProvider.overrideWithValue(resolvedTranslateApi),
    ],
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

void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _useCompactSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(560, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
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

class _FakeLyricsApi implements LyricsClient {
  int searchCalls = 0;
  int resolveCalls = 0;
  int songlistCalls = 0;
  int lyricsCalls = 0;
  final List<String> keywords = <String>[];
  final List<SearchType> searchTypes = <SearchType>[];
  APIResultList<SourceAware>? searchResult;
  final Map<String, LyricsResolveResult> resolveBySongId =
      <String, LyricsResolveResult>{};
  final Map<String, APIResultList<SongInfo>> songlistById =
      <String, APIResultList<SongInfo>>{};
  final Map<String, Lyrics> lyricsById = <String, Lyrics>{};

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    searchCalls += 1;
    keywords.add(keyword);
    searchTypes.add(searchType);
    final APIResultList<SourceAware>? configured = searchResult;
    if (configured != null) {
      final Object? info = configured.info;
      if (info is SearchInfo && info.source == source) {
        return configured;
      }
    }
    return APIResultList<SourceAware>(
      const <SourceAware>[],
      info: SearchInfo(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: page,
      ),
    );
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    resolveCalls += 1;
    final LyricsResolveResult? result = resolveBySongId[songInfo.id];
    if (result == null) {
      throw StateError('未配置候选结果');
    }
    return result;
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    songlistCalls += 1;
    return songlistById[songListInfo.id] ??
        APIResultList<SongInfo>(const <SongInfo>[], info: songListInfo);
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw UnsupportedError('SearchLyricsSelector 测试场景不支持候选歌词列表');
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    lyricsCalls += 1;
    if (info case final LyricInfo lyric) {
      final Lyrics? lyrics = lyricsById[lyric.id];
      if (lyrics != null) {
        return lyrics;
      }
    }
    throw StateError('未配置本地歌词');
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

class _FakeAppFilePicker implements AppFilePicker {
  @override
  Future<String?> pickDirectory({String? initialDirectory}) async => null;

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    return null;
  }

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    return const <PickedFileHandle>[];
  }

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({
    String? initialDirectory,
  }) async {
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

class _FakeDragDropPort implements DragDropPort {}

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
