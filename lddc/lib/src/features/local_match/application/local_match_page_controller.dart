import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/capability/capability.dart';
import '../../../core/config/config.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'local_match_dependencies.dart';
import 'local_match_execution_coordinator.dart';
import 'local_match_input_coordinator.dart';
import 'local_match_input_picker.dart';
import 'local_match_page_state.dart';
import 'local_match_preview_save_coordinator.dart';
import 'local_match_run_validator.dart';

final NotifierProvider<LocalMatchPageController, LocalMatchPageState>
localMatchPageControllerProvider =
    NotifierProvider<LocalMatchPageController, LocalMatchPageState>(
      LocalMatchPageController.new,
      // controller 依赖局部注入的门面；声明 dependencies 后，Riverpod 才会在
      // app 组合层的子 ProviderScope 内创建独立实例，避免读到父容器的
      // fail-fast 默认实现。
      dependencies: [localMatchDependenciesProvider],
    );

/// 本地匹配页面控制器。
///
/// 这个 controller 同时管理桌面文件路径、Android SAF 树目录、队列选择状态和
/// 长任务进度。任务通道与预览通道分别使用异步代际守卫保护：页面销毁、用户
/// 取消或新任务启动后，旧任务的迟到回调不能再写入 UI state。
class LocalMatchPageController extends Notifier<LocalMatchPageState> {
  static const int _recentErrorLimit = 20;
  static const int _previewChunkSize = 100;
  static const String _taskEpochKey = 'task';
  static const String _previewEpochKey = 'preview';

  int _noticeId = 0;
  final OperationEpochGroup _epochs = OperationEpochGroup();
  LocalMatchCancellationToken? _activeCancellationToken;
  AndroidSafLocalMatchBatchCheckpoint? _androidBatchCheckpoint;
  LocalMatchInputPicker? _inputPickerCache;
  LocalMatchInputCoordinator? _inputCoordinatorCache;
  LocalMatchExecutionCoordinator? _executionCoordinatorCache;
  static const LocalMatchPreviewSaveCoordinator _previewSaveCoordinator =
      LocalMatchPreviewSaveCoordinator();
  final TaskQueueRuntime<LocalMatchQueueItem> _queueRuntime =
      TaskQueueRuntime<LocalMatchQueueItem>(
        idOf: (LocalMatchQueueItem item) => item.id,
      );

  LocalMatchDependencies get _dependencies =>
      ref.read(localMatchDependenciesProvider);

  LocalMatchInputPicker get _inputPicker {
    final LocalMatchInputPicker cached =
        _inputPickerCache ?? _dependencies.inputPicker;
    _inputPickerCache = cached;
    return cached;
  }

  AppConfig get _config => _dependencies.configRepository.current;

  AppCapability get _capability => _dependencies.capability;

  LocalMatchInputCoordinator get _inputCoordinator {
    return _inputCoordinatorCache ??= LocalMatchInputCoordinator(
      songInfoResolver: DroppedSongInfoResolver(mediaGateway: _mediaGateway),
    );
  }

  LocalMatchExecutionCoordinator get _executionCoordinator {
    return _executionCoordinatorCache ??= LocalMatchExecutionCoordinator(
      desktopGetInfosUseCase: _dependencies.desktopGetInfosUseCase,
      androidGetInfosUseCase: _dependencies.androidGetInfosUseCase,
      desktopMatchUseCase: _dependencies.localMatchUseCase,
      androidBatchUseCase: _dependencies.androidBatchUseCase,
    );
  }

  AppPathOpener get _pathOpener => _dependencies.pathOpener;
  LocalMatchMediaGateway get _mediaGateway => _dependencies.mediaGateway;

  ValueListenable<List<String>> get queueOrderListenable =>
      _queueRuntime.orderListenable;

  TaskQueueBinding<LocalMatchQueueItem>? queueBinding(String itemId) =>
      _queueRuntime.binding(itemId);

  LocalMatchPageState get currentState => state;

  LocalMatchPreviewOptions get _previewOptions {
    final AndroidSafTreeToken? tree = state.androidTreeToken;
    return LocalMatchPreviewOptions(
      saveMode: state.saveMode,
      fileNameMode: state.fileNameMode,
      saveToTagMode: state.saveToTagMode,
      lyricsFormat: state.lyricsFormat,
      fileNameFormat: _config.lyrics.fileNameFormat,
      selectedLangs: state.selectedLangs,
      saveRootPath: state.saveRootPath,
      androidTreeLabel: tree?.displayName ?? tree?.uri ?? '',
    );
  }

  List<LocalMatchQueueItem> get queueSnapshot => _queueItems;

  List<LocalMatchQueueItem> get _queueItems => _queueRuntime.snapshot;

  @override
  LocalMatchPageState build() {
    ref.onDispose(() {
      // provider 销毁时让所有 await 后返回的旧任务失效，并通知 use case 尽快停止。
      // `IndexedStack` 会延长页面生命周期，但测试容器、应用退出或 provider override
      // 仍可能触发 dispose，所以这里仍是最后一道泄漏保护。
      _epochs.invalidateAll();
      _activeCancellationToken?.cancel();
      _activeCancellationToken = null;
      _androidBatchCheckpoint = null;
      _queueRuntime.dispose();
    });
    return LocalMatchPageState.initial(
      defaultSources: _defaultSources(),
      defaultSaveRootPath: _config.storage.defaultSavePath,
      // Android 必须在选择目录前进入 SAF 模式，否则 UI 只渲染桌面路径按钮，
      // 而切换到 androidTree 的唯一入口又依赖已经完成的目录选择，形成死锁。
      inputMode: _initialInputMode,
    );
  }

  LocalMatchInputMode get _initialInputMode =>
      _dependencies.capability.androidSafTreeAccess
      ? LocalMatchInputMode.androidTree
      : LocalMatchInputMode.desktopPaths;

  void dismissNotice([int? id]) {
    if (id != null && state.notice?.id != id) {
      return;
    }
    state = state.copyWith(clearNotice: true);
  }

  void updateSelectedLangs(Set<String> langs) {
    state = state.copyWith(selectedLangs: langs.toList(growable: false));
    unawaited(_refreshQueuePreviews());
  }

  void toggleSource(Source source) {
    if (!_availableSources.contains(source) || state.isBusy) {
      return;
    }
    final List<Source> next = <Source>[...state.selectedSources];
    if (!next.remove(source)) {
      next.add(source);
    }
    next.sort(_compareSourceOrder);
    state = state.copyWith(selectedSources: next);
  }

