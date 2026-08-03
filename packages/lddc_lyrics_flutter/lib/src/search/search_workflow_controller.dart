import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../state/state.dart';
import 'search_batch_save_lyrics_usecase.dart';
import 'search_dependencies.dart';
import 'search_preview_coordinator.dart';
import 'search_query_coordinator.dart';
import 'search_save_coordinator.dart';
import 'search_workflow_state.dart';

export 'search_dependencies.dart';

/// 搜索网络与调度器的只读诊断快照。
///
/// 该对象不持有 Future、Timer、令牌或第二份页面状态，只用于测试和长驻资源验收
/// 判断 controller 是否已经完全空闲。业务 UI 仍只消费 [SearchWorkflowState]。
@immutable
final class SearchWorkflowDiagnostics {
  const SearchWorkflowDiagnostics({
    required this.hasActiveBatch,
    required this.hasActiveRequest,
    required this.hasPendingRequest,
    required this.hasDebounceTimer,
    required this.isSearching,
    required this.isLoadingMore,
    required this.isDisposed,
    required this.searchBatchStartedCount,
    required this.searchBatchSettledCount,
    required this.sourceRequestStartedCount,
    required this.sourceRequestSettledCount,
  });

  final bool hasActiveBatch;
  final bool hasActiveRequest;
  final bool hasPendingRequest;
  final bool hasDebounceTimer;
  final bool isSearching;
  final bool isLoadingMore;
  final bool isDisposed;
  final int searchBatchStartedCount;
  final int searchBatchSettledCount;
  final int sourceRequestStartedCount;
  final int sourceRequestSettledCount;

  bool get isIdle =>
      !hasActiveBatch &&
      !hasActiveRequest &&
      !hasPendingRequest &&
      !hasDebounceTimer &&
      !isSearching &&
      !isLoadingMore;
}

/// 搜索页工作流控制器。
///
/// 按Python版语义收口：
/// - 搜索/分页
/// - 列表层级跳转
/// - 预览与翻译
/// - 保存到目录/标签/专辑歌单批量保存
class SearchWorkflowController extends ChangeNotifier {
  SearchWorkflowController({required SearchWorkflowDependencies dependencies})
    : _dependencies = dependencies,
      _queryCoordinator = SearchQueryCoordinator(
        lyricsClient: dependencies.lyricsApi,
      ),
      _previewCoordinator = SearchPreviewCoordinator(
        translationClient: dependencies.translateApi,
      ),
      _saveCoordinator = SearchSaveCoordinator(
        filePicker: dependencies.filePicker,
        mediaGateway: dependencies.mediaGateway,
        fileSaveFactory: dependencies.fileSavePersistenceFactory,
        batchSaveUseCase: dependencies.batchSaveUseCase,
        androidBatchSaveUseCase: dependencies.androidSafBatchSaveUseCase,
      ),
      _state = SearchWorkflowState.initial(
        defaultSaveDirectory: dependencies
            .optionsResolver()
            .defaultSaveDirectory,
      );

  static const String _batchEpochKey = 'batch';
  static const String _tableEpochKey = 'table';
  static const String _previewEpochKey = 'preview';
  static const String _previewSaveEpochKey = 'previewSave';
  static const String _externalInputEpochKey = 'externalInput';
  static const String _translationEpochKey = 'translation';

  SearchBatchSaveCancellationToken? _batchCancellationToken;
  RequestCancellationToken? _searchCancellationToken;
  Timer? _externalSearchDebounce;
  _QueuedSearch? _pendingSearch;
  Future<void>? _searchRunner;
  int _externalPresetGeneration = 0;
  // 这些计数只用于宿主诊断和真实窗口验收，不参与页面状态。它们能区分
  // “请求已经完成并进入 idle”和“请求根本没有从 selector engine 启动”两种情况。
  int _searchBatchStartedCount = 0;
  int _searchBatchSettledCount = 0;
  int _sourceRequestStartedCount = 0;
  int _sourceRequestSettledCount = 0;
  // 搜索页同时存在表格、预览、外部输入和翻译等多条异步链路。
  // 分通道记录代际可以避免“分页加载”和“打开歌词预览”互相取消；
  // 预览代际变化时会同步取消旧翻译，因为翻译结果只属于当前歌词。
  final OperationEpochGroup _epochs = OperationEpochGroup();
  int _noticeId = 0;

  final SearchWorkflowDependencies _dependencies;
  final SearchQueryCoordinator _queryCoordinator;
  final SearchPreviewCoordinator _previewCoordinator;
  final SearchSaveCoordinator _saveCoordinator;
  final StreamController<SearchWorkflowState> _stateController =
      StreamController<SearchWorkflowState>.broadcast(sync: true);
  SearchWorkflowState _state;
  bool _disposed = false;

  SearchWorkflowState get state => _state;

  SearchWorkflowDiagnostics get diagnostics => SearchWorkflowDiagnostics(
    hasActiveBatch: _searchRunner != null,
    hasActiveRequest: _searchCancellationToken != null,
    hasPendingRequest: _pendingSearch != null,
    hasDebounceTimer: _externalSearchDebounce?.isActive ?? false,
    isSearching: state.isSearching,
    isLoadingMore: state.isLoadingMore,
    isDisposed: _disposed,
    searchBatchStartedCount: _searchBatchStartedCount,
    searchBatchSettledCount: _searchBatchSettledCount,
    sourceRequestStartedCount: _sourceRequestStartedCount,
    sourceRequestSettledCount: _sourceRequestSettledCount,
  );

  Stream<SearchWorkflowState> get states async* {
    yield _state;
    yield* _stateController.stream;
  }

  set state(SearchWorkflowState value) {
    if (_disposed || identical(_state, value)) {
      return;
    }
    _state = value;
    _stateController.add(value);
    notifyListeners();
  }

  LyricsClient get _lyricsApi => _dependencies.lyricsApi;
  LocalMatchMediaGateway get _mediaGateway => _dependencies.mediaGateway;
  AppFilePicker get _filePicker => _dependencies.filePicker;
  AndroidSafTreePort get _androidSafTreePort =>
      _dependencies.androidSafTreePort;
  AutoFetchUseCase get _autoFetchUseCase => _dependencies.autoFetchUseCase;
  DroppedSongInfoResolver get _droppedSongInfoResolver =>
      DroppedSongInfoResolver(mediaGateway: _mediaGateway);

  bool get _isDesktopPlatform => _dependencies.capabilities.multiWindow;
  bool get _isAndroidSafPlatform =>
      !_isDesktopPlatform && _dependencies.capabilities.androidSafTreeAccess;

