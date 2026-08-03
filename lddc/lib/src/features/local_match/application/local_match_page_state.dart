import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

enum LocalMatchNoticeCode {
  busyImportFiles,
  selectedFilesUnavailable,
  unsupportedOperation,
  importFilesFailed,
  busyImportDirectories,
  importDirectoriesFailed,
  droppedNoAccessibleFiles,
  droppedSongResolveFailed,
  importCompletedWithErrors,
  safTreeUnsupported,
  busySwitchTree,
  selectTreeFailed,
  selectSaveRootFailed,
  busyClearQueue,
  selectItemsToDelete,
  selectItemsToSetRoot,
  selectedRootSkippedSongs,
  setRootFailed,
  selectItemsToRestore,
  cancelling,
  validationFailed,
  songDirectoryUnavailable,
  openSongDirectoryFailed,
  saveDirectoryUnavailable,
  openSaveDirectoryFailed,
  lyricsFileUnavailable,
  openLyricsFailed,
  scanCancelled,
  scanCompletedWithErrors,
  scanFailed,
  treeScanFailed,
  matchCancelled,
  matchCompleted,
  matchFailed,
  missingAndroidTree,
  androidMatchCancelledResume,
  androidMatchFailed,
}

enum LocalMatchRunValidationCode {
  emptyLangs,
  emptySources,
  emptyQueue,
  tagRequiresLrc,
  skipExistingFileNameConflict,
  savePlanBlocked,
  missingAndroidTree,
}

class LocalMatchRunValidationIssue {
  const LocalMatchRunValidationIssue({
    required this.code,
    this.detail,
    this.savePlanBlocker,
  });

  final LocalMatchRunValidationCode code;
  final String? detail;
  final LocalMatchSavePlanBlocker? savePlanBlocker;
}

typedef LocalMatchNotice = PageNotice<LocalMatchNoticeCode>;

extension LocalMatchNoticeValidation on LocalMatchNotice {
  List<LocalMatchRunValidationIssue>? get validationIssues {
    final Object? value = extra;
    return value is List<LocalMatchRunValidationIssue> ? value : null;
  }
}

enum LocalMatchInputMode { desktopPaths, androidTree }

enum LocalMatchTaskPhase { idle, scanning, matching, writing, completed }

enum LocalMatchProgressMessageCode {
  none,
  importCompleted,
  cancelling,
  scanningFiles,
  scanCancelled,
  scanCompleted,
  scanFailed,
  matchingCancelled,
  matchingCompleted,
  matchingFailed,
  preparingMatch,
  external,
}

class LocalMatchProgressMessage {
  const LocalMatchProgressMessage({required this.code, this.detail});

  const LocalMatchProgressMessage.none()
    : code = LocalMatchProgressMessageCode.none,
      detail = null;

  const LocalMatchProgressMessage.external(String text)
    : code = LocalMatchProgressMessageCode.external,
      detail = text;

  final LocalMatchProgressMessageCode code;
  final String? detail;

  bool get isEmpty =>
      code == LocalMatchProgressMessageCode.none &&
      (detail == null || detail!.trim().isEmpty);
}

enum LocalMatchSavePlanKind { none, tagOnly, fileOnly, fileAndTag }

enum LocalMatchSavePlanBlocker { none, needsSaveRoot, needsSongRoot, unknown }

class LocalMatchSavePlan {
  const LocalMatchSavePlan({
    required this.kind,
    this.targetPath,
    this.pendingFileNameRootLabel,
    this.blocker = LocalMatchSavePlanBlocker.none,
  });

  final LocalMatchSavePlanKind kind;
  final String? targetPath;
  final String? pendingFileNameRootLabel;
  final LocalMatchSavePlanBlocker blocker;

  bool get hasBlockingError => blocker != LocalMatchSavePlanBlocker.none;

  bool get waitsForLyricsFileName =>
      pendingFileNameRootLabel != null ||
      (targetPath == null &&
          (kind == LocalMatchSavePlanKind.fileOnly ||
              kind == LocalMatchSavePlanKind.fileAndTag));
}

class LocalMatchQueueItem {
  const LocalMatchQueueItem({
    required this.id,
    required this.songInfo,
    required this.defaultRootPath,
    required this.songRootPath,
    required this.savePlan,
    required this.lastStatus,
    required this.outputPath,
  });

