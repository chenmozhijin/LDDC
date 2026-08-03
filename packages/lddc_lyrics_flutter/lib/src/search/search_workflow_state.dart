import 'package:flutter/foundation.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../state/state.dart';
import 'search_batch_save_lyrics_usecase.dart';

/// 搜索结果表格状态文案码。
abstract final class SearchTableStatusMessageCode {
  static const String autoFetching = 'search.table.loading.autoFetching';
  static const String searching = 'search.table.loading.searching';
  static const String fetchingSongList = 'search.table.loading.songList';
  static const String noResults = 'search.table.empty.noResults';
  static const String emptyList = 'search.table.empty.list';
  static const String unsupportedSearchType =
      'search.table.error.unsupportedSearchType';
  static const String searchFailed = 'search.table.error.searchFailed';
  static const String autoFetchFailed = 'search.table.error.autoFetchFailed';
  static const String songListFailed = 'search.table.error.songListFailed';
  static const String partialSourceUnavailable =
      'search.table.warning.partialSourceUnavailable';
  static const String loadMoreFailed = 'search.table.warning.loadMoreFailed';
}

/// 搜索表格状态文案编码器。
///
/// `AsyncViewState` 是 shared UI 基础模型，仍使用字符串承载提示。这里用稳定
/// message code 替代最终中文句子，并允许附带 detail，避免 controller 依赖 UI
/// locale，同时不扩大 shared 模型改动面。
abstract final class SearchTableStatusMessage {
  static const String _separator = '\u001F';

  static String encode(String code, [String? detail]) {
    final String? normalized = detail?.trim();
    if (normalized == null || normalized.isEmpty) {
      return code;
    }
    return '$code$_separator$normalized';
  }

  static (String code, String? detail) decode(String message) {
    final int index = message.indexOf(_separator);
    if (index < 0) {
      return (message, null);
    }
    return (
      message.substring(0, index),
      message.substring(index + _separator.length),
    );
  }
}

/// 搜索页一次性通知语义码。
///
/// controller 只保存语义和必要参数，不保存最终中文文案。这样运行时切换
/// locale 后，页面可以用当前 `AppLocalizations` 重新渲染同一条通知。
enum SearchNoticeCode {
  searchPartialSourcesFailed,
  searchAllSourcesFailed,
  searchLoadMoreFailed,
  directoryPickerUnsupported,
  autoFetchSucceeded,
  autoFetchFailed,
  selectedSongUnavailable,
  filePickerUnsupported,
  openSongFailed,
  droppedSongUnavailable,
  droppedSongResolveFailed,
  emptyKeyword,
  getLyricsFirst,
  translationCancelled,
  translationCompleted,
  translationFailed,
  lyricsSaveSucceeded,
  lyricsSaveFailed,
  saveFileUnsupported,
  filePickerForTagUnsupported,
  filePickerFailed,
  batchCancelling,
  selectAlbumOrPlaylistFirst,
  selectAtLeastOneLyricsLanguage,
  noSongsToSave,
  batchSaveCancelled,
  batchSaveCompleted,
  batchSaveFailed,
  multipleLyricsCandidates,
  getLyricsFailed,
  selectSavePathFirst,
  directoryPickFailed,
  previewLoading,
  previewNoLanguage,
  previewNoContent,
  previewNoSelection,
  audioTagRequiresLrc,
}

typedef SearchNotice = PageNotice<SearchNoticeCode>;

enum SearchSourceFailureKind {
  request,
  timeout,
  parameters,
  unsupported,
  unknown,
}

/// 当前搜索批次中单个来源的有界失败快照。
///
/// 页面只保留异常文本，不保留异常对象或堆栈，避免状态树间接延长大型响应和
/// StackTrace 的生命周期。完整诊断仍由请求层日志负责。
@immutable
final class SearchSourceFailure {
  const SearchSourceFailure({
    required this.source,
    required this.kind,
    required this.detail,
  });

  static const int maximumDetailLength = 1000;

  final Source source;
  final SearchSourceFailureKind kind;
  final String detail;

