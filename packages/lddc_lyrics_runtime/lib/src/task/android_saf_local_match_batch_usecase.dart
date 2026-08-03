import 'dart:collection';

import 'android_saf_ports.dart';
import 'lyrics_save_persistence.dart';
import 'android_saf_local_match_get_infos_usecase.dart';
import 'local_match_usecase.dart';

/// Android SAF 本地匹配批处理阶段。
enum AndroidSafLocalMatchBatchStage {
  idle,
  scanning,
  matching,
  writing,
  completed,
}

/// Android SAF 本地匹配批处理进度。
class AndroidSafLocalMatchBatchProgress {
  const AndroidSafLocalMatchBatchProgress({
    required this.stage,
    required this.text,
    required this.value,
    required this.maxValue,
    this.status,
  });

  final AndroidSafLocalMatchBatchStage stage;
  final String text;
  final int value;
  final int maxValue;
  final LocalMatchingStatus? status;
}

typedef AndroidSafLocalMatchBatchProgressCallback =
    void Function(AndroidSafLocalMatchBatchProgress value);

/// Android SAF 本地匹配批处理恢复检查点。
class AndroidSafLocalMatchBatchCheckpoint {
  AndroidSafLocalMatchBatchCheckpoint({
    required this.rootTreeUri,
    required this.stage,
    required this.scanCheckpoint,
    required List<LocalMatchSongEntry> entries,
    required List<String> scanErrors,
    required this.nextMatchIndex,
    required this.successCount,
    required this.skipCount,
    required List<LocalMatchingStatus> statuses,
  }) : entries = _freezeList(entries),
       scanErrors = _freezeList(scanErrors),
       statuses = _freezeList(statuses);

  final String rootTreeUri;
  final AndroidSafLocalMatchBatchStage stage;
  final AndroidSafScanCheckpoint? scanCheckpoint;
  final List<LocalMatchSongEntry> entries;
  final List<String> scanErrors;
  final int nextMatchIndex;
  final int successCount;
  final int skipCount;
  final List<LocalMatchingStatus> statuses;
}

/// Android SAF 本地匹配批处理结果。
class AndroidSafLocalMatchBatchResult {
  AndroidSafLocalMatchBatchResult({
    required this.stage,
    required this.total,
    required this.successCount,
    required this.failCount,
    required this.skipCount,
    required this.cancelled,
    required List<LocalMatchSongEntry> entries,
    required List<String> scanErrors,
    required List<LocalMatchingStatus> statuses,
    required this.checkpoint,
  }) : entries = _freezeList(entries),
       scanErrors = _freezeList(scanErrors),
       statuses = _freezeList(statuses);

  final AndroidSafLocalMatchBatchStage stage;
  final int total;
  final int successCount;
  final int failCount;
  final int skipCount;
  final bool cancelled;
  final List<LocalMatchSongEntry> entries;
  final List<String> scanErrors;
  final List<LocalMatchingStatus> statuses;
  final AndroidSafLocalMatchBatchCheckpoint? checkpoint;
}

/// Android SAF 端“扫描 -> 匹配 -> 写回”批处理编排。
///
/// 语义约束：
/// - 扫描阶段复用 `AndroidSafLocalMatchGetInfosUseCase` checkpoint。
/// - 匹配/写回阶段对齐Python版 `LocalMatchWorker` 统计规则：
///   `fail = total - success - skip`。
/// - 取消后返回 checkpoint，支持从断点继续。
class AndroidSafLocalMatchBatchUseCase {
  const AndroidSafLocalMatchBatchUseCase({
    required this._getInfosUseCase,
    required this._localMatchUseCase,
  });

  final AndroidSafLocalMatchGetInfosUseCase _getInfosUseCase;
  final LocalMatchUseCase _localMatchUseCase;

