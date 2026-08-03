import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide AsyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/search/application/search_workflow_host_mapper.dart';
import 'package:lddc/src/features/search/application/search_workflow_providers.dart';
import 'package:lddc/src/infra/storage/file_lyrics_save_persistence.dart';
import 'package:lddc/src/platform/drag_drop/drag_drop_port.dart';

void main() {
  group('SearchWorkflowController', () {
    test('applyExternalPreset 会更新关键词、语言、偏移并应用外部歌词预览', () async {
      final ProviderContainer container = _createContainer();
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      final SongInfo song = _song(id: 'preset-song', title: 'Preset Song');

      await controller.applyExternalPreset(
        keyword: 'preset keyword',
        lyrics: _lyricsForSong(song, text: '外部预设歌词'),
        selectedLangs: const <String>['orig'],
        offsetMs: 250,
      );

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.keyword, 'preset keyword');
      expect(state.selectedLangs, const <String>['orig']);
      expect(state.offsetMs, 250);
      expect(state.currentLyrics, isNotNull);
      expect(state.previewText, contains('外部预设歌词'));
      expect(state.previewPhase, SearchPreviewPhase.ready);
    });

    test('applyExternalPreset 可按外部要求触发一次搜索', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      api.setSearchResult(
        source: Source.qm,
        keyword: 'preset-search',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[_song(id: 'preset-1', title: 'Preset Result')],
          source: Source.qm,
          keyword: 'preset-search',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      final ProviderContainer container = _createContainer(
        lyricsApi: api,
        config: _buildConfig(searchSources: const <String>['QM']),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      await controller.applyExternalPreset(
        keyword: 'preset-search',
        selectedSource: Source.multi,
        selectedSearchType: SearchType.song,
        triggerSearch: true,
      );

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(api.searchCalls.length, 1);
      expect(api.searchCalls.single.source, Source.qm);
      expect(api.searchCalls.single.keyword, 'preset-search');
      expect(api.searchCalls.single.type, SearchType.song);
      expect(state.currentPathResult?.length, 1);
    });

    test('autoFetchFromSongInfo 会进入自动获取并联动刷新候选与预览', () async {
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: r'D:\music\demo.mp3',
        title: 'Demo',
        artist: SongArtist(<String>['Singer']),
        album: 'Album',
      );
      final SongInfo matchedSong = SongInfo(
        source: Source.kg,
        id: 'kg-demo',
        title: 'Demo',
        artist: SongArtist(<String>['Singer']),
        album: 'Album',
      );
      final SongInfo qmSecondary = SongInfo(
        source: Source.qm,
        id: 'qm-secondary',
        title: 'Demo',
        artist: SongArtist(<String>['Singer']),
        album: 'Album',
      );
      final _FakeAutoFetchUseCase autoFetchUseCase = _FakeAutoFetchUseCase(
        result: AutoFetchResult(
          lyrics: _lyricsForSong(matchedSong, text: '自动获取歌词'),
          matchedSongInfo: matchedSong,
          score: 95,
          searchResults: APIResultList<SongInfo>(
            <SongInfo>[matchedSong, qmSecondary],
            info: SearchInfo(
              source: Source.qm,
              keyword: 'Singer - Demo',
              searchType: SearchType.song,
              page: 1,
            ),
            ranges: <Source, SourceRange>{
              Source.kg: const SourceRange(start: 0, end: 0, total: 1),
              Source.qm: const SourceRange(start: 0, end: 0, total: 1),
            },
            preserveOrder: true,
          ),
        ),
      );
      final ProviderContainer container = _createContainer(
        autoFetchUseCase: autoFetchUseCase,
        config: _buildConfig(searchSources: const <String>['QM', 'NE']),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      await controller.autoFetchFromSongInfo(localSong);

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(autoFetchUseCase.lastRequest?.info, same(localSong));
      expect(autoFetchUseCase.lastRequest?.includeSearchResults, isTrue);
      expect(state.keyword, 'Singer - Demo');
      expect(state.tableState, isA<AsyncSuccess<List<SourceAware>>>());
      expect(state.currentPathResult?.length, 2);
      expect((state.currentPathResult?.first as SongInfo?)?.id, 'kg-demo');
      expect(state.previewPhase, SearchPreviewPhase.ready);
      expect(state.previewText, contains('自动获取歌词'));
    });

    test('openDroppedSongFile 会按 .cue + index 解析轨道并进入自动获取', () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'search-workflow-dropped-cue-',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final File audioFile = File(
        '${directory.path}${Platform.pathSeparator}disc.wav',
      );
      await audioFile.writeAsBytes(const <int>[]);
      final File cueFile = File(
        '${directory.path}${Platform.pathSeparator}disc.cue',
      );
      await cueFile.writeAsString(_cueText());
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()..durations[audioFile.path] = 240000;
      final SongInfo matchedSong = SongInfo(
        source: Source.qm,
        id: 'qm-demo',
        title: 'Second',
        artist: SongArtist(<String>['Singer']),
        album: 'Album',
      );
      final _FakeAutoFetchUseCase autoFetchUseCase = _FakeAutoFetchUseCase(
        result: AutoFetchResult(
          lyrics: _lyricsForSong(matchedSong, text: '自动获取歌词'),
          matchedSongInfo: matchedSong,
          score: 98,
          searchResults: APIResultList<SongInfo>(
            <SongInfo>[matchedSong],
            info: SearchInfo(
              source: Source.qm,
              keyword: 'Singer - Second',
              searchType: SearchType.song,
              page: 1,
            ),
            ranges: <Source, SourceRange>{
              Source.qm: const SourceRange(start: 0, end: 0, total: 1),
            },
          ),
        ),
      );
      final ProviderContainer container = _createContainer(
        mediaGateway: mediaGateway,
        autoFetchUseCase: autoFetchUseCase,
        config: _buildConfig(searchSources: const <String>['QM']),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      await controller.openDroppedSongFile(cueFile.path, index: '1');

      final SongInfo? requestInfo = autoFetchUseCase.lastRequest?.info;
      expect(requestInfo, isNotNull);
      expect(requestInfo?.fromCue, isTrue);
      expect(requestInfo?.id, '02');
      expect(requestInfo?.title, 'Second');
      expect(requestInfo?.path, audioFile.path);
      expect(mediaGateway.readAudioSongInfosCallCount, 0);
    });

    test('空关键词返回一次性警告提示且不进入已搜索态', () async {
      final ProviderContainer container = _createContainer();
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      await controller.search();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.tableState, isA<AsyncEmpty<List<SourceAware>>>());
      expect((state.tableState as AsyncEmpty<List<SourceAware>>).message, '');
      expect(state.hasSubmittedSearch, isFalse);
      expect(state.notice?.code, SearchNoticeCode.emptyKeyword);
      expect(state.notice?.severity, PageNoticeSeverity.warning);
    });

    test('取消全部歌词语言后会回写 noLanguage 预览空态原因', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(id: 'song-1', title: 'NeedLang');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'lang',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'lang',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: '原文行'),
      );

      final ProviderContainer container = _createContainer(
        lyricsApi: api,
        config: _buildConfig(searchSources: <String>['QM']),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('lang');
      await controller.search();
      await controller.openResult(0);

      controller.updatePreviewOptions(
        originalEnabled: false,
        translationEnabled: false,
      );

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.previewPhase, SearchPreviewPhase.ready);
      expect(state.previewText, isEmpty);
      expect(state.previewEmptyReason, SearchPreviewEmptyReason.noLanguage);
    });

    test('聚合源不支持当前搜索类型时返回错误', () async {
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['LRCLIB']),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('demo');
      controller.updateSearchType(SearchType.album);

      await controller.search();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.tableState, isA<AsyncError<List<SourceAware>>>());
      expect(
        (state.tableState as AsyncError<List<SourceAware>>).message,
        SearchTableStatusMessageCode.unsupportedSearchType,
      );
    });

    test('聚合搜索会按搜索类型过滤来源', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(id: 'qm-album-song', title: 'AlbumResult');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'album',
        searchType: SearchType.album,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'album',
          searchType: SearchType.album,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM', 'LRCLIB']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('album');
      controller.updateSearchType(SearchType.album);

      await controller.search();

      expect(api.searchCalls.length, 1);
      expect(api.searchCalls.single.source, Source.qm);
      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.tableState, isA<AsyncSuccess<List<SourceAware>>>());
      expect(
        (state.tableState as AsyncSuccess<List<SourceAware>>).data.length,
        1,
      );
    });

    test('分页 loadMore 会按来源范围请求下一页并合并结果', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final List<SongInfo> page1 = List<SongInfo>.generate(
        20,
        (int index) => _song(id: 'p1-$index', title: 'Song-$index'),
      );
      final List<SongInfo> page2 = List<SongInfo>.generate(
        20,
        (int index) => _song(id: 'p2-$index', title: 'Song-${index + 20}'),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'demo',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: page1,
          source: Source.qm,
          keyword: 'demo',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 40,
        ),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'demo',
        searchType: SearchType.song,
        page: 2,
        result: _searchResult(
          items: page2,
          source: Source.qm,
          keyword: 'demo',
          searchType: SearchType.song,
          page: 2,
          start: 20,
          total: 40,
        ),
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('demo');
      await controller.search();
      await controller.loadMore();

      expect(api.searchCalls.map((entry) => entry.page).toList(), <int>[1, 2]);
      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.currentPathResult?.length, 40);
      expect(state.hasMore, isFalse);
    });

    test('不足整页但仍有更多结果时会前进到第 2 页', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final List<SongInfo> page1 = List<SongInfo>.generate(
        15,
        (int index) => _song(id: 'short-$index', title: 'Short-$index'),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'short-page',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: page1,
          source: Source.qm,
          keyword: 'short-page',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 40,
        ),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'short-page',
        searchType: SearchType.song,
        page: 2,
        result: _searchResult(
          items: <SourceAware>[_song(id: 'page-2', title: 'Page 2')],
          source: Source.qm,
          keyword: 'short-page',
          searchType: SearchType.song,
          page: 2,
          start: 20,
          total: 40,
        ),
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('short-page');
      await controller.search();
      await controller.loadMore();

      expect(api.searchCalls.map((entry) => entry.page).toList(), <int>[1, 2]);
    });

    test('分页范围重叠时保留当前结果并进入可重试状态', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final List<SongInfo> page1 = List<SongInfo>.generate(
        20,
        (int index) => _song(id: 'overlap-p1-$index', title: 'Page 1-$index'),
      );
      final List<SongInfo> page2 = List<SongInfo>.generate(
        40,
        (int index) => _song(id: 'overlap-p2-$index', title: 'Page 2-$index'),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'overlap',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: page1,
          source: Source.qm,
          keyword: 'overlap',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 984,
        ),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'overlap',
        searchType: SearchType.song,
        page: 2,
        result: _searchResult(
          items: page2,
          source: Source.qm,
          keyword: 'overlap',
          searchType: SearchType.song,
          page: 2,
          start: 15,
          total: 984,
        ),
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('overlap');
      await controller.search();
      await controller.loadMore();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.isLoadingMore, isFalse);
      expect(state.currentPathResult, hasLength(20));
      expect(state.tableState, isA<AsyncPartial<List<SourceAware>>>());
      expect(
        (state.tableState as AsyncPartial<List<SourceAware>>).warningMessage,
        SearchTableStatusMessageCode.loadMoreFailed,
      );
    });

    test('分页请求迟到不会取消正在打开的歌词预览', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final List<SongInfo> page1 = List<SongInfo>.generate(
        20,
        (int index) => _song(id: 'preview-p1-$index', title: 'Preview $index'),
      );
      final List<SongInfo> page2 = List<SongInfo>.generate(
        20,
        (int index) =>
            _song(id: 'preview-p2-$index', title: 'Preview ${index + 20}'),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'preview-loadmore',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: page1,
          source: Source.qm,
          keyword: 'preview-loadmore',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 40,
        ),
      );
      api.setControlledSearchResult(
        source: Source.qm,
        keyword: 'preview-loadmore',
        searchType: SearchType.song,
        page: 2,
        result: _searchResult(
          items: page2,
          source: Source.qm,
          keyword: 'preview-loadmore',
          searchType: SearchType.song,
          page: 2,
          start: 20,
          total: 40,
        ),
      );
      api.setControlledResolveResult(
        page1.first.id!,
        LyricsResolvedResult(
          lyrics: _lyricsForSong(page1.first, text: '分页期间打开的歌词'),
        ),
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('preview-loadmore');
      await controller.search();

      final Future<void> openPreview = controller.openResult(0);
      final Future<void> loadMore = controller.loadMore();
      api.completeSearch(
        source: Source.qm,
        keyword: 'preview-loadmore',
        searchType: SearchType.song,
        page: 2,
      );
      await loadMore;
      api.completeResolve(page1.first.id!);
      await openPreview;

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.currentPathResult?.length, 40);
      expect(state.previewPhase, SearchPreviewPhase.ready);
      expect(state.previewText, contains('分页期间打开的歌词'));
    });

    test('打开歌词预览迟到不会取消正在合并的分页结果', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final List<SongInfo> page1 = List<SongInfo>.generate(
        20,
        (int index) => _song(id: 'load-p1-$index', title: 'Load $index'),
      );
      final List<SongInfo> page2 = List<SongInfo>.generate(
        20,
        (int index) => _song(id: 'load-p2-$index', title: 'Load ${index + 20}'),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'loadmore-preview',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: page1,
          source: Source.qm,
          keyword: 'loadmore-preview',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 40,
        ),
      );
      api.setControlledSearchResult(
        source: Source.qm,
        keyword: 'loadmore-preview',
        searchType: SearchType.song,
        page: 2,
        result: _searchResult(
          items: page2,
          source: Source.qm,
          keyword: 'loadmore-preview',
          searchType: SearchType.song,
          page: 2,
          start: 20,
          total: 40,
        ),
      );
      api.setControlledResolveResult(
        page1.first.id!,
        LyricsResolvedResult(
          lyrics: _lyricsForSong(page1.first, text: '打开预览期间分页'),
        ),
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('loadmore-preview');
      await controller.search();

      final Future<void> loadMore = controller.loadMore();
      final Future<void> openPreview = controller.openResult(0);
      api.completeResolve(page1.first.id!);
      await openPreview;
      api.completeSearch(
        source: Source.qm,
        keyword: 'loadmore-preview',
        searchType: SearchType.song,
        page: 2,
      );
      await loadMore;

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.currentPathResult?.length, 40);
      expect(state.previewPhase, SearchPreviewPhase.ready);
      expect(state.previewText, contains('打开预览期间分页'));
    });

    test('旧搜索迟到不会覆盖后发起的新搜索结果', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      api.setControlledSearchResult(
        source: Source.qm,
        keyword: 'old-search',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[_song(id: 'old-1', title: '旧结果')],
          source: Source.qm,
          keyword: 'old-search',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'new-search',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[_song(id: 'new-1', title: '新结果')],
          source: Source.qm,
          keyword: 'new-search',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('old-search');
      final Future<void> oldSearch = controller.search();
      controller.setKeyword('new-search');
      await controller.search();

      api.completeSearch(
        source: Source.qm,
        keyword: 'old-search',
        searchType: SearchType.song,
        page: 1,
      );
      await oldSearch;

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect((state.currentPathResult?.single as SongInfo?)?.id, 'new-1');
      expect(state.keyword, 'new-search');
    });

    test('旧歌词预览迟到不会覆盖后打开的歌词', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo first = _song(id: 'preview-old', title: '旧预览');
      final SongInfo second = _song(id: 'preview-new', title: '新预览');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'preview-race',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[first, second],
          source: Source.qm,
          keyword: 'preview-race',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 2,
        ),
      );
      api.setControlledResolveResult(
        first.id!,
        LyricsResolvedResult(lyrics: _lyricsForSong(first, text: '旧预览歌词')),
      );
      api.setControlledResolveResult(
        second.id!,
        LyricsResolvedResult(lyrics: _lyricsForSong(second, text: '新预览歌词')),
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('preview-race');
      await controller.search();

      final Future<void> oldPreview = controller.openResult(0);
      final Future<void> newPreview = controller.openResult(1);
      api.completeResolve(second.id!);
      await newPreview;
      api.completeResolve(first.id!);
      await oldPreview;

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.songIdText, second.id);
      expect(state.previewText, contains('新预览歌词'));
      expect(state.previewText, isNot(contains('旧预览歌词')));
    });

    test('双击歌单进入子层并支持返回', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongListInfo listInfo = SongListInfo(
        source: Source.qm,
        type: SongListType.album,
        id: 'album-1',
        title: 'Album',
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
          items: <SourceAware>[listInfo],
          source: Source.qm,
          keyword: 'album',
          searchType: SearchType.album,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.songlistById[listInfo.id] = APIResultList<SongInfo>(
        <SongInfo>[_song(id: 's1', title: 'ChildSong')],
        info: listInfo,
        ranges: <Source, SourceRange>{
          Source.qm: const SourceRange(start: 0, end: 0, total: 1),
        },
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.updateSearchType(SearchType.album);
      controller.setKeyword('album');
      await controller.search();

      await controller.openResult(0);
      expect(
        container.read(searchWorkflowControllerProvider).pathStack.length,
        2,
      );

      controller.returnPath();
      expect(
        container.read(searchWorkflowControllerProvider).pathStack.length,
        1,
      );
    });

    test('打开歌单前会清空上一条歌曲残留的预览状态', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(id: 'preview-song', title: 'Preview Song');
      final SongListInfo listInfo = SongListInfo(
        source: Source.qm,
        type: SongListType.album,
        id: 'album-preview',
        title: 'Preview Album',
        imgUrl: '',
        songCount: 1,
        publishTimeS: 1700000000,
        author: 'Author',
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'preview-song',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'preview-song',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: '旧歌词预览'),
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'preview-album',
        searchType: SearchType.album,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[listInfo],
          source: Source.qm,
          keyword: 'preview-album',
          searchType: SearchType.album,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.songlistById[listInfo.id] = APIResultList<SongInfo>(
        <SongInfo>[_song(id: 'child-song', title: 'Child Song')],
        info: listInfo,
        ranges: <Source, SourceRange>{
          Source.qm: const SourceRange(start: 0, end: 0, total: 1),
        },
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('preview-song');
      await controller.search();
      await controller.openResult(0);

      SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.currentLyrics, isNotNull);
      expect(state.previewPhase, SearchPreviewPhase.ready);
      expect(state.previewText, contains('旧歌词预览'));

      controller.updateSearchType(SearchType.album);
      controller.setKeyword('preview-album');
      await controller.search();
      await controller.openResult(0);

      state = container.read(searchWorkflowControllerProvider);
      expect(state.currentPathResult?.info, same(listInfo));
      expect(state.currentLyrics, isNull);
      expect(state.previewText, isEmpty);
      expect(state.songIdText, isEmpty);
      expect(state.previewPhase, SearchPreviewPhase.idle);
      expect(state.previewEmptyReason, SearchPreviewEmptyReason.noSelection);
    });

    test('保存当前歌单歌词会回写批量进度与汇总状态', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongListInfo listInfo = SongListInfo(
        source: Source.qm,
        type: SongListType.songlist,
        id: 'list-1',
        title: 'List',
        imgUrl: '',
        songCount: 2,
        publishTimeS: 1700000000,
        author: 'Tester',
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'list',
        searchType: SearchType.songlist,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[listInfo],
          source: Source.qm,
          keyword: 'list',
          searchType: SearchType.songlist,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.songlistById[listInfo.id] = APIResultList<SongInfo>(
        <SongInfo>[
          _song(id: 'ls-1', title: 'Song-A'),
          _song(id: 'ls-2', title: 'Song-B'),
        ],
        info: listInfo,
        ranges: <Source, SourceRange>{
          Source.qm: const SourceRange(start: 0, end: 1, total: 2),
        },
      );
      final _FakeBatchSaveUseCase batchSaveUseCase = _FakeBatchSaveUseCase();
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: _FakeAppFilePicker(directory: 'D:/tmp'),
        batchSaveUseCase: batchSaveUseCase,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.updateSearchType(SearchType.songlist);
      controller.setKeyword('list');
      await controller.search();
      await controller.openResult(0);
      controller.updateSaveDirectoryPath('D:/tmp');
      await controller.saveCurrentListLyrics();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(batchSaveUseCase.callCount, 1);
      expect(state.isBatchSaving, isFalse);
      expect(state.batchProgress, isNull);
      expect(state.notice?.code, SearchNoticeCode.batchSaveCompleted);
      expect(state.notice?.successCount, 2);
      expect(state.notice?.failureCount, 0);
      expect(state.notice?.skippedCount, 0);
      expect(state.notice?.severity, PageNoticeSeverity.success);
    });

    test('销毁 provider 容器时会取消正在执行的批量保存', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongListInfo listInfo = SongListInfo(
        source: Source.qm,
        type: SongListType.songlist,
        id: 'list-dispose',
        title: 'List Dispose',
        imgUrl: '',
        songCount: 1,
        publishTimeS: 1700000000,
        author: 'Tester',
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'dispose-list',
        searchType: SearchType.songlist,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[listInfo],
          source: Source.qm,
          keyword: 'dispose-list',
          searchType: SearchType.songlist,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.songlistById[listInfo.id] = APIResultList<SongInfo>(
        <SongInfo>[_song(id: 'dispose-song', title: 'Dispose Song')],
        info: listInfo,
        ranges: <Source, SourceRange>{
          Source.qm: const SourceRange(start: 0, end: 0, total: 1),
        },
      );
      final _ControlledBatchSaveUseCase batchSaveUseCase =
          _ControlledBatchSaveUseCase();
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: _FakeAppFilePicker(directory: 'D:/tmp'),
        batchSaveUseCase: batchSaveUseCase,
      );
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.updateSearchType(SearchType.songlist);
      controller.setKeyword('dispose-list');
      await controller.search();
      await controller.openResult(0);
      controller.updateSaveDirectoryPath('D:/tmp');
      final Future<void> saveFuture = controller.saveCurrentListLyrics();
      await batchSaveUseCase.started;

      expect(batchSaveUseCase.lastToken?.isCancelled, isFalse);
      container.dispose();
      expect(batchSaveUseCase.lastToken?.isCancelled, isTrue);

      batchSaveUseCase.complete(cancelled: true);
      await saveFuture;
    });

    test('取消后迟到的批量保存进度不会继续污染状态', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongListInfo listInfo = SongListInfo(
        source: Source.qm,
        type: SongListType.songlist,
        id: 'list-cancel-progress',
        title: 'List Cancel',
        imgUrl: '',
        songCount: 1,
        publishTimeS: 1700000000,
        author: 'Tester',
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'cancel-progress',
        searchType: SearchType.songlist,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[listInfo],
          source: Source.qm,
          keyword: 'cancel-progress',
          searchType: SearchType.songlist,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.songlistById[listInfo.id] = APIResultList<SongInfo>(
        <SongInfo>[_song(id: 'cancel-song', title: 'Cancel Song')],
        info: listInfo,
        ranges: <Source, SourceRange>{
          Source.qm: const SourceRange(start: 0, end: 0, total: 1),
        },
      );
      final _ControlledBatchSaveUseCase batchSaveUseCase =
          _ControlledBatchSaveUseCase();
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: _FakeAppFilePicker(directory: 'D:/tmp'),
        batchSaveUseCase: batchSaveUseCase,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.updateSearchType(SearchType.songlist);
      controller.setKeyword('cancel-progress');
      await controller.search();
      await controller.openResult(0);
      controller.updateSaveDirectoryPath('D:/tmp');
      final Future<void> saveFuture = controller.saveCurrentListLyrics();
      await batchSaveUseCase.started;

      await controller.saveCurrentListLyrics();
      batchSaveUseCase.emitProgress(
        const SearchBatchSaveProgressMessage(
          code: SearchBatchSaveProgressMessageCode.fetchingLyrics,
          songName: 'cancelled',
        ),
      );

      SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(
        state.batchProgress?.message.code,
        isNot(SearchBatchSaveProgressMessageCode.fetchingLyrics),
      );
      expect(state.notice?.code, SearchNoticeCode.batchCancelling);

      batchSaveUseCase.complete(cancelled: true);
      await saveFuture;

      state = container.read(searchWorkflowControllerProvider);
      expect(state.isBatchSaving, isFalse);
      expect(state.batchProgress, isNull);
      expect(state.notice?.code, SearchNoticeCode.batchSaveCancelled);
      expect(state.notice?.successCount, 0);
      expect(state.notice?.failureCount, 0);
      expect(state.notice?.skippedCount, 0);
      expect(state.notice?.severity, PageNoticeSeverity.info);
    });

    test('桌面端保存预览到文件夹时直接使用当前保存路径', () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'lddc-search-save-',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(id: 'song-save-dir', title: 'SaveDir');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'save-dir',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'save-dir',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: '保存到文件夹'),
      );
      final _FakeAppFilePicker picker = _FakeAppFilePicker();
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.setKeyword('save-dir');
      await controller.search();
      await controller.openResult(0);
      controller.updateSaveDirectoryPath(root.path);
      await controller.savePreviewToDirectory();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(picker.pickDirectoryCallCount, 0);
      expect(state.notice?.severity, PageNoticeSeverity.success);
      expect(state.notice?.code, SearchNoticeCode.lyricsSaveSucceeded);
      expect(state.notice?.detail, contains(root.path));
      expect(root.listSync(recursive: true).whereType<File>(), isNotEmpty);
    });

    test('保存路径为空时批量保存直接提示且不调目录选择', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongListInfo listInfo = SongListInfo(
        source: Source.qm,
        type: SongListType.songlist,
        id: 'list-empty-path',
        title: 'List',
        imgUrl: '',
        songCount: 1,
        publishTimeS: 1700000000,
        author: 'Tester',
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'empty-path',
        searchType: SearchType.songlist,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[listInfo],
          source: Source.qm,
          keyword: 'empty-path',
          searchType: SearchType.songlist,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.songlistById[listInfo.id] = APIResultList<SongInfo>(
        <SongInfo>[_song(id: 'ls-1', title: 'Song-A')],
        info: listInfo,
        ranges: <Source, SourceRange>{
          Source.qm: const SourceRange(start: 0, end: 0, total: 1),
        },
      );
      final _FakeAppFilePicker picker = _FakeAppFilePicker();
      final _FakeBatchSaveUseCase batchSaveUseCase = _FakeBatchSaveUseCase();
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
        batchSaveUseCase: batchSaveUseCase,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.updateSaveDirectoryPath('');
      controller.updateSearchType(SearchType.songlist);
      controller.setKeyword('empty-path');
      await controller.search();
      await controller.openResult(0);
      await controller.saveCurrentListLyrics();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(batchSaveUseCase.callCount, 0);
      expect(picker.pickDirectoryCallCount, 0);
      expect(state.notice?.code, SearchNoticeCode.selectSavePathFirst);
      expect(state.notice?.severity, PageNoticeSeverity.warning);
    });

    test('保存预览到文件会调用 saveTextFile 并写回建议文件名', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(id: 'song-save-file', title: 'SaveFile');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'save-file',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'save-file',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: '保存到文件'),
      );
      final _FakeAppFilePicker picker = _FakeAppFilePicker(
        savedFilePath: 'D:/save/SaveFile.lrc',
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.setKeyword('save-file');
      await controller.search();
      await controller.openResult(0);
      await controller.savePreviewToFile();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(picker.saveTextFileCallCount, 1);
      expect(picker.lastSavedFileName, contains('SaveFile'));
      expect(picker.lastSavedText, contains('保存到文件'));
      expect(picker.lastAllowedExtensions, <String>['lrc']);
      expect(state.saveDirectoryPath, 'D:/save');
      expect(state.notice?.severity, PageNoticeSeverity.success);
    });

    test('保存预览到文件迟到完成不会污染后打开的歌词状态', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo first = _song(id: 'save-race-old', title: 'OldSave');
      final SongInfo second = _song(id: 'save-race-new', title: 'NewSave');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'save-race',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[first, second],
          source: Source.qm,
          keyword: 'save-race',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 2,
        ),
      );
      api.resolveBySongId[first.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(first, text: '旧保存歌词'),
      );
      api.resolveBySongId[second.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(second, text: '新预览歌词'),
      );
      final Completer<SavedTextFileResult?> saveCompleter =
          Completer<SavedTextFileResult?>();
      final _FakeAppFilePicker picker = _FakeAppFilePicker(
        savedFilePath: 'D:/save/old.lrc',
        saveTextCompleter: saveCompleter,
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.setKeyword('save-race');
      await controller.search();
      await controller.openResult(0);
      final Future<void> pendingSave = controller.savePreviewToFile();
      expect(picker.saveTextFileCallCount, 1);
      expect(
        container.read(searchWorkflowControllerProvider).isSavingPreview,
        isTrue,
      );

      await controller.openResult(1);
      saveCompleter.complete(SavedTextFileResult.localPath('D:/save/old.lrc'));
      await pendingSave;

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(picker.lastSavedText, contains('旧保存歌词'));
      expect(state.songIdText, second.id);
      expect(state.previewText, contains('新预览歌词'));
      expect(state.previewText, isNot(contains('旧保存歌词')));
      expect(state.isSavingPreview, isFalse);
      expect(state.lastSavedPath, isNull);
      expect(state.notice?.detail, isNot(contains('old.lrc')));
    });

    test('Android 保存预览到文件成功后不回写桌面保存路径状态', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(
        id: 'song-android-save-file',
        title: 'AndroidSaveFile',
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'android-save-file',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'android-save-file',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: 'Android 保存到文件'),
      );
      final _FakeAppFilePicker picker = _FakeAppFilePicker(
        savedFilePath: 'content://documents/document/android-save-file.lrc',
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
        capability: _androidCapability(),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.updateSaveDirectoryPath('D:/desktop-default');
      controller.setKeyword('android-save-file');
      await controller.search();
      await controller.openResult(0);
      await controller.savePreviewToFile();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(picker.saveTextFileCallCount, 1);
      expect(state.saveDirectoryPath, 'D:/desktop-default');
      expect(
        state.notice?.detail,
        contains('content://documents/document/android-save-file.lrc'),
      );
      expect(state.notice?.severity, PageNoticeSeverity.success);
    });

    test('iOS 保存预览到文件成功后不回写桌面保存路径状态', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(id: 'song-ios-save-file', title: 'IosSave');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'ios-save-file',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'ios-save-file',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: 'iOS 保存到文件'),
      );
      final _FakeAppFilePicker picker = _FakeAppFilePicker(
        savedFilePath:
            'file:///private/var/mobile/Containers/Data/lyrics/ios-save-file.lrc',
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
        capability: _iosCapability(),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.updateSaveDirectoryPath('D:/desktop-default');
      controller.setKeyword('ios-save-file');
      await controller.search();
      await controller.openResult(0);
      await controller.savePreviewToFile();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(picker.saveTextFileCallCount, 1);
      expect(state.saveDirectoryPath, 'D:/desktop-default');
      expect(
        state.notice?.detail,
        contains(
          'file:///private/var/mobile/Containers/Data/lyrics/ios-save-file.lrc',
        ),
      );
      expect(state.notice?.severity, PageNoticeSeverity.success);
    });

    test('保存预览到歌曲标签时优先使用 Android content uri', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(id: 'song-save-tag', title: 'SaveTag');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'save-tag',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'save-tag',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: '保存到标签'),
      );
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway();
      final _FakeAppFilePicker picker = _FakeAppFilePicker(
        pickedAudioFile: const PickedAudioFileHandle(
          name: 'picked.mp3',
          path: '/storage/emulated/0/Music/picked.mp3',
          identifier: 'content://media/external/audio/media/42',
        ),
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
        mediaGateway: mediaGateway,
        capability: _androidCapability(),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.setKeyword('save-tag');
      await controller.search();
      await controller.openResult(0);
      await controller.savePreviewToTag();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(picker.pickAudioFileCallCount, 1);
      expect(
        mediaGateway.lastSongPath,
        'content://media/external/audio/media/42',
      );
      expect(mediaGateway.lastLyricsText, contains('保存到标签'));
      expect(state.notice?.severity, PageNoticeSeverity.success);
    });

    test('iOS 保存预览到歌曲标签时透传 fd 并在成功后释放句柄', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(id: 'song-ios-save-tag', title: 'IosSaveTag');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'ios-save-tag',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'ios-save-tag',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: 'iOS 标签保存'),
      );
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway();
      final PickedAudioFileHandle pickedAudioFile = const PickedAudioFileHandle(
        name: 'picked.m4a',
        path: '/private/var/mobile/song.m4a',
        identifier: 'file:///private/var/mobile/song.m4a',
        fileDescriptor: 55,
        fileDescriptorNameHint: 'picked.m4a',
      );
      final _FakeAppFilePicker picker = _FakeAppFilePicker(
        pickedAudioFile: pickedAudioFile,
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
        mediaGateway: mediaGateway,
        capability: _iosCapability(),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.setKeyword('ios-save-tag');
      await controller.search();
      await controller.openResult(0);
      await controller.savePreviewToTag();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(mediaGateway.lastSongPath, pickedAudioFile.targetPath);
      expect(mediaGateway.lastFileDescriptor, 55);
      expect(mediaGateway.lastFileDescriptorNameHint, 'picked.m4a');
      expect(picker.releaseAudioFileCallCount, 1);
      expect(picker.releasedFiles.single, pickedAudioFile);
      expect(state.notice?.severity, PageNoticeSeverity.success);
    });

    test('iOS 保存预览到歌曲标签失败后仍会释放句柄', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(
        id: 'song-ios-save-tag-fail',
        title: 'IosFail',
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'ios-save-tag-fail',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'ios-save-tag-fail',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: 'iOS 标签保存失败'),
      );
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()
            ..writeError = const LocalMatchTagWriteException('写入失败');
      final PickedAudioFileHandle pickedAudioFile = const PickedAudioFileHandle(
        name: 'picked.flac',
        path: '/private/var/mobile/song.flac',
        fileDescriptor: 66,
        fileDescriptorNameHint: 'picked.flac',
      );
      final _FakeAppFilePicker picker = _FakeAppFilePicker(
        pickedAudioFile: pickedAudioFile,
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        filePicker: picker,
        mediaGateway: mediaGateway,
        capability: _iosCapability(),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.setKeyword('ios-save-tag-fail');
      await controller.search();
      await controller.openResult(0);
      await controller.savePreviewToTag();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(picker.releaseAudioFileCallCount, 1);
      expect(state.notice?.severity, PageNoticeSeverity.error);
      expect(state.notice?.code, SearchNoticeCode.lyricsSaveFailed);
      expect(state.notice?.detail, contains('写入失败'));
    });

    test('Android 批量保存歌词走 SAF 用例而不是桌面目录保存', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongListInfo listInfo = SongListInfo(
        source: Source.qm,
        type: SongListType.songlist,
        id: 'android-list-1',
        title: 'Android List',
        imgUrl: '',
        songCount: 2,
        publishTimeS: 1700000000,
        author: 'Tester',
      );
      api.setSearchResult(
        source: Source.qm,
        keyword: 'android-list',
        searchType: SearchType.songlist,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[listInfo],
          source: Source.qm,
          keyword: 'android-list',
          searchType: SearchType.songlist,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.songlistById[listInfo.id] = APIResultList<SongInfo>(
        <SongInfo>[
          _song(id: 'android-song-1', title: 'Android Song A'),
          _song(id: 'android-song-2', title: 'Android Song B'),
        ],
        info: listInfo,
        ranges: <Source, SourceRange>{
          Source.qm: const SourceRange(start: 0, end: 1, total: 2),
        },
      );
      final _FakeBatchSaveUseCase batchSaveUseCase = _FakeBatchSaveUseCase();
      final _FakeAndroidSafBatchSaveUseCase androidSafBatchSaveUseCase =
          _FakeAndroidSafBatchSaveUseCase();
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        pickedTree: const AndroidSafTreeToken(
          uri: 'content://tree/primary%3ADocuments%2FLyrics',
          displayName: 'Lyrics',
        ),
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        batchSaveUseCase: batchSaveUseCase,
        androidSafBatchSaveUseCase: androidSafBatchSaveUseCase,
        androidSafTreePort: treePort,
        capability: _androidCapability(),
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );

      controller.updateSearchType(SearchType.songlist);
      controller.setKeyword('android-list');
      await controller.search();
      await controller.openResult(0);
      await controller.saveCurrentListLyrics();

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(treePort.pickTreeCallCount, 1);
      expect(treePort.persistedUris, <String>[
        'content://tree/primary%3ADocuments%2FLyrics',
      ]);
      expect(batchSaveUseCase.callCount, 0);
      expect(androidSafBatchSaveUseCase.callCount, 1);
      expect(
        androidSafBatchSaveUseCase.lastTreeUri,
        'content://tree/primary%3ADocuments%2FLyrics',
      );
      expect(state.isBatchSaving, isFalse);
      expect(state.batchProgress, isNull);
      expect(state.notice?.code, SearchNoticeCode.batchSaveCompleted);
      expect(state.notice?.successCount, 2);
      expect(state.notice?.failureCount, 0);
      expect(state.notice?.skippedCount, 0);
      expect(state.notice?.severity, PageNoticeSeverity.success);
    });

    test('候选歌词流程支持“先候选后回退到歌词预览”', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo song = _song(
        source: Source.kg,
        id: 'kg-1',
        title: 'NeedSelect',
      );
      final LyricInfo candidate = LyricInfo(
        source: Source.kg,
        songInfo: song,
        id: 'lyric-1',
      );
      api.setSearchResult(
        source: Source.kg,
        keyword: 'need',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.kg,
          keyword: 'need',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsSelectionRequiredResult(
        candidates: APIResultList<LyricInfo>(
          <LyricInfo>[candidate],
          info: song,
          ranges: <Source, SourceRange>{
            Source.kg: const SourceRange(start: 0, end: 0, total: 1),
          },
        ),
      );
      api.lyricsById[candidate.id!] = _lyricsForSong(song, text: 'Selected');

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['KG'], autoSelect: false),
        lyricsApi: api,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('need');
      await controller.search();
      await controller.openResult(0);

      final SearchWorkflowState afterSelect = container.read(
        searchWorkflowControllerProvider,
      );
      expect(afterSelect.pathStack.length, 2);
      expect(afterSelect.previewPhase, SearchPreviewPhase.idle);
      expect(
        afterSelect.notice?.code,
        SearchNoticeCode.multipleLyricsCandidates,
      );

      await controller.openResult(0);
      final SearchWorkflowState finalState = container.read(
        searchWorkflowControllerProvider,
      );
      expect(finalState.currentLyrics, isNotNull);
      expect(finalState.previewPhase, SearchPreviewPhase.ready);
      expect(finalState.previewText, contains('Selected'));
    });

    test('翻译切换会在歌词中增删 LDDC_ts', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final _FakeTranslateApi translateApi = _FakeTranslateApi()
        ..translated = <LyricsLine>[
          LyricsLine(
            startMs: 0,
            endMs: 1000,
            words: const <LyricsWord>[
              LyricsWord(startMs: 0, endMs: 1000, text: '翻译行'),
            ],
          ),
        ];
      final SongInfo song = _song(id: 'song-1', title: 'TranslateMe');
      api.setSearchResult(
        source: Source.qm,
        keyword: 't',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 't',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: '原文行'),
      );

      final ProviderContainer container = _createContainer(
        config: _buildConfig(searchSources: <String>['QM']),
        lyricsApi: api,
        translateApi: translateApi,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('t');
      await controller.search();
      await controller.openResult(0);

      await controller.toggleTranslation();
      SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.currentLyrics?.data.containsKey('LDDC_ts'), isTrue);
      expect(translateApi.callCount, 1);

      await controller.toggleTranslation();
      state = container.read(searchWorkflowControllerProvider);
      expect(state.currentLyrics?.data.containsKey('LDDC_ts'), isFalse);
    });

    test('OpenAI 翻译流式进度只在当前歌词请求内写入状态', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final _FakeTranslateApi translateApi = _FakeTranslateApi()
        ..progresses = <OpenAiTranslationProgress>[
          const OpenAiTranslationProgress(
            completedLines: 1,
            totalLines: 2,
            isIndeterminate: false,
          ),
        ]
        ..completer = Completer<LyricsData>()
        ..translated = <LyricsLine>[
          LyricsLine(
            startMs: 0,
            endMs: 1000,
            words: const <LyricsWord>[
              LyricsWord(startMs: 0, endMs: 1000, text: '翻译行'),
            ],
          ),
        ];
      final SongInfo song = _song(id: 'song-progress', title: 'Progress');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'progress',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'progress',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: '原文行'),
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(
          searchSources: <String>['QM'],
          translateSource: TranslateSource.openai,
        ),
        lyricsApi: api,
        translateApi: translateApi,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('progress');
      await controller.search();
      await controller.openResult(0);

      final Future<void> translation = controller.toggleTranslation();
      await Future<void>.delayed(Duration.zero);

      SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(translateApi.receivedProgressCallback, isTrue);
      expect(state.translationProgress?.completedLines, 1);
      expect(state.translationProgress?.totalLines, 2);

      translateApi.completer!.complete(translateApi.translated);
      await translation;
      state = container.read(searchWorkflowControllerProvider);
      expect(state.translationProgress, isNull);
      expect(state.currentLyrics?.data.containsKey('LDDC_ts'), isTrue);
    });

    test('非 OpenAI 翻译源不启用行级进度回调', () async {
      final _FakeLyricsApi api = _FakeLyricsApi();
      final _FakeTranslateApi translateApi = _FakeTranslateApi()
        ..completer = Completer<LyricsData>()
        ..translated = <LyricsLine>[
          LyricsLine(
            startMs: 0,
            endMs: 1000,
            words: const <LyricsWord>[
              LyricsWord(startMs: 0, endMs: 1000, text: '翻译行'),
            ],
          ),
        ];
      final SongInfo song = _song(id: 'song-bing', title: 'Bing');
      api.setSearchResult(
        source: Source.qm,
        keyword: 'bing',
        searchType: SearchType.song,
        page: 1,
        result: _searchResult(
          items: <SourceAware>[song],
          source: Source.qm,
          keyword: 'bing',
          searchType: SearchType.song,
          page: 1,
          start: 0,
          total: 1,
        ),
      );
      api.resolveBySongId[song.id!] = LyricsResolvedResult(
        lyrics: _lyricsForSong(song, text: '原文行'),
      );
      final ProviderContainer container = _createContainer(
        config: _buildConfig(
          searchSources: <String>['QM'],
          translateSource: TranslateSource.bing,
        ),
        lyricsApi: api,
        translateApi: translateApi,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      controller.setKeyword('bing');
      await controller.search();
      await controller.openResult(0);

      final Future<void> translation = controller.toggleTranslation();
      await Future<void>.delayed(Duration.zero);

      SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(translateApi.receivedProgressCallback, isFalse);
      expect(state.isTranslating, isTrue);
      expect(state.translationProgress, isNull);
      await controller.toggleTranslation();
      expect(translateApi.callCount, 1);

      translateApi.completer!.complete(translateApi.translated);
      await translation;
      state = container.read(searchWorkflowControllerProvider);
      expect(state.isTranslating, isFalse);
      expect(state.currentLyrics?.data.containsKey('LDDC_ts'), isTrue);

      await controller.toggleTranslation();
      translateApi.completer = Completer<LyricsData>();
      final Future<void> failedTranslation = controller.toggleTranslation();
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(searchWorkflowControllerProvider).isTranslating,
        isTrue,
      );
      translateApi.completer!.completeError(Exception('模拟翻译失败'));
      await failedTranslation;
      state = container.read(searchWorkflowControllerProvider);
      expect(state.isTranslating, isFalse);
      expect(state.notice?.code, SearchNoticeCode.translationFailed);
    });

    test('替换歌词会终止旧翻译活动且迟到结果不能覆盖新歌词', () async {
      final _FakeTranslateApi translateApi = _FakeTranslateApi()
        ..completer = Completer<LyricsData>();
      final ProviderContainer container = _createContainer(
        config: _buildConfig(translateSource: TranslateSource.bing),
        translateApi: translateApi,
      );
      addTearDown(container.dispose);
      final SearchWorkflowController controller = container.read(
        searchWorkflowControllerInstanceProvider,
      );
      final SongInfo oldSong = _song(id: 'old', title: 'Old');
      final SongInfo newSong = _song(id: 'new', title: 'New');
      final Lyrics oldLyrics = _lyricsForSong(oldSong, text: '旧歌词');
      final Lyrics newLyrics = _lyricsForSong(newSong, text: '新歌词');
      await controller.applyExternalPreset(lyrics: oldLyrics);

      final Future<void> translation = controller.toggleTranslation();
      await Future<void>.delayed(Duration.zero);
      await controller.applyExternalPreset(lyrics: newLyrics);
      expect(
        container.read(searchWorkflowControllerProvider).isTranslating,
        isFalse,
      );

      translateApi.completer!.complete(<LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: const <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: '迟到翻译'),
          ],
        ),
      ]);
      await translation;

      final SearchWorkflowState state = container.read(
        searchWorkflowControllerProvider,
      );
      expect(state.currentLyrics, same(newLyrics));
      expect(state.currentLyrics?.data.containsKey('LDDC_ts'), isFalse);
    });
  });
}