  final String id;
  final SongInfo songInfo;
  final String? defaultRootPath;
  final String? songRootPath;
  final LocalMatchSavePlan savePlan;
  final LocalMatchingStatus? lastStatus;
  final String? outputPath;

  bool get hasCompleted => lastStatus != null;

  bool get isTagOnlyOutput => savePlan.kind == LocalMatchSavePlanKind.tagOnly;

  bool get isLyricsPathPlaceholder => savePlan.waitsForLyricsFileName;

  bool get hasFailed {
    if (savePlan.hasBlockingError) {
      return true;
    }
    return switch (lastStatus?.type) {
      LocalMatchingStatusType.autoFetchFail ||
      LocalMatchingStatusType.saveFail ||
      LocalMatchingStatusType.unknownError => true,
      _ => false,
    };
  }

  LocalMatchQueueItem copyWith({
    String? id,
    SongInfo? songInfo,
    String? defaultRootPath,
    bool clearDefaultRootPath = false,
    String? songRootPath,
    bool clearSongRootPath = false,
    LocalMatchSavePlan? savePlan,
    LocalMatchingStatus? lastStatus,
    bool clearLastStatus = false,
    String? outputPath,
    bool clearOutputPath = false,
  }) {
    return LocalMatchQueueItem(
      id: id ?? this.id,
      songInfo: songInfo ?? this.songInfo,
      defaultRootPath: clearDefaultRootPath
          ? null
          : (defaultRootPath ?? this.defaultRootPath),
      songRootPath: clearSongRootPath
          ? null
          : (songRootPath ?? this.songRootPath),
      savePlan: savePlan ?? this.savePlan,
      lastStatus: clearLastStatus ? null : (lastStatus ?? this.lastStatus),
      outputPath: clearOutputPath ? null : (outputPath ?? this.outputPath),
    );
  }
}

class LocalMatchPageState {
  const LocalMatchPageState({
    required this.inputMode,
    required this.androidTreeToken,
    required this.queueItems,
    required this.focusedItemId,
    required this.selectedItemIds,
    required this.isSelectionMode,
    required this.saveMode,
    required this.fileNameMode,
    required this.saveToTagMode,
    required this.lyricsFormat,
    required this.selectedLangs,
    required this.selectedSources,
    required this.minScore,
    required this.skipExistingLyrics,
    required this.saveRootPath,
    required this.taskPhase,
    required this.progressCurrent,
    required this.progressTotal,
    required this.progressMessage,
    required this.successCount,
    required this.skipCount,
    required this.failCount,
    required this.isRefreshingPreview,
    required this.recentErrors,
    required this.notice,
  });

  final LocalMatchInputMode inputMode;
  final AndroidSafTreeToken? androidTreeToken;
  final List<LocalMatchQueueItem> queueItems;
  final String? focusedItemId;
  final Set<String> selectedItemIds;
  final bool isSelectionMode;
  final LocalMatchSaveMode saveMode;
  final LocalMatchFileNameMode fileNameMode;
  final LocalMatchSaveToTagMode saveToTagMode;
  final LyricsFormat lyricsFormat;
  final List<String> selectedLangs;
  final List<Source> selectedSources;
  final double minScore;
  final bool skipExistingLyrics;
  final String? saveRootPath;
  final LocalMatchTaskPhase taskPhase;
  final int progressCurrent;
  final int progressTotal;
  final LocalMatchProgressMessage progressMessage;
  final int successCount;
  final int skipCount;
  final int failCount;
  final bool isRefreshingPreview;
  final List<String> recentErrors;
  final LocalMatchNotice? notice;

  bool get isBusy =>
      taskPhase == LocalMatchTaskPhase.scanning ||
      taskPhase == LocalMatchTaskPhase.matching ||
      taskPhase == LocalMatchTaskPhase.writing;

  bool get isDesktopMode => inputMode == LocalMatchInputMode.desktopPaths;

  bool get isAndroidMode => inputMode == LocalMatchInputMode.androidTree;

  bool get canStart => !isBusy && queueItems.isNotEmpty;

  int get totalCount => queueItems.length;