  Future<AndroidSafLocalMatchBatchResult> run({
    required AndroidSafTreeToken rootTree,
    required LocalMatchRunOptions options,
    AndroidSafLocalMatchBatchCheckpoint? checkpoint,
    LocalMatchCancellationToken? cancellationToken,
    LyricsSavePersistencePort? lyricsPersistencePort,
    AndroidSafLocalMatchBatchProgressCallback? onProgress,
  }) async {
    final LocalMatchCancellationToken token =
        cancellationToken ?? LocalMatchCancellationToken();
    final _AndroidSafLocalMatchBatchMutableState state = _createInitialState(
      rootTree: rootTree,
      checkpoint: checkpoint,
    );

    if (state.stage == AndroidSafLocalMatchBatchStage.completed &&
        state.nextMatchIndex >= state.entries.length &&
        state.scanCheckpoint == null) {
      return _toResult(state: state, cancelled: false, checkpoint: null);
    }

    if (state.stage == AndroidSafLocalMatchBatchStage.scanning) {
      final AndroidSafLocalMatchGetInfosResult scanResult =
          await _getInfosUseCase.run(
            rootTree: rootTree,
            checkpoint: state.scanCheckpoint,
            cancellationToken: token,
            collectEntries: false,
            onEntries: state.entries.addAll,
            onProgress: (LocalMatchGetInfosProgress progress) {
              onProgress?.call(
                AndroidSafLocalMatchBatchProgress(
                  stage: AndroidSafLocalMatchBatchStage.scanning,
                  text: progress.text,
                  value: progress.value,
                  maxValue: progress.maxValue,
                ),
              );
            },
          );
      state.scanErrors.addAll(scanResult.errors);
      if (scanResult.cancelled) {
        state.scanCheckpoint = scanResult.checkpoint;
        state.stage = AndroidSafLocalMatchBatchStage.scanning;
        return _toResult(
          state: state,
          cancelled: true,
          checkpoint: _toCheckpoint(state),
        );
      }
      state.scanCheckpoint = null;
      state.stage = AndroidSafLocalMatchBatchStage.matching;
    }

    if (state.stage == AndroidSafLocalMatchBatchStage.matching ||
        state.stage == AndroidSafLocalMatchBatchStage.writing) {
      while (state.nextMatchIndex < state.entries.length) {
        if (token.isCancelled) {
          state.stage = AndroidSafLocalMatchBatchStage.matching;
          return _toResult(
            state: state,
            cancelled: true,
            checkpoint: _toCheckpoint(state),
          );
        }
        final int processingIndex = state.nextMatchIndex;
        final LocalMatchSongEntry entry = state.entries[processingIndex];
        LocalMatchingStatus? finishedStatus;
        final LocalMatchResult singleResult = await _localMatchUseCase.run(
          entries: <LocalMatchSongEntry>[entry],
          options: options,
          cancellationToken: token,
          lyricsPersistencePort: lyricsPersistencePort,
          onProgress: (LocalMatchProgress progress) {
            if (progress.text.isNotEmpty) {
              onProgress?.call(
                AndroidSafLocalMatchBatchProgress(
                  stage: AndroidSafLocalMatchBatchStage.matching,
                  text: progress.text,
                  value: processingIndex,
                  maxValue: state.entries.length,
                ),
              );
              return;
            }
            if (progress.status == null) {
              return;
            }
            finishedStatus = _withGlobalIndex(
              progress.status!,
              processingIndex,
            );
            state.stage = AndroidSafLocalMatchBatchStage.writing;
            onProgress?.call(
              AndroidSafLocalMatchBatchProgress(
                stage: AndroidSafLocalMatchBatchStage.writing,
                text: finishedStatus!.text,
                value: processingIndex + 1,
                maxValue: state.entries.length,
                status: finishedStatus,
              ),
            );
          },
        );

        if (finishedStatus == null && singleResult.statuses.isNotEmpty) {
          finishedStatus = _withGlobalIndex(
            singleResult.statuses.last,
            processingIndex,
          );
        }
        if (singleResult.cancelled && finishedStatus == null) {
          // 当前条目在自动匹配等可取消阶段尚未产生结果，checkpoint 必须仍指向
          // 当前索引。若直接 +1，恢复后会永久跳过这首歌。
          state.stage = AndroidSafLocalMatchBatchStage.matching;
          return _toResult(
            state: state,
            cancelled: true,
            checkpoint: _toCheckpoint(state),
          );
        }
        if (finishedStatus != null) {
          state.statuses.add(finishedStatus!);
        }
        state.successCount += singleResult.successCount;
        state.skipCount += singleResult.skipCount;
        state.nextMatchIndex = processingIndex + 1;
        state.stage = AndroidSafLocalMatchBatchStage.matching;

        if (token.isCancelled) {
          return _toResult(
            state: state,
            cancelled: true,
            checkpoint: _toCheckpoint(state),
          );
        }
      }
    }

    state.stage = AndroidSafLocalMatchBatchStage.completed;
    onProgress?.call(
      AndroidSafLocalMatchBatchProgress(
        stage: AndroidSafLocalMatchBatchStage.completed,
        text: '',
        value: state.entries.length,
        maxValue: state.entries.length,
        status: state.statuses.isEmpty ? null : state.statuses.last,
      ),
    );
    return _toResult(state: state, cancelled: false, checkpoint: null);
  }

