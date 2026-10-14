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

/// 批量转换的保存根：桌面端是本地目录，安卓端是 SAF 授权树。
///
/// 两种形态互斥（同一时刻只会命中一种），但语义都是"输出去哪"；收进一个值对象后，
/// [BatchConvertPageState.copyWith] 只需要替换或清空一处状态，不会留下
/// "本地路径已清空但树 URI 还留着"的中间态。
class BatchConvertSaveRoot {
  /// 桌面端：写到本地目录根。
  const BatchConvertSaveRoot.local(String path)
    : localPath = path,
      treeUri = null,
      treeLabel = null;

  /// 安卓端：写到用户选定的 SAF 授权树；[treeLabel] 是目录选择器给出的可读树名。
  const BatchConvertSaveRoot.saf({
    required this.treeUri,
    required this.treeLabel,
  }) : localPath = null;

  /// 本地目录根（桌面端才有值）。
  final String? localPath;

  /// 授权树 URI（安卓端才有值）；不得交给 dart:io 或桌面目录选择器。
  final String? treeUri;

  /// 授权树显示名，供控制区直接展示。
  final String? treeLabel;

  /// 控制区展示文本：安卓端只给树显示名，桌面端给本地目录。
  ///
  /// 这里刻意不返回树 URI：`content://…` 既长又没有可读信息，用户看到后无法
  /// 判断 lyrics 到底写到了哪里。
  String? get displayLabel {
    final String? path = localPath?.trim();
    if (path != null && path.isNotEmpty) {
      return path;
    }
    final String? label = treeLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is BatchConvertSaveRoot &&
      other.localPath == localPath &&
      other.treeUri == treeUri &&
      other.treeLabel == treeLabel;

  @override
  int get hashCode => Object.hash(localPath, treeUri, treeLabel);
}

class BatchConvertQueueItem {
  const BatchConvertQueueItem({
    required this.id,
    required this.source,
    required this.target,
    required this.targetDisplayPath,
    required this.fileName,
    required this.status,
    this.shortMessage,
  });

  /// 条目身份：本地源用路径，SAF 源用文档 URI。
  ///
  /// 身份必须只由源决定，不随保存根或目标格式变化，否则每次改保存目录都会让
  /// "重复导入去重"失效，同一条目会被重复入队。
  final String id;

  /// 读源：本地文件路径或 SAF 授权树内的文档。
  final BatchConvertSource source;

  /// 写目标：本地文件路径或 SAF 授权树内的新文档。
  final BatchConvertTarget target;

  /// 目标落点的可读文本，与 use case 日志同源。
  final String targetDisplayPath;

  final String fileName;
  final BatchConvertQueueItemStatus status;
  final BatchConvertProgressMessage? shortMessage;

  BatchConvertQueueItem copyWith({
    BatchConvertTarget? target,
    String? targetDisplayPath,
    BatchConvertQueueItemStatus? status,
    BatchConvertProgressMessage? shortMessage,
    bool clearShortMessage = false,
  }) {
    return BatchConvertQueueItem(
      id: id,
      source: source,
      target: target ?? this.target,
      targetDisplayPath: targetDisplayPath ?? this.targetDisplayPath,
      fileName: fileName,
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
    required this.saveRoot,
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

  /// 用户选定的保存根；为空表示"输出写在每个源文件旁边"。
  final BatchConvertSaveRoot? saveRoot;

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
    BatchConvertSaveRoot? saveRoot,
    bool clearSaveRoot = false,
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
      saveRoot: clearSaveRoot ? null : (saveRoot ?? this.saveRoot),
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
      saveRoot: null,
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
