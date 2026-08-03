import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/features/local_match/application/local_match_execution_coordinator.dart';
import 'package:lddc/src/features/local_match/application/local_match_input_coordinator.dart';
import 'package:lddc/src/features/local_match/application/local_match_page_state.dart';
import 'package:lddc/src/features/local_match/application/local_match_preview_save_coordinator.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  group('LocalMatchInputCoordinator', () {
    test('归一化路径并冻结返回列表', () {
      final LocalMatchInputCoordinator coordinator = _inputCoordinator();

      final List<String> paths = coordinator.normalizePaths(const <String>[
        ' C:/a.mp3 ',
        '',
        '   ',
        'D:/b.flac',
      ]);

      expect(paths, <String>['C:/a.mp3', 'D:/b.flac']);
      expect(() => paths.add('E:/c.mp3'), throwsUnsupportedError);
    });

    test('异步解析后检测到取消时不发布迟到歌曲', () async {
      final Completer<void> metadataGate = Completer<void>();
      final _FakeMediaGateway gateway = _FakeMediaGateway(
        songInfos: <SongInfo>[_song(path: 'C:/late.mp3')],
        gate: metadataGate,
      );
      final LocalMatchInputCoordinator coordinator = _inputCoordinator(gateway);
      bool active = true;

      final Future<LocalMatchResolvedInputs> pending = coordinator
          .resolveDroppedItems(
            items: <DragDropItemDescriptor>[
              DragDropItemDescriptor.song(
                DragDropSongDescriptor(path: 'C:/late.mp3'),
              ),
            ],
            shouldContinue: () => active,
          );
      await Future<void>.delayed(Duration.zero);
      active = false;
      metadataGate.complete();
      final LocalMatchResolvedInputs result = await pending;

      expect(result.cancelled, isTrue);
      expect(result.entries, isEmpty);
      expect(result.paths, isEmpty);
    });
  });

  group('LocalMatchExecutionCoordinator', () {
    test('桌面与 Android 扫描只通过批次回调收集单份条目', () async {
      final LocalMatchSongEntry desktopEntry = LocalMatchSongEntry(
        songInfo: _song(path: 'C:/desktop.mp3'),
        rootPath: 'C:/',
      );
      final LocalMatchSongEntry androidEntry = LocalMatchSongEntry(
        songInfo: _song(path: 'content://android/song'),
        rootPath: 'content://tree/root',
      );
      final LocalMatchExecutionCoordinator coordinator =
          LocalMatchExecutionCoordinator(
            desktopGetInfosUseCase: _FakeDesktopGetInfosUseCase(desktopEntry),
            androidGetInfosUseCase: _FakeAndroidGetInfosUseCase(androidEntry),
            desktopMatchUseCase: _FakeDesktopMatchUseCase(),
            androidBatchUseCase: _FakeAndroidBatchUseCase(),
          );

      final LocalMatchDesktopScanOutcome desktop = await coordinator
          .scanDesktop(
            inputPaths: const <String>['C:/'],
            cancellationToken: LocalMatchCancellationToken(),
          );
      final LocalMatchAndroidScanOutcome android = await coordinator
          .scanAndroid(
            rootTree: const AndroidSafTreeToken(uri: 'content://tree/root'),
            cancellationToken: LocalMatchCancellationToken(),
          );

      expect(desktop.result.entries, isEmpty);
      expect(desktop.entries.single.songInfo.path, 'C:/desktop.mp3');
      expect(android.result.entries, isEmpty);
      expect(android.entries.single.songInfo.path, 'content://android/song');
      expect(() => desktop.entries.clear(), throwsUnsupportedError);
      expect(() => android.entries.clear(), throwsUnsupportedError);
    });

    test('桌面与 Android 执行保持取消令牌和 checkpoint 身份', () async {
      final _FakeDesktopMatchUseCase desktopUseCase =
          _FakeDesktopMatchUseCase();
      final _FakeAndroidBatchUseCase androidUseCase =
          _FakeAndroidBatchUseCase();
      final LocalMatchExecutionCoordinator coordinator =
          LocalMatchExecutionCoordinator(
            desktopGetInfosUseCase: _FakeDesktopGetInfosUseCase(null),
            androidGetInfosUseCase: _FakeAndroidGetInfosUseCase(null),
            desktopMatchUseCase: desktopUseCase,
            androidBatchUseCase: androidUseCase,
          );
      final LocalMatchCancellationToken desktopToken =
          LocalMatchCancellationToken()..cancel();
      final LocalMatchCancellationToken androidToken =
          LocalMatchCancellationToken()..cancel();
      final AndroidSafLocalMatchBatchCheckpoint checkpoint = _emptyCheckpoint();

      final LocalMatchResult desktop = await coordinator.runDesktop(
        entries: const <LocalMatchSongEntry>[],
        options: _runOptions(),
        cancellationToken: desktopToken,
      );
      final AndroidSafLocalMatchBatchResult android = await coordinator
          .runAndroid(
            rootTree: const AndroidSafTreeToken(uri: 'content://tree/root'),
            options: _runOptions(),
            checkpoint: checkpoint,
            cancellationToken: androidToken,
          );

      expect(desktop.cancelled, isTrue);
      expect(android.cancelled, isTrue);
      expect(desktopUseCase.lastToken, same(desktopToken));
      expect(androidUseCase.lastToken, same(androidToken));
      expect(androidUseCase.lastCheckpoint, same(checkpoint));
    });
  });

  group('LocalMatchPreviewSaveCoordinator', () {
    test('桌面镜像保存缺少根目录时产生可校验阻断项', () {
      const LocalMatchPreviewSaveCoordinator coordinator =
          LocalMatchPreviewSaveCoordinator();

      final LocalMatchQueueItem result = coordinator.buildDesktopPreview(
        _queueItem(_song(path: 'C:/music/song.mp3')),
        _previewOptions(
          saveMode: LocalMatchSaveMode.mirror,
          saveRootPath: null,
        ),
      );

      expect(result.savePlan.kind, LocalMatchSavePlanKind.fileOnly);
      expect(result.savePlan.blocker, LocalMatchSavePlanBlocker.needsSaveRoot);
    });

    test('Android 按歌词命名保留树标签占位且冻结语言快照', () {
      const LocalMatchPreviewSaveCoordinator coordinator =
          LocalMatchPreviewSaveCoordinator();
      final List<String> langs = <String>['orig'];
      final LocalMatchPreviewOptions options = _previewOptions(
        fileNameMode: LocalMatchFileNameMode.formatByLyrics,
        selectedLangs: langs,
      );
      langs.add('ts');

      final LocalMatchSavePlan plan = coordinator.buildAndroidSavePlan(
        _song(path: 'content://audio/song'),
        options,
      );

      expect(options.selectedLangs, const <String>['orig']);
      expect(() => options.selectedLangs.add('roma'), throwsUnsupportedError);
      expect(plan.kind, LocalMatchSavePlanKind.fileOnly);
      expect(plan.targetPath, isNull);
      expect(plan.pendingFileNameRootLabel, 'Music');
    });
  });
}