  LocalMatchQueueItem? get focusedItem {
    final String? itemId = focusedItemId;
    if (itemId == null) {
      return queueItems.isEmpty ? null : queueItems.first;
    }
    for (final LocalMatchQueueItem item in queueItems) {
      if (item.id == itemId) {
        return item;
      }
    }
    return queueItems.isEmpty ? null : queueItems.first;
  }

  LocalMatchPageState copyWith({
    LocalMatchInputMode? inputMode,
    AndroidSafTreeToken? androidTreeToken,
    bool clearAndroidTreeToken = false,
    List<LocalMatchQueueItem>? queueItems,
    String? focusedItemId,
    bool clearFocusedItemId = false,
    Set<String>? selectedItemIds,
    bool? isSelectionMode,
    LocalMatchSaveMode? saveMode,
    LocalMatchFileNameMode? fileNameMode,
    LocalMatchSaveToTagMode? saveToTagMode,
    LyricsFormat? lyricsFormat,
    List<String>? selectedLangs,
    List<Source>? selectedSources,
    double? minScore,
    bool? skipExistingLyrics,
    String? saveRootPath,
    bool clearSaveRootPath = false,
    LocalMatchTaskPhase? taskPhase,
    int? progressCurrent,
    int? progressTotal,
    LocalMatchProgressMessage? progressMessage,
    int? successCount,
    int? skipCount,
    int? failCount,
    bool? isRefreshingPreview,
    List<String>? recentErrors,
    LocalMatchNotice? notice,
    bool clearNotice = false,
  }) {
    return LocalMatchPageState(
      inputMode: inputMode ?? this.inputMode,
      androidTreeToken: clearAndroidTreeToken
          ? null
          : (androidTreeToken ?? this.androidTreeToken),
      queueItems: queueItems ?? this.queueItems,
      focusedItemId: clearFocusedItemId
          ? null
          : (focusedItemId ?? this.focusedItemId),
      selectedItemIds: selectedItemIds ?? this.selectedItemIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      saveMode: saveMode ?? this.saveMode,
      fileNameMode: fileNameMode ?? this.fileNameMode,
      saveToTagMode: saveToTagMode ?? this.saveToTagMode,
      lyricsFormat: lyricsFormat ?? this.lyricsFormat,
      selectedLangs: selectedLangs ?? this.selectedLangs,
      selectedSources: selectedSources ?? this.selectedSources,
      minScore: minScore ?? this.minScore,
      skipExistingLyrics: skipExistingLyrics ?? this.skipExistingLyrics,
      saveRootPath: clearSaveRootPath
          ? null
          : (saveRootPath ?? this.saveRootPath),
      taskPhase: taskPhase ?? this.taskPhase,
      progressCurrent: progressCurrent ?? this.progressCurrent,
      progressTotal: progressTotal ?? this.progressTotal,
      progressMessage: progressMessage ?? this.progressMessage,
      successCount: successCount ?? this.successCount,
      skipCount: skipCount ?? this.skipCount,
      failCount: failCount ?? this.failCount,
      isRefreshingPreview: isRefreshingPreview ?? this.isRefreshingPreview,
      recentErrors: recentErrors ?? this.recentErrors,
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  static LocalMatchPageState initial({
    required List<Source> defaultSources,
    required String? defaultSaveRootPath,
    required LocalMatchInputMode inputMode,
  }) {
    return LocalMatchPageState(
      inputMode: inputMode,
      androidTreeToken: null,
      queueItems: const <LocalMatchQueueItem>[],
      focusedItemId: null,
      selectedItemIds: const <String>{},
      isSelectionMode: false,
      saveMode: LocalMatchSaveMode.song,
      fileNameMode: LocalMatchFileNameMode.song,
      saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
      lyricsFormat: LyricsFormat.lineByLineLrc,
      selectedLangs: const <String>['orig', 'ts'],
      selectedSources: defaultSources,
      minScore: 60,
      skipExistingLyrics: false,
      saveRootPath: defaultSaveRootPath,
      taskPhase: LocalMatchTaskPhase.idle,
      progressCurrent: 0,
      progressTotal: 0,
      progressMessage: const LocalMatchProgressMessage.none(),
      successCount: 0,
      skipCount: 0,
      failCount: 0,
      isRefreshingPreview: false,
      recentErrors: const <String>[],
      notice: null,
    );
  }
}
