import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import 'local_match_page_state.dart';

/// 生成队列预览所需的不可变配置快照。
final class LocalMatchPreviewOptions {
  LocalMatchPreviewOptions({
    required this.saveMode,
    required this.fileNameMode,
    required this.saveToTagMode,
    required this.lyricsFormat,
    required this.fileNameFormat,
    required List<String> selectedLangs,
    required this.saveRootPath,
    required this.androidSongTreeUri,
    required this.androidSongTreeLabel,
    required this.androidSaveTreeUri,
    required this.androidSaveTreeLabel,
  }) : selectedLangs = List<String>.unmodifiable(selectedLangs);

  final LocalMatchSaveMode saveMode;
  final LocalMatchFileNameMode fileNameMode;
  final LocalMatchSaveToTagMode saveToTagMode;
  final LyricsFormat lyricsFormat;
  final String fileNameFormat;
  final List<String> selectedLangs;
  final String? saveRootPath;

  /// 歌曲所在授权树（Android）。
  final String androidSongTreeUri;
  final String androidSongTreeLabel;

  /// 保存根授权树（Android，仅 mirror/specify 使用）。
  final String? androidSaveTreeUri;
  final String androidSaveTreeLabel;
}

/// 队列预览与保存路径规划协调器，不持有 controller state 或第二份队列。
final class LocalMatchPreviewSaveCoordinator {
  const LocalMatchPreviewSaveCoordinator();

  LocalMatchQueueItem buildDesktopPreview(
    LocalMatchQueueItem item,
    LocalMatchPreviewOptions options,
  ) {
    final bool needsTagWrite =
        !item.songInfo.fromCue &&
        (options.saveToTagMode == LocalMatchSaveToTagMode.onlyTag ||
            options.saveToTagMode == LocalMatchSaveToTagMode.both);
    final bool needsFileWrite =
        item.songInfo.fromCue ||
        options.saveToTagMode != LocalMatchSaveToTagMode.onlyTag;
    if (!needsFileWrite) {
      return item.copyWith(
        savePlan: needsTagWrite
            ? const LocalMatchSavePlan(kind: LocalMatchSavePlanKind.tagOnly)
            : const LocalMatchSavePlan(kind: LocalMatchSavePlanKind.none),
      );
    }
    final LyricsSavePlan plan = LyricsSavePlanner.planLocalMatch(
      directoryMode: toPlannerDirectoryMode(options.saveMode),
      fileNameMode: toPlannerFileNameMode(options.fileNameMode),
      localInfo: item.songInfo,
      lyricsFormat: options.lyricsFormat,
      fileNameFormat: options.fileNameFormat,
      lyricLangs: options.selectedLangs,
      saveRootPath: options.saveRootPath,
      lyricsInfo: null,
      allowLyricsPlaceholder: true,
      songRootPath: item.songRootPath,
    );
    final LocalMatchSavePlanKind kind = needsTagWrite
        ? LocalMatchSavePlanKind.fileAndTag
        : LocalMatchSavePlanKind.fileOnly;
    final LocalMatchSavePlan savePlan = plan.isSuccess
        ? LocalMatchSavePlan(kind: kind, targetPath: plan.displayPath)
        : plan.errorCode == LyricsSavePlanErrorCode.missingLyricsInfo
        ? LocalMatchSavePlan(kind: kind, pendingFileNameRootLabel: '')
        : LocalMatchSavePlan(
            kind: kind,
            blocker: savePathBlocker(plan.errorCode),
          );
    return item.copyWith(savePlan: savePlan);
  }

  LocalMatchQueueItem buildAndroidQueueItem(
    LocalMatchSongEntry entry,
    LocalMatchPreviewOptions options,
  ) {
    final LocalMatchQueueItem item = LocalMatchQueueItem(
      id: buildQueueItemId(entry.songInfo, entry.rootPath),
      songInfo: entry.songInfo,
      defaultRootPath: entry.rootPath,
      songRootPath: entry.rootPath,
      savePlan: const LocalMatchSavePlan(kind: LocalMatchSavePlanKind.none),
      lastStatus: null,
      outputPath: null,
    );
    return item.copyWith(
      savePlan: buildAndroidSavePlan(item.songInfo, options),
    );
  }