  factory SearchSourceFailure.bounded({
    required Source source,
    required SearchSourceFailureKind kind,
    required String detail,
  }) {
    final String normalized = detail.trim();
    return SearchSourceFailure(
      source: source,
      kind: kind,
      detail: normalized.length <= maximumDetailLength
          ? normalized
          : '${normalized.substring(0, maximumDetailLength)}…',
    );
  }
}

/// 歌词预览面板阶段。
enum SearchPreviewPhase { idle, loading, ready }

/// 歌词预览空态原因。
enum SearchPreviewEmptyReason { noSelection, noLanguage, noContent }

/// 搜索预览单次文件动作类型。
enum SearchPreviewFileAction { saveDirectory, saveFile, saveTag }

/// 搜索页状态快照。
class SearchWorkflowState {
  const SearchWorkflowState({
    required this.keyword,
    required this.selectedSource,
    required this.availableSearchTypes,
    required this.selectedSearchType,
    required this.selectedLangs,
    required this.lyricsFormat,
    required this.offsetMs,
    required this.tableState,
    required this.pathStack,
    required this.previewText,
    required this.songIdText,
    required this.hasSubmittedSearch,
    required this.previewPhase,
    required this.previewEmptyReason,
    required this.isSearching,
    required this.isLoadingMore,
    required this.isBatchSaving,
    required this.isSavingPreview,
    required this.isTranslating,
    required this.batchProgress,
    required this.statusMessage,
    required this.saveDirectoryPath,
    required this.currentLyrics,
    required this.translationProgress,
    required this.notice,
    required this.lastFileAction,
    required this.lastSavedPath,
    required this.lastFileError,
    this.sourceFailures = const <SearchSourceFailure>[],
  });

  final String keyword;
  final Source selectedSource;
  final List<SearchType> availableSearchTypes;
  final SearchType selectedSearchType;
  final List<String> selectedLangs;
  final LyricsFormat lyricsFormat;
  final int offsetMs;
  final AsyncViewState<List<SourceAware>> tableState;
  final List<APIResultList<SourceAware>> pathStack;
  final String previewText;
  final String songIdText;
  final bool hasSubmittedSearch;
  final SearchPreviewPhase previewPhase;
  final SearchPreviewEmptyReason? previewEmptyReason;
  final bool isSearching;
  final bool isLoadingMore;
  final bool isBatchSaving;
  final bool isSavingPreview;
  final bool isTranslating;
  final SearchBatchSaveProgress? batchProgress;
  final String? statusMessage;
  final String? saveDirectoryPath;
  final Lyrics? currentLyrics;
  final OpenAiTranslationProgress? translationProgress;
  final SearchNotice? notice;
  final SearchPreviewFileAction? lastFileAction;
  final String? lastSavedPath;
  final String? lastFileError;
  final List<SearchSourceFailure> sourceFailures;

  bool get canReturn => pathStack.length > 1;

  APIResultList<SourceAware>? get currentPathResult {
    if (pathStack.isEmpty) {
      return null;
    }
    return pathStack.last;
  }

  bool get hasMore {
    final APIResultList<SourceAware>? result = currentPathResult;
    if (result == null) {
      return false;
    }
    return result.more.isNotEmpty;
  }

  bool get canLoadMore => !isSearching && !isLoadingMore && hasMore;