LocalMatchInputCoordinator _inputCoordinator([_FakeMediaGateway? gateway]) {
  return LocalMatchInputCoordinator(
    songInfoResolver: DroppedSongInfoResolver(
      mediaGateway: gateway ?? _FakeMediaGateway(songInfos: <SongInfo>[]),
    ),
  );
}

final class _FakeMediaGateway extends Fake implements LocalMatchMediaGateway {
  _FakeMediaGateway({required this.songInfos, this.gate});

  final List<SongInfo> songInfos;
  final Completer<void>? gate;

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async {
    await gate?.future;
    return songInfos;
  }
}

final class _FakeDesktopGetInfosUseCase extends Fake
    implements LocalMatchGetInfosUseCase {
  _FakeDesktopGetInfosUseCase(this.entry);

  final LocalMatchSongEntry? entry;

  @override
  Future<LocalMatchGetInfosResult> run({
    required List<String> inputPaths,
    LocalMatchCancellationToken? cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
    LocalMatchSongEntryBatchCallback? onEntries,
    bool collectEntries = true,
  }) async {
    final LocalMatchSongEntry? value = entry;
    if (value != null) {
      await onEntries?.call(<LocalMatchSongEntry>[value]);
    }
    return LocalMatchGetInfosResult(
      entries: const <LocalMatchSongEntry>[],
      errors: const <String>[],
      cancelled: false,
    );
  }
}

final class _FakeAndroidGetInfosUseCase extends Fake
    implements AndroidSafLocalMatchGetInfosUseCase {
  _FakeAndroidGetInfosUseCase(this.entry);

  final LocalMatchSongEntry? entry;

  @override
  Future<AndroidSafLocalMatchGetInfosResult> run({
    required AndroidSafTreeToken rootTree,
    AndroidSafScanCheckpoint? checkpoint,
    LocalMatchCancellationToken? cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
    LocalMatchSongEntryBatchCallback? onEntries,
    bool collectEntries = true,
  }) async {
    final LocalMatchSongEntry? value = entry;
    if (value != null) {
      await onEntries?.call(<LocalMatchSongEntry>[value]);
    }
    return AndroidSafLocalMatchGetInfosResult(
      entries: const <LocalMatchSongEntry>[],
      errors: const <String>[],
      cancelled: false,
      checkpoint: null,
    );
  }
}