  LocalMatchSavePlan buildAndroidSavePlan(
    SongInfo songInfo,
    LocalMatchPreviewOptions options,
  ) {
    final bool needsTagWrite =
        !songInfo.fromCue &&
        (options.saveToTagMode == LocalMatchSaveToTagMode.onlyTag ||
            options.saveToTagMode == LocalMatchSaveToTagMode.both);
    final bool needsFileWrite =
        songInfo.fromCue ||
        options.saveToTagMode != LocalMatchSaveToTagMode.onlyTag;
    if (needsFileWrite) {
      final LocalMatchSavePlanKind kind = needsTagWrite
          ? LocalMatchSavePlanKind.fileAndTag
          : LocalMatchSavePlanKind.fileOnly;
      // 预览与真实写入共用同一个纯函数推导目标，避免"预览显示写到 A、实际写到 B"。
      final AndroidSafSaveTargetResult resolved = resolveAndroidSafSaveTarget(
        saveMode: options.saveMode,
        songPath: songInfo.path,
        songTreeUri: options.androidSongTreeUri,
        saveTreeUri: options.androidSaveTreeUri,
        songTreeLabel: options.androidSongTreeLabel,
        saveTreeLabel: options.androidSaveTreeLabel,
      );
      final AndroidSafSaveTarget? target = resolved.target;
      if (target == null) {
        return LocalMatchSavePlan(
          kind: kind,
          blocker: switch (resolved.failure) {
            AndroidSafSaveTargetFailure.missingSaveTree =>
              LocalMatchSavePlanBlocker.needsSaveRoot,
            _ => LocalMatchSavePlanBlocker.unknown,
          },
        );
      }
      final bool waitsForLyrics =
          options.fileNameMode == LocalMatchFileNameMode.formatByLyrics;
      final String directoryLabel = target.directoryLabel.trim();
      final String? fileLabel = waitsForLyrics
          ? null
          : (directoryLabel.isEmpty
                ? LyricsPathTemplateFormatter.buildFileName(
                    fileNameFormat:
                        '${options.fileNameFormat}${options.lyricsFormat.ext}',
                    songInfo: songInfo,
                    lyricLangs: options.selectedLangs,
                  )
                : '$directoryLabel / '
                      '${LyricsPathTemplateFormatter.buildFileName(fileNameFormat: '${options.fileNameFormat}${options.lyricsFormat.ext}', songInfo: songInfo, lyricLangs: options.selectedLangs)}');
      return LocalMatchSavePlan(
        kind: kind,
        targetPath: fileLabel,
        pendingFileNameRootLabel: waitsForLyrics ? directoryLabel : null,
      );
    }
    return needsTagWrite
        ? const LocalMatchSavePlan(kind: LocalMatchSavePlanKind.tagOnly)
        : const LocalMatchSavePlan(kind: LocalMatchSavePlanKind.none);
  }

  String buildQueueItemId(SongInfo songInfo, String? rootPath) {
    return <String>[
      songInfo.path ?? '',
      rootPath ?? '',
      songInfo.title ?? '',
      songInfo.artistText,
      songInfo.album ?? '',
      songInfo.fromCue ? 'cue' : 'song',
    ].join('|');
  }

  LyricsSaveDirectoryMode toPlannerDirectoryMode(LocalMatchSaveMode mode) {
    return switch (mode) {
      LocalMatchSaveMode.mirror => LyricsSaveDirectoryMode.mirrorSourceRoot,
      LocalMatchSaveMode.song => LyricsSaveDirectoryMode.songDirectory,
      LocalMatchSaveMode.specify => LyricsSaveDirectoryMode.folder,
    };
  }

  LyricsSaveFileNameMode toPlannerFileNameMode(LocalMatchFileNameMode mode) {
    return switch (mode) {
      LocalMatchFileNameMode.formatByLyrics =>
        LyricsSaveFileNameMode.templateByLyrics,
      LocalMatchFileNameMode.formatBySong =>
        LyricsSaveFileNameMode.templateBySong,
      LocalMatchFileNameMode.song => LyricsSaveFileNameMode.sourceBasename,
    };
  }

  LocalMatchSavePlanBlocker savePathBlocker(LyricsSavePlanErrorCode? code) {
    return switch (code) {
      LyricsSavePlanErrorCode.missingSaveRoot =>
        LocalMatchSavePlanBlocker.needsSaveRoot,
      LyricsSavePlanErrorCode.missingSongRoot =>
        LocalMatchSavePlanBlocker.needsSongRoot,
      _ => LocalMatchSavePlanBlocker.unknown,
    };
  }
}