  SearchWorkflowState copyWith({
    String? keyword,
    Source? selectedSource,
    List<SearchType>? availableSearchTypes,
    SearchType? selectedSearchType,
    List<String>? selectedLangs,
    LyricsFormat? lyricsFormat,
    int? offsetMs,
    AsyncViewState<List<SourceAware>>? tableState,
    List<APIResultList<SourceAware>>? pathStack,
    String? previewText,
    String? songIdText,
    bool? hasSubmittedSearch,
    SearchPreviewPhase? previewPhase,
    SearchPreviewEmptyReason? previewEmptyReason,
    bool clearPreviewEmptyReason = false,
    bool? isSearching,
    bool? isLoadingMore,
    bool? isBatchSaving,
    bool? isSavingPreview,
    bool? isTranslating,
    SearchBatchSaveProgress? batchProgress,
    bool clearBatchProgress = false,
    String? statusMessage,
    bool clearStatusMessage = false,
    String? saveDirectoryPath,
    bool clearSaveDirectoryPath = false,
    Lyrics? currentLyrics,
    bool clearCurrentLyrics = false,
    OpenAiTranslationProgress? translationProgress,
    bool clearTranslationProgress = false,
    SearchNotice? notice,
    bool clearNotice = false,
    SearchPreviewFileAction? lastFileAction,
    bool clearLastFileAction = false,
    String? lastSavedPath,
    bool clearLastSavedPath = false,
    String? lastFileError,
    bool clearLastFileError = false,
    List<SearchSourceFailure>? sourceFailures,
    bool clearSourceFailures = false,
  }) {
    return SearchWorkflowState(
      keyword: keyword ?? this.keyword,
      selectedSource: selectedSource ?? this.selectedSource,
      availableSearchTypes: availableSearchTypes ?? this.availableSearchTypes,
      selectedSearchType: selectedSearchType ?? this.selectedSearchType,
      selectedLangs: selectedLangs ?? this.selectedLangs,
      lyricsFormat: lyricsFormat ?? this.lyricsFormat,
      offsetMs: offsetMs ?? this.offsetMs,
      tableState: tableState ?? this.tableState,
      pathStack: pathStack ?? this.pathStack,
      previewText: previewText ?? this.previewText,
      songIdText: songIdText ?? this.songIdText,
      hasSubmittedSearch: hasSubmittedSearch ?? this.hasSubmittedSearch,
      previewPhase: previewPhase ?? this.previewPhase,
      previewEmptyReason: clearPreviewEmptyReason
          ? null
          : (previewEmptyReason ?? this.previewEmptyReason),
      isSearching: isSearching ?? this.isSearching,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isBatchSaving: isBatchSaving ?? this.isBatchSaving,
      isSavingPreview: isSavingPreview ?? this.isSavingPreview,
      isTranslating: isTranslating ?? this.isTranslating,
      batchProgress: clearBatchProgress
          ? null
          : (batchProgress ?? this.batchProgress),
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      saveDirectoryPath: clearSaveDirectoryPath
          ? null
          : (saveDirectoryPath ?? this.saveDirectoryPath),
      currentLyrics: clearCurrentLyrics
          ? null
          : (currentLyrics ?? this.currentLyrics),
      translationProgress: clearTranslationProgress
          ? null
          : (translationProgress ?? this.translationProgress),
      notice: clearNotice ? null : (notice ?? this.notice),
      lastFileAction: clearLastFileAction
          ? null
          : (lastFileAction ?? this.lastFileAction),
      lastSavedPath: clearLastSavedPath
          ? null
          : (lastSavedPath ?? this.lastSavedPath),
      lastFileError: clearLastFileError
          ? null
          : (lastFileError ?? this.lastFileError),
      sourceFailures: clearSourceFailures
          ? const <SearchSourceFailure>[]
          : (sourceFailures ?? this.sourceFailures),
    );
  }

  static SearchWorkflowState initial({String? defaultSaveDirectory}) {
    final List<SearchType> types = Source.multi.supportedSearchTypes.toList(
      growable: false,
    );
    return SearchWorkflowState(
      keyword: '',
      selectedSource: Source.multi,
      availableSearchTypes: types,
      selectedSearchType: types.first,
      selectedLangs: const <String>['orig', 'ts'],
      lyricsFormat: LyricsFormat.verbatimLrc,
      offsetMs: 0,
      tableState: const AsyncEmpty<List<SourceAware>>(message: ''),
      pathStack: const <APIResultList<SourceAware>>[],
      previewText: '',
      songIdText: '',
      hasSubmittedSearch: false,
      previewPhase: SearchPreviewPhase.idle,
      previewEmptyReason: SearchPreviewEmptyReason.noSelection,
      isSearching: false,
      isLoadingMore: false,
      isBatchSaving: false,
      isSavingPreview: false,
      isTranslating: false,
      batchProgress: null,
      statusMessage: null,
      saveDirectoryPath: defaultSaveDirectory,
      currentLyrics: null,
      translationProgress: null,
      notice: null,
      lastFileAction: null,
      lastSavedPath: null,
      lastFileError: null,
      sourceFailures: const <SearchSourceFailure>[],
    );
  }
}