  void updateSaveMode(LocalMatchSaveMode saveMode) {
    if (!state.isDesktopMode || state.isBusy) {
      return;
    }
    state = state.copyWith(saveMode: saveMode);
    unawaited(_refreshQueuePreviews());
  }

  void updateFileNameMode(LocalMatchFileNameMode fileNameMode) {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(fileNameMode: fileNameMode);
    unawaited(_refreshQueuePreviews());
  }

  void updateSaveToTagMode(LocalMatchSaveToTagMode saveToTagMode) {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(saveToTagMode: saveToTagMode);
    unawaited(_refreshQueuePreviews());
  }

  void updateLyricsFormat(LyricsFormat lyricsFormat) {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(lyricsFormat: lyricsFormat);
    unawaited(_refreshQueuePreviews());
  }

  void updateMinScore(double minScore) {
    state = state.copyWith(minScore: minScore.clamp(0, 100).toDouble());
  }

  void updateSkipExistingLyrics(bool value) {
    state = state.copyWith(skipExistingLyrics: value);
  }

  void focusItem(String itemId) {
    if (!_containsItem(itemId)) {
      return;
    }
    state = state.copyWith(focusedItemId: itemId);
    _syncQueuePresentation();
  }

  void selectOnlyItem(String itemId) {
    if (!_containsItem(itemId)) {
      return;
    }
    state = state.copyWith(
      focusedItemId: itemId,
      isSelectionMode: false,
      selectedItemIds: const <String>{},
    );
    _syncQueuePresentation();
  }

  void toggleSelectionMode() {
    final bool nextValue = !state.isSelectionMode;
    state = state.copyWith(
      isSelectionMode: nextValue,
      selectedItemIds: nextValue ? state.selectedItemIds : const <String>{},
    );
    _syncQueuePresentation();
  }

  void enterSelectionMode([String? itemId]) {
    final Set<String> next = <String>{...state.selectedItemIds};
    if (itemId != null && _containsItem(itemId)) {
      next.add(itemId);
    }
    state = state.copyWith(
      focusedItemId: itemId ?? state.focusedItemId,
      isSelectionMode: true,
      selectedItemIds: next,
    );
    _syncQueuePresentation();
  }

  void exitSelectionMode() {
    state = state.copyWith(
      isSelectionMode: false,
      selectedItemIds: const <String>{},
    );
    _syncQueuePresentation();
  }

  void toggleSelectAll() {
    if (_queueItems.isEmpty) {
      return;
    }
    final bool selectAll = state.selectedItemIds.length != _queueItems.length;
    state = state.copyWith(
      isSelectionMode: true,
      selectedItemIds: selectAll
          ? _queueItems.map((LocalMatchQueueItem item) => item.id).toSet()
          : const <String>{},
    );
    _syncQueuePresentation();
  }

  void toggleItemSelected(String itemId) {
    if (!_containsItem(itemId)) {
      return;
    }
    final Set<String> next = <String>{...state.selectedItemIds};
    if (!next.remove(itemId)) {
      next.add(itemId);
    }
    state = state.copyWith(
      focusedItemId: itemId,
      isSelectionMode: next.isNotEmpty || state.isSelectionMode,
      selectedItemIds: next,
    );
    _syncQueuePresentation();
  }

