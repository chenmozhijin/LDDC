import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

enum BatchConvertNoticeCode {
  selectedFilesUnavailable,
  importFilesCompleted,
  pageError,
  droppedNoAccessibleFiles,
  selectSaveRootFailed,
  emptyQueue,
  overwriteCancelled,
  conversionCancelledCompleted,
  conversionCompletedWithFailures,
  conversionCompleted,
  conversionFailed,
  unsupportedOperation,
  openSourceDirectoryFailed,
  openSaveDirectoryFailed,
  outputFileUnavailable,
  openOutputFileFailed,
  scanNoSupportedFiles,
  scanImportedFromDirectory,
  duplicateItems,
}

enum BatchConvertTaskPhase { idle, scanning, running, completed }

enum BatchConvertQueueItemStatus { waiting, running, success, failure }

typedef BatchConvertNotice = PageNotice<BatchConvertNoticeCode>;

class BatchConvertRunSummary {
  const BatchConvertRunSummary({
    required this.totalCount,
    required this.successCount,
    required this.failureCount,
    required this.cancelled,
  });

  final int totalCount;
  final int successCount;
  final int failureCount;
  final bool cancelled;
}

class BatchConvertQueueItem {
  const BatchConvertQueueItem({
    required this.id,
    required this.sourcePath,
    required this.fileName,
    required this.targetPath,
    required this.status,
    this.shortMessage,
  });

  final String id;
  final String sourcePath;
  final String fileName;
  final String targetPath;
  final BatchConvertQueueItemStatus status;
  final BatchConvertProgressMessage? shortMessage;

  BatchConvertQueueItem copyWith({
    String? targetPath,
    BatchConvertQueueItemStatus? status,
    BatchConvertProgressMessage? shortMessage,
    bool clearShortMessage = false,
  }) {
    return BatchConvertQueueItem(
      id: id,
      sourcePath: sourcePath,
      fileName: fileName,
      targetPath: targetPath ?? this.targetPath,
      status: status ?? this.status,
      shortMessage: clearShortMessage
          ? null
          : (shortMessage ?? this.shortMessage),
    );
  }
}

class BatchConvertPageState {
  const BatchConvertPageState({
    required this.queueItems,
    required this.targetFormat,
    required this.saveRootPath,
    required this.recursive,
    required this.taskPhase,
    required this.progressCurrent,
    required this.progressTotal,
    required this.progressMessage,
    required this.errorMessage,
    required this.runSummary,
    required this.selectedItemId,
    required this.notice,
  });

  final List<BatchConvertQueueItem> queueItems;
  final LyricsFormat targetFormat;
  final String? saveRootPath;
  final bool recursive;
  final BatchConvertTaskPhase taskPhase;
  final int progressCurrent;
  final int progressTotal;
  final BatchConvertProgressMessage progressMessage;
  final String? errorMessage;
  final BatchConvertRunSummary? runSummary;
  final String? selectedItemId;
  final BatchConvertNotice? notice;

  bool get isScanning => taskPhase == BatchConvertTaskPhase.scanning;
  bool get isRunning => taskPhase == BatchConvertTaskPhase.running;
  bool get isBusy => isScanning || isRunning;
  bool get hasQueue => queueItems.isNotEmpty;
  bool get canStart => !isBusy && queueItems.isNotEmpty;
  bool get hasPageError =>
      errorMessage != null && errorMessage!.trim().isNotEmpty;
  bool get showEmptyState => !isBusy && queueItems.isEmpty && !hasPageError;
  bool get showErrorState => !isBusy && queueItems.isEmpty && hasPageError;
  bool get showPartialSuccess =>
      !isBusy &&
      runSummary != null &&
      runSummary!.successCount > 0 &&
      runSummary!.failureCount > 0;

  int get waitingCount => queueItems
      .where(
        (BatchConvertQueueItem item) =>
            item.status == BatchConvertQueueItemStatus.waiting,
      )
      .length;

  int get successCount => queueItems
      .where(
        (BatchConvertQueueItem item) =>
            item.status == BatchConvertQueueItemStatus.success,
      )
      .length;

  int get failureCount => queueItems
      .where(
        (BatchConvertQueueItem item) =>
            item.status == BatchConvertQueueItemStatus.failure,
      )
      .length;

  int get completedCount => successCount + failureCount;

  BatchConvertPageState copyWith({
    List<BatchConvertQueueItem>? queueItems,
    LyricsFormat? targetFormat,
    String? saveRootPath,
    bool clearSaveRootPath = false,
    bool? recursive,
    BatchConvertTaskPhase? taskPhase,
    int? progressCurrent,
    int? progressTotal,
    BatchConvertProgressMessage? progressMessage,
    String? errorMessage,
    bool clearErrorMessage = false,
    BatchConvertRunSummary? runSummary,
    bool clearRunSummary = false,
    String? selectedItemId,
    bool clearSelectedItemId = false,
    BatchConvertNotice? notice,
    bool clearNotice = false,
  }) {
    return BatchConvertPageState(
      queueItems: queueItems ?? this.queueItems,
      targetFormat: targetFormat ?? this.targetFormat,
      saveRootPath: clearSaveRootPath
          ? null
          : (saveRootPath ?? this.saveRootPath),
      recursive: recursive ?? this.recursive,
      taskPhase: taskPhase ?? this.taskPhase,
      progressCurrent: progressCurrent ?? this.progressCurrent,
      progressTotal: progressTotal ?? this.progressTotal,
      progressMessage: progressMessage ?? this.progressMessage,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      runSummary: clearRunSummary ? null : (runSummary ?? this.runSummary),
      selectedItemId: clearSelectedItemId
          ? null
          : (selectedItemId ?? this.selectedItemId),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  static BatchConvertPageState initial() {
    return const BatchConvertPageState(
      queueItems: <BatchConvertQueueItem>[],
      targetFormat: LyricsFormat.lineByLineLrc,
      saveRootPath: null,
      recursive: false,
      taskPhase: BatchConvertTaskPhase.idle,
      progressCurrent: 0,
      progressTotal: 0,
      progressMessage: BatchConvertProgressMessage.empty(),
      errorMessage: null,
      runSummary: null,
      selectedItemId: null,
      notice: null,
    );
  }
}