final class _FakeDesktopMatchUseCase extends Fake implements LocalMatchUseCase {
  LocalMatchCancellationToken? lastToken;

  @override
  Future<LocalMatchResult> run({
    required List<LocalMatchSongEntry> entries,
    required LocalMatchRunOptions options,
    LocalMatchCancellationToken? cancellationToken,
    LyricsSavePersistencePort? lyricsPersistencePort,
    LocalMatchProgressCallback? onProgress,
  }) async {
    lastToken = cancellationToken;
    return LocalMatchResult(
      total: entries.length,
      successCount: 0,
      failCount: 0,
      skipCount: 0,
      cancelled: cancellationToken?.isCancelled ?? false,
      statuses: const <LocalMatchingStatus>[],
    );
  }
}

final class _FakeAndroidBatchUseCase extends Fake
    implements AndroidSafLocalMatchBatchUseCase {
  LocalMatchCancellationToken? lastToken;
  AndroidSafLocalMatchBatchCheckpoint? lastCheckpoint;

  @override
  Future<AndroidSafLocalMatchBatchResult> run({
    required AndroidSafTreeToken rootTree,
    required LocalMatchRunOptions options,
    AndroidSafLocalMatchBatchCheckpoint? checkpoint,
    LocalMatchCancellationToken? cancellationToken,
    LyricsSavePersistencePort? lyricsPersistencePort,
    AndroidSafLocalMatchBatchProgressCallback? onProgress,
  }) async {
    lastToken = cancellationToken;
    lastCheckpoint = checkpoint;
    return AndroidSafLocalMatchBatchResult(
      stage: AndroidSafLocalMatchBatchStage.matching,
      total: 0,
      successCount: 0,
      failCount: 0,
      skipCount: 0,
      cancelled: cancellationToken?.isCancelled ?? false,
      entries: const <LocalMatchSongEntry>[],
      scanErrors: const <String>[],
      statuses: const <LocalMatchingStatus>[],
      checkpoint: checkpoint,
    );
  }
}

LocalMatchPreviewOptions _previewOptions({
  LocalMatchSaveMode saveMode = LocalMatchSaveMode.song,
  LocalMatchFileNameMode fileNameMode = LocalMatchFileNameMode.song,
  List<String>? selectedLangs,
  String? saveRootPath = 'C:/lyrics',
}) {
  return LocalMatchPreviewOptions(
    saveMode: saveMode,
    fileNameMode: fileNameMode,
    saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
    lyricsFormat: LyricsFormat.lineByLineLrc,
    fileNameFormat: '%<artist> - %<title>',
    selectedLangs: selectedLangs ?? const <String>['orig'],
    saveRootPath: saveRootPath,
    androidTreeLabel: 'Music',
  );
}

LocalMatchRunOptions _runOptions() {
  return LocalMatchRunOptions(
    saveMode: LocalMatchSaveMode.song,
    fileNameMode: LocalMatchFileNameMode.song,
    saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
    lyricsFormat: LyricsFormat.lineByLineLrc,
    langs: const <String>['orig'],
    minScore: 60,
    sources: const <Source>[Source.qm],
    skipExistingLyrics: false,
  );
}

AndroidSafLocalMatchBatchCheckpoint _emptyCheckpoint() {
  return AndroidSafLocalMatchBatchCheckpoint(
    rootTreeUri: 'content://tree/root',
    stage: AndroidSafLocalMatchBatchStage.matching,
    scanCheckpoint: null,
    entries: const <LocalMatchSongEntry>[],
    scanErrors: const <String>[],
    nextMatchIndex: 0,
    successCount: 0,
    skipCount: 0,
    statuses: const <LocalMatchingStatus>[],
  );
}

LocalMatchQueueItem _queueItem(SongInfo song) {
  return LocalMatchQueueItem(
    id: song.path ?? '',
    songInfo: song,
    defaultRootPath: 'C:/music',
    songRootPath: 'C:/music',
    savePlan: const LocalMatchSavePlan(kind: LocalMatchSavePlanKind.none),
    lastStatus: null,
    outputPath: null,
  );
}

SongInfo _song({required String path}) {
  return SongInfo(
    source: Source.local,
    id: '1',
    title: 'Song',
    artist: SongArtist(<String>['Singer']),
    path: path,
  );
}
