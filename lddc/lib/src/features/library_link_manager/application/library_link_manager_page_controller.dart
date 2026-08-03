import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../../../core/library_link/library_link.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../presentation/library_link_manager_dependencies.dart';
import 'library_link_manager_page_state.dart';
import 'library_link_manager_usecase.dart';

final NotifierProvider<
  LibraryLinkManagerPageController,
  LibraryLinkManagerPageState
>
libraryLinkManagerPageControllerProvider =
    NotifierProvider<
      LibraryLinkManagerPageController,
      LibraryLinkManagerPageState
    >(
      LibraryLinkManagerPageController.new,
      // 关联库管理页依赖 app 层注入的仓储、文件选择器和导航回调。
      // 显式声明 scoped dependency，测试和多窗口页面才能各自拿到自己的依赖实例。
      dependencies: [libraryLinkManagerDependenciesProvider],
    );

class LibraryLinkManagerPageController
    extends Notifier<LibraryLinkManagerPageState> {
  // 关联库可能有几千条记录，controller 只维护当前滚动窗口附近的 chunk。
  // 页面可以保持虚拟列表的总长度，但 Dart 内存不会长期持有整表对象。
  static const int chunkSize = 200;
  static const int prefetchChunkRadius = 1;
  static const int maxRetainedChunkCount = 4;
  static const Duration searchDebounceDuration = Duration(milliseconds: 250);

  StreamSubscription<void>? _changesSubscription;
  Timer? _searchDebounceTimer;
  bool _initialized = false;
  bool _pendingRefresh = false;
  bool _windowLoadInFlight = false;
  Set<int> _requestedChunkIndexes = <int>{};
  Set<int> _lastVisibleChunkIndexes = <int>{0};
  final Set<int> _failedChunkIndexes = <int>{};
  int _lastAnchorIndex = 0;
  int _loadGeneration = 0;
  int _windowRequestSerial = 0;
  String _pendingSearchText = '';
  final OperationEpoch _actionEpoch = OperationEpoch();

  LibraryLinkManagerDependencies get _dependencies =>
      ref.read(libraryLinkManagerDependenciesProvider);
  LibraryLinkRepository get _repository => _dependencies.repository;
  AppFilePicker get _filePicker => _dependencies.filePicker;
  LibraryLinkManagerUseCase get _useCase => _dependencies.useCase;

  @override
  LibraryLinkManagerPageState build() {
    ref.onDispose(() {
      _actionEpoch.invalidate();
      _loadGeneration += 1;
      _windowRequestSerial += 1;
      _searchDebounceTimer?.cancel();
      unawaited(_changesSubscription?.cancel());
    });
    return LibraryLinkManagerPageState.initial();
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _repository.initialize();
    if (!_isCurrent) {
      return;
    }
    _changesSubscription = _repository.watchChanges(emitCurrent: true).listen((
      _,
    ) {
      if (state.busy) {
        _pendingRefresh = true;
        return;
      }
      unawaited(refreshForIndex(_lastAnchorIndex));
    });
  }

  Future<void> returnToSettings() {
    return _dependencies.returnToSettings();
  }

  Future<void> refresh() => refreshForIndex(_lastAnchorIndex);

  Future<void> refreshForIndex(int index, {String? searchText}) async {
    final int generation = ++_loadGeneration;
    _windowRequestSerial += 1;
    _requestedChunkIndexes = <int>{};
    _failedChunkIndexes.clear();
    _lastAnchorIndex = index < 0 ? 0 : index;
    state = state.copyWith(loading: true);
    final String normalizedSearchText = (searchText ?? state.searchText).trim();
    try {
      final int totalCount = await _repository.countItems(
        searchText: normalizedSearchText,
      );
      if (!_isCurrentLoadGeneration(generation)) {
        return;
      }
      if (totalCount <= 0) {
        _lastAnchorIndex = 0;
        _lastVisibleChunkIndexes = <int>{0};
        state = state.copyWith(
          loading: false,
          totalCount: 0,
          searchText: normalizedSearchText,
          loadedChunks: const <int, List<LibraryLinkItem>>{},
        );
        return;
      }

      final int initialIndex = _lastAnchorIndex.clamp(0, totalCount - 1);
      final int initialChunk = initialIndex ~/ chunkSize;
      final List<LibraryLinkItem> initialItems = await _readChunk(
        chunkIndex: initialChunk,
        totalCount: totalCount,
        searchText: normalizedSearchText,
      );
      if (!_isCurrentLoadGeneration(generation)) {
        return;
      }
      _lastAnchorIndex = initialIndex;
      _lastVisibleChunkIndexes = <int>{initialChunk};
      state = state.copyWith(
        loading: false,
        totalCount: totalCount,
        searchText: normalizedSearchText,
        loadedChunks: <int, List<LibraryLinkItem>>{initialChunk: initialItems},
      );
      _scheduleWindowForChunks(<int>{initialChunk});
    } catch (error) {
      if (!_isCurrentLoadGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        loading: false,
        notice: LibraryLinkManagerNotice(
          code: LibraryLinkManagerNoticeCode.loadFailed,
          detail: error.toString(),
        ),
      );
    }
  }

  void handleRequiredIndexes(Iterable<int> indexes) {
    if (state.loading || state.totalCount <= 0) {
      return;
    }
    final Set<int> visibleChunks = <int>{};
    for (final int index in indexes) {
      if (index < 0 || index >= state.totalCount) {
        continue;
      }
      visibleChunks.add(index ~/ chunkSize);
      _lastAnchorIndex = index;
    }
    if (visibleChunks.isEmpty) {
      return;
    }
    _lastVisibleChunkIndexes = visibleChunks;
    _scheduleWindowForChunks(visibleChunks);
  }

  void scheduleSearch(String searchText) {
    final String normalizedSearchText = searchText.trim();
    _pendingSearchText = normalizedSearchText;
    _searchDebounceTimer?.cancel();
    if (state.selectedIds.isNotEmpty) {
      state = state.copyWith(selectedIds: const <int>{});
    }
    if (normalizedSearchText == state.searchText) {
      return;
    }
    _searchDebounceTimer = Timer(searchDebounceDuration, () {
      _searchDebounceTimer = null;
      unawaited(_applyPendingSearch());
    });
  }

  Future<void> submitSearch(String searchText) async {
    _pendingSearchText = searchText.trim();
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = null;
    if (state.selectedIds.isNotEmpty) {
      state = state.copyWith(selectedIds: const <int>{});
    }
    await _applyPendingSearch();
  }

  Future<void> _applyPendingSearch() async {
    if (_pendingSearchText == state.searchText) {
      return;
    }
    _lastAnchorIndex = 0;
    await refreshForIndex(0, searchText: _pendingSearchText);
  }

  void toggleSelection(int id, bool? selected) {
    final Set<int> next = Set<int>.from(state.selectedIds);
    if (selected == true) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(selectedIds: next);
  }

  Future<void> deleteSelected() async {
    final Set<int> ids = Set<int>.from(state.selectedIds);
    if (ids.isEmpty) {
      return;
    }
    await _runBusyAction(
      successNotice: LibraryLinkManagerNotice(
        code: LibraryLinkManagerNoticeCode.deleteSelectedSuccess,
      ),
      action: () async {
        await _repository.delItems(ids);
        state = state.copyWith(selectedIds: const <int>{});
      },
    );
  }

  Future<void> deleteAll() async {
    await _runBusyAction(
      successNotice: LibraryLinkManagerNotice(
        code: LibraryLinkManagerNoticeCode.deleteAllSuccess,
      ),
      action: () async {
        await _repository.delAll();
        state = state.copyWith(selectedIds: const <int>{});
      },
    );
  }

  Future<void> clearInvalid() async {
    await _runBusyAction(
      action: () async {
        final LibraryLinkClearInvalidResult result = await _useCase
            .clearInvalid();
        final Set<int> selected = Set<int>.from(state.selectedIds)
          ..removeAll(result.deletedIds);
        state = state.copyWith(
          selectedIds: selected,
          notice: LibraryLinkManagerNotice(
            code: LibraryLinkManagerNoticeCode.clearInvalidSuccess,
            count: result.count,
          ),
        );
      },
    );
  }

  Future<void> changeDirectory() async {
    final String? oldDir = await _filePicker.pickDirectory();
    if (oldDir == null || oldDir.isEmpty) {
      return;
    }
    final String? newDir = await _filePicker.pickDirectory(
      initialDirectory: oldDir,
    );
    if (newDir == null || newDir.isEmpty || oldDir == newDir) {
      return;
    }
    await _runBusyAction(
      action: () async {
        final LibraryLinkRewriteDirectoryResult result = await _useCase
            .rewriteDirectory(oldDir: oldDir, newDir: newDir);
        final Set<int> selected = Set<int>.from(state.selectedIds)
          ..removeAll(result.originalIds);
        state = state.copyWith(
          selectedIds: selected,
          notice: LibraryLinkManagerNotice(
            code: LibraryLinkManagerNoticeCode.changeDirectorySuccess,
            count: result.count,
          ),
        );
      },
    );
  }

  Future<void> backupToJson() async {
    await _runBusyAction(
      action: () async {
        final String backupJson = await _useCase.buildBackupJson();
        final SavedTextFileResult? saveResult = await _filePicker.saveTextFile(
          fileName: 'local_song_lyrics_backup.json',
          text: backupJson,
          allowedExtensions: const <String>['json'],
        );
        if (saveResult == null) {
          return;
        }
        state = state.copyWith(
          notice: LibraryLinkManagerNotice(
            code: LibraryLinkManagerNoticeCode.backupSuccess,
            extra: saveResult.displayPath,
          ),
        );
      },
    );
  }

  Future<LibraryLinkManagerRestoreFile?> pickRestoreFile({
    required String confirmButtonText,
  }) async {
    final PickedFileHandle? file = await _filePicker.pickFile(
      allowedExtensions: const <String>['json'],
      confirmButtonText: confirmButtonText,
      label: 'json',
    );
    return file == null ? null : LibraryLinkManagerRestoreFile(file);
  }

  Future<void> restoreFromJson({
    required LibraryLinkManagerRestoreFile file,
    required String invalidBackupFormatMessage,
  }) async {
    await _runBusyAction(
      successNotice: LibraryLinkManagerNotice(
        code: LibraryLinkManagerNoticeCode.restoreSuccess,
      ),
      action: () async {
        await _useCase.restoreFromJsonBytes(
          await file.handle.readAsBytes(),
          invalidBackupFormatMessage: invalidBackupFormatMessage,
        );
        state = state.copyWith(selectedIds: const <int>{});
      },
    );
  }

  Future<void> exportLyrics() async {
    final String? saveDir = await _filePicker.pickDirectory();
    if (saveDir == null || saveDir.isEmpty) {
      return;
    }
    await _runBusyAction(
      action: () async {
        final int exported = await _useCase.exportLyrics(saveDir: saveDir);
        state = state.copyWith(
          notice: LibraryLinkManagerNotice(
            code: LibraryLinkManagerNoticeCode.exportSuccess,
            count: exported,
          ),
        );
      },
    );
  }

  void _scheduleWindowForChunks(Set<int> visibleChunks) {
    if (state.totalCount <= 0 || visibleChunks.isEmpty) {
      return;
    }
    final List<int> targets = _buildTargetChunks(visibleChunks);
    final Set<int> missing = targets
        .where(
          (int chunkIndex) =>
              !state.loadedChunks.containsKey(chunkIndex) &&
              !_failedChunkIndexes.contains(chunkIndex),
        )
        .toSet();
    _requestedChunkIndexes = missing;
    _windowRequestSerial += 1;
    _pruneChunks();
    if (_windowLoadInFlight || missing.isEmpty) {
      return;
    }
    unawaited(_drainWindowRequests());
  }

  Future<void> _drainWindowRequests() async {
    if (_windowLoadInFlight) {
      return;
    }
    _windowLoadInFlight = true;
    try {
      while (_requestedChunkIndexes.isNotEmpty && _isCurrent) {
        final Set<int> requested = _requestedChunkIndexes;
        _requestedChunkIndexes = <int>{};
        final int generation = _loadGeneration;
        final int requestSerial = _windowRequestSerial;
        for (final int chunkIndex in requested) {
          if (!_isCurrentLoadGeneration(generation)) {
            return;
          }
          if (state.loadedChunks.containsKey(chunkIndex) ||
              _failedChunkIndexes.contains(chunkIndex)) {
            continue;
          }
          try {
            final List<LibraryLinkItem> items = await _readChunk(
              chunkIndex: chunkIndex,
              totalCount: state.totalCount,
              searchText: state.searchText,
            );
            if (!_isCurrentLoadGeneration(generation)) {
              return;
            }
            // 快速滚动时只发布仍属于当前请求序列的结果；旧请求的数据库
            // 操作无法取消，但其结果不能再污染新的可见窗口。
            if (requestSerial != _windowRequestSerial &&
                !_lastVisibleChunkIndexes.contains(chunkIndex)) {
              continue;
            }
            final Map<int, List<LibraryLinkItem>> next =
                Map<int, List<LibraryLinkItem>>.from(state.loadedChunks)
                  ..[chunkIndex] = items;
            state = state.copyWith(loadedChunks: next);
          } catch (error) {
            if (!_isCurrentLoadGeneration(generation)) {
              return;
            }
            _failedChunkIndexes.add(chunkIndex);
            state = state.copyWith(
              notice: LibraryLinkManagerNotice(
                code: LibraryLinkManagerNoticeCode.loadFailed,
                detail: error.toString(),
              ),
            );
          }
          if (_requestedChunkIndexes.isNotEmpty) {
            break;
          }
        }
        _pruneChunks();
      }
    } finally {
      _windowLoadInFlight = false;
      if (_requestedChunkIndexes.isNotEmpty && _isCurrent) {
        unawaited(_drainWindowRequests());
      }
    }
  }

  Future<List<LibraryLinkItem>> _readChunk({
    required int chunkIndex,
    required int totalCount,
    required String searchText,
  }) async {
    final int offset = chunkIndex * chunkSize;
    if (offset >= totalCount) {
      return const <LibraryLinkItem>[];
    }
    final int remaining = totalCount - offset;
    final int limit = remaining < chunkSize ? remaining : chunkSize;
    return _repository.getPage(
      offset: offset,
      limit: limit,
      searchText: searchText,
    );
  }

  List<int> _buildTargetChunks(Set<int> visibleChunks) {
    final int lastChunk = (state.totalCount - 1) ~/ chunkSize;
    final Set<int> targets = <int>{};
    for (final int visibleChunk in visibleChunks) {
      for (
        int delta = -prefetchChunkRadius;
        delta <= prefetchChunkRadius;
        delta += 1
      ) {
        final int target = visibleChunk + delta;
        if (target >= 0 && target <= lastChunk) {
          targets.add(target);
        }
      }
    }
    final List<int> ordered = targets.toList(growable: false)
      ..sort((int left, int right) {
        int distance(int value) => visibleChunks
            .map((int visible) => (value - visible).abs())
            .reduce((int a, int b) => a < b ? a : b);
        return distance(left).compareTo(distance(right));
      });
    return ordered;
  }

  void _pruneChunks() {
    if (state.loadedChunks.length <= maxRetainedChunkCount) {
      return;
    }
    final List<int> ordered = state.loadedChunks.keys.toList(growable: false)
      ..sort((int left, int right) {
        int distance(int value) => _lastVisibleChunkIndexes
            .map((int visible) => (value - visible).abs())
            .reduce((int a, int b) => a < b ? a : b);
        return distance(left).compareTo(distance(right));
      });
    final Set<int> retained = ordered.take(maxRetainedChunkCount).toSet();
    final Map<int, List<LibraryLinkItem>> next =
        Map<int, List<LibraryLinkItem>>.from(state.loadedChunks)
          ..removeWhere((int chunkIndex, _) => !retained.contains(chunkIndex));
    state = state.copyWith(loadedChunks: next);
  }

  Future<void> _runBusyAction({
    LibraryLinkManagerNotice? successNotice,
    required Future<void> Function() action,
  }) async {
    final int generation = _actionEpoch.next();
    state = state.copyWith(busy: true, clearNotice: true);
    try {
      await action();
      if (!_isCurrentActionGeneration(generation)) {
        return;
      }
      if (successNotice != null) {
        state = state.copyWith(notice: successNotice);
      }
    } catch (error) {
      if (!_isCurrentActionGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        notice: LibraryLinkManagerNotice(
          code: LibraryLinkManagerNoticeCode.operationFailed,
          detail: error.toString(),
        ),
      );
    } finally {
      if (_isCurrentActionGeneration(generation)) {
        state = state.copyWith(busy: false);
      }
      if (_pendingRefresh) {
        _pendingRefresh = false;
        await refreshForIndex(_lastAnchorIndex);
      }
    }
  }

  bool get _isCurrent => ref.mounted;

  bool _isCurrentLoadGeneration(int generation) {
    return ref.mounted && generation == _loadGeneration;
  }

  bool _isCurrentActionGeneration(int generation) {
    return ref.mounted && _actionEpoch.isCurrent(generation);
  }
}