  _AndroidSafLocalMatchBatchMutableState _createInitialState({
    required AndroidSafTreeToken rootTree,
    required AndroidSafLocalMatchBatchCheckpoint? checkpoint,
  }) {
    if (checkpoint == null) {
      return _AndroidSafLocalMatchBatchMutableState(
        rootTreeUri: rootTree.uri,
        stage: AndroidSafLocalMatchBatchStage.scanning,
        scanCheckpoint: null,
        entries: <LocalMatchSongEntry>[],
        scanErrors: <String>[],
        nextMatchIndex: 0,
        successCount: 0,
        skipCount: 0,
        statuses: <LocalMatchingStatus>[],
      );
    }
    if (checkpoint.rootTreeUri != rootTree.uri) {
      throw ArgumentError.value(
        checkpoint.rootTreeUri,
        'checkpoint.rootTreeUri',
        'checkpoint 与当前 rootTree 不匹配',
      );
    }
    final int safeNextMatchIndex;
    if (checkpoint.nextMatchIndex < 0) {
      safeNextMatchIndex = 0;
    } else if (checkpoint.nextMatchIndex > checkpoint.entries.length) {
      safeNextMatchIndex = checkpoint.entries.length;
    } else {
      safeNextMatchIndex = checkpoint.nextMatchIndex;
    }

    AndroidSafLocalMatchBatchStage stage = checkpoint.stage;
    if (stage == AndroidSafLocalMatchBatchStage.idle) {
      stage = checkpoint.entries.isEmpty
          ? AndroidSafLocalMatchBatchStage.scanning
          : AndroidSafLocalMatchBatchStage.matching;
    }
    if (stage == AndroidSafLocalMatchBatchStage.writing) {
      stage = AndroidSafLocalMatchBatchStage.matching;
    }
    if (stage == AndroidSafLocalMatchBatchStage.scanning &&
        checkpoint.scanCheckpoint == null) {
      stage = AndroidSafLocalMatchBatchStage.matching;
    }
    if (stage == AndroidSafLocalMatchBatchStage.completed &&
        safeNextMatchIndex < checkpoint.entries.length) {
      stage = AndroidSafLocalMatchBatchStage.matching;
    }

    return _AndroidSafLocalMatchBatchMutableState(
      rootTreeUri: checkpoint.rootTreeUri,
      stage: stage,
      scanCheckpoint: checkpoint.scanCheckpoint,
      entries: <LocalMatchSongEntry>[...checkpoint.entries],
      scanErrors: <String>[...checkpoint.scanErrors],
      nextMatchIndex: safeNextMatchIndex,
      successCount: checkpoint.successCount,
      skipCount: checkpoint.skipCount,
      statuses: <LocalMatchingStatus>[...checkpoint.statuses],
    );
  }

  AndroidSafLocalMatchBatchCheckpoint _toCheckpoint(
    _AndroidSafLocalMatchBatchMutableState state,
  ) {
    return AndroidSafLocalMatchBatchCheckpoint(
      rootTreeUri: state.rootTreeUri,
      stage: state.stage,
      scanCheckpoint: state.scanCheckpoint,
      entries: state.entries,
      scanErrors: state.scanErrors,
      nextMatchIndex: state.nextMatchIndex,
      successCount: state.successCount,
      skipCount: state.skipCount,
      statuses: state.statuses,
    );
  }

  AndroidSafLocalMatchBatchResult _toResult({
    required _AndroidSafLocalMatchBatchMutableState state,
    required bool cancelled,
    required AndroidSafLocalMatchBatchCheckpoint? checkpoint,
  }) {
    final int total = state.entries.length;
    final int failCount = total - state.successCount - state.skipCount;
    return AndroidSafLocalMatchBatchResult(
      stage: state.stage,
      total: total,
      successCount: state.successCount,
      failCount: failCount,
      skipCount: state.skipCount,
      cancelled: cancelled,
      // 取消时 checkpoint 已经持有同一份不可变快照，结果对象直接
      // 复用，避免大队列在返回瞬间再复制一份。
      entries: checkpoint?.entries ?? state.entries,
      scanErrors: checkpoint?.scanErrors ?? state.scanErrors,
      statuses: checkpoint?.statuses ?? state.statuses,
      checkpoint: checkpoint,
    );
  }

  LocalMatchingStatus _withGlobalIndex(LocalMatchingStatus status, int index) {
    return LocalMatchingStatus(
      type: status.type,
      index: index,
      text: status.text,
      path: status.path,
    );
  }
}

class _AndroidSafLocalMatchBatchMutableState {
  _AndroidSafLocalMatchBatchMutableState({
    required this.rootTreeUri,
    required this.stage,
    required this.scanCheckpoint,
    required this.entries,
    required this.scanErrors,
    required this.nextMatchIndex,
    required this.successCount,
    required this.skipCount,
    required this.statuses,
  });

  final String rootTreeUri;
  AndroidSafLocalMatchBatchStage stage;
  AndroidSafScanCheckpoint? scanCheckpoint;
  final List<LocalMatchSongEntry> entries;
  final List<String> scanErrors;
  int nextMatchIndex;
  int successCount;
  int skipCount;
  final List<LocalMatchingStatus> statuses;
}

List<T> _freezeList<T>(List<T> values) {
  if (values is UnmodifiableListView<T>) {
    return values;
  }
  return UnmodifiableListView<T>(List<T>.of(values));
}
