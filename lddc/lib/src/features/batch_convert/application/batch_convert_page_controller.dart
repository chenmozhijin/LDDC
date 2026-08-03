import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/config.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'batch_convert_directory_scanner.dart';
import 'batch_convert_dependencies.dart';
import 'batch_convert_input_picker.dart';
import 'batch_convert_overwrite_summary.dart';
import 'batch_convert_page_state.dart';

final NotifierProvider<BatchConvertPageController, BatchConvertPageState>
batchConvertPageControllerProvider =
    NotifierProvider<BatchConvertPageController, BatchConvertPageState>(
      BatchConvertPageController.new,
      // 批量转换页在 app 层局部注入文件选择、路径打开和拖拽能力；声明依赖门面后，
      // 页面保活时仍会使用当前 route scope 的实例，不会退回父容器默认实现。
      dependencies: [batchConvertDependenciesProvider],
    );

class BatchConvertPageController extends Notifier<BatchConvertPageState> {
  int _noticeId = 0;
  final OperationEpoch _taskEpoch = OperationEpoch();
  BatchConvertCancellationToken? _cancellationToken;
  String? _runningItemId;
  final TaskQueueRuntime<BatchConvertQueueItem> _queueRuntime =
      TaskQueueRuntime<BatchConvertQueueItem>(
        idOf: (BatchConvertQueueItem item) => item.id,
      );

  BatchConvertInputPicker get _inputPicker =>
      ref.read(batchConvertDependenciesProvider).inputPicker;
  BatchConvertDirectoryScanner get _directoryScanner =>
      ref.read(batchConvertDirectoryScannerProvider);
  BatchConvertUseCase get _useCase =>
      ref.read(batchConvertDependenciesProvider).useCase;
  AppConfig get _config =>
      ref.read(batchConvertDependenciesProvider).configRepository.current;
  AppPathOpener get _pathOpener =>
      ref.read(batchConvertDependenciesProvider).pathOpener;
  Future<bool> Function(BatchConvertOverwriteSummary summary)
  get _confirmOverwrite =>
      ref.read(batchConvertDependenciesProvider).confirmOverwrite;

  ValueListenable<List<String>> get queueOrderListenable =>
      _queueRuntime.orderListenable;

  ValueListenable<int> get queueRevisionListenable =>
      _queueRuntime.revisionListenable;

  TaskQueueBinding<BatchConvertQueueItem>? queueBinding(String itemId) =>
      _queueRuntime.binding(itemId);

  BatchConvertPageState get currentState => state;

  List<BatchConvertQueueItem> get queueSnapshot => _queueItems;

  List<BatchConvertQueueItem> get _queueItems => _queueRuntime.snapshot;

  @override
  BatchConvertPageState build() {
    ref.onDispose(() {
      // 销毁时先推进 generation，让已经 await 出去的扫描/转换回调全部失效；
      // 再取消 token 和释放队列 runtime，避免迟到回调写 disposed notifier。
      _taskEpoch.invalidate();
      _cancellationToken?.cancel();
      _cancellationToken = null;
      _queueRuntime.dispose();
    });
    return BatchConvertPageState.initial();
  }

  void dismissNotice([int? id]) {
    if (id != null && state.notice?.id != id) {
      return;
    }
    state = state.copyWith(clearNotice: true);
  }

  void selectQueueItem(String itemId) {
    if (!_queueItems.any((BatchConvertQueueItem item) => item.id == itemId)) {
      clearSelectedQueueItem();
      return;
    }
    state = state.copyWith(selectedItemId: itemId);
  }

  void clearSelectedQueueItem() {
    state = state.copyWith(clearSelectedItemId: true);
  }