  Future<void> addSongFiles() async {
    if (state.isBusy) {
      _emitNotice(
        LocalMatchNoticeCode.busyImportFiles,
        PageNoticeSeverity.warning,
      );
      return;
    }
    try {
      final List<PickedFileHandle> files = await _inputPicker.pickSongFiles(
        initialDirectory: _resolveInitialDirectory(),
      );
      if (files.isEmpty) {
        return;
      }
      final List<String> inputPaths = files
          .map((PickedFileHandle file) => file.path?.trim() ?? '')
          .where((String path) => path.isNotEmpty)
          .toList(growable: false);
      if (inputPaths.isEmpty) {
        _emitNotice(
          LocalMatchNoticeCode.selectedFilesUnavailable,
          PageNoticeSeverity.warning,
        );
        return;
      }
      await _scanDesktopInputs(inputPaths);
    } on UnsupportedError catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.importFilesFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> addSongDirectories() async {
    if (state.isBusy) {
      _emitNotice(
        LocalMatchNoticeCode.busyImportDirectories,
        PageNoticeSeverity.warning,
      );
      return;
    }
    try {
      final List<String> directories = await _inputPicker.pickSongDirectories(
        initialDirectory: _resolveInitialDirectory(),
      );
      if (directories.isEmpty) {
        return;
      }
      await _scanDesktopInputs(directories);
    } on UnsupportedError catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.importDirectoriesFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> importExternalDesktopPaths(List<String> inputPaths) async {
    if (state.isBusy) {
      _emitNotice(
        LocalMatchNoticeCode.busyImportFiles,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final List<String> normalized = _inputCoordinator.normalizePaths(
      inputPaths,
    );
    if (normalized.isEmpty) {
      _emitNotice(
        LocalMatchNoticeCode.droppedNoAccessibleFiles,
        PageNoticeSeverity.warning,
      );
      return;
    }
    await _scanDesktopInputs(normalized);
  }

  Future<void> importExternalDesktopItems(
    List<DragDropItemDescriptor> items,
  ) async {
    if (state.isBusy) {
      _emitNotice(
        LocalMatchNoticeCode.busyImportFiles,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final int generation = _epochs.next(_taskEpochKey);
    final LocalMatchResolvedInputs resolved = await _inputCoordinator
        .resolveDroppedItems(
          items: items,
          // 解析 CUE/标签可能跨多个 await；每个条目之间检查 task epoch，避免
          // 已换代的导入继续消耗 IO，最终状态仍只由 controller 发布。
          shouldContinue: () => _isCurrentTask(generation),
        );
    if (resolved.cancelled || !_isCurrentTask(generation)) {
      return;
    }
    if (resolved.paths.isNotEmpty) {
      await _scanDesktopInputs(
        resolved.paths,
        initialEntries: resolved.entries,
        initialErrors: resolved.errors,
      );
      return;
    }
    if (resolved.entries.isEmpty) {
      _emitNotice(
        resolved.errors.isNotEmpty
            ? LocalMatchNoticeCode.droppedSongResolveFailed
            : LocalMatchNoticeCode.droppedNoAccessibleFiles,
        PageNoticeSeverity.warning,
        detail: resolved.errors.isNotEmpty ? resolved.errors.first : null,
      );
      if (resolved.errors.length > 1) {
        _appendRecentErrors(resolved.errors);
      }
      return;
    }
    _setQueueItems(_mergeDesktopEntries(resolved.entries));
    state = state.copyWith(
      taskPhase: LocalMatchTaskPhase.completed,
      progressCurrent: _queueItems.length,
      progressTotal: _queueItems.length,
      progressMessage: const LocalMatchProgressMessage(
        code: LocalMatchProgressMessageCode.importCompleted,
      ),
    );
    if (resolved.errors.isNotEmpty) {
      _appendRecentErrors(resolved.errors);
      _emitNotice(
        LocalMatchNoticeCode.importCompletedWithErrors,
        PageNoticeSeverity.warning,
      );
    }
    await _refreshQueuePreviews();
  }

  Future<void> selectAndroidTree() async {
    if (!_capability.androidSafTreeAccess) {
      _emitNotice(
        LocalMatchNoticeCode.safTreeUnsupported,
        PageNoticeSeverity.warning,
      );
      return;
    }
    if (state.isBusy) {
      _emitNotice(
        LocalMatchNoticeCode.busySwitchTree,
        PageNoticeSeverity.warning,
      );
      return;
    }
    try {
      final AndroidSafTreeToken? tree = await _inputPicker.pickAndroidTree(
        initialUri: state.androidTreeToken?.uri,
      );
      if (tree == null) {
        return;
      }
      await _scanAndroidTree(tree);
    } on UnsupportedError catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.selectTreeFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> selectSaveRootDirectory() async {
    if (!state.isDesktopMode || state.isBusy) {
      return;
    }
    try {
      final String? directory = await _inputPicker.pickSaveRootDirectory(
        initialDirectory: state.saveRootPath ?? _resolveInitialDirectory(),
      );
      if (directory == null || directory.trim().isEmpty) {
        return;
      }
      state = state.copyWith(saveRootPath: directory.trim());
      await _refreshQueuePreviews();
    } on UnsupportedError catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.selectSaveRootFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> clearQueue() async {
    if (state.isBusy) {
      _emitNotice(
        LocalMatchNoticeCode.busyClearQueue,
        PageNoticeSeverity.warning,
      );
      return;
    }
    _epochs.invalidate(_taskEpochKey);
    _epochs.invalidate(_previewEpochKey);
    _activeCancellationToken = null;
    _androidBatchCheckpoint = null;
    _queueRuntime.replaceAll(const <LocalMatchQueueItem>[]);
    state = LocalMatchPageState.initial(
      defaultSources: _defaultSources(),
      defaultSaveRootPath: _config.storage.defaultSavePath,
      // 清空队列应回到当前平台的空状态，不能把 Android 再切回不可操作的桌面模式。
      inputMode: _initialInputMode,
    );
  }

  Future<void> removeSelectedItems() async {
    if (!state.isDesktopMode || state.isBusy) {
      return;
    }
    final Set<String> selectedIds = state.selectedItemIds;
    if (selectedIds.isEmpty) {
      _emitNotice(
        LocalMatchNoticeCode.selectItemsToDelete,
        PageNoticeSeverity.info,
      );
      return;
    }
    _setQueueItems(
      _queueItems
          .where((LocalMatchQueueItem item) => !selectedIds.contains(item.id))
          .toList(growable: false),
      isSelectionMode: false,
      selectedItemIds: const <String>{},
    );
  }

  Future<void> setRootPathForSelected() async {
    if (!state.isDesktopMode || state.isBusy) {
      return;
    }
    final List<LocalMatchQueueItem> selectedItems = _selectedDesktopItems();
    if (selectedItems.isEmpty) {
      _emitNotice(
        LocalMatchNoticeCode.selectItemsToSetRoot,
        PageNoticeSeverity.info,
      );
      return;
    }
    try {
      final String? directory = await _inputPicker.pickSaveRootDirectory(
        initialDirectory: _preferredRootDirectory(selectedItems),
      );
      if (directory == null || directory.trim().isEmpty) {
        return;
      }
      final String normalizedRoot = p.normalize(directory.trim());
      final List<String> skippedPaths = <String>[];
      final List<LocalMatchQueueItem> nextItems = <LocalMatchQueueItem>[
        for (final LocalMatchQueueItem item in _queueItems)
          if (!state.selectedItemIds.contains(item.id))
            item
          else
            _replaceSongRootPath(
              item,
              normalizedRoot,
              skippedPaths: skippedPaths,
            ),
      ];
      _setQueueItems(nextItems);
      await _refreshQueuePreviews();
      if (skippedPaths.isNotEmpty) {
        _emitNotice(
          LocalMatchNoticeCode.selectedRootSkippedSongs,
          PageNoticeSeverity.warning,
          detail: skippedPaths.take(3).join('；'),
        );
      }
    } on UnsupportedError catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.setRootFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> restoreDefaultRootPathForSelected() async {
    if (!state.isDesktopMode || state.isBusy) {
      return;
    }
    final Set<String> selectedIds = state.selectedItemIds;
    if (selectedIds.isEmpty) {
      _emitNotice(
        LocalMatchNoticeCode.selectItemsToRestore,
        PageNoticeSeverity.info,
      );
      return;
    }
    _setQueueItems(<LocalMatchQueueItem>[
      for (final LocalMatchQueueItem item in _queueItems)
        selectedIds.contains(item.id)
            ? item.copyWith(songRootPath: item.defaultRootPath)
            : item,
    ]);
    await _refreshQueuePreviews();
  }

  Future<void> startOrCancel() async {
    if (state.isBusy) {
      // 忙碌态再次点击是“请求取消”，真正停止由 use case 在下一个取消检查点完成。
      // 这样可以避免同步打断文件写入或 SAF fd 关闭流程。
      _activeCancellationToken?.cancel();
      state = state.copyWith(
        progressMessage: const LocalMatchProgressMessage(
          code: LocalMatchProgressMessageCode.cancelling,
        ),
      );
      _emitNotice(LocalMatchNoticeCode.cancelling, PageNoticeSeverity.info);
      return;
    }
    final List<LocalMatchRunValidationIssue> validationIssues =
        _validateBeforeRun();
    if (validationIssues.isNotEmpty) {
      _emitNotice(
        LocalMatchNoticeCode.validationFailed,
        PageNoticeSeverity.warning,
        validationIssues: validationIssues,
      );
      return;
    }
    await _runMatch();
  }

  Future<void> openSongDirectory(String itemId) async {
    final LocalMatchQueueItem? item = _findItem(itemId);
    final String? songPath = item?.songInfo.path;
    if (item == null ||
        songPath == null ||
        songPath.trim().isEmpty ||
        songPath.startsWith('content://')) {
      _emitNotice(
        LocalMatchNoticeCode.songDirectoryUnavailable,
        PageNoticeSeverity.info,
      );
      return;
    }
    try {
      await _pathOpener.openDirectory(p.dirname(songPath));
    } on UnsupportedError catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.openSongDirectoryFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> openSaveDirectory(String itemId) async {
    final LocalMatchQueueItem? item = _findItem(itemId);
    final String? outputPath = item?.outputPath;
    if (item == null || outputPath == null || outputPath.trim().isEmpty) {
      _emitNotice(
        LocalMatchNoticeCode.saveDirectoryUnavailable,
        PageNoticeSeverity.info,
      );
      return;
    }
    try {
      await _pathOpener.openDirectory(
        outputPath.startsWith('content://')
            ? outputPath
            : p.dirname(outputPath),
      );
    } on UnsupportedError catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.openSaveDirectoryFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> openLyricsFile(String itemId) async {
    final LocalMatchQueueItem? item = _findItem(itemId);
    final String? outputPath = item?.outputPath;
    if (item == null || outputPath == null || outputPath.trim().isEmpty) {
      _emitNotice(
        LocalMatchNoticeCode.lyricsFileUnavailable,
        PageNoticeSeverity.info,
      );
      return;
    }
    try {
      await _pathOpener.openFile(outputPath);
    } on UnsupportedError catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.unsupportedOperation,
        PageNoticeSeverity.warning,
        detail: error.message ?? error.toString(),
      );
    } on Exception catch (error) {
      _emitNotice(
        LocalMatchNoticeCode.openLyricsFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
    }
  }

  Future<void> openInSearch(String itemId) async {
    final LocalMatchQueueItem? item = _findItem(itemId);
    if (item == null) {
      return;
    }
    await _dependencies.openInSearch(item.songInfo, state.selectedSources);
  }

  Future<void> _scanDesktopInputs(
    List<String> inputPaths, {
    List<LocalMatchSongEntry> initialEntries = const <LocalMatchSongEntry>[],
    List<String> initialErrors = const <String>[],
  }) async {
    // 每次扫描都提升 generation，旧扫描的进度回调即使晚到，也只能被丢弃。
    // 这比只检查 mounted 更严格，因为 controller 可能仍存活但任务已经换代。
    final int generation = _epochs.next(_taskEpochKey);
    final LocalMatchCancellationToken token = _replaceCancellationToken();
    state = state.copyWith(
      inputMode: LocalMatchInputMode.desktopPaths,
      clearAndroidTreeToken: true,
      taskPhase: LocalMatchTaskPhase.scanning,
      progressCurrent: 0,
      progressTotal: 0,
      progressMessage: const LocalMatchProgressMessage(
        code: LocalMatchProgressMessageCode.scanningFiles,
      ),
      successCount: 0,
      skipCount: 0,
      failCount: 0,
      clearNotice: true,
    );
    try {
      final LocalMatchDesktopScanOutcome outcome = await _executionCoordinator
          .scanDesktop(
            inputPaths: inputPaths,
            cancellationToken: token,
            onProgress: (LocalMatchGetInfosProgress progress) {
              // 取消后，底层扫描可能还会在当前文件解析完成后吐出迟到进度；
              // 此时保持取消反馈，避免 UI 又跳回“正在扫描”。
              if (!_isCurrentTask(generation) || token.isCancelled) {
                return;
              }
              state = state.copyWith(
                taskPhase: LocalMatchTaskPhase.scanning,
                progressCurrent: progress.value,
                progressTotal: progress.maxValue,
                progressMessage: LocalMatchProgressMessage.external(
                  progress.text,
                ),
              );
            },
          );
      if (!_isCurrentTask(generation)) {
        return;
      }
      _setQueueItems(
        _mergeDesktopEntries(<LocalMatchSongEntry>[
          ...initialEntries,
          ...outcome.entries,
        ]),
      );
      state = state.copyWith(
        taskPhase: LocalMatchTaskPhase.completed,
        progressCurrent: _queueItems.length,
        progressTotal: _queueItems.length,
        progressMessage: LocalMatchProgressMessage(
          code: outcome.result.cancelled
              ? LocalMatchProgressMessageCode.scanCancelled
              : LocalMatchProgressMessageCode.scanCompleted,
        ),
      );
      final List<String> mergedErrors = <String>[
        ...initialErrors,
        ...outcome.result.errors,
      ];
      if (mergedErrors.isNotEmpty) {
        _appendRecentErrors(mergedErrors);
      }
      await _refreshQueuePreviews();
      if (outcome.result.cancelled) {
        _emitNotice(
          LocalMatchNoticeCode.scanCancelled,
          PageNoticeSeverity.info,
        );
      } else if (mergedErrors.isNotEmpty) {
        _emitNotice(
          LocalMatchNoticeCode.scanCompletedWithErrors,
          PageNoticeSeverity.warning,
        );
      }
    } on Exception catch (error) {
      if (_isCurrentTask(generation)) {
        state = state.copyWith(
          taskPhase: LocalMatchTaskPhase.completed,
          progressMessage: const LocalMatchProgressMessage(
            code: LocalMatchProgressMessageCode.scanFailed,
          ),
        );
        _appendRecentErrors(<String>['桌面扫描失败：$error']);
        _emitNotice(
          LocalMatchNoticeCode.scanFailed,
          PageNoticeSeverity.error,
          detail: error.toString(),
        );
      }
    } finally {
      if (_isCurrentTask(generation)) {
        _activeCancellationToken = null;
      }
    }
  }

  Future<void> _scanAndroidTree(AndroidSafTreeToken tree) async {
    final int generation = _epochs.next(_taskEpochKey);
    final LocalMatchCancellationToken token = _replaceCancellationToken();
    _androidBatchCheckpoint = null;
    _queueRuntime.replaceAll(const <LocalMatchQueueItem>[]);
    state = state.copyWith(
      inputMode: LocalMatchInputMode.androidTree,
      androidTreeToken: tree,
      queueItems: const <LocalMatchQueueItem>[],
      focusedItemId: null,
      selectedItemIds: const <String>{},
      isSelectionMode: false,
      taskPhase: LocalMatchTaskPhase.scanning,
      progressCurrent: 0,
      progressTotal: 0,
      progressMessage: const LocalMatchProgressMessage(
        code: LocalMatchProgressMessageCode.scanningFiles,
      ),
      successCount: 0,
      skipCount: 0,
      failCount: 0,
      recentErrors: const <String>[],
      clearNotice: true,
    );
    try {
      final LocalMatchAndroidScanOutcome outcome = await _executionCoordinator
          .scanAndroid(
            rootTree: tree,
            cancellationToken: token,
            onProgress: (LocalMatchGetInfosProgress progress) {
              // SAF 扫描同样可能在取消后完成一个 chunk；旧 progress 不应覆盖取消反馈。
              if (!_isCurrentTask(generation) || token.isCancelled) {
                return;
              }
              state = state.copyWith(
                taskPhase: LocalMatchTaskPhase.scanning,
                progressCurrent: progress.value,
                progressTotal: progress.maxValue,
                progressMessage: LocalMatchProgressMessage.external(
                  progress.text,
                ),
              );
            },
          );
      if (!_isCurrentTask(generation)) {
        return;
      }
      _setQueueItems(
        outcome.entries.map(_buildAndroidQueueItem).toList(growable: false),
      );
      state = state.copyWith(
        taskPhase: LocalMatchTaskPhase.completed,
        progressCurrent: _queueItems.length,
        progressTotal: _queueItems.length,
        progressMessage: LocalMatchProgressMessage(
          code: outcome.result.cancelled
              ? LocalMatchProgressMessageCode.scanCancelled
              : LocalMatchProgressMessageCode.scanCompleted,
        ),
      );
      if (outcome.result.errors.isNotEmpty) {
        _appendRecentErrors(outcome.result.errors);
      }
      if (outcome.result.cancelled) {
        if (outcome.result.checkpoint != null) {
          _androidBatchCheckpoint = AndroidSafLocalMatchBatchCheckpoint(
            rootTreeUri: tree.uri,
            stage: AndroidSafLocalMatchBatchStage.scanning,
            scanCheckpoint: outcome.result.checkpoint,
            entries: outcome.entries,
            scanErrors: outcome.result.errors,
            nextMatchIndex: 0,
            successCount: 0,
            skipCount: 0,
            statuses: const <LocalMatchingStatus>[],
          );
        }
        _emitNotice(
          LocalMatchNoticeCode.scanCancelled,
          PageNoticeSeverity.info,
        );
      } else if (outcome.result.errors.isNotEmpty) {
        _emitNotice(
          LocalMatchNoticeCode.scanCompletedWithErrors,
          PageNoticeSeverity.warning,
        );
      }
    } on Exception catch (error) {
      if (_isCurrentTask(generation)) {
        state = state.copyWith(
          taskPhase: LocalMatchTaskPhase.completed,
          progressMessage: const LocalMatchProgressMessage(
            code: LocalMatchProgressMessageCode.scanFailed,
          ),
        );
        _appendRecentErrors(<String>['目录树扫描失败：$error']);
        _emitNotice(
          LocalMatchNoticeCode.treeScanFailed,
          PageNoticeSeverity.error,
          detail: error.toString(),
        );
      }
    } finally {
      if (_isCurrentTask(generation)) {
        _activeCancellationToken = null;
      }
    }
  }

  Future<void> _runMatch() async {
    if (state.isAndroidMode) {
      await _runAndroidBatchMatch();
      return;
    }
    final int generation = _epochs.next(_taskEpochKey);
    final LocalMatchCancellationToken token = _replaceCancellationToken();
    _resetQueueStatuses();
    state = state.copyWith(
      taskPhase: LocalMatchTaskPhase.matching,
      progressCurrent: 0,
      progressTotal: _queueItems.length,
      progressMessage: const LocalMatchProgressMessage.none(),
      successCount: 0,
      skipCount: 0,
      failCount: 0,
      clearNotice: true,
    );
    try {
      final LocalMatchResult result = await _executionCoordinator.runDesktop(
        entries: _queueItems
            .map(
              (LocalMatchQueueItem item) => LocalMatchSongEntry(
                songInfo: item.songInfo,
                rootPath: item.songRootPath,
              ),
            )
            .toList(growable: false),
        options: _buildRunOptions(),
        cancellationToken: token,
        lyricsPersistencePort: _buildLyricsPersistencePort(),
        onProgress: (LocalMatchProgress progress) {
          // 匹配取消后可能仍等待当前网络、转换或保存检查点返回；
          // 迟到 progress 只属于被取消的执行链，不再刷新当前页面进度。
          if (!_isCurrentTask(generation) || token.isCancelled) {
            return;
          }
          if (progress.status != null) {
            _applyStatus(progress.status!);
          }
          state = state.copyWith(
            taskPhase: progress.status == null
                ? LocalMatchTaskPhase.matching
                : LocalMatchTaskPhase.writing,
            progressCurrent: progress.value,
            progressTotal: progress.maxValue,
            progressMessage: LocalMatchProgressMessage.external(progress.text),
          );
        },
      );
      if (!_isCurrentTask(generation)) {
        return;
      }
      _syncQueueSnapshotToState();
      state = state.copyWith(
        taskPhase: LocalMatchTaskPhase.completed,
        progressCurrent: result.total,
        progressTotal: result.total,
        progressMessage: LocalMatchProgressMessage(
          code: result.cancelled
              ? LocalMatchProgressMessageCode.matchingCancelled
              : LocalMatchProgressMessageCode.matchingCompleted,
        ),
        successCount: result.successCount,
        skipCount: result.skipCount,
        failCount: result.failCount,
      );
      if (result.cancelled) {
        _emitNotice(
          LocalMatchNoticeCode.matchCancelled,
          PageNoticeSeverity.info,
        );
      } else {
        _emitNotice(
          LocalMatchNoticeCode.matchCompleted,
          PageNoticeSeverity.success,
          totalCount: result.total,
          successCount: result.successCount,
          failCount: result.failCount,
          skipCount: result.skipCount,
        );
      }
    } on Exception catch (error) {
      if (_isCurrentTask(generation)) {
        _syncQueueSnapshotToState();
        state = state.copyWith(
          taskPhase: LocalMatchTaskPhase.completed,
          progressMessage: const LocalMatchProgressMessage(
            code: LocalMatchProgressMessageCode.matchingFailed,
          ),
        );
        _appendRecentErrors(<String>['本地匹配执行失败：$error']);
        _emitNotice(
          LocalMatchNoticeCode.matchFailed,
          PageNoticeSeverity.error,
          detail: error.toString(),
        );
      }
    } finally {
      if (_isCurrentTask(generation)) {
        _activeCancellationToken = null;
      }
    }
  }

  Future<void> _runAndroidBatchMatch() async {
    final AndroidSafTreeToken? tree = state.androidTreeToken;
    if (tree == null) {
      _emitNotice(
        LocalMatchNoticeCode.missingAndroidTree,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final int generation = _epochs.next(_taskEpochKey);
    final LocalMatchCancellationToken token = _replaceCancellationToken();
    final AndroidSafLocalMatchBatchCheckpoint checkpoint =
        _androidBatchCheckpoint ?? _buildAndroidBatchCheckpoint(tree);
    if (_androidBatchCheckpoint == null) {
      _resetQueueStatuses();
    }
    state = state.copyWith(
      taskPhase: LocalMatchTaskPhase.matching,
      progressCurrent: checkpoint.nextMatchIndex,
      progressTotal: checkpoint.entries.length,
      progressMessage: const LocalMatchProgressMessage(
        code: LocalMatchProgressMessageCode.preparingMatch,
      ),
      successCount: checkpoint.successCount,
      skipCount: checkpoint.skipCount,
      failCount: 0,
      clearNotice: true,
    );
    _applyStatusSnapshot(checkpoint.statuses);
    try {
      final AndroidSafLocalMatchBatchResult result = await _executionCoordinator
          .runAndroid(
            rootTree: tree,
            options: _buildRunOptions(),
            checkpoint: checkpoint,
            cancellationToken: token,
            lyricsPersistencePort: _buildLyricsPersistencePort(),
            onProgress: (AndroidSafLocalMatchBatchProgress progress) {
              // Android batch 取消后保留 checkpoint 收尾，但忽略旧 progress 文案。
              if (!_isCurrentTask(generation) || token.isCancelled) {
                return;
              }
              if (progress.status != null) {
                _applyStatus(progress.status!);
              }
              state = state.copyWith(
                taskPhase: _taskPhaseForAndroidStage(progress.stage),
                progressCurrent: progress.value,
                progressTotal: progress.maxValue,
                progressMessage: LocalMatchProgressMessage.external(
                  progress.text,
                ),
              );
            },
          );
      if (!_isCurrentTask(generation)) {
        return;
      }
      _androidBatchCheckpoint = result.checkpoint;
      if (result.entries.length != _queueItems.length) {
        _setQueueItems(
          result.entries.map(_buildAndroidQueueItem).toList(growable: false),
        );
      }
      _applyStatusSnapshot(result.statuses);
      if (result.scanErrors.isNotEmpty) {
        _appendRecentErrors(result.scanErrors);
      }
      _syncQueueSnapshotToState();
      state = state.copyWith(
        taskPhase: LocalMatchTaskPhase.completed,
        progressCurrent: result.total,
        progressTotal: result.total,
        progressMessage: LocalMatchProgressMessage(
          code: result.cancelled
              ? LocalMatchProgressMessageCode.matchingCancelled
              : LocalMatchProgressMessageCode.matchingCompleted,
        ),
        successCount: result.successCount,
        skipCount: result.skipCount,
        failCount: result.failCount,
      );
      if (result.cancelled) {
        _emitNotice(
          LocalMatchNoticeCode.androidMatchCancelledResume,
          PageNoticeSeverity.info,
        );
      } else {
        _emitNotice(
          LocalMatchNoticeCode.matchCompleted,
          result.scanErrors.isEmpty
              ? PageNoticeSeverity.success
              : PageNoticeSeverity.warning,
          totalCount: result.total,
          successCount: result.successCount,
          failCount: result.failCount,
          skipCount: result.skipCount,
        );
      }
    } on Exception catch (error) {
      if (_isCurrentTask(generation)) {
        _syncQueueSnapshotToState();
        state = state.copyWith(
          taskPhase: LocalMatchTaskPhase.completed,
          progressMessage: const LocalMatchProgressMessage(
            code: LocalMatchProgressMessageCode.matchingFailed,
          ),
        );
        _appendRecentErrors(<String>['Android SAF 本地匹配执行失败：$error']);
        _emitNotice(
          LocalMatchNoticeCode.androidMatchFailed,
          PageNoticeSeverity.error,
          detail: error.toString(),
        );
      }
    } finally {
      if (_isCurrentTask(generation)) {
        _activeCancellationToken = null;
      }
    }
  }

  Future<void> _refreshQueuePreviews() async {
    if (state.isAndroidMode) {
      final List<LocalMatchQueueItem> nextItems = <LocalMatchQueueItem>[
        for (final LocalMatchQueueItem item in _queueItems)
          _withAndroidSavePlan(item),
      ];
      _setQueueItems(nextItems);
      return;
    }
    await _refreshDesktopPreviews();
  }

  Future<void> _refreshDesktopPreviews() async {
    if (state.isAndroidMode) {
      return;
    }
    final int generation = _epochs.next(_previewEpochKey);
    final List<LocalMatchQueueItem> items = _queueItems;
    if (items.isEmpty) {
      state = state.copyWith(isRefreshingPreview: false);
      return;
    }
    state = state.copyWith(isRefreshingPreview: true);
    final List<LocalMatchQueueItem> nextItems = List<LocalMatchQueueItem>.from(
      items,
    );
    for (int start = 0; start < nextItems.length; start += _previewChunkSize) {
      final int end = start + _previewChunkSize > nextItems.length
          ? nextItems.length
          : start + _previewChunkSize;
      for (int index = start; index < end; index += 1) {
        nextItems[index] = _buildDesktopPreview(nextItems[index]);
      }
      if (end < nextItems.length) {
        await Future<void>.delayed(Duration.zero);
      }
      if (!_epochs.isCurrent(_previewEpochKey, generation) ||
          state.isAndroidMode) {
        return;
      }
    }
    _setQueueItems(nextItems);
    state = state.copyWith(isRefreshingPreview: false);
  }

  LocalMatchQueueItem _buildDesktopPreview(LocalMatchQueueItem item) {
    return _previewSaveCoordinator.buildDesktopPreview(item, _previewOptions);
  }

  LocalMatchQueueItem _buildAndroidQueueItem(LocalMatchSongEntry entry) {
    return _previewSaveCoordinator.buildAndroidQueueItem(
      entry,
      _previewOptions,
    );
  }

  LocalMatchQueueItem _withAndroidSavePlan(LocalMatchQueueItem item) {
    final LocalMatchSavePlan savePlan = _previewSaveCoordinator
        .buildAndroidSavePlan(item.songInfo, _previewOptions);
    return item.copyWith(savePlan: savePlan);
  }

  void _applyStatus(LocalMatchingStatus status) {
    if (status.index < 0 || status.index >= _queueItems.length) {
      return;
    }
    final LocalMatchQueueItem currentItem = _queueItems[status.index];
    final LocalMatchingStatus? previousStatus = currentItem.lastStatus;
    _queueRuntime.patchItem(
      currentItem.id,
      (LocalMatchQueueItem item) =>
          item.copyWith(lastStatus: status, outputPath: status.path),
    );
    final (int successCount, int skipCount, int failCount) adjustedCounts =
        _adjustCounts(
          previousStatus: previousStatus,
          nextStatus: status,
          successCount: state.successCount,
          skipCount: state.skipCount,
          failCount: state.failCount,
        );
    state = state.copyWith(
      successCount: adjustedCounts.$1,
      skipCount: adjustedCounts.$2,
      failCount: adjustedCounts.$3,
    );
  }

  void _applyStatusSnapshot(List<LocalMatchingStatus> statuses) {
    if (statuses.isEmpty) {
      return;
    }
    for (final LocalMatchingStatus status in statuses) {
      if (status.index < 0 || status.index >= _queueItems.length) {
        continue;
      }
      final LocalMatchQueueItem currentItem = _queueItems[status.index];
      _queueRuntime.patchItem(
        currentItem.id,
        (LocalMatchQueueItem item) =>
            item.copyWith(lastStatus: status, outputPath: status.path),
      );
    }
    _syncQueueSnapshotToState();
  }

  void _resetQueueStatuses() {
    _setQueueItems(<LocalMatchQueueItem>[
      for (final LocalMatchQueueItem item in _queueItems)
        item.copyWith(clearLastStatus: true, clearOutputPath: true),
    ]);
  }

  List<LocalMatchQueueItem> _mergeDesktopEntries(
    List<LocalMatchSongEntry> entries,
  ) {
    final Map<String, LocalMatchQueueItem> existingById =
        <String, LocalMatchQueueItem>{
          for (final LocalMatchQueueItem item
              in state.isDesktopMode
                  ? _queueItems
                  : const <LocalMatchQueueItem>[])
            item.id: item,
        };
    final List<LocalMatchQueueItem> nextItems = <LocalMatchQueueItem>[
      if (state.isDesktopMode) ..._queueItems,
    ];
    for (final LocalMatchSongEntry entry in entries) {
      final LocalMatchQueueItem item = LocalMatchQueueItem(
        id: _previewSaveCoordinator.buildQueueItemId(
          entry.songInfo,
          entry.rootPath,
        ),
        songInfo: entry.songInfo,
        defaultRootPath: entry.rootPath,
        songRootPath: entry.rootPath,
        savePlan: const LocalMatchSavePlan(kind: LocalMatchSavePlanKind.none),
        lastStatus: null,
        outputPath: null,
      );
      if (existingById.containsKey(item.id)) {
        continue;
      }
      existingById[item.id] = item;
      nextItems.add(item);
    }
    return nextItems;
  }

  LocalMatchQueueItem _replaceSongRootPath(
    LocalMatchQueueItem item,
    String normalizedRoot, {
    required List<String> skippedPaths,
  }) {
    final String? songPath = item.songInfo.path;
    if (songPath == null || songPath.trim().isEmpty) {
      skippedPaths.add(item.songInfo.artistTitle(replaceMissing: true));
      return item;
    }
    final String normalizedSongPath = p.normalize(songPath);
    if (!_isWithinRoot(normalizedRoot, normalizedSongPath)) {
      skippedPaths.add(normalizedSongPath);
      return item;
    }
    return item.copyWith(songRootPath: normalizedRoot);
  }

  void _setQueueItems(
    List<LocalMatchQueueItem> items, {
    bool? isSelectionMode,
    Set<String>? selectedItemIds,
  }) {
    final Set<String> itemIds = items
        .map((LocalMatchQueueItem item) => item.id)
        .toSet();
    final Set<String> resolvedSelectedIds =
        selectedItemIds ??
        state.selectedItemIds
            .where((String itemId) => itemIds.contains(itemId))
            .toSet();
    final String? resolvedFocusedId =
        items.any((LocalMatchQueueItem item) => item.id == state.focusedItemId)
        ? state.focusedItemId
        : (items.isEmpty ? null : items.first.id);
    final bool resolvedSelectionMode =
        isSelectionMode ??
        (resolvedSelectedIds.isNotEmpty && state.isSelectionMode);
    _queueRuntime.replaceAll(items);
    state = state.copyWith(
      queueItems: items,
      focusedItemId: resolvedFocusedId,
      selectedItemIds: resolvedSelectedIds,
      isSelectionMode: resolvedSelectionMode,
    );
    _syncQueuePresentation();
  }

  void _syncQueuePresentation() {
    _queueRuntime.setSelectedIds(state.selectedItemIds);
    _queueRuntime.setFocusedId(state.focusedItemId);
  }

  void _syncQueueSnapshotToState() {
    state = state.copyWith(queueItems: _queueItems);
    _syncQueuePresentation();
  }

  LocalMatchRunOptions _buildRunOptions() {
    return LocalMatchRunOptions(
      saveMode: state.isAndroidMode ? LocalMatchSaveMode.song : state.saveMode,
      fileNameMode: state.fileNameMode,
      saveToTagMode: state.saveToTagMode,
      lyricsFormat: state.lyricsFormat,
      langs: state.selectedLangs,
      minScore: state.minScore,
      sources: state.selectedSources,
      skipExistingLyrics: state.skipExistingLyrics,
      saveRootPath: state.saveRootPath,
      fileNameFormat: _config.lyrics.fileNameFormat,
      skipInstLyrics: _config.match.skipInst,
      id3Version: _config.lyrics.id3Version,
      convertOptions: _config.toLyricsConvertOptions(),
    );
  }

  LyricsSavePersistencePort? _buildLyricsPersistencePort() {
    if (!state.isAndroidMode) {
      return null;
    }
    final AndroidSafTreeToken? tree = state.androidTreeToken;
    if (tree == null) {
      return null;
    }
    return _dependencies.androidLyricsPersistenceFactory(tree);
  }

  List<LocalMatchRunValidationIssue> _validateBeforeRun() {
    final List<LocalMatchRunValidationIssue> issues = validateLocalMatchRun(
      state,
    );
    return issues;
  }

  AndroidSafLocalMatchBatchCheckpoint _buildAndroidBatchCheckpoint(
    AndroidSafTreeToken tree,
  ) {
    return AndroidSafLocalMatchBatchCheckpoint(
      rootTreeUri: tree.uri,
      stage: AndroidSafLocalMatchBatchStage.matching,
      scanCheckpoint: null,
      entries: _queueItems
          .map(
            (LocalMatchQueueItem item) => LocalMatchSongEntry(
              songInfo: item.songInfo,
              rootPath: item.songRootPath,
            ),
          )
          .toList(growable: false),
      scanErrors: const <String>[],
      nextMatchIndex: 0,
      successCount: 0,
      skipCount: 0,
      statuses: const <LocalMatchingStatus>[],
    );
  }

  LocalMatchTaskPhase _taskPhaseForAndroidStage(
    AndroidSafLocalMatchBatchStage stage,
  ) {
    return switch (stage) {
      AndroidSafLocalMatchBatchStage.idle => LocalMatchTaskPhase.idle,
      AndroidSafLocalMatchBatchStage.scanning => LocalMatchTaskPhase.scanning,
      AndroidSafLocalMatchBatchStage.matching => LocalMatchTaskPhase.matching,
      AndroidSafLocalMatchBatchStage.writing => LocalMatchTaskPhase.writing,
      AndroidSafLocalMatchBatchStage.completed => LocalMatchTaskPhase.completed,
    };
  }

  (int, int, int) _adjustCounts({
    required LocalMatchingStatus? previousStatus,
    required LocalMatchingStatus nextStatus,
    required int successCount,
    required int skipCount,
    required int failCount,
  }) {
    int nextSuccess = successCount;
    int nextSkip = skipCount;
    int nextFail = failCount;
    if (previousStatus != null) {
      switch (previousStatus.type) {
        case LocalMatchingStatusType.success:
          nextSuccess -= 1;
        case LocalMatchingStatusType.skipInst ||
            LocalMatchingStatusType.skipExisting:
          nextSkip -= 1;
        case LocalMatchingStatusType.autoFetchFail ||
            LocalMatchingStatusType.saveFail ||
            LocalMatchingStatusType.unknownError:
          nextFail -= 1;
      }
    }
    switch (nextStatus.type) {
      case LocalMatchingStatusType.success:
        nextSuccess += 1;
      case LocalMatchingStatusType.skipInst ||
          LocalMatchingStatusType.skipExisting:
        nextSkip += 1;
      case LocalMatchingStatusType.autoFetchFail ||
          LocalMatchingStatusType.saveFail ||
          LocalMatchingStatusType.unknownError:
        nextFail += 1;
    }
    return (nextSuccess, nextSkip, nextFail);
  }

  List<LocalMatchQueueItem> _selectedDesktopItems() {
    final Set<String> selectedIds = state.selectedItemIds;
    return _queueItems
        .where((LocalMatchQueueItem item) => selectedIds.contains(item.id))
        .toList(growable: false);
  }

  String? _resolveInitialDirectory() {
    final String? focusedPath = state.focusedItem?.songInfo.path;
    if (focusedPath != null &&
        focusedPath.trim().isNotEmpty &&
        !focusedPath.startsWith('content://')) {
      return p.dirname(focusedPath);
    }
    return state.saveRootPath ?? _config.storage.defaultSavePath;
  }

  String? _preferredRootDirectory(List<LocalMatchQueueItem> items) {
    final String? rootPath = items.first.songRootPath;
    if (rootPath != null && rootPath.trim().isNotEmpty) {
      return rootPath;
    }
    final String? songPath = items.first.songInfo.path;
    if (songPath != null &&
        songPath.trim().isNotEmpty &&
        !songPath.startsWith('content://')) {
      return p.dirname(songPath);
    }
    return _resolveInitialDirectory();
  }

  LocalMatchCancellationToken _replaceCancellationToken() {
    _activeCancellationToken?.cancel();
    final LocalMatchCancellationToken token = LocalMatchCancellationToken();
    _activeCancellationToken = token;
    return token;
  }

  void _appendRecentErrors(List<String> errors) {
    final List<String> next = <String>[
      ...state.recentErrors,
      ...errors.where((String item) => item.trim().isNotEmpty),
    ];
    final int overflow = next.length - _recentErrorLimit;
    state = state.copyWith(
      recentErrors: overflow > 0 ? next.sublist(overflow) : next,
    );
  }

  void _emitNotice(
    LocalMatchNoticeCode code,
    PageNoticeSeverity severity, {
    String? detail,
    int? totalCount,
    int? successCount,
    int? failCount,
    int? skipCount,
    List<LocalMatchRunValidationIssue>? validationIssues,
  }) {
    state = state.copyWith(
      notice: LocalMatchNotice(
        id: ++_noticeId,
        severity: severity,
        code: code,
        detail: detail,
        totalCount: totalCount,
        successCount: successCount,
        failureCount: failCount,
        skippedCount: skipCount,
        extra: validationIssues == null
            ? null
            : List<LocalMatchRunValidationIssue>.unmodifiable(validationIssues),
      ),
    );
  }

  List<Source> _defaultSources() {
    final List<Source> resolved = _config.search.sources
        .map((String value) {
          try {
            return Source.fromValue(value);
          } on ArgumentError {
            return null;
          }
        })
        .whereType<Source>()
        .where((Source source) => _availableSources.contains(source))
        .toList(growable: false);
    if (resolved.isNotEmpty) {
      return resolved;
    }
    return const <Source>[Source.qm, Source.kg, Source.ne];
  }

  List<Source> get _availableSources => const <Source>[
    Source.qm,
    Source.kg,
    Source.ne,
    Source.lrclib,
  ];

  int _compareSourceOrder(Source left, Source right) {
    return _availableSources
        .indexOf(left)
        .compareTo(_availableSources.indexOf(right));
  }

  bool _containsItem(String itemId) {
    return _queueItems.any((LocalMatchQueueItem item) => item.id == itemId);
  }

  LocalMatchQueueItem? _findItem(String itemId) {
    for (final LocalMatchQueueItem item in _queueItems) {
      if (item.id == itemId) {
        return item;
      }
    }
    return null;
  }

  bool _isCurrentTask(int generation) =>
      _epochs.isCurrent(_taskEpochKey, generation);

  bool _isWithinRoot(String rootPath, String filePath) {
    return p.equals(rootPath, filePath) || p.isWithin(rootPath, filePath);
  }
}