  SearchWorkflowOptions get _options => _dependencies.optionsResolver();

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    // generation 用来让仍在 await 后返回的旧任务失效，避免释放后继续发布状态。
    _epochs.invalidateAll();
    _externalSearchDebounce?.cancel();
    _externalSearchDebounce = null;
    _pendingSearch?.complete();
    _pendingSearch = null;
    _searchCancellationToken?.cancel();
    _searchCancellationToken?.dispose();
    _searchCancellationToken = null;
    _batchCancellationToken?.cancel();
    _batchCancellationToken = null;
    unawaited(_stateController.close());
    super.dispose();
  }

  /// 清除已消费的一次性通知。
  void dismissNotice([int? id]) {
    if (id != null && state.notice?.id != id) {
      return;
    }
    state = state.copyWith(clearNotice: true);
  }

  /// 当前预览内容是否允许保存。
  bool canSavePreview(SearchWorkflowState value) {
    return !value.isSavingPreview &&
        !value.isBatchSaving &&
        value.currentLyrics != null &&
        value.previewPhase == SearchPreviewPhase.ready &&
        value.selectedLangs.isNotEmpty &&
        value.previewText.trim().isNotEmpty;
  }

  /// 更新关键词。
  void setKeyword(String keyword) {
    _startTableGeneration();
    state = state.copyWith(keyword: keyword, clearStatusMessage: true);
  }

  /// 更新保存路径输入框内容。
  void updateSaveDirectoryPath(String value) {
    state = state.copyWith(
      saveDirectoryPath: value.trim().isEmpty ? '' : value.trim(),
      clearStatusMessage: true,
    );
  }

  /// 显式选择保存目录。
  Future<void> selectSaveDirectory() async {
    final String? initialDirectory = _normalizedSaveDirectory();
    final String? directory;
    try {
      directory = await _filePicker.pickDirectory(
        initialDirectory: initialDirectory,
      );
    } on UnsupportedError {
      _emitNotice(
        SearchNoticeCode.directoryPickerUnsupported,
        PageNoticeSeverity.warning,
      );
      return;
    }
    if (directory == null || directory.trim().isEmpty) {
      return;
    }
    state = state.copyWith(saveDirectoryPath: directory.trim());
  }

  /// 更新来源。
  void updateSource(Source source) {
    _startTableGeneration();
    final List<SearchType> available = source.supportedSearchTypes.toList(
      growable: false,
    );
    final SearchType selected = available.contains(state.selectedSearchType)
        ? state.selectedSearchType
        : available.first;
    state = state.copyWith(
      selectedSource: source,
      availableSearchTypes: available,
      selectedSearchType: selected,
      clearStatusMessage: true,
    );
  }

  /// 更新搜索类型。
  void updateSearchType(SearchType searchType) {
    if (!state.availableSearchTypes.contains(searchType)) {
      return;
    }
    _startTableGeneration();
    state = state.copyWith(
      selectedSearchType: searchType,
      clearStatusMessage: true,
    );
  }

  /// 更新预览参数（语言/格式/偏移）。
  void updatePreviewOptions({
    bool? originalEnabled,
    bool? translationEnabled,
    bool? romanizedEnabled,
    LyricsFormat? lyricsFormat,
    int? offsetMs,
  }) {
    final Set<String> langs = state.selectedLangs.toSet();
    _toggleLangSelection(langs, 'orig', originalEnabled);
    _toggleLangSelection(langs, 'ts', translationEnabled);
    _toggleLangSelection(langs, 'roma', romanizedEnabled);
    state = state.copyWith(
      selectedLangs: langs.toList(growable: false),
      lyricsFormat: lyricsFormat ?? state.lyricsFormat,
      offsetMs: offsetMs ?? state.offsetMs,
      clearStatusMessage: true,
      previewEmptyReason: _resolvePreviewEmptyReason(
        lyrics: state.currentLyrics,
        previewPhase: state.previewPhase,
        previewText: state.previewText,
      ),
    );
    final Lyrics? lyrics = state.currentLyrics;
    if (lyrics != null) {
      _applyLyrics(
        lyrics,
        clearTranslationProgress: false,
        preserveTranslationActivity: true,
      );
    }
  }

  /// 应用外部传入的预设上下文。
  ///
  /// 用于桌面歌词选择器等“复用搜索工作流但由外部驱动上下文”的场景：
  /// - 先更新来源/搜索类型/关键词/语言/偏移；
  /// - 若要求自动搜索，则按更新后的关键词触发搜索；
  /// - 最后再应用外部已知歌词，避免搜索过程把预览内容覆盖掉。
  Future<void> applyExternalPreset({
    String? keyword,
    Lyrics? lyrics,
    List<String>? selectedLangs,
    int? offsetMs,
    Source? selectedSource,
    SearchType? selectedSearchType,
    bool triggerSearch = false,
    bool clearLyricsWhenNull = false,
  }) async {
    final int presetGeneration = ++_externalPresetGeneration;
    if (selectedSource != null && selectedSource != state.selectedSource) {
      updateSource(selectedSource);
    }
    if (selectedSearchType != null &&
        selectedSearchType != state.selectedSearchType) {
      updateSearchType(selectedSearchType);
    }
    final List<String> nextLangs = selectedLangs == null
        ? state.selectedLangs
        : List<String>.unmodifiable(selectedLangs);
    state = state.copyWith(
      keyword: keyword ?? state.keyword,
      selectedLangs: nextLangs,
      offsetMs: offsetMs ?? state.offsetMs,
      clearStatusMessage: true,
    );
    if (triggerSearch && (keyword?.trim().isNotEmpty ?? false)) {
      await _enqueueSearch(debounce: true);
      if (_disposed || presetGeneration != _externalPresetGeneration) {
        return;
      }
    }
    if (lyrics != null) {
      _applyLyrics(lyrics);
      return;
    }
    if (clearLyricsWhenNull) {
      _epochs.invalidate(_previewSaveEpochKey);
      state = state.copyWith(
        previewPhase: SearchPreviewPhase.idle,
        previewEmptyReason: SearchPreviewEmptyReason.noSelection,
        clearCurrentLyrics: true,
        clearTranslationProgress: true,
        isSavingPreview: false,
        isTranslating: false,
        previewText: '',
        songIdText: '',
      );
    }
    if (!triggerSearch &&
        _searchRunner == null &&
        _searchCancellationToken == null &&
        _pendingSearch == null &&
        !_disposed &&
        state.isSearching) {
      // selector 的 refreshToken 可能只更新偏移/歌词上下文，不应重新搜索；
      // 如果它恰好接在已取消 batch 后到达，则由这个空闲出口收掉旧 loading，
      // 避免同一关键词 refresh 把页面永久留在 searching。
      _settleTransientSearchState();
    }
  }

  /// 对齐Python版 `search_widget.auto_fetch(song)`：
  /// 进入“自动获取”状态，完成后联动更新候选列表与首条预览。
  Future<void> autoFetchFromSongInfo(
    SongInfo songInfo, {
    List<Source>? preferredSources,
  }) async {
    final String displayName = songInfo.artistTitle(replaceMissing: true);
    final List<Source> sources = _resolveAutoFetchSources(preferredSources);
    final Source pageSource = _resolveAutoFetchPageSource(sources);
    if (pageSource != state.selectedSource) {
      updateSource(pageSource);
    }
    if (state.selectedSearchType != SearchType.song) {
      updateSearchType(SearchType.song);
    }
    final int tableGeneration = _startTableGeneration();
    final int previewGeneration = _startPreviewGeneration();
    state = state.copyWith(
      keyword: displayName,
      hasSubmittedSearch: true,
      tableState: const AsyncLoading<List<SourceAware>>(
        message: SearchTableStatusMessageCode.autoFetching,
      ),
      pathStack: const <APIResultList<SourceAware>>[],
      clearSourceFailures: true,
      clearStatusMessage: true,
      clearLastFileAction: true,
      clearLastSavedPath: true,
      clearLastFileError: true,
      isSavingPreview: false,
      previewPhase: SearchPreviewPhase.loading,
      clearPreviewEmptyReason: true,
      clearCurrentLyrics: true,
      clearTranslationProgress: true,
      isTranslating: false,
      previewText: '',
      songIdText: '',
    );

    try {
      final AutoFetchResult result = await _autoFetchUseCase.execute(
        AutoFetchRequest(
          info: songInfo,
          sources: sources,
          includeSearchResults: true,
        ),
      );
      if (!_isCurrentTableGeneration(tableGeneration) ||
          !_isCurrentPreviewGeneration(previewGeneration)) {
        return;
      }
      final APIResultList<SourceAware>? converted = _convertAutoFetchResults(
        result.searchResults,
      );
      final String keyword = _resolveAutoFetchKeyword(
        searchResults: result.searchResults,
        fallbackInfo: result.matchedSongInfo,
      );
      state = state.copyWith(
        keyword: keyword,
        hasSubmittedSearch: true,
        pathStack: converted == null
            ? const <APIResultList<SourceAware>>[]
            : <APIResultList<SourceAware>>[converted],
        tableState: converted == null || converted.isEmpty
            ? const AsyncEmpty<List<SourceAware>>(
                message: SearchTableStatusMessageCode.noResults,
              )
            : AsyncSuccess<List<SourceAware>>(
                data: converted.toList(growable: false),
              ),
      );
      _applyLyrics(result.lyrics);
      _emitNotice(
        SearchNoticeCode.autoFetchSucceeded,
        PageNoticeSeverity.success,
        detail: displayName,
      );
    } on Exception catch (error) {
      if (!_isCurrentTableGeneration(tableGeneration) ||
          !_isCurrentPreviewGeneration(previewGeneration)) {
        return;
      }
      state = state.copyWith(
        keyword: displayName,
        hasSubmittedSearch: true,
        pathStack: const <APIResultList<SourceAware>>[],
        tableState: AsyncError<List<SourceAware>>(
          message: SearchTableStatusMessage.encode(
            SearchTableStatusMessageCode.autoFetchFailed,
            error.toString(),
          ),
        ),
        previewPhase: SearchPreviewPhase.idle,
        previewEmptyReason: SearchPreviewEmptyReason.noSelection,
        clearCurrentLyrics: true,
        clearTranslationProgress: true,
        isSavingPreview: false,
        isTranslating: false,
        previewText: '',
        songIdText: '',
      );
      _emitNotice(
        SearchNoticeCode.autoFetchFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  /// 通过外部歌曲文件触发搜索主链。
  Future<void> openSongFileForSearch() async {
    PickedAudioFileHandle? pickedAudioFile;
    try {
      pickedAudioFile = await _filePicker.pickAudioFile(
        initialDirectory: _normalizedSaveDirectory(),
      );
      final String? songPath = pickedAudioFile?.targetPath;
      if (songPath == null || songPath.trim().isEmpty) {
        _emitNotice(
          SearchNoticeCode.selectedSongUnavailable,
          PageNoticeSeverity.warning,
        );
        return;
      }
      await openDroppedSongFile(songPath);
    } on UnsupportedError {
      _emitNotice(
        SearchNoticeCode.filePickerUnsupported,
        PageNoticeSeverity.warning,
      );
    } on Exception catch (error) {
      _emitNotice(
        SearchNoticeCode.openSongFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    } finally {
      if (pickedAudioFile != null) {
        try {
          await _filePicker.releaseAudioFile(pickedAudioFile);
        } on Exception {
          // 句柄释放失败不覆盖主流程结果。
        }
      }
    }
  }

  /// 处理拖拽或外部注入的歌曲文件。
  Future<void> openDroppedSongFile(
    String path, {
    String? track,
    String? index,
  }) async {
    final String normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      _emitNotice(
        SearchNoticeCode.droppedSongUnavailable,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final int generation = _startExternalInputGeneration();
    final SongInfo songInfo;
    try {
      songInfo = await _droppedSongInfoResolver.resolve(
        path: normalizedPath,
        track: track,
        index: index,
      );
    } on DroppedSongInfoResolveException catch (error) {
      // 解析拖拽歌曲可能跨过异步文件读取；如果用户已经发起新搜索/新拖拽，
      // 旧错误不能再覆盖当前页面提示。
      if (!_isCurrentExternalInputGeneration(generation)) {
        return;
      }
      _emitNotice(
        SearchNoticeCode.droppedSongResolveFailed,
        PageNoticeSeverity.warning,
        detail: error.message,
      );
      return;
    }
    if (!_isCurrentExternalInputGeneration(generation)) {
      return;
    }
    await autoFetchFromSongInfo(songInfo);
  }

  /// 使用完整集合更新歌词语言选择。
  void updateSelectedLangs(Set<String> langs) {
    updatePreviewOptions(
      originalEnabled: langs.contains('orig'),
      translationEnabled: langs.contains('ts'),
      romanizedEnabled: langs.contains('roma'),
    );
  }

  /// 搜索入口。
  Future<void> search() => _enqueueSearch(debounce: false);

  /// 只重试当前批次失败的来源，成功来源的结果和分页范围保持不动。
  Future<void> retryFailedSources() async {
    if (_disposed ||
        state.isSearching ||
        state.isLoadingMore ||
        state.sourceFailures.isEmpty) {
      return;
    }
    final List<Source> sources = state.sourceFailures
        .map((SearchSourceFailure failure) => failure.source)
        .toSet()
        .toList(growable: false);
    final String keyword = state.keyword.trim();
    if (keyword.isEmpty || sources.isEmpty) {
      return;
    }
    if (_hasLoadMoreFailure) {
      await _retryFailedLoadMoreSources(sources);
      return;
    }

    final RequestCancellationToken token = RequestCancellationToken();
    _searchCancellationToken = token;
    final int generation = _startTableGeneration();
    _searchBatchStartedCount += 1;
    _sourceRequestStartedCount += sources.length;
    final APIResultList<SourceAware>? current = state.currentPathResult;
    state = state.copyWith(
      isSearching: true,
      tableState: current == null
          ? const AsyncLoading<List<SourceAware>>(
              message: SearchTableStatusMessageCode.searching,
            )
          : AsyncPartial<List<SourceAware>>(
              data: current.toList(growable: false),
              message: SearchTableStatusMessageCode.searching,
            ),
      clearSourceFailures: true,
    );

    try {
      final List<SearchSourceQueryResult> entries = await _queryCoordinator
          .searchFirstPage(
            sources: sources,
            keyword: keyword,
            searchType: state.selectedSearchType,
            cancellationToken: token,
          );
      _sourceRequestSettledCount += entries.length;
      if (token.isCancelled || !_isCurrentTableGeneration(generation)) {
        return;
      }

      final List<SearchSourceFailure> failures = _failureSnapshots(entries);
      APIResultList<SourceAware>? merged = current;
      for (final SearchSourceQueryResult entry in entries) {
        final APIResultList<SourceAware>? result = entry.result;
        if (result == null) {
          continue;
        }
        merged = merged == null ? result : merged + result;
      }
      if (merged == null || (merged.isEmpty && failures.isNotEmpty)) {
        final String detail = _failureDetails(failures);
        state = state.copyWith(
          isSearching: false,
          sourceFailures: failures,
          tableState: AsyncError<List<SourceAware>>(
            message: SearchTableStatusMessage.encode(
              SearchTableStatusMessageCode.searchFailed,
              detail,
            ),
          ),
        );
        _emitNotice(
          SearchNoticeCode.searchAllSourcesFailed,
          PageNoticeSeverity.error,
          detail: detail,
        );
        return;
      }

      final APIResultList<SourceAware> settled = merged;
      final AsyncViewState<List<SourceAware>> tableState = failures.isEmpty
          ? AsyncSuccess<List<SourceAware>>(
              data: settled.toList(growable: false),
            )
          : AsyncPartial<List<SourceAware>>(
              data: settled.toList(growable: false),
              warningMessage: SearchTableStatusMessage.encode(
                SearchTableStatusMessageCode.partialSourceUnavailable,
                _failureDetails(failures),
              ),
            );
      final List<APIResultList<SourceAware>> path =
          <APIResultList<SourceAware>>[...state.pathStack];
      if (path.isEmpty) {
        path.add(settled);
      } else {
        path[path.length - 1] = settled;
      }
      state = state.copyWith(
        isSearching: false,
        pathStack: path,
        sourceFailures: failures,
        tableState: tableState,
      );
      if (failures.isNotEmpty) {
        _emitNotice(
          SearchNoticeCode.searchPartialSourcesFailed,
          PageNoticeSeverity.warning,
          detail: _failureDetails(failures),
        );
      }
    } finally {
      _searchBatchSettledCount += 1;
      token.dispose();
      if (identical(_searchCancellationToken, token)) {
        _searchCancellationToken = null;
      }
      if (!_disposed && state.isSearching) {
        state = state.copyWith(isSearching: false);
      }
    }
  }

  bool get _hasLoadMoreFailure {
    final AsyncViewState<List<SourceAware>> tableState = state.tableState;
    if (tableState is! AsyncPartial<List<SourceAware>> ||
        tableState.warningMessage == null) {
      return false;
    }
    return SearchTableStatusMessage.decode(tableState.warningMessage!).$1 ==
        SearchTableStatusMessageCode.loadMoreFailed;
  }

  Future<void> _retryFailedLoadMoreSources(List<Source> sources) async {
    final APIResultList<SourceAware>? current = state.currentPathResult;
    if (current == null || current.info is! SearchInfo) {
      return;
    }

    final RequestCancellationToken token = RequestCancellationToken();
    _searchCancellationToken = token;
    final int generation = _startTableGeneration();
    _sourceRequestStartedCount += sources.length;
    state = state.copyWith(
      isLoadingMore: true,
      tableState: AsyncPartial<List<SourceAware>>(
        data: current.toList(growable: false),
        message: SearchTableStatusMessageCode.fetchingSongList,
      ),
      clearSourceFailures: true,
    );

    try {
      final List<SearchSourceQueryResult> entries = await _queryCoordinator
          .loadMore(current, sources: sources, cancellationToken: token);
      _sourceRequestSettledCount += entries.length;
      if (token.isCancelled || !_isCurrentTableGeneration(generation)) {
        return;
      }

      final APIResultList<SourceAware> merged = _mergePageResults(
        current,
        sources,
        entries,
      );
      final List<SearchSourceFailure> failures = _failureSnapshots(entries);
      final List<APIResultList<SourceAware>> path =
          <APIResultList<SourceAware>>[...state.pathStack];
      if (path.isNotEmpty) {
        path[path.length - 1] = merged;
      }
      state = state.copyWith(
        isLoadingMore: false,
        pathStack: path,
        sourceFailures: failures,
        tableState: failures.isEmpty
            ? AsyncSuccess<List<SourceAware>>(
                data: merged.toList(growable: false),
              )
            : AsyncPartial<List<SourceAware>>(
                data: merged.toList(growable: false),
                warningMessage: SearchTableStatusMessage.encode(
                  SearchTableStatusMessageCode.loadMoreFailed,
                  _failureDetails(failures),
                ),
              ),
      );
      if (failures.isNotEmpty) {
        _emitNotice(
          SearchNoticeCode.searchLoadMoreFailed,
          PageNoticeSeverity.warning,
          detail: _failureDetails(failures),
        );
      }
    } on Object catch (error) {
      if (!token.isCancelled && _isCurrentTableGeneration(generation)) {
        // 分页范围异常同样不能清空已展示结果；保留原失败详情，用户仍可从
        // 结果尾部再次发起有界重试。
        final List<SearchSourceFailure> failures = sources
            .map(
              (Source source) => SearchSourceFailure.bounded(
                source: source,
                kind: SearchSourceFailureKind.unknown,
                detail: error.toString(),
              ),
            )
            .toList(growable: false);
        final String detail = _failureDetails(failures);
        state = state.copyWith(
          isLoadingMore: false,
          sourceFailures: failures,
          tableState: AsyncPartial<List<SourceAware>>(
            data: current.toList(growable: false),
            warningMessage: SearchTableStatusMessage.encode(
              SearchTableStatusMessageCode.loadMoreFailed,
              detail,
            ),
          ),
        );
        _emitNotice(
          SearchNoticeCode.searchLoadMoreFailed,
          PageNoticeSeverity.warning,
          detail: detail,
        );
      }
    } finally {
      _releaseSearchToken(token);
      if (!_disposed && state.isLoadingMore) {
        state = state.copyWith(isLoadingMore: false);
      }
    }
  }

  Future<void> _enqueueSearch({required bool debounce}) {
    if (_disposed) {
      return Future<void>.value();
    }
    _epochs.invalidate(_tableEpochKey);
    _searchCancellationToken?.cancel();
    _externalSearchDebounce?.cancel();
    _externalSearchDebounce = null;
    _pendingSearch?.complete();
    final _QueuedSearch request = _QueuedSearch();
    _pendingSearch = request;

    void start() {
      _externalSearchDebounce = null;
      _startSearchRunner();
    }

    if (debounce) {
      _externalSearchDebounce = Timer(const Duration(milliseconds: 300), start);
    } else {
      scheduleMicrotask(start);
    }
    return request.future;
  }

  void _startSearchRunner() {
    if (_disposed || _searchRunner != null || _pendingSearch == null) {
      return;
    }
    final Future<void> runner = _drainSearchQueue();
    _searchRunner = runner;
    runner.whenComplete(() {
      if (identical(_searchRunner, runner)) {
        _searchRunner = null;
      }
      if (!_disposed && _pendingSearch != null) {
        _startSearchRunner();
        return;
      }
      _finishSearchActivityIfIdle();
    });
  }

  Future<void> _drainSearchQueue() async {
    while (!_disposed) {
      final _QueuedSearch? request = _pendingSearch;
      _pendingSearch = null;
      if (request == null) {
        return;
      }
      final RequestCancellationToken token = RequestCancellationToken();
      _searchCancellationToken = token;
      final int batchStartedBefore = _searchBatchStartedCount;
      try {
        await _executeSearch(token);
      } finally {
        if (_searchBatchStartedCount > batchStartedBefore) {
          _searchBatchSettledCount += 1;
        }
        _finishSearchActivityIfCurrent(token);
        if (!_disposed && state.isSearching) {
          // 一个 batch 的 Future 已经 settle 后，无论它是成功、超时、取消还是
          // epoch 失效，都不能继续占用 UI 的 searching 状态；最新 pending 若存在，
          // 下一轮 _executeSearch 会立即重新置为 true。
          _settleTransientSearchState();
        }
        token.dispose();
        if (identical(_searchCancellationToken, token)) {
          _searchCancellationToken = null;
        }
        request.complete();
      }
    }
  }

  Future<void> _executeSearch(RequestCancellationToken token) async {
    final String keyword = state.keyword.trim();
    if (keyword.isEmpty) {
      _emitNotice(SearchNoticeCode.emptyKeyword, PageNoticeSeverity.warning);
      return;
    }

    final SearchType searchType = state.selectedSearchType;
    final List<Source> effectiveSources = _queryCoordinator.resolveSources(
      selectedSource: state.selectedSource,
      searchType: searchType,
      configuredSources: _options.searchSources,
    );
    if (effectiveSources.isEmpty) {
      state = state.copyWith(
        hasSubmittedSearch: true,
        tableState: const AsyncError<List<SourceAware>>(
          message: SearchTableStatusMessageCode.unsupportedSearchType,
        ),
      );
      return;
    }

    _searchBatchStartedCount += 1;
    _sourceRequestStartedCount += effectiveSources.length;

    state = state.copyWith(
      hasSubmittedSearch: true,
      isSearching: true,
      isLoadingMore: false,
      tableState: const AsyncLoading<List<SourceAware>>(
        message: SearchTableStatusMessageCode.searching,
      ),
      pathStack: const <APIResultList<SourceAware>>[],
      clearStatusMessage: true,
      clearSourceFailures: true,
      clearTranslationProgress: true,
    );

    final int generation = _startTableGeneration();
    final Map<Source, SearchSourceQueryResult> completed =
        <Source, SearchSourceQueryResult>{};
    final List<SearchSourceQueryResult> entries = await _queryCoordinator
        .searchFirstPage(
          sources: effectiveSources,
          keyword: keyword,
          searchType: searchType,
          cancellationToken: token,
          onResult: (SearchSourceQueryResult entry) {
            if (token.isCancelled || !_isCurrentTableGeneration(generation)) {
              return;
            }
            completed[entry.source] = entry;
            final APIResultList<SourceAware>? merged = _mergeSearchEntries(
              effectiveSources,
              completed.values,
            );
            if (merged == null || merged.isEmpty) {
              return;
            }
            state = state.copyWith(
              hasSubmittedSearch: true,
              isSearching: true,
              pathStack: <APIResultList<SourceAware>>[merged],
              sourceFailures: _failureSnapshots(completed.values),
              tableState: AsyncPartial<List<SourceAware>>(
                data: merged.toList(growable: false),
                message: SearchTableStatusMessageCode.searching,
              ),
            );
          },
        );
    _sourceRequestSettledCount += entries.length;
    if (token.isCancelled || !_isCurrentTableGeneration(generation)) {
      return;
    }
    final List<APIResultList<SourceAware>> success = entries
        .where((entry) => entry.result != null)
        .map((entry) => entry.result!)
        .toList(growable: false);
    if (success.isEmpty) {
      final List<SearchSourceFailure> failures = _failureSnapshots(entries);
      final String message = _failureDetails(failures);
      state = state.copyWith(
        hasSubmittedSearch: true,
        isSearching: false,
        sourceFailures: failures,
        tableState: AsyncError<List<SourceAware>>(
          message: SearchTableStatusMessage.encode(
            SearchTableStatusMessageCode.searchFailed,
            message,
          ),
        ),
      );
      _emitNotice(
        SearchNoticeCode.searchAllSourcesFailed,
        PageNoticeSeverity.error,
        detail: message,
      );
      return;
    }

    final APIResultList<SourceAware> merged = _mergeSearchEntries(
      effectiveSources,
      entries,
    )!;
    final List<SearchSourceFailure> failures = _failureSnapshots(entries);
    if (merged.isEmpty && failures.isEmpty) {
      state = state.copyWith(
        hasSubmittedSearch: true,
        isSearching: false,
        pathStack: <APIResultList<SourceAware>>[merged],
        tableState: const AsyncEmpty<List<SourceAware>>(
          message: SearchTableStatusMessageCode.noResults,
        ),
      );
      return;
    }

    final AsyncViewState<List<SourceAware>> tableState = failures.isNotEmpty
        ? AsyncPartial<List<SourceAware>>(
            data: merged.toList(growable: false),
            warningMessage: SearchTableStatusMessage.encode(
              SearchTableStatusMessageCode.partialSourceUnavailable,
              _failureDetails(failures),
            ),
          )
        : AsyncSuccess<List<SourceAware>>(data: merged.toList(growable: false));

    state = state.copyWith(
      hasSubmittedSearch: true,
      isSearching: false,
      pathStack: <APIResultList<SourceAware>>[merged],
      sourceFailures: failures,
      tableState: tableState,
    );
    if (failures.isNotEmpty) {
      _emitNotice(
        SearchNoticeCode.searchPartialSourcesFailed,
        PageNoticeSeverity.warning,
        detail: _failureDetails(failures),
      );
    }
  }

  List<SearchSourceFailure> _failureSnapshots(
    Iterable<SearchSourceQueryResult> entries,
  ) {
    return List<SearchSourceFailure>.unmodifiable(
      entries
          .where((SearchSourceQueryResult entry) => entry.result == null)
          .map(
            (SearchSourceQueryResult entry) =>
                entry.failure ??
                SearchSourceFailure.bounded(
                  source: entry.source,
                  kind: entry.status == SearchSourceQueryStatus.timeout
                      ? SearchSourceFailureKind.timeout
                      : SearchSourceFailureKind.unknown,
                  detail: entry.error ?? '未知错误',
                ),
          ),
    );
  }

  String _failureDetails(Iterable<SearchSourceFailure> failures) {
    return failures
        .map(
          (SearchSourceFailure failure) =>
              '${failure.source.value}: ${failure.detail}',
        )
        .join('；');
  }

  APIResultList<SourceAware>? _mergeSearchEntries(
    List<Source> sources,
    Iterable<SearchSourceQueryResult> entries,
  ) {
    final Map<Source, SearchSourceQueryResult> bySource =
        <Source, SearchSourceQueryResult>{
          for (final SearchSourceQueryResult entry in entries)
            entry.source: entry,
        };
    APIResultList<SourceAware>? merged;
    for (final Source source in sources) {
      final APIResultList<SourceAware>? result = bySource[source]?.result;
      if (result == null) {
        continue;
      }
      merged = merged == null ? result : merged + result;
    }
    return merged;
  }

  /// 加载更多。
  Future<void> loadMore() async {
    if (!state.canLoadMore) {
      return;
    }
    final APIResultList<SourceAware>? current = state.currentPathResult;
    final Object? info = current?.info;
    if (current == null || info is! SearchInfo || current.more.isEmpty) {
      return;
    }
    state = state.copyWith(
      isLoadingMore: true,
      clearStatusMessage: true,
      clearTranslationProgress: true,
    );
    final int generation = _startTableGeneration();
    final RequestCancellationToken token = RequestCancellationToken();
    _searchCancellationToken = token;
    _sourceRequestStartedCount += current.more.length;
    final Map<Source, SearchSourceQueryResult> completed =
        <Source, SearchSourceQueryResult>{};
    late final List<SearchSourceQueryResult> entries;
    try {
      entries = await _queryCoordinator.loadMore(
        current,
        cancellationToken: token,
        onResult: (SearchSourceQueryResult entry) {
          if (token.isCancelled || !_isCurrentTableGeneration(generation)) {
            return;
          }
          completed[entry.source] = entry;
          final APIResultList<SourceAware> merged = _mergePageResults(
            current,
            current.more,
            completed.values,
          );
          final List<APIResultList<SourceAware>> path =
              <APIResultList<SourceAware>>[...state.pathStack];
          if (path.isNotEmpty) {
            path[path.length - 1] = merged;
          }
          state = state.copyWith(
            isLoadingMore: true,
            pathStack: path,
            sourceFailures: _failureSnapshots(completed.values),
            tableState: AsyncPartial<List<SourceAware>>(
              data: merged.toList(growable: false),
              message: SearchTableStatusMessageCode.fetchingSongList,
            ),
          );
        },
      );
      _sourceRequestSettledCount += entries.length;
    } catch (_) {
      if (!token.isCancelled && _isCurrentTableGeneration(generation)) {
        state = state.copyWith(
          isLoadingMore: false,
          tableState: AsyncPartial<List<SourceAware>>(
            data: current.toList(growable: false),
            warningMessage: SearchTableStatusMessageCode.loadMoreFailed,
          ),
        );
      }
      _releaseSearchToken(token);
      return;
    }
    if (token.isCancelled || !_isCurrentTableGeneration(generation)) {
      _releaseSearchToken(token);
      return;
    }

    APIResultList<SourceAware> merged = current;
    try {
      merged = _mergePageResults(current, current.more, entries);
    } catch (_) {
      if (!_isCurrentTableGeneration(generation)) {
        return;
      }
      // APIResultList 用 ArgumentError 报告范围重叠或断裂，它不属于 Exception。
      // 控制器边界必须捕获这类模型错误，保留已经展示的结果并允许用户重试，
      // 避免自动触底加载把一次远端数据漂移升级为未处理异常。
      state = state.copyWith(
        isLoadingMore: false,
        tableState: AsyncPartial<List<SourceAware>>(
          data: current.toList(growable: false),
          warningMessage: SearchTableStatusMessageCode.loadMoreFailed,
        ),
      );
      _releaseSearchToken(token);
      return;
    }

    final List<APIResultList<SourceAware>> path = <APIResultList<SourceAware>>[
      ...state.pathStack,
    ];
    if (path.isNotEmpty) {
      path[path.length - 1] = merged;
    }

    final List<SearchSourceFailure> failures = _failureSnapshots(entries);
    final AsyncViewState<List<SourceAware>> nextTableState = failures.isNotEmpty
        ? AsyncPartial<List<SourceAware>>(
            data: merged.toList(growable: false),
            warningMessage: SearchTableStatusMessage.encode(
              SearchTableStatusMessageCode.loadMoreFailed,
              _failureDetails(failures),
            ),
          )
        : AsyncSuccess<List<SourceAware>>(data: merged.toList(growable: false));
    state = state.copyWith(
      isLoadingMore: false,
      pathStack: path,
      sourceFailures: failures,
      tableState: nextTableState,
    );
    if (failures.isNotEmpty) {
      _emitNotice(
        SearchNoticeCode.searchLoadMoreFailed,
        PageNoticeSeverity.warning,
        detail: _failureDetails(failures),
      );
    }
    _releaseSearchToken(token);
  }

  APIResultList<SourceAware> _mergePageResults(
    APIResultList<SourceAware> current,
    Iterable<Source> sources,
    Iterable<SearchSourceQueryResult> entries,
  ) {
    final Map<Source, SearchSourceQueryResult> bySource =
        <Source, SearchSourceQueryResult>{
          for (final SearchSourceQueryResult entry in entries)
            entry.source: entry,
        };
    APIResultList<SourceAware> merged = current;
    for (final Source source in sources) {
      final APIResultList<SourceAware>? result = bySource[source]?.result;
      if (result == null || result.isEmpty) {
        continue;
      }
      merged = merged + result;
    }
    return merged;
  }

  void _releaseSearchToken(RequestCancellationToken token) {
    if (!_disposed &&
        identical(_searchCancellationToken, token) &&
        state.isLoadingMore) {
      // 输入、层级或新搜索使分页 epoch 失效时，迟到分页结果虽然会被丢弃，
      // 但 loading 标志仍必须由令牌所有者复位，否则下一页入口会永久冻结。
      state = state.copyWith(isLoadingMore: false);
    }
    token.dispose();
    if (identical(_searchCancellationToken, token)) {
      _searchCancellationToken = null;
    }
  }

  void _finishSearchActivityIfCurrent(RequestCancellationToken token) {
    if (_disposed ||
        !identical(_searchCancellationToken, token) ||
        _pendingSearch != null ||
        !state.isSearching) {
      return;
    }
    _settleTransientSearchState();
  }

  void _finishSearchActivityIfIdle() {
    if (_disposed ||
        _searchRunner != null ||
        _pendingSearch != null ||
        (_externalSearchDebounce?.isActive ?? false) ||
        !state.isSearching) {
      return;
    }
    // 单个令牌结束时可能已经有最新 pending 接管，因此令牌出口不能抢先清理。
    // runner 完全排空后再次校验不变量，避免“pending 随后被覆盖/消费”留下永久
    // searching 状态；这个出口不创建请求，也不改变一个 active + 一个 pending 限制。
    _settleTransientSearchState();
  }

  void _settleTransientSearchState() {
    final AsyncViewState<List<SourceAware>> currentTableState =
        state.tableState;
    // epoch 失效会阻止旧批次发布终态，这是正确的迟到结果隔离；但它不能把
    // UI 永久留在 searching。没有新 pending 接管时，将临时 loading/partial
    // 投影收成稳定状态，同时保留已经逐源展示的数据。
    final AsyncViewState<List<SourceAware>> settledTableState =
        switch (currentTableState) {
          AsyncLoading<List<SourceAware>>() =>
            const AsyncEmpty<List<SourceAware>>(message: ''),
          AsyncPartial<List<SourceAware>>(
            data: final List<SourceAware> data,
            warningMessage: final String? warningMessage,
          ) =>
            warningMessage == null
                ? AsyncSuccess<List<SourceAware>>(data: data)
                : AsyncPartial<List<SourceAware>>(
                    data: data,
                    warningMessage: warningMessage,
                  ),
          _ => currentTableState,
        };
    state = state.copyWith(isSearching: false, tableState: settledTableState);
  }

  /// 打开表格项（搜索结果单击或键盘 Enter 行为）。
  Future<void> openResult(int rowIndex) async {
    final APIResultList<SourceAware>? result = state.currentPathResult;
    if (result == null || rowIndex < 0 || rowIndex >= result.length) {
      return;
    }
    final SourceAware row = result[rowIndex];
    if (row is SongListInfo) {
      await _openSongList(row);
      return;
    }
    if (row is SongInfo) {
      await _openSong(row);
      return;
    }
    if (row is LyricInfo) {
      await _openLyric(row);
    }
  }

  /// 返回上一层结果。
  void returnPath() {
    if (state.pathStack.length <= 1) {
      return;
    }
    _startTableGeneration();
    final List<APIResultList<SourceAware>> path = <APIResultList<SourceAware>>[
      ...state.pathStack,
    ]..removeLast();
    state = state.copyWith(
      pathStack: path,
      tableState: AsyncSuccess<List<SourceAware>>(
        data: path.last.toList(growable: false),
      ),
      clearStatusMessage: true,
    );
  }

  /// 翻译/取消翻译。
  Future<void> toggleTranslation() async {
    final Lyrics? lyrics = state.currentLyrics;
    if (lyrics == null) {
      _emitNotice(SearchNoticeCode.getLyricsFirst, PageNoticeSeverity.warning);
      return;
    }

    if (state.isTranslating) {
      return;
    }

    if (lyrics.data.containsKey('LDDC_ts')) {
      _startTranslationGeneration();
      _applyLyrics(_previewCoordinator.removeTranslation(lyrics));
      _emitNotice(
        SearchNoticeCode.translationCancelled,
        PageNoticeSeverity.info,
      );
      return;
    }

    final int generation = _startTranslationGeneration();
    final bool reportsOpenAiProgress =
        _options.translationSource == TranslateSource.openai;
    state = state.copyWith(
      isTranslating: true,
      translationProgress: reportsOpenAiProgress
          ? OpenAiTranslationProgress.initial(
              totalLines: lyrics['orig']?.length ?? 0,
            )
          : null,
      clearTranslationProgress: !reportsOpenAiProgress,
      clearStatusMessage: true,
    );
    try {
      final Lyrics translatedLyrics = await _previewCoordinator.translate(
        lyrics: lyrics,
        onOpenAiProgress: reportsOpenAiProgress
            ? (OpenAiTranslationProgress progress) {
                if (!_isCurrentTranslationGeneration(generation) ||
                    state.currentLyrics != lyrics) {
                  return;
                }
                state = state.copyWith(translationProgress: progress);
              }
            : null,
      );
      if (!_isCurrentTranslationGeneration(generation) ||
          state.currentLyrics != lyrics) {
        return;
      }
      _applyLyrics(translatedLyrics, preserveTranslationActivity: true);
      _emitNotice(
        SearchNoticeCode.translationCompleted,
        PageNoticeSeverity.success,
      );
    } on Exception catch (error) {
      if (!_isCurrentTranslationGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        isTranslating: false,
        clearTranslationProgress: true,
      );
      _emitNotice(
        SearchNoticeCode.translationFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  /// 保存预览歌词到目录。
  Future<void> savePreviewToDirectory() async {
    final Lyrics? lyrics = state.currentLyrics;
    final String preview = state.previewText.trim();
    if (!canSavePreview(state) || lyrics == null || preview.isEmpty) {
      _rejectPreviewSave(
        SearchPreviewFileAction.saveDirectory,
        _previewUnavailableMessage(),
        _previewUnavailableNoticeCode(),
      );
      return;
    }

    final String? folder = _requiredSaveDirectory(
      action: SearchPreviewFileAction.saveDirectory,
    );
    if (folder == null) {
      return;
    }

    final int saveGeneration = _startPreviewSave(
      SearchPreviewFileAction.saveDirectory,
    );
    try {
      final String savePath = await _saveCoordinator.savePreviewToDirectory(
        folder: folder,
        fileNameFormat: _options.fileNameFormat,
        lyrics: lyrics,
        langs: state.selectedLangs,
        lyricsFormat: state.lyricsFormat,
        text: preview,
      );
      if (!_isCurrentPreviewSave(saveGeneration)) {
        return;
      }
      state = state.copyWith(
        isSavingPreview: false,
        saveDirectoryPath: folder,
        lastSavedPath: savePath,
        clearLastFileError: true,
      );
      _emitNotice(
        SearchNoticeCode.lyricsSaveSucceeded,
        PageNoticeSeverity.success,
        detail: savePath,
      );
    } on Exception catch (error) {
      if (!_isCurrentPreviewSave(saveGeneration)) {
        return;
      }
      _finishPreviewSaveWithError(saveGeneration, error.toString());
      _emitNotice(
        SearchNoticeCode.lyricsSaveFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  /// 保存预览歌词到单个文件。
  Future<void> savePreviewToFile() async {
    final Lyrics? lyrics = state.currentLyrics;
    final String preview = state.previewText.trim();
    if (!canSavePreview(state) || lyrics == null || preview.isEmpty) {
      _rejectPreviewSave(
        SearchPreviewFileAction.saveFile,
        _previewUnavailableMessage(),
        _previewUnavailableNoticeCode(),
      );
      return;
    }

    final String suggestedFileName = _saveCoordinator
        .buildPreviewPlan(
          folder: '',
          fileNameFormat: _options.fileNameFormat,
          lyrics: lyrics,
          langs: state.selectedLangs,
          lyricsFormat: state.lyricsFormat,
        )
        .fileName;
    final List<String>? allowedExtensions = _allowedSaveExtensions(
      state.lyricsFormat.ext,
    );

    final int saveGeneration = _startPreviewSave(
      SearchPreviewFileAction.saveFile,
    );
    try {
      final SavedTextFileResult? saveResult = await _saveCoordinator
          .savePreviewToFile(
            fileName: suggestedFileName,
            text: preview,
            initialDirectory: _normalizedSaveDirectory(),
            allowedExtensions: allowedExtensions,
          );
      if (!_isCurrentPreviewSave(saveGeneration)) {
        return;
      }
      if (saveResult == null) {
        _finishPreviewSave(saveGeneration);
        return;
      }
      String? nextDirectory;
      if (_isDesktopPlatform && saveResult.localPath != null) {
        nextDirectory = p.dirname(saveResult.localPath!);
      }
      state = state.copyWith(
        isSavingPreview: false,
        saveDirectoryPath: nextDirectory ?? state.saveDirectoryPath,
        lastSavedPath: saveResult.displayPath,
        clearLastFileError: true,
      );
      _emitNotice(
        SearchNoticeCode.lyricsSaveSucceeded,
        PageNoticeSeverity.success,
        detail: saveResult.displayPath,
      );
    } on UnsupportedError {
      if (!_isCurrentPreviewSave(saveGeneration)) {
        return;
      }
      _finishPreviewSaveWithError(
        saveGeneration,
        SearchNoticeCode.saveFileUnsupported.name,
      );
      _emitNotice(
        SearchNoticeCode.saveFileUnsupported,
        PageNoticeSeverity.warning,
      );
    } on Exception catch (error) {
      if (!_isCurrentPreviewSave(saveGeneration)) {
        return;
      }
      _finishPreviewSaveWithError(saveGeneration, error.toString());
      _emitNotice(
        SearchNoticeCode.lyricsSaveFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  /// 保存预览歌词到歌曲标签。
  Future<void> savePreviewToTag() async {
    final Lyrics? lyrics = state.currentLyrics;
    final String preview = state.previewText.trim();
    if (!canSavePreview(state) || lyrics == null || preview.isEmpty) {
      _rejectPreviewSave(
        SearchPreviewFileAction.saveTag,
        _previewUnavailableMessage(),
        _previewUnavailableNoticeCode(),
      );
      return;
    }
    if (!LyricsFormatCapabilities.isLrcFamily(state.lyricsFormat)) {
      _rejectPreviewSave(
        SearchPreviewFileAction.saveTag,
        SearchNoticeCode.audioTagRequiresLrc.name,
        SearchNoticeCode.audioTagRequiresLrc,
      );
      return;
    }

    final int saveGeneration = _startPreviewSave(
      SearchPreviewFileAction.saveTag,
    );
    PickedAudioFileHandle? pickedAudioFile;
    PickedAudioFileHandle? writableAudioFile;
    try {
      pickedAudioFile = await _filePicker.pickAudioFile(
        initialDirectory: _resolveInitialDirectoryForTag(lyrics.songInfo.path),
      );
    } on UnsupportedError {
      if (_isCurrentPreviewSave(saveGeneration)) {
        _finishPreviewSaveWithError(
          saveGeneration,
          SearchNoticeCode.filePickerForTagUnsupported.name,
        );
        _emitNotice(
          SearchNoticeCode.filePickerForTagUnsupported,
          PageNoticeSeverity.warning,
        );
      }
      return;
    } on Exception catch (error) {
      if (_isCurrentPreviewSave(saveGeneration)) {
        _finishPreviewSaveWithError(saveGeneration, error.toString());
        _emitNotice(
          SearchNoticeCode.filePickerFailed,
          PageNoticeSeverity.error,
          detail: error.toString(),
        );
      }
      return;
    }

    try {
      if (!_isCurrentPreviewSave(saveGeneration)) {
        return;
      }
      final String? songPath = pickedAudioFile?.targetPath;
      if (songPath == null || songPath.trim().isEmpty) {
        _finishPreviewSave(saveGeneration);
        return;
      }
      writableAudioFile = pickedAudioFile == null
          ? null
          : await _filePicker.openAudioFileForWrite(pickedAudioFile);
      await _saveCoordinator.writeLyricsTag(
        file: writableAudioFile!,
        songPath: songPath,
        text: preview,
        lyrics: lyrics,
        id3Version: _options.id3Version,
      );
      if (!_isCurrentPreviewSave(saveGeneration)) {
        return;
      }
      state = state.copyWith(
        isSavingPreview: false,
        lastSavedPath: songPath,
        clearLastFileError: true,
      );
      _emitNotice(
        SearchNoticeCode.lyricsSaveSucceeded,
        PageNoticeSeverity.success,
      );
    } on Exception catch (error) {
      if (!_isCurrentPreviewSave(saveGeneration)) {
        return;
      }
      _finishPreviewSaveWithError(saveGeneration, error.toString());
      _emitNotice(
        SearchNoticeCode.lyricsSaveFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    } finally {
      if (writableAudioFile != null && writableAudioFile != pickedAudioFile) {
        try {
          await _filePicker.releaseAudioFile(writableAudioFile);
        } on Exception {
          // 可写 fd 释放失败不覆盖主流程结果。
        }
      }
      if (pickedAudioFile != null) {
        try {
          // iOS 打开的 security-scoped fd 需要在写入结束后显式释放。
          await _filePicker.releaseAudioFile(pickedAudioFile);
        } on Exception {
          // 释放失败不覆盖主流程结果，避免误报保存失败。
        }
      }
    }
  }

  /// 保存当前专辑/歌单歌曲歌词。
  Future<void> saveCurrentListLyrics() async {
    if (state.isBatchSaving) {
      _batchCancellationToken?.cancel();
      _emitNotice(SearchNoticeCode.batchCancelling, PageNoticeSeverity.info);
      return;
    }

    final APIResultList<SourceAware>? current = state.currentPathResult;
    if (current == null || current.info is! SongListInfo) {
      _emitNotice(
        SearchNoticeCode.selectAlbumOrPlaylistFirst,
        PageNoticeSeverity.warning,
      );
      return;
    }
    if (state.selectedLangs.isEmpty) {
      _emitNotice(
        SearchNoticeCode.selectAtLeastOneLyricsLanguage,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final List<SongInfo> songs = current.whereType<SongInfo>().toList(
      growable: false,
    );
    if (songs.isEmpty) {
      _emitNotice(SearchNoticeCode.noSongsToSave, PageNoticeSeverity.warning);
      return;
    }
    if (_isAndroidSafPlatform) {
      await _saveCurrentListLyricsToAndroidSaf(songs);
      return;
    }
    final String? folder = _requiredSaveDirectory();
    if (folder == null) {
      return;
    }

    final SearchBatchSaveCancellationToken token =
        SearchBatchSaveCancellationToken();
    final int batchGeneration = _startBatchSave(token);
    state = state.copyWith(
      isBatchSaving: true,
      saveDirectoryPath: folder,
      clearStatusMessage: true,
      batchProgress: SearchBatchSaveProgress(
        current: 0,
        total: songs.length,
        message: const SearchBatchSaveProgressMessage(
          code: SearchBatchSaveProgressMessageCode.preparing,
        ),
      ),
    );

    try {
      final SearchBatchSaveResult result = await _saveCoordinator.saveBatch(
        songs: songs,
        langs: state.selectedLangs,
        lyricsFormat: state.lyricsFormat,
        saveFolder: folder,
        options: _options.toBatchSaveOptions(),
        cancellationToken: token,
        onProgress: (SearchBatchSaveProgress progress) {
          if (!_canApplyBatchProgress(batchGeneration, token)) {
            return;
          }
          state = state.copyWith(batchProgress: progress);
        },
      );
      if (!_isCurrentBatchSave(batchGeneration, token)) {
        return;
      }
      state = state.copyWith(isBatchSaving: false, clearBatchProgress: true);
      _emitBatchSaveNotice(result);
    } on Exception catch (error) {
      if (!_isCurrentBatchSave(batchGeneration, token)) {
        return;
      }
      state = state.copyWith(isBatchSaving: false, clearBatchProgress: true);
      _emitNotice(
        SearchNoticeCode.batchSaveFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    } finally {
      if (_isCurrentBatchSave(batchGeneration, token)) {
        _batchCancellationToken = null;
      }
    }
  }

  int _startPreviewSave(SearchPreviewFileAction action) {
    final int generation = _epochs.next(_previewSaveEpochKey);
    state = state.copyWith(
      isSavingPreview: true,
      lastFileAction: action,
      clearLastSavedPath: true,
      clearLastFileError: true,
    );
    return generation;
  }

  bool _isCurrentPreviewSave(int generation) {
    return _epochs.isCurrent(_previewSaveEpochKey, generation);
  }

  void _finishPreviewSave(int generation) {
    if (!_isCurrentPreviewSave(generation)) {
      return;
    }
    state = state.copyWith(
      isSavingPreview: false,
      clearLastSavedPath: true,
      clearLastFileError: true,
    );
  }

  void _finishPreviewSaveWithError(int generation, String error) {
    if (!_isCurrentPreviewSave(generation)) {
      return;
    }
    state = state.copyWith(
      isSavingPreview: false,
      clearLastSavedPath: true,
      lastFileError: error,
    );
  }

  void _rejectPreviewSave(
    SearchPreviewFileAction action,
    String message,
    SearchNoticeCode code,
  ) {
    state = state.copyWith(
      lastFileAction: action,
      clearLastSavedPath: true,
      lastFileError: message,
    );
    _emitNotice(code, PageNoticeSeverity.warning);
  }

  Future<void> _saveCurrentListLyricsToAndroidSaf(List<SongInfo> songs) async {
    final AndroidSafTreeToken? tree = await _pickAndroidBatchSaveTree();
    if (tree == null) {
      return;
    }

    final SearchBatchSaveCancellationToken token =
        SearchBatchSaveCancellationToken();
    final int batchGeneration = _startBatchSave(token);
    state = state.copyWith(
      isBatchSaving: true,
      clearStatusMessage: true,
      batchProgress: SearchBatchSaveProgress(
        current: 0,
        total: songs.length,
        message: const SearchBatchSaveProgressMessage(
          code: SearchBatchSaveProgressMessageCode.preparing,
        ),
      ),
    );

    try {
      final SearchBatchSaveResult result = await _saveCoordinator
          .saveAndroidBatch(
            songs: songs,
            langs: state.selectedLangs,
            lyricsFormat: state.lyricsFormat,
            treeUri: tree.uri,
            options: _options.toBatchSaveOptions(),
            cancellationToken: token,
            onProgress: (SearchBatchSaveProgress progress) {
              if (!_canApplyBatchProgress(batchGeneration, token)) {
                return;
              }
              state = state.copyWith(batchProgress: progress);
            },
          );
      if (!_isCurrentBatchSave(batchGeneration, token)) {
        return;
      }
      state = state.copyWith(isBatchSaving: false, clearBatchProgress: true);
      _emitBatchSaveNotice(result);
    } on Exception catch (error) {
      if (!_isCurrentBatchSave(batchGeneration, token)) {
        return;
      }
      state = state.copyWith(isBatchSaving: false, clearBatchProgress: true);
      _emitNotice(
        SearchNoticeCode.batchSaveFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    } finally {
      if (_isCurrentBatchSave(batchGeneration, token)) {
        _batchCancellationToken = null;
      }
    }
  }

  int _startBatchSave(SearchBatchSaveCancellationToken token) {
    final int generation = _epochs.next(_batchEpochKey);
    _batchCancellationToken = token;
    return generation;
  }

  bool _isCurrentBatchSave(
    int batchGeneration,
    SearchBatchSaveCancellationToken token,
  ) {
    return _epochs.isCurrent(_batchEpochKey, batchGeneration) &&
        identical(_batchCancellationToken, token);
  }

  bool _canApplyBatchProgress(
    int batchGeneration,
    SearchBatchSaveCancellationToken token,
  ) {
    return !token.isCancelled && _isCurrentBatchSave(batchGeneration, token);
  }

  Future<void> _openSongList(SongListInfo songList) async {
    final int generation = _startTableGeneration();
    _startPreviewGeneration();
    state = state.copyWith(
      tableState: const AsyncLoading<List<SourceAware>>(
        message: SearchTableStatusMessageCode.fetchingSongList,
      ),
      clearStatusMessage: true,
      clearSourceFailures: true,
      clearCurrentLyrics: true,
      clearTranslationProgress: true,
      isSavingPreview: false,
      isTranslating: false,
      previewText: '',
      songIdText: '',
      previewPhase: SearchPreviewPhase.idle,
      previewEmptyReason: SearchPreviewEmptyReason.noSelection,
    );
    try {
      final APIResultList<SongInfo> songs = await _lyricsApi.getSonglist(
        songList,
      );
      if (!_isCurrentTableGeneration(generation)) {
        return;
      }
      final APIResultList<SourceAware> converted = APIResultList<SourceAware>(
        songs.toList(growable: false),
        info: songs.info,
        ranges: songs.sourceRanges,
        cached: songs.cached,
      );
      final List<APIResultList<SourceAware>> path =
          <APIResultList<SourceAware>>[...state.pathStack, converted];
      state = state.copyWith(
        pathStack: path,
        tableState: converted.isEmpty
            ? const AsyncEmpty<List<SourceAware>>(
                message: SearchTableStatusMessageCode.emptyList,
              )
            : AsyncSuccess<List<SourceAware>>(
                data: converted.toList(growable: false),
              ),
      );
    } on Exception catch (error) {
      if (!_isCurrentTableGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        tableState: AsyncError<List<SourceAware>>(
          message: SearchTableStatusMessage.encode(
            SearchTableStatusMessageCode.songListFailed,
            error.toString(),
          ),
        ),
      );
    }
  }

  Future<void> _openSong(SongInfo song) async {
    final int generation = _startPreviewGeneration();
    _setPreviewLoading(song.id ?? '');
    try {
      final LyricsResolveResult result = await _lyricsApi.resolveSongLyrics(
        songInfo: song,
        autoSelect: _options.autoSelect,
      );
      if (!_isCurrentPreviewGeneration(generation)) {
        return;
      }
      if (result is LyricsSelectionRequiredResult) {
        final APIResultList<SourceAware> converted = APIResultList<SourceAware>(
          result.candidates.toList(growable: false),
          info: result.candidates.info,
          ranges: result.candidates.sourceRanges,
          cached: result.candidates.cached,
        );
        final List<APIResultList<SourceAware>> path =
            <APIResultList<SourceAware>>[...state.pathStack, converted];
        state = state.copyWith(
          pathStack: path,
          tableState: AsyncSuccess<List<SourceAware>>(
            data: converted.toList(growable: false),
          ),
          clearCurrentLyrics: true,
          clearTranslationProgress: true,
          isSavingPreview: false,
          isTranslating: false,
          previewText: '',
          previewPhase: SearchPreviewPhase.idle,
          previewEmptyReason: SearchPreviewEmptyReason.noSelection,
        );
        _emitNotice(
          SearchNoticeCode.multipleLyricsCandidates,
          PageNoticeSeverity.info,
        );
        return;
      }
      final LyricsResolvedResult resolved = result as LyricsResolvedResult;
      _applyLyrics(resolved.lyrics);
    } on Exception catch (error) {
      if (!_isCurrentPreviewGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        previewPhase: SearchPreviewPhase.idle,
        previewEmptyReason: SearchPreviewEmptyReason.noSelection,
        clearCurrentLyrics: true,
        clearTranslationProgress: true,
        isSavingPreview: false,
        isTranslating: false,
        previewText: '',
      );
      _emitNotice(
        SearchNoticeCode.getLyricsFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> _openLyric(LyricInfo lyric) async {
    final int generation = _startPreviewGeneration();
    _setPreviewLoading(lyric.id ?? lyric.songInfo.id ?? '');
    try {
      final Lyrics lyrics = await _lyricsApi.getLyrics(info: lyric);
      if (!_isCurrentPreviewGeneration(generation)) {
        return;
      }
      _applyLyrics(lyrics);
    } on Exception catch (error) {
      if (!_isCurrentPreviewGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        previewPhase: SearchPreviewPhase.idle,
        previewEmptyReason: SearchPreviewEmptyReason.noSelection,
        clearCurrentLyrics: true,
        clearTranslationProgress: true,
        isSavingPreview: false,
        isTranslating: false,
        previewText: '',
      );
      _emitNotice(
        SearchNoticeCode.getLyricsFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  void _applyLyrics(
    Lyrics lyrics, {
    bool clearTranslationProgress = true,
    bool preserveTranslationActivity = false,
  }) {
    // 保存动作可能跨过系统文件选择器、磁盘或标签写入；期间用户可能切换歌词/格式。
    // 预览内容一旦重建，就让旧保存动作失效，并释放按钮忙碌态，避免旧完成提示误指向新歌词。
    _epochs.invalidate(_previewSaveEpochKey);
    if (!preserveTranslationActivity) {
      _epochs.invalidate(_translationEpochKey);
    }
    final SearchPreviewProjection projection = _previewCoordinator
        .buildProjection(
          lyrics: lyrics,
          selectedLangs: state.selectedLangs,
          lyricsFormat: state.lyricsFormat,
          offsetMs: state.offsetMs,
          convertOptions: _options.convertOptions,
        );
    state = state.copyWith(
      currentLyrics: lyrics,
      previewText: projection.previewText,
      songIdText: projection.songIdText,
      previewPhase: SearchPreviewPhase.ready,
      previewEmptyReason: projection.emptyReason,
      isSavingPreview: false,
      isTranslating: preserveTranslationActivity && !clearTranslationProgress
          ? state.isTranslating
          : false,
      clearTranslationProgress: clearTranslationProgress,
    );
  }

  List<Source> _resolveSearchSources(Source selectedSource) {
    return _queryCoordinator.resolveSources(
      selectedSource: selectedSource,
      searchType: SearchType.song,
      configuredSources: _options.searchSources,
    );
  }

  List<Source> _resolveAutoFetchSources(List<Source>? preferredSources) {
    final List<Source> candidates =
        (preferredSources ?? _resolveSearchSources(Source.multi))
            .where(
              (Source source) =>
                  source != Source.multi && source != Source.local,
            )
            .toList(growable: false);
    final List<Source> normalized = <Source>[];
    for (final Source source in candidates) {
      if (!normalized.contains(source)) {
        normalized.add(source);
      }
    }
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return _resolveSearchSources(Source.multi);
  }

  Source _resolveAutoFetchPageSource(List<Source> sources) {
    return sources.length == 1 ? sources.first : Source.multi;
  }

  APIResultList<SourceAware>? _convertAutoFetchResults(
    APIResultList<SongInfo>? searchResults,
  ) {
    if (searchResults == null) {
      return null;
    }
    return APIResultList<SourceAware>(
      searchResults.toList(growable: false),
      info: searchResults.info,
      ranges: searchResults.sourceRanges,
      cached: searchResults.cached,
      preserveOrder: true,
    );
  }

  String _resolveAutoFetchKeyword({
    required APIResultList<SongInfo>? searchResults,
    required SongInfo fallbackInfo,
  }) {
    final Object? info = searchResults?.info;
    if (info is SearchInfo && info.keyword.trim().isNotEmpty) {
      return info.keyword;
    }
    return fallbackInfo.artistTitle(replaceMissing: true);
  }

  String? _requiredSaveDirectory({SearchPreviewFileAction? action}) {
    final String? directory = _normalizedSaveDirectory();
    if (directory != null) {
      return directory;
    }
    if (action != null) {
      state = state.copyWith(
        lastFileAction: action,
        clearLastSavedPath: true,
        lastFileError: SearchNoticeCode.selectSavePathFirst.name,
      );
    }
    _emitNotice(
      SearchNoticeCode.selectSavePathFirst,
      PageNoticeSeverity.warning,
    );
    return null;
  }

  String? _normalizedSaveDirectory() {
    final String? raw = state.saveDirectoryPath;
    if (raw == null) {
      return null;
    }
    final String normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  List<String>? _allowedSaveExtensions(String ext) {
    final String normalized = ext.startsWith('.') ? ext.substring(1) : ext;
    if (normalized.isEmpty) {
      return null;
    }
    return <String>[normalized];
  }

  String? _resolveInitialDirectoryForTag(String? songPath) {
    if (songPath == null || songPath.trim().isEmpty) {
      return state.saveDirectoryPath;
    }
    final int index = songPath.lastIndexOf(RegExp(r'[\\/]'));
    if (index <= 0) {
      return state.saveDirectoryPath;
    }
    return songPath.substring(0, index);
  }

  Future<AndroidSafTreeToken?> _pickAndroidBatchSaveTree() async {
    try {
      final AndroidSafTreeToken tree = await _androidSafTreePort.pickTree();
      // Android 批量导出需要在用户确认后立即持久化授权，避免后续写入阶段失去访问权限。
      await _androidSafTreePort.persistTreePermission(tree.uri);
      return tree;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        return null;
      }
      _emitNotice(
        SearchNoticeCode.directoryPickFailed,
        PageNoticeSeverity.error,
        detail: error.message ?? error.code,
      );
      return null;
    } on Exception catch (error) {
      _emitNotice(
        SearchNoticeCode.directoryPickFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      return null;
    }
  }

  void _setPreviewLoading(String songId) {
    state = state.copyWith(
      previewPhase: SearchPreviewPhase.loading,
      clearPreviewEmptyReason: true,
      clearCurrentLyrics: true,
      clearTranslationProgress: true,
      isSavingPreview: false,
      isTranslating: false,
      previewText: '',
      songIdText: songId,
    );
  }

  SearchPreviewEmptyReason? _resolvePreviewEmptyReason({
    required Lyrics? lyrics,
    required SearchPreviewPhase previewPhase,
    required String previewText,
  }) {
    if (previewPhase == SearchPreviewPhase.loading) {
      return null;
    }
    if (lyrics == null) {
      return SearchPreviewEmptyReason.noSelection;
    }
    if (state.selectedLangs.isEmpty) {
      return SearchPreviewEmptyReason.noLanguage;
    }
    if (previewText.trim().isEmpty) {
      return SearchPreviewEmptyReason.noContent;
    }
    return null;
  }

  String _previewUnavailableMessage() {
    return _previewUnavailableNoticeCode().name;
  }

  SearchNoticeCode _previewUnavailableNoticeCode() {
    if (state.previewPhase == SearchPreviewPhase.loading) {
      return SearchNoticeCode.previewLoading;
    }
    return switch (state.previewEmptyReason) {
      SearchPreviewEmptyReason.noLanguage => SearchNoticeCode.previewNoLanguage,
      SearchPreviewEmptyReason.noContent => SearchNoticeCode.previewNoContent,
      SearchPreviewEmptyReason.noSelection ||
      null => SearchNoticeCode.previewNoSelection,
    };
  }

  void _emitBatchSaveNotice(SearchBatchSaveResult result) {
    _emitNotice(
      result.cancelled
          ? SearchNoticeCode.batchSaveCancelled
          : SearchNoticeCode.batchSaveCompleted,
      result.cancelled ? PageNoticeSeverity.info : PageNoticeSeverity.success,
      successCount: result.savedCount,
      failureCount: result.failedCount,
      skippedCount: result.skippedCount,
    );
  }

  void _emitNotice(
    SearchNoticeCode code,
    PageNoticeSeverity severity, {
    String? detail,
    int? successCount,
    int? failureCount,
    int? skippedCount,
  }) {
    _noticeId += 1;
    state = state.copyWith(
      notice: SearchNotice(
        id: _noticeId,
        severity: severity,
        code: code,
        detail: detail,
        successCount: successCount,
        failureCount: failureCount,
        skippedCount: skippedCount,
      ),
    );
  }

  int _startTableGeneration() {
    return _epochs.next(_tableEpochKey);
  }

  bool _isCurrentTableGeneration(int generation) {
    return _epochs.isCurrent(_tableEpochKey, generation);
  }

  int _startPreviewGeneration() {
    final int generation = _epochs.next(_previewEpochKey);
    _epochs.invalidate(_previewSaveEpochKey);
    _epochs.invalidate(_translationEpochKey);
    return generation;
  }

  bool _isCurrentPreviewGeneration(int generation) {
    return _epochs.isCurrent(_previewEpochKey, generation);
  }

  int _startExternalInputGeneration() {
    return _epochs.next(_externalInputEpochKey);
  }

  bool _isCurrentExternalInputGeneration(int generation) {
    return _epochs.isCurrent(_externalInputEpochKey, generation);
  }

  int _startTranslationGeneration() {
    return _epochs.next(_translationEpochKey);
  }

  bool _isCurrentTranslationGeneration(int generation) {
    return _epochs.isCurrent(_translationEpochKey, generation);
  }

  static void _toggleLangSelection(
    Set<String> langs,
    String key,
    bool? enabled,
  ) {
    if (enabled == null) {
      return;
    }
    if (enabled) {
      langs.add(key);
      return;
    }
    langs.remove(key);
  }
}

/// 搜索队列中的一次触发；被更新请求取代时正常完成，不向 UI 传播取消异常。
final class _QueuedSearch {
  final Completer<void> _completer = Completer<void>();

  Future<void> get future => _completer.future;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}