  Future<void> addFiles() async {
    if (state.isBusy) {
      return;
    }
    try {
      final List<PickedFileHandle> files = await _inputPicker.pickLyricsFiles(
        initialDirectory: _resolveInitialDirectory(),
      );
      if (files.isEmpty) {
        return;
      }
      final List<String> paths = files
          .map((PickedFileHandle file) => file.path?.trim() ?? '')
          .where((String path) => path.isNotEmpty)
          .toList(growable: false);
      if (paths.isEmpty) {
        _emitNotice(
          BatchConvertNoticeCode.selectedFilesUnavailable,
          PageNoticeSeverity.warning,
        );
        return;
      }
      _appendSourcePaths(paths);
      _emitNotice(
        BatchConvertNoticeCode.importFilesCompleted,
        PageNoticeSeverity.success,
        count: paths.length,
      );
    } on Exception catch (error) {
      _setPageError('导入文件失败：$error');
    }
  }

  Future<void> addDirectories() async {
    if (state.isBusy) {
      return;
    }
    try {
      final List<String> directories = await _inputPicker.pickLyricsDirectories(
        initialDirectory: _resolveInitialDirectory(),
      );
      if (directories.isEmpty) {
        return;
      }
      await _scanDirectories(directories);
    } on Exception catch (error) {
      _setPageError('选择文件夹失败：$error');
    }
  }

