import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

final class LocalMatchDesktopScanOutcome {
  LocalMatchDesktopScanOutcome({
    required this.result,
    required List<LocalMatchSongEntry> entries,
  }) : entries = List<LocalMatchSongEntry>.unmodifiable(entries);

  final LocalMatchGetInfosResult result;
  final List<LocalMatchSongEntry> entries;
}

final class LocalMatchAndroidScanOutcome {
  LocalMatchAndroidScanOutcome({
    required this.result,
    required List<LocalMatchSongEntry> entries,
  }) : entries = List<LocalMatchSongEntry>.unmodifiable(entries);

  final AndroidSafLocalMatchGetInfosResult result;
  final List<LocalMatchSongEntry> entries;
}

/// 桌面与 Android 执行协调器，只转发现有用例和进度事件，不保存任务状态。
final class LocalMatchExecutionCoordinator {
  const LocalMatchExecutionCoordinator({
    required this._desktopGetInfosUseCase,
    required this._androidGetInfosUseCase,
    required this._desktopMatchUseCase,
    required this._androidBatchUseCase,
  });

  final LocalMatchGetInfosUseCase _desktopGetInfosUseCase;
  final AndroidSafLocalMatchGetInfosUseCase _androidGetInfosUseCase;
  final LocalMatchUseCase _desktopMatchUseCase;
  final AndroidSafLocalMatchBatchUseCase _androidBatchUseCase;

  Future<LocalMatchDesktopScanOutcome> scanDesktop({
    required List<String> inputPaths,
    required LocalMatchCancellationToken cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
  }) async {
    final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[];
    final LocalMatchGetInfosResult result = await _desktopGetInfosUseCase.run(
      inputPaths: inputPaths,
      cancellationToken: cancellationToken,
      collectEntries: false,
      onEntries: entries.addAll,
      onProgress: onProgress,
    );
    return LocalMatchDesktopScanOutcome(result: result, entries: entries);
  }

  Future<LocalMatchAndroidScanOutcome> scanAndroid({
    required AndroidSafTreeToken rootTree,
    required LocalMatchCancellationToken cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
  }) async {
    final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[];
    final AndroidSafLocalMatchGetInfosResult result =
        await _androidGetInfosUseCase.run(
          rootTree: rootTree,
          cancellationToken: cancellationToken,
          collectEntries: false,
          onEntries: entries.addAll,
          onProgress: onProgress,
        );
    return LocalMatchAndroidScanOutcome(result: result, entries: entries);
  }

  Future<LocalMatchResult> runDesktop({
    required List<LocalMatchSongEntry> entries,
    required LocalMatchRunOptions options,
    required LocalMatchCancellationToken cancellationToken,
    LyricsSavePersistencePort? lyricsPersistencePort,
    LocalMatchProgressCallback? onProgress,
  }) {
    return _desktopMatchUseCase.run(
      entries: entries,
      options: options,
      cancellationToken: cancellationToken,
      lyricsPersistencePort: lyricsPersistencePort,
      onProgress: onProgress,
    );
  }

  Future<AndroidSafLocalMatchBatchResult> runAndroid({
    required AndroidSafTreeToken rootTree,
    required LocalMatchRunOptions options,
    required AndroidSafLocalMatchBatchCheckpoint checkpoint,
    required LocalMatchCancellationToken cancellationToken,
    LyricsSavePersistencePort? lyricsPersistencePort,
    AndroidSafLocalMatchBatchProgressCallback? onProgress,
  }) {
    return _androidBatchUseCase.run(
      rootTree: rootTree,
      options: options,
      checkpoint: checkpoint,
      cancellationToken: cancellationToken,
      lyricsPersistencePort: lyricsPersistencePort,
      onProgress: onProgress,
    );
  }
}
