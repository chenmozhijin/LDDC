import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/app/app.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc/src/app/desktop/desktop_selector_window_content.dart';
import 'package:lddc/src/app/shell/app_shell_page.dart';
import 'package:lddc/src/app/shell/app_shell_providers.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/accessibility/app_action_semantics.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/search/application/search_workflow_host_mapper.dart';
import 'package:lddc/src/features/search/application/search_workflow_providers.dart';
import 'package:lddc/src/infra/storage/file_lyrics_save_persistence.dart';
import 'package:lddc/src/platform/desktop/window/desktop_window_providers.dart';
import 'package:lddc/src/platform/drag_drop/drag_drop_port.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import '../support/in_memory_library_link_repository.dart';

void main() {
  test('关联管理器沿用设置导航项，避免隐藏子路由高亮搜索', () {
    expect(
      AppShellRoute.associationManager.navigationRoute,
      AppShellRoute.settings,
    );
  });

  testWidgets('宽屏使用侧栏导航', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 800));

    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LddcApp()),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('歌词关联管理器'), findsNothing);
  });

  testWidgets('窄屏使用底部导航并可切换页面', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 844));

    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LddcApp()),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    for (final String identifier in <String>[
      AppSemanticsIdentifiers.navLocalMatch,
      AppSemanticsIdentifiers.navOpenLyrics,
      AppSemanticsIdentifiers.navBatchConvert,
      AppSemanticsIdentifiers.navSettings,
    ]) {
      expect(find.bySemanticsIdentifier(identifier), findsOneWidget);
    }

    await tester.tap(
      find.bySemanticsIdentifier(AppSemanticsIdentifiers.navLocalMatch),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('local_match_start_or_cancel')),
      findsOneWidget,
    );
  });

  testWidgets('壳层在手机、平板和桌面尺寸矩阵中保持可用', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 800));
    final AppConfig base = _buildConfig();
    final ProviderContainer container = _createContainer(
      config: base.copyWith(
        app: AppUiConfig(
          language: AppLanguage.ru,
          colorScheme: base.app.colorScheme,
          logLevel: base.app.logLevel,
          autoCheckUpdate: base.app.autoCheckUpdate,
        ),
      ),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LddcApp()),
    );

    for (final Size size in <Size>[
      const Size(360, 800),
      const Size(412, 915),
      const Size(600, 1024),
      const Size(960, 640),
      const Size(1280, 720),
      const Size(1440, 900),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byType(size.width >= 980 ? NavigationRail : NavigationBar),
        findsOneWidget,
        reason: '导航模式必须与当前逻辑宽度匹配: $size',
      );
      expect(
        find.byKey(const ValueKey<AppShellRoute>(AppShellRoute.search)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: '响应式尺寸出现渲染异常: $size');
    }
  });

  testWidgets('切换页面时保留已创建页面，避免长任务控制器被导航销毁', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 800));

    final ProviderContainer container = _createContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppShellPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ValueNotifier<AppShellRoute> routeListenable = container.read(
      appShellRouteListenableProvider,
    );

    expect(
      find.byKey(
        const ValueKey<AppShellRoute>(AppShellRoute.search),
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    routeListenable.value = AppShellRoute.localMatch;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(
        const ValueKey<AppShellRoute>(AppShellRoute.search),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<AppShellRoute>(AppShellRoute.localMatch),
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    routeListenable.value = AppShellRoute.settings;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(
        const ValueKey<AppShellRoute>(AppShellRoute.localMatch),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<AppShellRoute>(AppShellRoute.settings),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('界面语言配置为英文时导航文案即时切换', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 800));

    final AppConfig base = ConfigDefaults.current;
    final ProviderContainer container = _createContainer(
      config: AppConfig(
        schemaVersion: base.schemaVersion,
        search: base.search,
        lyrics: base.lyrics,
        match: base.match,
        translate: base.translate,
        desktop: base.desktop,
        app: const AppUiConfig(
          language: AppLanguage.en,
          colorScheme: AppColorScheme.auto,
          logLevel: AppLogLevel.info,
          autoCheckUpdate: true,
        ),
        storage: base.storage,
        legacyExtras: base.legacyExtras,
      ),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LddcApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('侧栏模式下搜索页内容区仍为窄屏时，单击歌曲即可打开预览并可安全扩宽', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1000, 844));

    final _FakeLyricsApi api = _FakeLyricsApi();
    final SongInfo song = _song(id: 'shell-song', title: 'Shell Song');
    api.setSearchResult(
      source: Source.qm,
      keyword: 'shell',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: <SourceAware>[song],
        source: Source.qm,
        keyword: 'shell',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 1,
      ),
    );
    api.resolveBySongId[song.id!] = LyricsResolvedResult(
      lyrics: _lyricsForSong(song, text: '壳层切换歌词'),
    );

    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      capability: _desktopCapability(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const LddcApp()),
    );
    await tester.enterText(find.byType(EditableText).first, 'shell');
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.textContaining('Shell Song'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('壳层切换歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面歌词选择器内容会在 app 适配层注入搜索工作流依赖', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1024, 768));

    final SongInfo song = _song(id: 'selector-shell-song', title: 'Selector');
    final Lyrics lyrics = _lyricsForSong(song, text: '子窗口预设歌词');
    final _FakeLyricsApi api = _FakeLyricsApi();
    api.setSearchResult(
      source: Source.qm,
      keyword: 'Selector',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: const <SourceAware>[],
        source: Source.qm,
        keyword: 'Selector',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 0,
      ),
    );
    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      overrideSearchWorkflowDependencies: false,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DesktopSelectorWindowContent(
            instanceId: 1024,
            contextSnapshot: DesktopSelectorWindowContext(
              keyword: 'Selector',
              lyrics: lyrics,
              langs: const <String>['orig'],
              offsetMs: 0,
            ),
            onLyricsSelected: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('子窗口预设歌词'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面歌词选择器刷新上下文时复用同一可用 controller', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    final _FakeLyricsApi api = _FakeLyricsApi();
    for (final String keyword in <String>['First Context', 'Second Context']) {
      api.setSearchResult(
        source: Source.qm,
        keyword: keyword,
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: const <SourceAware>[],
          source: Source.qm,
          keyword: keyword,
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 0,
        ),
      );
    }
    final ProviderContainer container = _createContainer(
      lyricsApi: api,
      overrideSearchWorkflowDependencies: false,
    );
    addTearDown(container.dispose);

    Future<void> pumpContext(String keyword, int revision) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DesktopSelectorWindowContent(
              instanceId: 1024,
              contextSnapshot: DesktopSelectorWindowContext(
                keyword: keyword,
                langs: const <String>['orig'],
                offsetMs: revision,
                refreshToken: revision,
              ),
              onLyricsSelected: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    await pumpContext('First Context', 1);
    await pumpContext('Second Context', 2);

    expect(
      api.searchKeywords,
      containsAll(<String>['First Context', 'Second Context']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面歌词选择器不会污染主搜索页工作流状态', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1024, 768));

    final SongInfo parentSong = _song(id: 'main-song', title: 'Main');
    final Lyrics parentLyrics = _lyricsForSong(parentSong, text: '主搜索页歌词');
    final SongInfo selectorSong = _song(id: 'selector-song', title: 'Selector');
    final Lyrics selectorLyrics = _lyricsForSong(selectorSong, text: '选择器歌词');
    final _FakeLyricsApi api = _FakeLyricsApi();
    api.setSearchResult(
      source: Source.qm,
      keyword: 'main',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: const <SourceAware>[],
        source: Source.qm,
        keyword: 'main',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 0,
      ),
    );
    api.setSearchResult(
      source: Source.qm,
      keyword: 'selector',
      searchType: SearchType.song,
      page: 1,
      result: _searchResult(
        items: const <SourceAware>[],
        source: Source.qm,
        keyword: 'selector',
        searchType: SearchType.song,
        page: 1,
        start: 0,
        total: 0,
      ),
    );
    final ProviderContainer container = _createContainer(lyricsApi: api);
    addTearDown(container.dispose);
    await container
        .read(searchWorkflowControllerInstanceProvider)
        .applyExternalPreset(
          keyword: 'main',
          lyrics: parentLyrics,
          selectedLangs: const <String>['orig'],
          clearLyricsWhenNull: false,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DesktopSelectorWindowContent(
            instanceId: 2048,
            contextSnapshot: DesktopSelectorWindowContext(
              keyword: 'selector',
              lyrics: selectorLyrics,
              langs: const <String>['orig'],
              offsetMs: 0,
            ),
            onLyricsSelected: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 选择器通过内部 ProviderScope 创建临时搜索工作流。这里直接读取外层
    // container，可以确认子窗口初始化不会把歌词或关键词写回主搜索页。
    final SearchWorkflowState parentState = container.read(
      searchWorkflowControllerProvider,
    );
    expect(parentState.keyword, 'main');
    expect(parentState.previewText, contains('主搜索页歌词'));
    expect(parentState.previewText, isNot(contains('选择器歌词')));
    expect(find.textContaining('选择器歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('多个桌面歌词选择器 ProviderScope 的搜索状态互相隔离', () async {
    final SongInfo leftSong = _song(id: 'left-selector-song', title: 'Left');
    final SongInfo rightSong = _song(id: 'right-selector-song', title: 'Right');
    final Lyrics leftLyrics = _lyricsForSong(leftSong, text: '左侧选择器歌词');
    final Lyrics rightLyrics = _lyricsForSong(rightSong, text: '右侧选择器歌词');
    final _FakeLyricsApi api = _FakeLyricsApi();
    final ProviderContainer container = _createContainer(lyricsApi: api);
    addTearDown(container.dispose);
    final SearchWorkflowDependencies dependencies = container.read(
      searchWorkflowDependenciesProvider,
    );
    final ProviderContainer leftScope = ProviderContainer(
      parent: container,
      overrides: <Override>[
        searchWorkflowDependenciesProvider.overrideWithValue(dependencies),
      ],
    );
    final ProviderContainer rightScope = ProviderContainer(
      parent: container,
      overrides: <Override>[
        searchWorkflowDependenciesProvider.overrideWithValue(dependencies),
      ],
    );
    addTearDown(leftScope.dispose);
    addTearDown(rightScope.dispose);

    await leftScope
        .read(searchWorkflowControllerInstanceProvider)
        .applyExternalPreset(
          keyword: 'left',
          lyrics: leftLyrics,
          selectedLangs: const <String>['orig'],
          clearLyricsWhenNull: false,
        );
    await rightScope
        .read(searchWorkflowControllerInstanceProvider)
        .applyExternalPreset(
          keyword: 'right',
          lyrics: rightLyrics,
          selectedLangs: const <String>['orig'],
          clearLyricsWhenNull: false,
        );

    // DesktopSelectorWindowContent 为每个桌面子窗口创建独立 ProviderScope。
    // 这里用两个子 container 复刻同一缓存边界，防止 keepAlive controller
    // 在未来改依赖声明时意外退化成跨窗口共享状态。
    expect(
      leftScope.read(searchWorkflowControllerProvider).previewText,
      contains('左侧选择器歌词'),
    );
    expect(
      leftScope.read(searchWorkflowControllerProvider).previewText,
      isNot(contains('右侧选择器歌词')),
    );
    expect(
      rightScope.read(searchWorkflowControllerProvider).previewText,
      contains('右侧选择器歌词'),
    );
    expect(
      container.read(searchWorkflowControllerProvider).currentLyrics,
      isNull,
    );
  });
}

ProviderContainer _createContainer({
  _FakeLyricsApi? lyricsApi,
  AppConfig? config,
  AppCapability? capability,
  AppFilePicker? filePicker,
  bool overrideSearchWorkflowDependencies = true,
}) {
  final _FixedConfigRepository repository = _FixedConfigRepository(
    config ?? _buildConfig(),
  );
  final AppCapability resolvedCapability = capability ?? _desktopCapability();
  final _FakeLyricsApi resolvedLyricsApi = lyricsApi ?? _FakeLyricsApi();
  final AppFilePicker resolvedFilePicker = filePicker ?? _FakeAppFilePicker();
  final List<Override> overrides = <Override>[
    appCapabilityProvider.overrideWith((ref) => resolvedCapability),
    desktopWindowAppDependenciesProvider.overrideWithValue(
      DesktopWindowAppDependencies(
        configRepository: repository,
        libraryLinkRepository: InMemoryLibraryLinkRepository(),
        loadLinkedLyrics: (String lyricsPath) {
          return resolvedLyricsApi.getLyrics(path: lyricsPath);
        },
        runAutoFetch: (AutoFetchRequest request) {
          return AutoFetchUseCase(
            gateway: _NoopAutoFetchGateway(),
          ).execute(request);
        },
        resolveAutoSaveDirectory: () async => Directory.systemTemp,
        fileSavePersistenceFactory: (String folder) =>
            FileLyricsSavePersistence(folder: folder),
        openAssociationManager: () async {},
      ),
    ),
    configRepositoryProvider.overrideWithValue(repository),
    lyricsApiProvider.overrideWithValue(resolvedLyricsApi),
    translateApiProvider.overrideWithValue(_FakeTranslateApi()),
    appFilePickerProvider.overrideWithValue(resolvedFilePicker),
    localMatchMediaGatewayProvider.overrideWithValue(
      _FakeLocalMatchMediaGateway(),
    ),
    dragDropPortProvider.overrideWithValue(const DragDropPortImpl()),
    autoFetchUseCaseProvider.overrideWithValue(
      AutoFetchUseCase(gateway: _NoopAutoFetchGateway()),
    ),
  ];
  if (overrideSearchWorkflowDependencies) {
    overrides.add(
      searchWorkflowDependenciesProvider.overrideWithValue(
        SearchWorkflowDependencies(
          optionsResolver: () => repository.current.toSearchWorkflowOptions(),
          capabilities: resolvedCapability.toSearchWorkflowCapabilities(),
          lyricsApi: resolvedLyricsApi,
          translateApi: _FakeTranslateApi(),
          mediaGateway: _FakeLocalMatchMediaGateway(),
          filePicker: resolvedFilePicker,
          dragDropPort: const DragDropPortImpl(),
          androidSafTreePort: _FakeAndroidSafTreePort(),
          batchSaveUseCase: SearchBatchSaveLyricsUseCase(
            lyricsApi: resolvedLyricsApi,
            persistenceFactory: (String folder) =>
                FileLyricsSavePersistence(folder: folder),
          ),
          androidSafBatchSaveUseCase: SearchAndroidSafBatchSaveLyricsUseCase(
            lyricsApi: resolvedLyricsApi,
            persistenceFactory: (String folder) =>
                FileLyricsSavePersistence(folder: folder),
          ),
          fileSavePersistenceFactory: (String folder) =>
              FileLyricsSavePersistence(folder: folder),
          autoFetchUseCase: AutoFetchUseCase(gateway: _NoopAutoFetchGateway()),
        ),
      ),
    );
  }
  return ProviderContainer(overrides: overrides);
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
    throw UnsupportedError('app shell 测试未配置自动获取歌词');
  }

  @override
  Future<APIResultList<SongInfo>> searchSongs({
    required Source source,
    required String keyword,
    required SearchType searchType,
  }) {
    throw UnsupportedError('app shell 测试未配置自动获取搜索');
  }
}

class _FakeLyricsApi implements LyricsClient {
  final Map<String, APIResultList<SourceAware>> _searchResults =
      <String, APIResultList<SourceAware>>{};
  final Map<String, LyricsResolveResult> resolveBySongId =
      <String, LyricsResolveResult>{};
  final List<String> searchKeywords = <String>[];

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

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    searchKeywords.add(keyword);
    final APIResultList<SourceAware>? result =
        _searchResults['${source.value}|$keyword|${searchType.value}|$page'];
    if (result == null) {
      throw StateError('未配置搜索结果');
    }
    return result;
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) {
    throw UnsupportedError('app shell 测试未配置歌单歌曲列表');
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) {
    throw UnsupportedError('app shell 测试未配置歌词候选列表');
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
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) {
    if (path != null) {
      throw UnsupportedError('app shell 测试未配置本地歌词读取: $path');
    }
    throw UnsupportedError('app shell 测试未配置歌词读取');
  }
}

class _FakeTranslateApi implements TranslationClient {
  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {}

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) async {
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
  }) async => null;

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