  Future<void> importExternalPaths(List<String> inputPaths) async {
    if (state.isBusy) {
      return;
    }
    final List<String> normalized = inputPaths
        .map((String path) => path.trim())
        .where((String path) => path.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      _emitNotice(
        BatchConvertNoticeCode.droppedNoAccessibleFiles,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final List<String> filePaths = <String>[];
    final List<String> directoryPaths = <String>[];
    for (final String path in normalized) {
      // 拖拽导入可能一次带入很多路径，异步 stat 可避免同步文件系统调用卡住页面。
      // ignore: avoid_slow_async_io
      final FileSystemEntityType type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
        directoryPaths.add(path);
      } else if (type == FileSystemEntityType.file) {
        filePaths.add(path);
      }
    }
    if (filePaths.isNotEmpty) {
      _appendSourcePaths(filePaths);
    }
    if (directoryPaths.isNotEmpty) {
      await _scanDirectories(directoryPaths);
      return;
    }
    if (filePaths.isNotEmpty) {
      _emitNotice(
        BatchConvertNoticeCode.importFilesCompleted,
        PageNoticeSeverity.success,
        count: filePaths.length,
      );
    }
  }

  Future<void> selectSaveRootDirectory() async {
    if (state.isBusy) {
      return;
    }
    try {
      final String? picked = await _inputPicker.pickSaveRootDirectory(
        initialDirectory: state.saveRootPath ?? _resolveInitialDirectory(),
      );
      if (picked == null || picked.trim().isEmpty) {
        return;
      }
      _rebuildQueue(
        saveRootPath: picked.trim(),
        targetFormat: state.targetFormat,
      );
    } on Exception catch (error) {
      _emitNotice(
        BatchConvertNoticeCode.selectSaveRootFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  void clearSaveRootDirectory() {
    if (state.isBusy) {
      return;
    }
    _rebuildQueue(targetFormat: state.targetFormat, clearSaveRootPath: true);
  }

  void toggleRecursive(bool value) {
    state = state.copyWith(recursive: value);
  }

  void updateTargetFormat(LyricsFormat targetFormat) {
    if (state.targetFormat == targetFormat) {
      return;
    }
    _rebuildQueue(targetFormat: targetFormat);
  }

  void removeQueueItem(String itemId) {
    if (state.isBusy) {
      return;
    }
    final List<BatchConvertQueueItem> nextItems = _queueItems
        .where((BatchConvertQueueItem item) => item.id != itemId)
        .toList(growable: false);
    _setQueueItems(
      nextItems,
      taskPhase: state.taskPhase,
      clearErrorMessage: true,
      clearRunSummary: true,
      progressCurrent: 0,
      progressTotal: 0,
      progressMessage: nextItems.isEmpty
          ? const BatchConvertProgressMessage.empty()
          : state.progressMessage,
    );
  }

  void clearQueue() {
    if (state.isBusy) {
      return;
    }
    _setQueueItems(
      const <BatchConvertQueueItem>[],
      taskPhase: BatchConvertTaskPhase.idle,
      clearErrorMessage: true,
      clearRunSummary: true,
      progressCurrent: 0,
      progressTotal: 0,
      progressMessage: const BatchConvertProgressMessage.empty(),
    );
    _runningItemId = null;
  }

  Future<void> startOrCancel() async {
    if (state.isRunning) {
      _cancellationToken?.cancel();
      state = state.copyWith(
        progressMessage: const BatchConvertProgressMessage(
          code: BatchConvertProgressMessageCode.cancellingConversion,
        ),
      );
      return;
    }
    if (_queueItems.isEmpty) {
      _emitNotice(
        BatchConvertNoticeCode.emptyQueue,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final BatchConvertOverwriteSummary overwriteSummary =
        await _inspectOverwriteSummary(_queueItems);
    if (overwriteSummary.hasRisk) {
      final bool confirmed = await _confirmOverwrite(overwriteSummary);
      if (!confirmed) {
        _emitNotice(
          BatchConvertNoticeCode.overwriteCancelled,
          PageNoticeSeverity.info,
        );
        return;
      }
    }

    final int generation = _taskEpoch.next();
    final BatchConvertCancellationToken token = BatchConvertCancellationToken();
    _cancellationToken = token;
    _resetQueueForRun();
    state = state.copyWith(
      taskPhase: BatchConvertTaskPhase.running,
      progressCurrent: 0,
      progressTotal: _queueItems.length,
      progressMessage: const BatchConvertProgressMessage(
        code: BatchConvertProgressMessageCode.preparingConversion,
      ),
      clearErrorMessage: true,
      clearRunSummary: true,
      clearNotice: true,
    );

    try {
      final BatchConvertResult result = await _useCase.run(
        items: <BatchConvertItem>[
          for (final BatchConvertQueueItem item in _queueItems)
            BatchConvertItem(
              sourcePath: item.sourcePath,
              targetPath: item.targetPath,
            ),
        ],
        targetFormat: state.targetFormat,
        convertOptions: _config.toLyricsConvertOptions(),
        allowOverwrite: overwriteSummary.hasRisk,
        cancellationToken: token,
        onProgress: (BatchConvertProgress progress) {
          // 用户点取消后，use case 可能仍在等待当前文件读写或外部解析结束；
          // 此时后续 progress 只代表旧执行链的迟到状态，不应覆盖“正在取消”的页面反馈。
          if (!_isCurrentTask(generation) || token.isCancelled) {
            return;
          }
          _applyProgress(progress);
        },
      );
      if (!_isCurrentTask(generation)) {
        return;
      }
      state = state.copyWith(
        taskPhase: BatchConvertTaskPhase.completed,
        progressCurrent: result.successCount + result.failureCount,
        progressTotal: _queueItems.length,
        progressMessage: result.cancelled
            ? const BatchConvertProgressMessage(
                code: BatchConvertProgressMessageCode.conversionCancelled,
              )
            : BatchConvertProgressMessage(
                code: BatchConvertProgressMessageCode.conversionCompleted,
                successCount: result.successCount,
                failureCount: result.failureCount,
              ),
        runSummary: BatchConvertRunSummary(
          totalCount: _queueItems.length,
          successCount: result.successCount,
          failureCount: result.failureCount,
          cancelled: result.cancelled,
        ),
      );
      _syncQueueSnapshotToState();
      if (result.cancelled) {
        _emitNotice(
          BatchConvertNoticeCode.conversionCancelledCompleted,
          PageNoticeSeverity.info,
          count: result.successCount + result.failureCount,
        );
      } else if (result.failureCount > 0) {
        _emitNotice(
          BatchConvertNoticeCode.conversionCompletedWithFailures,
          PageNoticeSeverity.warning,
          successCount: result.successCount,
          failureCount: result.failureCount,
        );
      } else {
        _emitNotice(
          BatchConvertNoticeCode.conversionCompleted,
          PageNoticeSeverity.success,
          count: result.successCount,
        );
      }
    } on Exception catch (error) {
      if (!_isCurrentTask(generation)) {
        return;
      }
      _syncQueueSnapshotToState();
      state = state.copyWith(
        taskPhase: BatchConvertTaskPhase.completed,
        progressMessage: BatchConvertProgressMessage(
          code: BatchConvertProgressMessageCode.conversionFailed,
          detail: error.toString(),
        ),
        errorMessage: '批量转换失败：$error',
      );
      _emitNotice(
        BatchConvertNoticeCode.conversionFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    } finally {
      if (_isCurrentTask(generation)) {
        _cancellationToken = null;
      }
    }
  }

  Future<void> openSourceDirectory(String itemId) async {
    final BatchConvertQueueItem? item = _findItem(itemId);
    if (item == null) {
      return;
    }
    try {
      await _pathOpener.openDirectory(p.dirname(item.sourcePath));
    } on UnsupportedError catch (error) {
      _emitNotice(
        BatchConvertNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        BatchConvertNoticeCode.openSourceDirectoryFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> openSaveDirectory(String itemId) async {
    final BatchConvertQueueItem? item = _findItem(itemId);
    if (item == null) {
      return;
    }
    try {
      await _pathOpener.openDirectory(p.dirname(item.targetPath));
    } on UnsupportedError catch (error) {
      _emitNotice(
        BatchConvertNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        BatchConvertNoticeCode.openSaveDirectoryFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> openOutputFile(String itemId) async {
    final BatchConvertQueueItem? item = _findItem(itemId);
    if (item == null) {
      return;
    }
    // 打开前只做轻量存在性确认，使用异步 exists 避免网络盘路径阻塞 UI。
    // ignore: avoid_slow_async_io
    if (!await File(item.targetPath).exists()) {
      _emitNotice(
        BatchConvertNoticeCode.outputFileUnavailable,
        PageNoticeSeverity.info,
      );
      return;
    }
    try {
      await _pathOpener.openFile(item.targetPath);
    } on UnsupportedError catch (error) {
      _emitNotice(
        BatchConvertNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        BatchConvertNoticeCode.openOutputFileFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> openInOpenLyrics(String itemId) async {
    final BatchConvertQueueItem? item = _findItem(itemId);
    if (item == null) {
      return;
    }
    // 打开前只做轻量存在性确认，使用异步 exists 避免网络盘路径阻塞 UI。
    // ignore: avoid_slow_async_io
    if (!await File(item.targetPath).exists()) {
      _emitNotice(
        BatchConvertNoticeCode.outputFileUnavailable,
        PageNoticeSeverity.info,
      );
      return;
    }
    await ref
        .read(batchConvertDependenciesProvider)
        .openInOpenLyrics(item.targetPath);
  }

  Future<void> _scanDirectories(List<String> directories) async {
    final int generation = _taskEpoch.next();
    state = state.copyWith(
      taskPhase: BatchConvertTaskPhase.scanning,
      progressCurrent: 0,
      progressTotal: 0,
      progressMessage: const BatchConvertProgressMessage(
        code: BatchConvertProgressMessageCode.scanningFolders,
      ),
      clearErrorMessage: true,
      clearRunSummary: true,
      clearNotice: true,
    );
    try {
      final BatchConvertDirectoryScanResult result = await _directoryScanner
          .scan(
            rootDirectories: directories,
            recursive: state.recursive,
            onChunk: (List<String> sourcePaths) {
              if (!_isCurrentTask(generation)) {
                return;
              }
              _appendSourcePaths(sourcePaths, silent: true);
            },
            onProgress:
                (BatchConvertProgressMessage message, int value, int maxValue) {
                  if (!_isCurrentTask(generation)) {
                    return;
                  }
                  state = state.copyWith(
                    taskPhase: BatchConvertTaskPhase.scanning,
                    progressCurrent: value,
                    progressTotal: maxValue,
                    progressMessage: message,
                  );
                },
            shouldCancel: () => !_isCurrentTask(generation),
          );
      if (!_isCurrentTask(generation)) {
        return;
      }
      state = state.copyWith(
        taskPhase: BatchConvertTaskPhase.completed,
        progressCurrent: _queueItems.length,
        progressTotal: _queueItems.length,
        progressMessage: result.cancelled
            ? const BatchConvertProgressMessage(
                code: BatchConvertProgressMessageCode.scanCancelled,
              )
            : (result.foundCount == 0
                  ? const BatchConvertProgressMessage(
                      code:
                          BatchConvertProgressMessageCode.scanNoSupportedFiles,
                    )
                  : const BatchConvertProgressMessage(
                      code: BatchConvertProgressMessageCode.scanCompleted,
                    )),
      );
      if (result.errors.isNotEmpty && _queueItems.isEmpty) {
        _setPageError('扫描失败：${result.errors.first}');
        return;
      }
      if (result.foundCount == 0) {
        _emitNotice(
          BatchConvertNoticeCode.scanNoSupportedFiles,
          PageNoticeSeverity.info,
        );
      } else {
        _emitNotice(
          BatchConvertNoticeCode.scanImportedFromDirectory,
          PageNoticeSeverity.success,
          count: result.foundCount,
        );
      }
    } on Exception catch (error) {
      if (!_isCurrentTask(generation)) {
        return;
      }
      _setPageError('扫描文件夹失败：$error');
    }
  }

  void _appendSourcePaths(List<String> sourcePaths, {bool silent = false}) {
    final Map<String, BatchConvertQueueItem> existing =
        <String, BatchConvertQueueItem>{
          for (final BatchConvertQueueItem item in _queueItems)
            item.sourcePath: item,
        };
    bool changed = false;
    for (final String rawPath in sourcePaths) {
      final String sourcePath = rawPath.trim();
      if (sourcePath.isEmpty || existing.containsKey(sourcePath)) {
        continue;
      }
      existing[sourcePath] = BatchConvertQueueItem(
        id: sourcePath,
        sourcePath: sourcePath,
        fileName: p.basename(sourcePath),
        targetPath: sourcePath,
        status: BatchConvertQueueItemStatus.waiting,
      );
      changed = true;
    }
    if (!changed) {
      if (!silent) {
        _emitNotice(
          BatchConvertNoticeCode.duplicateItems,
          PageNoticeSeverity.info,
        );
      }
      return;
    }
    _setQueueItems(
      existing.values.toList(growable: false),
      taskPhase: state.isScanning
          ? BatchConvertTaskPhase.scanning
          : BatchConvertTaskPhase.completed,
      clearErrorMessage: true,
      clearRunSummary: true,
    );
  }

  void _rebuildQueue({
    required LyricsFormat targetFormat,
    String? saveRootPath,
    bool clearSaveRootPath = false,
  }) {
    final String? effectiveRootPath = clearSaveRootPath
        ? null
        : (saveRootPath ?? state.saveRootPath);
    final List<BatchConvertQueueItem> nextItems = _queueItems
        .map(
          (BatchConvertQueueItem item) => item.copyWith(
            targetPath: _resolveBatchConvertTargetPath(
              sourcePath: item.sourcePath,
              targetFormat: targetFormat,
              saveRootPath: effectiveRootPath,
            ),
          ),
        )
        .toList(growable: false);
    _setQueueItems(
      nextItems,
      taskPhase: state.taskPhase,
      targetFormat: targetFormat,
      saveRootPath: effectiveRootPath,
      clearSaveRootPath: clearSaveRootPath,
      clearRunSummary: true,
      clearErrorMessage: true,
    );
  }

  void _resetQueueForRun() {
    _runningItemId = null;
    _setQueueItems(
      _queueItems
          .map(
            (BatchConvertQueueItem item) => item.copyWith(
              status: BatchConvertQueueItemStatus.waiting,
              clearShortMessage: true,
            ),
          )
          .toList(growable: false),
      taskPhase: state.taskPhase,
    );
  }

  void _applyProgress(BatchConvertProgress progress) {
    final BatchConvertStatus? status = progress.status;
    if (status != null &&
        status.index >= 0 &&
        status.index < _queueItems.length) {
      final BatchConvertQueueItem item = _queueItems[status.index];
      _queueRuntime.patchItem(
        item.id,
        (BatchConvertQueueItem current) => current.copyWith(
          status: status.type == BatchConvertStatusType.success
              ? BatchConvertQueueItemStatus.success
              : BatchConvertQueueItemStatus.failure,
          shortMessage: status.type == BatchConvertStatusType.success
              ? const BatchConvertProgressMessage(
                  code: BatchConvertProgressMessageCode.itemSuccess,
                )
              : const BatchConvertProgressMessage(
                  code: BatchConvertProgressMessageCode.itemFailure,
                ),
        ),
      );
      if (_runningItemId == item.id) {
        _runningItemId = null;
      }
    }

    final String? previousRunningItemId = _runningItemId;
    final String? nextRunningItemId =
        progress.value >= 0 &&
            progress.value < progress.maxValue &&
            progress.value < _queueItems.length &&
            !progress.message.isEmpty
        ? _queueItems[progress.value].id
        : null;

    if (previousRunningItemId != null &&
        previousRunningItemId != nextRunningItemId) {
      _queueRuntime.patchItem(
        previousRunningItemId,
        (BatchConvertQueueItem item) =>
            item.status == BatchConvertQueueItemStatus.running
            ? item.copyWith(
                status: BatchConvertQueueItemStatus.waiting,
                clearShortMessage: true,
              )
            : item,
      );
    }

    if (nextRunningItemId != null) {
      _queueRuntime.patchItem(
        nextRunningItemId,
        (BatchConvertQueueItem item) => item.copyWith(
          status: BatchConvertQueueItemStatus.running,
          shortMessage: progress.message,
        ),
      );
    }

    _runningItemId = nextRunningItemId;
    state = state.copyWith(
      progressCurrent: progress.value,
      progressTotal: progress.maxValue,
      progressMessage: progress.message,
    );
  }

  void _setQueueItems(
    List<BatchConvertQueueItem> items, {
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
    BatchConvertNotice? notice,
    bool clearNotice = false,
  }) {
    final LyricsFormat effectiveTargetFormat =
        targetFormat ?? state.targetFormat;
    final String? effectiveSaveRootPath = clearSaveRootPath
        ? null
        : (saveRootPath ?? state.saveRootPath);
    final List<BatchConvertQueueItem> plannedItems = <BatchConvertQueueItem>[
      for (final BatchConvertQueueItem item in items)
        item.copyWith(
          targetPath: _resolveBatchConvertTargetPath(
            sourcePath: item.sourcePath,
            targetFormat: effectiveTargetFormat,
            saveRootPath: effectiveSaveRootPath,
          ),
        ),
    ];
    _queueRuntime.replaceAll(plannedItems);
    final String? selectedItemId = state.selectedItemId;
    final bool keepSelectedItem =
        selectedItemId != null &&
        plannedItems.any(
          (BatchConvertQueueItem item) => item.id == selectedItemId,
        );
    state = state.copyWith(
      queueItems: plannedItems,
      targetFormat: targetFormat,
      saveRootPath: saveRootPath,
      clearSaveRootPath: clearSaveRootPath,
      recursive: recursive,
      taskPhase: taskPhase,
      progressCurrent: progressCurrent,
      progressTotal: progressTotal,
      progressMessage: progressMessage,
      errorMessage: errorMessage,
      clearErrorMessage: clearErrorMessage,
      runSummary: runSummary,
      clearRunSummary: clearRunSummary,
      clearSelectedItemId: !keepSelectedItem,
      notice: notice,
      clearNotice: clearNotice,
    );
  }

  void _syncQueueSnapshotToState() {
    state = state.copyWith(queueItems: _queueItems);
  }

  Future<BatchConvertOverwriteSummary> _inspectOverwriteSummary(
    List<BatchConvertQueueItem> items,
  ) async {
    final Map<String, int> targetCounts = <String, int>{};
    for (final BatchConvertQueueItem item in items) {
      final String key = _pathKey(item.targetPath);
      targetCounts[key] = (targetCounts[key] ?? 0) + 1;
    }
    int sourceOverwriteCount = 0;
    int existingTargetCount = 0;
    final Set<String> duplicateTargetKeys = <String>{};
    final List<String> samplePaths = <String>[];

    for (final BatchConvertQueueItem item in items) {
      final String targetKey = _pathKey(item.targetPath);
      final bool sameAsSource = _samePath(item.sourcePath, item.targetPath);
      if (sameAsSource) {
        sourceOverwriteCount += 1;
        _addSamplePath(samplePaths, item.targetPath);
      } else {
        // 覆盖确认会遍历整条队列，异步 exists 可避免大批量路径检查阻塞页面。
        // ignore: avoid_slow_async_io
        if (await File(item.targetPath).exists()) {
          existingTargetCount += 1;
          _addSamplePath(samplePaths, item.targetPath);
        }
      }
      if ((targetCounts[targetKey] ?? 0) > 1) {
        duplicateTargetKeys.add(targetKey);
        _addSamplePath(samplePaths, item.targetPath);
      }
    }
    return BatchConvertOverwriteSummary(
      sourceOverwriteCount: sourceOverwriteCount,
      existingTargetCount: existingTargetCount,
      duplicateTargetGroupCount: duplicateTargetKeys.length,
      samplePaths: List<String>.unmodifiable(samplePaths),
    );
  }

  void _addSamplePath(List<String> paths, String value) {
    if (paths.length >= 5 || paths.contains(value)) {
      return;
    }
    paths.add(value);
  }

  String _pathKey(String value) {
    final String normalized = p.normalize(p.absolute(value));
    if (Platform.isWindows) {
      return normalized.toLowerCase();
    }
    return normalized;
  }

  bool _samePath(String left, String right) =>
      _pathKey(left) == _pathKey(right);

  String _resolveBatchConvertTargetPath({
    required String sourcePath,
    required LyricsFormat targetFormat,
    required String? saveRootPath,
  }) {
    return LyricsSavePlanner.planBatchConvert(
      sourcePath: sourcePath,
      targetFormat: targetFormat,
      saveRootPath: saveRootPath,
    ).displayPath;
  }

  BatchConvertQueueItem? _findItem(String itemId) {
    for (final BatchConvertQueueItem item in _queueItems) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  String? _resolveInitialDirectory() {
    final String? saveRootPath = state.saveRootPath?.trim();
    if (saveRootPath != null && saveRootPath.isNotEmpty) {
      return saveRootPath;
    }
    if (_queueItems.isEmpty) {
      return null;
    }
    return p.dirname(_queueItems.first.sourcePath);
  }

  bool _isCurrentTask(int generation) => _taskEpoch.isCurrent(generation);

  void _setPageError(String message) {
    state = state.copyWith(
      taskPhase: BatchConvertTaskPhase.completed,
      errorMessage: message,
      progressMessage: const BatchConvertProgressMessage.empty(),
    );
    _emitNotice(
      BatchConvertNoticeCode.pageError,
      PageNoticeSeverity.error,
      detail: message,
    );
  }

  void _emitNotice(
    BatchConvertNoticeCode code,
    PageNoticeSeverity severity, {
    String? detail,
    int? count,
    int? successCount,
    int? failureCount,
  }) {
    _noticeId += 1;
    state = state.copyWith(
      notice: BatchConvertNotice(
        id: _noticeId,
        severity: severity,
        code: code,
        detail: detail,
        count: count,
        successCount: successCount,
        failureCount: failureCount,
      ),
    );
  }
}