ProviderContainer _createContainer({
  AppConfig? config,
  _FakeLyricsApi? lyricsApi,
  _FakeTranslateApi? translateApi,
  AppFilePicker? filePicker,
  SearchBatchSaveLyricsUseCase? batchSaveUseCase,
  SearchAndroidSafBatchSaveLyricsUseCase? androidSafBatchSaveUseCase,
  AndroidSafTreePort? androidSafTreePort,
  LocalMatchMediaGateway? mediaGateway,
  AppCapability? capability,
  AutoFetchUseCase? autoFetchUseCase,
}) {
  final _FixedConfigRepository repository = _FixedConfigRepository(
    config ?? _buildConfig(),
  );
  final AppCapability resolvedCapability = capability ?? _desktopCapability();
  final _FakeLyricsApi resolvedLyricsApi = lyricsApi ?? _FakeLyricsApi();
  final _FakeTranslateApi resolvedTranslateApi =
      translateApi ?? _FakeTranslateApi();
  final AppFilePicker resolvedFilePicker = filePicker ?? _FakeAppFilePicker();
  final LocalMatchMediaGateway resolvedMediaGateway =
      mediaGateway ?? _FakeLocalMatchMediaGateway();
  final AndroidSafTreePort resolvedAndroidSafTreePort =
      androidSafTreePort ?? _FakeAndroidSafTreePort();
  final AutoFetchUseCase resolvedAutoFetchUseCase =
      autoFetchUseCase ?? AutoFetchUseCase(gateway: _NoopAutoFetchGateway());
  final SearchBatchSaveLyricsUseCase resolvedBatchSaveUseCase =
      batchSaveUseCase ??
      SearchBatchSaveLyricsUseCase(
        lyricsApi: resolvedLyricsApi,
        persistenceFactory: _fakePersistenceFactory,
      );
  final SearchAndroidSafBatchSaveLyricsUseCase
  resolvedAndroidSafBatchSaveUseCase =
      androidSafBatchSaveUseCase ??
      SearchAndroidSafBatchSaveLyricsUseCase(
        lyricsApi: resolvedLyricsApi,
        persistenceFactory: _fakePersistenceFactory,
      );
  return ProviderContainer(
    overrides: [
      appCapabilityProvider.overrideWith((ref) => resolvedCapability),
      searchWorkflowDependenciesProvider.overrideWithValue(
        SearchWorkflowDependencies(
          optionsResolver: () => repository.current.toSearchWorkflowOptions(),
          capabilities: resolvedCapability.toSearchWorkflowCapabilities(),
          lyricsApi: resolvedLyricsApi,
          translateApi: resolvedTranslateApi,
          mediaGateway: resolvedMediaGateway,
          filePicker: resolvedFilePicker,
          dragDropPort: const DragDropPortImpl(),
          androidSafTreePort: resolvedAndroidSafTreePort,
          batchSaveUseCase: resolvedBatchSaveUseCase,
          androidSafBatchSaveUseCase: resolvedAndroidSafBatchSaveUseCase,
          fileSavePersistenceFactory: _fakePersistenceFactory,
          autoFetchUseCase: resolvedAutoFetchUseCase,
        ),
      ),
      configRepositoryProvider.overrideWithValue(repository),
      lyricsApiProvider.overrideWithValue(resolvedLyricsApi),
      translateApiProvider.overrideWithValue(resolvedTranslateApi),
      localMatchMediaGatewayProvider.overrideWithValue(resolvedMediaGateway),
      autoFetchUseCaseProvider.overrideWithValue(resolvedAutoFetchUseCase),
      appFilePickerProvider.overrideWithValue(resolvedFilePicker),
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

AppConfig _buildConfig({
  List<String>? searchSources,
  bool autoSelect = true,
  TranslateSource? translateSource,
}) {
  final AppConfig base = ConfigDefaults.current;
  return AppConfig(
    schemaVersion: base.schemaVersion,
    search: SearchConfig(sources: searchSources ?? base.search.sources),
    lyrics: base.lyrics,
    match: MatchConfig(skipInst: base.match.skipInst, autoSelect: autoSelect),
    translate: TranslateConfig(
      source: translateSource ?? base.translate.source,
      targetLang: base.translate.targetLang,
      openAi: base.translate.openAi,
    ),
    desktop: base.desktop,
    app: base.app,
    storage: base.storage,
    legacyExtras: base.legacyExtras,
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

SongInfo _song({
  Source source = Source.qm,
  required String id,
  required String title,
}) {
  return SongInfo(
    source: source,
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

String _cueText() {
  return '''
TITLE "Album"
PERFORMER "Singer"
FILE "disc.wav" WAVE
  TRACK 01 AUDIO
    TITLE "First"
    PERFORMER "Singer"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Second"
    PERFORMER "Singer"
    INDEX 01 01:00:00
''';
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
  final Map<String, APIResultList<SourceAware>> _searchResults =
      <String, APIResultList<SourceAware>>{};
  final Map<String, Completer<APIResultList<SourceAware>>> _searchCompleters =
      <String, Completer<APIResultList<SourceAware>>>{};
  final Map<String, APIResultList<SongInfo>> songlistById =
      <String, APIResultList<SongInfo>>{};
  final Map<String, LyricsResolveResult> resolveBySongId =
      <String, LyricsResolveResult>{};
  final Map<String, Completer<LyricsResolveResult>> _resolveCompleters =
      <String, Completer<LyricsResolveResult>>{};
  final Map<String, Lyrics> lyricsById = <String, Lyrics>{};
  final List<({Source source, String keyword, SearchType type, int page})>
  searchCalls =
      <({Source source, String keyword, SearchType type, int page})>[];

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

  void setControlledSearchResult({
    required Source source,
    required String keyword,
    required SearchType searchType,
    required int page,
    required APIResultList<SourceAware> result,
  }) {
    final String key = _searchKey(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
    _searchResults[key] = result;
    _searchCompleters[key] = Completer<APIResultList<SourceAware>>();
  }

  void completeSearch({
    required Source source,
    required String keyword,
    required SearchType searchType,
    required int page,
  }) {
    final String key = _searchKey(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
    final Completer<APIResultList<SourceAware>>? completer =
        _searchCompleters[key];
    if (completer != null && !completer.isCompleted) {
      completer.complete(_searchResults[key]!);
    }
  }

  void setControlledResolveResult(String songId, LyricsResolveResult result) {
    resolveBySongId[songId] = result;
    _resolveCompleters[songId] = Completer<LyricsResolveResult>();
  }

  void completeResolve(String songId) {
    final Completer<LyricsResolveResult>? completer =
        _resolveCompleters[songId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(resolveBySongId[songId]!);
    }
  }

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    searchCalls.add((
      source: source,
      keyword: keyword,
      type: searchType,
      page: page,
    ));
    final String key = _searchKey(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
    final Completer<APIResultList<SourceAware>>? completer =
        _searchCompleters[key];
    if (completer != null) {
      return completer.future;
    }
    final APIResultList<SourceAware>? result = _searchResults[key];
    if (result == null) {
      throw StateError('未配置搜索结果: $source/$keyword/$searchType/$page');
    }
    return result;
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    final APIResultList<SongInfo>? result = songlistById[songListInfo.id];
    if (result == null) {
      throw StateError('未配置 songlist 结果: ${songListInfo.id}');
    }
    return result;
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw UnsupportedError('SearchWorkflowController 测试场景不支持候选歌词列表');
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    final Completer<LyricsResolveResult>? completer =
        _resolveCompleters[songInfo.id ?? ''];
    if (completer != null) {
      return completer.future;
    }
    final LyricsResolveResult? result = resolveBySongId[songInfo.id ?? ''];
    if (result == null) {
      throw StateError('未配置 resolve 结果: ${songInfo.id}');
    }
    return result;
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    final String key = switch (info) {
      SongInfo value => value.id ?? '',
      LyricInfo value => value.id ?? value.songInfo.id ?? '',
      _ => '',
    };
    final Lyrics? lyrics = lyricsById[key];
    if (lyrics == null) {
      throw const LddcLyricsNotFoundException('没有找到歌词');
    }
    return lyrics;
  }

  String _searchKey({
    required Source source,
    required String keyword,
    required SearchType searchType,
    required int page,
  }) {
    return '${source.value}|$keyword|${searchType.value}|$page';
  }
}

class _FakeTranslateApi implements TranslationClient {
  LyricsData translated = <LyricsLine>[];
  List<OpenAiTranslationProgress> progresses = <OpenAiTranslationProgress>[];
  Completer<LyricsData>? completer;
  int callCount = 0;
  bool receivedProgressCallback = false;

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
    receivedProgressCallback = onOpenAiProgress != null;
    for (final OpenAiTranslationProgress progress in progresses) {
      onOpenAiProgress?.call(progress);
    }
    final Completer<LyricsData>? currentCompleter = completer;
    if (currentCompleter != null) {
      return currentCompleter.future;
    }
    return translated;
  }
}

class _FakeAppFilePicker implements AppFilePicker {
  _FakeAppFilePicker({
    this.directory,
    this.savedFilePath,
    this.saveTextCompleter,
    this.pickedAudioFile,
  });

  final String? directory;
  final String? savedFilePath;
  final Completer<SavedTextFileResult?>? saveTextCompleter;
  final PickedAudioFileHandle? pickedAudioFile;
  int pickDirectoryCallCount = 0;
  int pickAudioFileCallCount = 0;
  int releaseAudioFileCallCount = 0;
  int saveTextFileCallCount = 0;
  String? lastSavedFileName;
  String? lastSavedText;
  List<String>? lastAllowedExtensions;
  String? lastInitialDirectory;
  final List<PickedAudioFileHandle> releasedFiles = <PickedAudioFileHandle>[];

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async {
    pickDirectoryCallCount += 1;
    return directory;
  }

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
    pickAudioFileCallCount += 1;
    return pickedAudioFile;
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) async => file;

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) async {
    releaseAudioFileCallCount += 1;
    releasedFiles.add(file);
  }

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    saveTextFileCallCount += 1;
    lastSavedFileName = fileName;
    lastSavedText = text;
    lastAllowedExtensions = allowedExtensions;
    lastInitialDirectory = initialDirectory;
    final Completer<SavedTextFileResult?>? completer = saveTextCompleter;
    if (completer != null) {
      return completer.future;
    }
    return savedFilePath == null
        ? null
        : SavedTextFileResult.localPath(savedFilePath!);
  }
}

class _FakeBatchSaveUseCase extends SearchBatchSaveLyricsUseCase {
  _FakeBatchSaveUseCase()
    : super(
        lyricsApi: _NoopLyricsApi(),
        persistenceFactory: _fakePersistenceFactory,
      );

  int callCount = 0;

  @override
  Future<SearchBatchSaveResult> execute({
    required List<SongInfo> songs,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required String saveFolder,
    required SearchBatchSaveOptions options,
    SearchBatchSaveCancellationToken? cancellationToken,
    SearchBatchSaveProgressCallback? onProgress,
  }) async {
    callCount += 1;
    onProgress?.call(
      SearchBatchSaveProgress(
        current: 1,
        total: songs.length,
        message: const SearchBatchSaveProgressMessage(
          code: SearchBatchSaveProgressMessageCode.preparing,
        ),
      ),
    );
    return SearchBatchSaveResult(
      total: songs.length,
      savedCount: songs.length,
      skippedCount: 0,
      failedCount: 0,
      cancelled: false,
      entries: <SearchBatchSaveEntryResult>[
        for (int index = 0; index < songs.length; index += 1)
          SearchBatchSaveEntryResult(
            index: index,
            song: songs[index],
            status: SearchBatchSaveEntryStatus.saved,
            message: SearchBatchSaveEntryStatus.saved.name,
          ),
      ],
    );
  }
}

class _ControlledBatchSaveUseCase extends SearchBatchSaveLyricsUseCase {
  _ControlledBatchSaveUseCase()
    : super(
        lyricsApi: _NoopLyricsApi(),
        persistenceFactory: _fakePersistenceFactory,
      );

  final Completer<void> _started = Completer<void>();
  final Completer<SearchBatchSaveResult> _result =
      Completer<SearchBatchSaveResult>();
  SearchBatchSaveCancellationToken? lastToken;
  SearchBatchSaveProgressCallback? _onProgress;
  List<SongInfo> _songs = const <SongInfo>[];

  Future<void> get started => _started.future;

  @override
  Future<SearchBatchSaveResult> execute({
    required List<SongInfo> songs,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required String saveFolder,
    required SearchBatchSaveOptions options,
    SearchBatchSaveCancellationToken? cancellationToken,
    SearchBatchSaveProgressCallback? onProgress,
  }) {
    _songs = songs;
    lastToken = cancellationToken;
    _onProgress = onProgress;
    if (!_started.isCompleted) {
      _started.complete();
    }
    return _result.future;
  }

  void emitProgress(SearchBatchSaveProgressMessage message) {
    _onProgress?.call(
      SearchBatchSaveProgress(
        current: 1,
        total: _songs.length,
        message: message,
      ),
    );
  }

  void complete({bool cancelled = false}) {
    if (_result.isCompleted) {
      return;
    }
    _result.complete(
      SearchBatchSaveResult(
        total: _songs.length,
        savedCount: cancelled ? 0 : _songs.length,
        skippedCount: 0,
        failedCount: 0,
        cancelled: cancelled,
        entries: <SearchBatchSaveEntryResult>[
          if (!cancelled)
            for (int index = 0; index < _songs.length; index += 1)
              SearchBatchSaveEntryResult(
                index: index,
                song: _songs[index],
                status: SearchBatchSaveEntryStatus.saved,
                message: SearchBatchSaveEntryStatus.saved.name,
              ),
        ],
      ),
    );
  }
}

class _FakeAndroidSafBatchSaveUseCase
    extends SearchAndroidSafBatchSaveLyricsUseCase {
  _FakeAndroidSafBatchSaveUseCase()
    : super(
        lyricsApi: _NoopLyricsApi(),
        persistenceFactory: _fakePersistenceFactory,
      );

  int callCount = 0;
  String? lastTreeUri;

  @override
  Future<SearchBatchSaveResult> execute({
    required List<SongInfo> songs,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required String treeUri,
    required SearchBatchSaveOptions options,
    SearchBatchSaveCancellationToken? cancellationToken,
    SearchBatchSaveProgressCallback? onProgress,
  }) async {
    callCount += 1;
    lastTreeUri = treeUri;
    onProgress?.call(
      SearchBatchSaveProgress(
        current: 1,
        total: songs.length,
        message: const SearchBatchSaveProgressMessage(
          code: SearchBatchSaveProgressMessageCode.preparing,
        ),
      ),
    );
    return SearchBatchSaveResult(
      total: songs.length,
      savedCount: songs.length,
      skippedCount: 0,
      failedCount: 0,
      cancelled: false,
      entries: <SearchBatchSaveEntryResult>[
        for (int index = 0; index < songs.length; index += 1)
          SearchBatchSaveEntryResult(
            index: index,
            song: songs[index],
            status: SearchBatchSaveEntryStatus.saved,
            message: SearchBatchSaveEntryStatus.saved.name,
            savePath: '$treeUri/${songs[index].title}.lrc',
          ),
      ],
    );
  }
}

LyricsSavePersistencePort _fakePersistenceFactory(String target) {
  return FileLyricsSavePersistence(folder: target);
}

class _FakeAndroidSafTreePort implements AndroidSafTreePort {
  _FakeAndroidSafTreePort({this.pickedTree});

  final AndroidSafTreeToken? pickedTree;
  int pickTreeCallCount = 0;
  final List<String> persistedUris = <String>[];

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
    pickTreeCallCount += 1;
    final AndroidSafTreeToken? result = pickedTree;
    if (result == null) {
      throw PlatformException(code: 'cancelled');
    }
    return result;
  }

  @override
  Future<void> persistTreePermission(String uri) async {
    persistedUris.add(uri);
  }

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
}

class _FakeLocalMatchMediaGateway implements LocalMatchMediaGateway {
  final Map<String, List<SongInfo>> songInfosByPath =
      <String, List<SongInfo>>{};
  final Map<String, int?> durations = <String, int?>{};
  String? lastSongPath;
  String? lastLyricsText;
  Lyrics? lastLyrics;
  int? lastFileDescriptor;
  String? lastFileDescriptorNameHint;
  Exception? writeError;
  int readAudioSongInfosCallCount = 0;

  @override
  Future<bool> hasLyricsTag(String songPath) async => false;

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async {
    readAudioSongInfosCallCount += 1;
    return songInfosByPath[audioPath] ?? <SongInfo>[];
  }

  @override
  Future<int?> readAudioDurationMs(String audioPath) async =>
      durations[audioPath];

  @override
  Future<String?> readAudioLyricsText({
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    return null;
  }

  @override
  Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    lastSongPath = songPath;
    lastLyricsText = lyricsText;
    lastLyrics = lyrics;
    lastFileDescriptor = fileDescriptor;
    lastFileDescriptorNameHint = fileDescriptorNameHint;
    final Exception? error = writeError;
    if (error != null) {
      throw error;
    }
  }
}

class _FakeAutoFetchUseCase extends AutoFetchUseCase {
  _FakeAutoFetchUseCase({required this.result})
    : super(gateway: _NoopAutoFetchGateway());

  final AutoFetchResult result;
  AutoFetchRequest? lastRequest;

  @override
  Future<AutoFetchResult> execute(AutoFetchRequest request) async {
    lastRequest = request;
    return result;
  }
}

class _NoopAutoFetchGateway implements AutoFetchLyricsGateway {
  @override
  Future<Lyrics> getLyrics(SongInfo info) async {
    throw UnsupportedError('测试场景不支持自动获取歌词');
  }

  @override
  Future<APIResultList<SongInfo>> searchSongs({
    required Source source,
    required String keyword,
    required SearchType searchType,
  }) async {
    throw UnsupportedError('测试场景不支持自动搜索歌曲');
  }
}

class _NoopLyricsApi implements LyricsClient {
  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    throw UnsupportedError('测试场景不支持搜索');
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    throw UnsupportedError('测试场景不支持读取歌单');
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw UnsupportedError('测试场景不支持候选歌词列表');
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    throw UnsupportedError('测试场景不支持歌词解析');
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    throw UnsupportedError('测试场景不支持读取歌词');
  }
}
