import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../audio_tag/audio_tag_port.dart';
import '../auto_fetch/auto_fetch.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../files/background_file_io.dart';
import 'local_match_file_scanner.dart';
import 'lyrics_save_persistence.dart';
import 'lyrics_save_planner.dart';

/// 本地匹配扫描结果条目：歌曲信息 + 遍历根目录。
class LocalMatchSongEntry {
  const LocalMatchSongEntry({required this.songInfo, required this.rootPath});

  final SongInfo songInfo;
  final String? rootPath;
}

/// 本地匹配保存模式，对齐Python版 `SaveMode`。
enum LocalMatchSaveMode {
  mirror(0),
  song(1),
  specify(2);

  const LocalMatchSaveMode(this.code);
  final int code;
}

/// 本地匹配文件名模式，对齐Python版 `FileNameMode`。
enum LocalMatchFileNameMode {
  formatByLyrics(0),
  formatBySong(1),
  song(2);

  const LocalMatchFileNameMode(this.code);
  final int code;
}

/// 本地匹配“保存到标签”模式，对齐Python版 `LocalMatchSave2TagMode`。
enum LocalMatchSaveToTagMode {
  onlyFile(0),
  onlyTag(1),
  both(2);

  const LocalMatchSaveToTagMode(this.code);
  final int code;
}

/// 单条本地匹配状态类型，对齐Python版 `LocalMatchingStatusType`。
enum LocalMatchingStatusType {
  success,
  skipInst,
  autoFetchFail,
  saveFail,
  unknownError,
  skipExisting,
}

/// 单条本地匹配状态。
class LocalMatchingStatus {
  const LocalMatchingStatus({
    required this.type,
    required this.index,
    required this.text,
    this.path,
  });

  final LocalMatchingStatusType type;
  final int index;
  final String text;
  final String? path;
}

/// `GetInfos` 阶段进度，对齐Python版 `text/value/max` 结构。
class LocalMatchGetInfosProgress {
  const LocalMatchGetInfosProgress({
    required this.text,
    required this.value,
    required this.maxValue,
  });

  final String text;
  final int value;
  final int maxValue;
}

/// `GetInfos` 阶段结果。
class LocalMatchGetInfosResult {
  LocalMatchGetInfosResult({
    required List<LocalMatchSongEntry> entries,
    required List<String> errors,
    required this.cancelled,
  }) : entries = List<LocalMatchSongEntry>.unmodifiable(entries),
       errors = List<String>.unmodifiable(errors);

  final List<LocalMatchSongEntry> entries;
  final List<String> errors;
  final bool cancelled;
}

/// `LocalMatch` 阶段进度，对齐Python版 `text/value/max/status` 结构。
class LocalMatchProgress {
  const LocalMatchProgress({
    required this.text,
    required this.value,
    required this.maxValue,
    this.status,
  });

  final String text;
  final int value;
  final int maxValue;
  final LocalMatchingStatus? status;
}

/// 本地匹配运行参数。
class LocalMatchRunOptions {
  LocalMatchRunOptions({
    required this.saveMode,
    required this.fileNameMode,
    required this.saveToTagMode,
    required this.lyricsFormat,
    required List<String> langs,
    required this.minScore,
    required List<Source> sources,
    required this.skipExistingLyrics,
    this.saveRootPath,
    this.fileNameFormat = '%<artist> - %<title> (%<id>)',
    this.skipInstLyrics = true,
    this.id3Version = Id3Version.v23,
    LyricsConvertOptions? convertOptions,
  }) : langs = List<String>.unmodifiable(langs),
       sources = List<Source>.unmodifiable(sources),
       convertOptions = convertOptions ?? LyricsConvertOptions();

  final LocalMatchSaveMode saveMode;
  final LocalMatchFileNameMode fileNameMode;
  final LocalMatchSaveToTagMode saveToTagMode;
  final LyricsFormat lyricsFormat;
  final List<String> langs;
  final double minScore;
  final List<Source> sources;
  final bool skipExistingLyrics;
  final String? saveRootPath;
  final String fileNameFormat;
  final bool skipInstLyrics;
  final Id3Version id3Version;
  final LyricsConvertOptions convertOptions;
}

/// 本地匹配运行结果。
class LocalMatchResult {
  LocalMatchResult({
    required this.total,
    required this.successCount,
    required this.failCount,
    required this.skipCount,
    required this.cancelled,
    required List<LocalMatchingStatus> statuses,
  }) : statuses = List<LocalMatchingStatus>.unmodifiable(statuses);

  final int total;
  final int successCount;
  final int failCount;
  final int skipCount;
  final bool cancelled;
  final List<LocalMatchingStatus> statuses;
}

/// 取消令牌：`GetInfos` 与 `LocalMatch` 阶段共用。
class LocalMatchCancellationToken {
  bool _cancelled = false;
  final Completer<void> _cancelledCompleter = Completer<void>();

  bool get isCancelled => _cancelled;

  Future<void> get cancelled => _cancelledCompleter.future;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _cancelledCompleter.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const _LocalMatchCancelled();
    }
  }
}

/// 媒体网关：封装“读取音频信息/标签写回”等平台能力。
///
/// 说明：标签写回采用异步接口，便于 Android SAF 等平台能力接入。
abstract interface class LocalMatchMediaGateway {
  Future<List<SongInfo>> readAudioSongInfos(String audioPath);

  Future<int?> readAudioDurationMs(String audioPath);

  Future<bool> hasLyricsTag(String songPath);

  Future<String?> readAudioLyricsText({
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  });

  Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  });
}

/// 本地匹配后台元数据读取端口。
///
/// 桌面端 taglib/FFI 读取可能阻塞 UI isolate；core 只声明“可以异步读取元数据”
/// 这个能力，具体是否使用 isolate、线程或同步实现交给 infra 层决定。
abstract interface class LocalMatchAudioMetadataPort {
  Future<List<SongInfo>> readSongInfos(String songPath);

  Future<int?> readDurationMs(String songPath);
}

/// 标签写回失败异常（用于将失败分类到 `saveFail`）。
class LocalMatchTagWriteException implements Exception {
  const LocalMatchTagWriteException(
    this.message, {
    this.code,
    this.cause,
    this.stackTrace,
    this.songPath,
    this.fileDescriptor,
    this.fileDescriptorNameHint,
    this.context = const <String, Object?>{},
    this.writeResultUnknown = false,
  });

  factory LocalMatchTagWriteException.fromAudioTagException(
    AudioTagException error, {
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) {
    return LocalMatchTagWriteException(
      error.message,
      code: error.code,
      cause: error.cause,
      stackTrace: error.stackTrace,
      songPath: songPath,
      fileDescriptor: fileDescriptor,
      fileDescriptorNameHint: fileDescriptorNameHint,
      context: error.context,
      writeResultUnknown: error.writeResultUnknown,
    );
  }

  final String message;
  final AudioTagErrorCode? code;
  final Object? cause;
  final StackTrace? stackTrace;
  final String? songPath;
  final int? fileDescriptor;
  final String? fileDescriptorNameHint;
  final Map<String, Object?> context;
  final bool writeResultUnknown;

  @override
  String toString() => message;
}

/// 标签读取失败异常（用于区分“无歌词”和“读取异常”）。
class LocalMatchTagReadException implements Exception {
  const LocalMatchTagReadException(
    this.message, {
    this.code,
    this.cause,
    this.stackTrace,
    this.songPath,
    this.fileDescriptor,
    this.fileDescriptorNameHint,
    this.context = const <String, Object?>{},
  });

  factory LocalMatchTagReadException.fromAudioTagException(
    AudioTagException error, {
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) {
    return LocalMatchTagReadException(
      error.message,
      code: error.code,
      cause: error.cause,
      stackTrace: error.stackTrace,
      songPath: songPath,
      fileDescriptor: fileDescriptor,
      fileDescriptorNameHint: fileDescriptorNameHint,
      context: error.context,
    );
  }

  final String message;
  final AudioTagErrorCode? code;
  final Object? cause;
  final StackTrace? stackTrace;
  final String? songPath;
  final int? fileDescriptor;
  final String? fileDescriptorNameHint;
  final Map<String, Object?> context;

  @override
  String toString() => message;
}

typedef LocalMatchGetInfosProgressCallback =
    void Function(LocalMatchGetInfosProgress value);
typedef LocalMatchSongEntryBatchCallback =
    FutureOr<void> Function(List<LocalMatchSongEntry> entries);
typedef LocalMatchProgressCallback = void Function(LocalMatchProgress value);
typedef LocalMatchAutoFetchExecutor =
    Future<AutoFetchResult> Function(AutoFetchRequest request);

final class _LocalMatchCancelled implements Exception {
  const _LocalMatchCancelled();
}

/// 本地匹配阶段一：输入路径解析为 `SongInfo` 队列。
///
/// 对齐Python版 `GetInfosWorker`：
/// 1. 遍历输入目录
/// 2. 先解析 CUE，再解析普通音频
/// 3. 排除 CUE 已覆盖的音频文件
class LocalMatchGetInfosUseCase {
  const LocalMatchGetInfosUseCase({
    required this._mediaGateway,
    this._audioMetadataPort,
  });

  final LocalMatchMediaGateway _mediaGateway;
  final LocalMatchAudioMetadataPort? _audioMetadataPort;

  Future<LocalMatchGetInfosResult> run({
    required List<String> inputPaths,
    LocalMatchCancellationToken? cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
    LocalMatchSongEntryBatchCallback? onEntries,
    bool collectEntries = true,
  }) async {
    final List<String> pathSnapshot = List<String>.unmodifiable(inputPaths);
    final LocalMatchCancellationToken token =
        cancellationToken ?? LocalMatchCancellationToken();

    onProgress?.call(
      const LocalMatchGetInfosProgress(text: '遍历文件...', value: 0, maxValue: 0),
    );

    final List<String> errors = <String>[];
    final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[];
    final List<LocalMatchSongEntry> pendingEntries = <LocalMatchSongEntry>[];
    final Set<String> excludedAudioPaths = <String>{};
    int total = 0;
    int progress = 0;

    Future<void> flushEntries() async {
      if (pendingEntries.isEmpty) {
        return;
      }
      final List<LocalMatchSongEntry> batch =
          List<LocalMatchSongEntry>.unmodifiable(pendingEntries);
      pendingEntries.clear();
      await onEntries?.call(batch);
    }

    Future<void> publishEntries(Iterable<LocalMatchSongEntry> values) async {
      for (final LocalMatchSongEntry entry in values) {
        if (collectEntries) {
          entries.add(entry);
        }
        if (onEntries != null) {
          pendingEntries.add(entry);
          if (pendingEntries.length >= 64) {
            await flushEntries();
          }
        }
      }
    }

    final bool scanCompleted = await streamLocalMatchFiles(
      inputPaths: pathSnapshot,
      cancelled: token.cancelled,
      isCancelled: () => token.isCancelled,
      onEvent: (LocalMatchFileScanEvent event) async {
        switch (event) {
          case LocalMatchFileScanErrors(errors: final scanErrors):
            errors.addAll(scanErrors);
          case LocalMatchFileScanSummary(
            :final cueFileCount,
            :final audioFileCount,
          ):
            total = cueFileCount + audioFileCount;
          case LocalMatchFileScanCueBatch(:final items):
            for (final LocalMatchScannedCue item in items) {
              if (token.isCancelled) {
                return;
              }
              progress += 1;
              onProgress?.call(
                LocalMatchGetInfosProgress(
                  text: '解析cue${item.cueData.path}...',
                  value: progress,
                  maxValue: total,
                ),
              );
              try {
                final Set<String> audioRefs = item.audioPaths
                    .map(_canonicalFilePath)
                    .toSet();
                final Map<String, int?> durations = <String, int?>{};
                for (final String audioPath in item.audioPaths) {
                  if (token.isCancelled) {
                    return;
                  }
                  try {
                    durations[_canonicalFilePath(
                      audioPath,
                    )] = _audioMetadataPort == null
                        ? await _mediaGateway.readAudioDurationMs(audioPath)
                        : await _audioMetadataPort.readDurationMs(audioPath);
                  } on Exception catch (error) {
                    errors.add(
                      '读取 CUE 关联音频时长失败 $audioPath: '
                      '${error.runtimeType}: $error',
                    );
                  }
                }
                if (token.isCancelled) {
                  return;
                }
                bool audioExistsChecker(String audioPath) =>
                    audioRefs.contains(_canonicalFilePath(audioPath));
                final List<SongInfo> songs = item.cueData.toSongInfos(
                  durationResolver: (String audioPath) =>
                      durations[_canonicalFilePath(audioPath)],
                  audioExistsChecker: audioExistsChecker,
                );
                excludedAudioPaths.addAll(audioRefs);
                await publishEntries(
                  songs.map(
                    (SongInfo song) => LocalMatchSongEntry(
                      songInfo: song,
                      rootPath: item.rootPath,
                    ),
                  ),
                );
              } on Exception catch (error) {
                errors.add('${error.runtimeType}: $error');
              }
            }
          case LocalMatchFileScanAudioBatch(:final items):
            for (final LocalMatchScannedAudio item in items) {
              if (token.isCancelled) {
                return;
              }
              progress += 1;
              onProgress?.call(
                LocalMatchGetInfosProgress(
                  text: '解析歌曲文件${item.filePath}...',
                  value: progress,
                  maxValue: total,
                ),
              );
              if (excludedAudioPaths.contains(
                _canonicalFilePath(item.filePath),
              )) {
                continue;
              }
              try {
                final List<SongInfo> songs = _audioMetadataPort == null
                    ? await _mediaGateway.readAudioSongInfos(item.filePath)
                    : await _audioMetadataPort.readSongInfos(item.filePath);
                if (token.isCancelled) {
                  return;
                }
                await publishEntries(
                  songs.map(
                    (SongInfo song) => LocalMatchSongEntry(
                      songInfo: song,
                      rootPath: item.rootPath,
                    ),
                  ),
                );
              } on Exception catch (error) {
                errors.add('${error.runtimeType}: $error');
              }
            }
        }
      },
    );
    await flushEntries();

    onProgress?.call(
      const LocalMatchGetInfosProgress(text: '', value: 0, maxValue: 0),
    );

    return LocalMatchGetInfosResult(
      entries: entries,
      errors: errors,
      cancelled: !scanCompleted || token.isCancelled,
    );
  }
}

/// 本地匹配阶段二：批量自动匹配并保存歌词。
///
/// 对齐Python版 `LocalMatchWorker`：
/// - 支持取消、逐条状态回传
/// - 支持跳过已有歌词与纯音乐
/// - 支持保存到文件/标签（或两者）
class LocalMatchUseCase {
  const LocalMatchUseCase({
    required this._autoFetchExecutor,
    required this._mediaGateway,
  });

  final LocalMatchAutoFetchExecutor _autoFetchExecutor;
  final LocalMatchMediaGateway _mediaGateway;

  Future<LocalMatchResult> run({
    required List<LocalMatchSongEntry> entries,
    required LocalMatchRunOptions options,
    LocalMatchCancellationToken? cancellationToken,
    LyricsSavePersistencePort? lyricsPersistencePort,
    LocalMatchProgressCallback? onProgress,
  }) async {
    final List<LocalMatchSongEntry> entrySnapshot =
        List<LocalMatchSongEntry>.unmodifiable(entries);
    if (options.langs.isEmpty) {
      throw const LddcApiParamsException('本地匹配至少需要选择一种歌词语言');
    }
    if (options.sources.isEmpty) {
      throw const LddcApiParamsException('本地匹配歌词来源不能为空');
    }

    final LocalMatchCancellationToken token =
        cancellationToken ?? LocalMatchCancellationToken();

    final String fileNameFormat = options.fileNameFormat;
    final bool skipInstLyrics = options.skipInstLyrics;

    final int total = entrySnapshot.length;
    int successCount = 0;
    int skipCount = 0;
    LocalMatchingStatus? latestStatus;
    final List<LocalMatchingStatus> statuses = <LocalMatchingStatus>[];

    for (int index = 0; index < entrySnapshot.length; index += 1) {
      if (token.isCancelled) {
        break;
      }

      final LocalMatchSongEntry entry = entrySnapshot[index];
      final SongInfo info = entry.songInfo;
      onProgress?.call(
        LocalMatchProgress(
          text: '正在匹配 ${info.artistTitle(replaceMissing: true)} 的歌词...',
          value: index,
          maxValue: total,
          status: latestStatus,
        ),
      );

      try {
        token.throwIfCancelled();
        if (options.skipExistingLyrics &&
            await _checkSkipExistingLyrics(
              info: info,
              options: options,
              fileNameFormat: fileNameFormat,
              songRootPath: entry.rootPath,
              langs: options.langs,
              lyricsPersistencePort: lyricsPersistencePort,
              cancellationToken: token,
            )) {
          latestStatus = LocalMatchingStatus(
            type: LocalMatchingStatusType.skipExisting,
            index: index,
            text: '跳过已存在的歌词',
          );
          skipCount += 1;
          statuses.add(latestStatus);
          continue;
        }
        token.throwIfCancelled();
        final AutoFetchResult autoFetchResult = await _autoFetchExecutor(
          AutoFetchRequest(
            info: info,
            minScore: options.minScore,
            sources: options.sources,
            shouldCancel: () => token.isCancelled,
          ),
        );
        token.throwIfCancelled();
        final Lyrics lyrics = autoFetchResult.lyrics;

        if (skipInstLyrics && lyrics.isInstrumental()) {
          latestStatus = LocalMatchingStatus(
            type: LocalMatchingStatusType.skipInst,
            index: index,
            text: '跳过纯音乐',
          );
          skipCount += 1;
          statuses.add(latestStatus);
          continue;
        }

        token.throwIfCancelled();
        final String lyricsText = convert2(
          lyrics: lyrics,
          lyricsFormat: options.lyricsFormat,
          langs: options.langs,
          options: options.convertOptions,
        );

        String? savePath;
        bool fileWriteCompleted = false;
        if (info.fromCue ||
            options.saveToTagMode != LocalMatchSaveToTagMode.onlyTag) {
          token.throwIfCancelled();
          final SongInfo persistenceSongInfo = _resolvePersistenceSongInfo(
            localInfo: info,
            matchedSongInfo: autoFetchResult.matchedSongInfo,
            fileNameMode: options.fileNameMode,
          );
          if (lyricsPersistencePort != null) {
            savePath = await lyricsPersistencePort.saveText(
              request: LyricsSaveRequest(
                songInfo: persistenceSongInfo,
                lyricLangs: options.langs,
                lyricsFormat: options.lyricsFormat,
                fileNameFormat: fileNameFormat,
              ),
              text: lyricsText,
            );
          } else {
            final LyricsSavePlan savePlan = LyricsSavePlanner.planLocalMatch(
              directoryMode: _toPlannerDirectoryMode(options.saveMode),
              fileNameMode: _toPlannerFileNameMode(options.fileNameMode),
              localInfo: info,
              lyricsFormat: options.lyricsFormat,
              fileNameFormat: fileNameFormat,
              lyricLangs: options.langs,
              saveRootPath: options.saveRootPath,
              lyricsInfo: autoFetchResult.matchedSongInfo,
              allowLyricsPlaceholder: false,
              songRootPath: entry.rootPath,
            );
            if (!savePlan.isSuccess) {
              latestStatus = LocalMatchingStatus(
                type: LocalMatchingStatusType.saveFail,
                index: index,
                text: '计算歌词保存路径失败',
              );
              statuses.add(latestStatus);
              continue;
            }
            final String targetPath = savePlan.displayPath;
            savePath = await BackgroundFileIo.writeText(
              path: targetPath,
              text: lyricsText,
            );
          }
          fileWriteCompleted = true;
        }

        if ((options.saveToTagMode == LocalMatchSaveToTagMode.onlyTag ||
                options.saveToTagMode == LocalMatchSaveToTagMode.both) &&
            !info.fromCue) {
          // both 模式下文件写入已经产生不可回滚副作用，当前条目继续完成标签写入，
          // 取消从下一条生效；onlyTag 尚未写入任何内容，可以在这里立即中断。
          if (!fileWriteCompleted) {
            token.throwIfCancelled();
          }
          final String? songPath = info.path;
          if (songPath == null || songPath.trim().isEmpty) {
            latestStatus = LocalMatchingStatus(
              type: LocalMatchingStatusType.saveFail,
              index: index,
              text:
                  '没有获取到${info.artistTitle(replaceMissing: true)}的歌曲路径,无法保存到标签',
            );
            statuses.add(latestStatus);
            continue;
          }
          await _mediaGateway.writeLyricsTag(
            songPath: songPath,
            lyricsText: lyricsText,
            lyrics: lyrics,
            // 标签版本属于本次能力调用参数，运行时不读取 LDDC 的全局配置。
            id3Version: options.id3Version,
          );
        }

        latestStatus = LocalMatchingStatus(
          type: LocalMatchingStatusType.success,
          index: index,
          text: '成功',
          path: savePath,
        );
        successCount += 1;
        statuses.add(latestStatus);
      } on LocalMatchTagWriteException catch (error) {
        if (error.writeResultUnknown) {
          token.cancel();
        }
        latestStatus = LocalMatchingStatus(
          type: LocalMatchingStatusType.saveFail,
          index: index,
          text: error.writeResultUnknown ? '保存到标签结果未知' : '保存到标签失败',
        );
        statuses.add(latestStatus);
      } on _LocalMatchCancelled {
        break;
      } on AutoFetchCancelledException {
        token.cancel();
        break;
      } on TimeoutException {
        latestStatus = LocalMatchingStatus(
          type: LocalMatchingStatusType.autoFetchFail,
          index: index,
          text: '匹配超时',
        );
        statuses.add(latestStatus);
      } on LddcLyricsNotFoundException {
        latestStatus = LocalMatchingStatus(
          type: LocalMatchingStatusType.autoFetchFail,
          index: index,
          text: '没有匹配到歌词',
        );
        statuses.add(latestStatus);
      } on FileSystemException {
        latestStatus = LocalMatchingStatus(
          type: LocalMatchingStatusType.saveFail,
          index: index,
          text: '保存失败',
        );
        statuses.add(latestStatus);
      } on IOException {
        latestStatus = LocalMatchingStatus(
          type: LocalMatchingStatusType.saveFail,
          index: index,
          text: '保存失败',
        );
        statuses.add(latestStatus);
      } on Exception catch (error) {
        latestStatus = LocalMatchingStatus(
          type: LocalMatchingStatusType.unknownError,
          index: index,
          text: '未知错误 ${error.runtimeType}: $error',
        );
        statuses.add(latestStatus);
      }
    }

    onProgress?.call(
      LocalMatchProgress(text: '', value: 0, maxValue: 0, status: latestStatus),
    );

    // 对齐Python版完成统计：`fail = total - success - skip`（取消后未处理条目也计入失败）。
    final int failCount = total - successCount - skipCount;
    final bool cancelled =
        token.isCancelled && (successCount + skipCount) < total;
    return LocalMatchResult(
      total: total,
      successCount: successCount,
      failCount: failCount,
      skipCount: skipCount,
      cancelled: cancelled,
      statuses: statuses,
    );
  }

  Future<bool> _checkSkipExistingLyrics({
    required SongInfo info,
    required LocalMatchRunOptions options,
    required String fileNameFormat,
    required String? songRootPath,
    required List<String> langs,
    required LyricsSavePersistencePort? lyricsPersistencePort,
    required LocalMatchCancellationToken cancellationToken,
  }) async {
    final String? songPath = info.path;
    if (options.saveToTagMode != LocalMatchSaveToTagMode.onlyFile) {
      final bool songFileHasLyrics =
          songPath != null && songPath.trim().isNotEmpty
          ? await _mediaGateway.hasLyricsTag(songPath)
          : false;
      if (songFileHasLyrics) {
        return true;
      }
      if (options.saveToTagMode == LocalMatchSaveToTagMode.onlyTag) {
        return false;
      }
      cancellationToken.throwIfCancelled();
    }

    final LyricsSaveRequest request = LyricsSaveRequest(
      songInfo: _resolvePersistenceSongInfo(
        localInfo: info,
        matchedSongInfo: null,
        fileNameMode: options.fileNameMode,
      ),
      lyricLangs: langs,
      lyricsFormat: options.lyricsFormat,
      fileNameFormat: fileNameFormat,
    );
    final bool lyricsFileExists;
    if (lyricsPersistencePort
        case final LyricsSaveExistencePort existencePort) {
      lyricsFileExists = await existencePort.exists(request: request);
    } else {
      final LyricsSavePlan savePlan = LyricsSavePlanner.planLocalMatch(
        directoryMode: _toPlannerDirectoryMode(options.saveMode),
        fileNameMode: _toPlannerFileNameMode(options.fileNameMode),
        localInfo: info,
        lyricsFormat: options.lyricsFormat,
        fileNameFormat: fileNameFormat,
        lyricLangs: langs,
        saveRootPath: options.saveRootPath,
        lyricsInfo: null,
        allowLyricsPlaceholder: false,
        songRootPath: songRootPath,
      );
      lyricsFileExists = savePlan.isSuccess
          // 本地匹配可能在用户启动后连续检查大量目标文件；这里保持异步 IO，
          // 避免把磁盘 stat 压回 UI isolate。Dart lint 面向普通短路径场景，
          // 本批任务链的性能边界以“不阻塞交互线程”为准。
          // ignore: avoid_slow_async_io
          ? await File(savePlan.displayPath).exists()
          : false;
    }
    return lyricsFileExists;
  }

  SongInfo _resolvePersistenceSongInfo({
    required SongInfo localInfo,
    required SongInfo? matchedSongInfo,
    required LocalMatchFileNameMode fileNameMode,
  }) {
    return switch (fileNameMode) {
      LocalMatchFileNameMode.formatByLyrics when matchedSongInfo != null =>
        matchedSongInfo,
      _ => localInfo,
    };
  }
}

LyricsSaveDirectoryMode _toPlannerDirectoryMode(LocalMatchSaveMode mode) {
  return switch (mode) {
    LocalMatchSaveMode.mirror => LyricsSaveDirectoryMode.mirrorSourceRoot,
    LocalMatchSaveMode.song => LyricsSaveDirectoryMode.songDirectory,
    LocalMatchSaveMode.specify => LyricsSaveDirectoryMode.folder,
  };
}

LyricsSaveFileNameMode _toPlannerFileNameMode(LocalMatchFileNameMode mode) {
  return switch (mode) {
    LocalMatchFileNameMode.formatByLyrics =>
      LyricsSaveFileNameMode.templateByLyrics,
    LocalMatchFileNameMode.formatBySong =>
      LyricsSaveFileNameMode.templateBySong,
    LocalMatchFileNameMode.song => LyricsSaveFileNameMode.sourceBasename,
  };
}

/// 保存路径解析结果（成功）。
class LocalMatchSavePathResolved extends LocalMatchSavePathResolution {
  const LocalMatchSavePathResolved(this.path);

  final String path;
}

/// 保存路径解析结果（失败）。
class LocalMatchSavePathError extends LocalMatchSavePathResolution {
  const LocalMatchSavePathError(this.code);

  final int code;
}

/// 保存路径解析结果基类。
sealed class LocalMatchSavePathResolution {
  const LocalMatchSavePathResolution();
}

/// 路径占位符与保存路径计算器，对齐Python版 `get_local_match_save_path`。
class LocalMatchSavePathResolver {
  const LocalMatchSavePathResolver._();

  static LocalMatchSavePathResolution resolve({
    required LocalMatchSaveMode saveMode,
    required LocalMatchFileNameMode fileNameMode,
    required SongInfo localInfo,
    required LyricsFormat lyricsFormat,
    required String fileNameFormat,
    required List<String> langs,
    required String? saveRootPath,
    required SongInfo? cloudInfo,
    required bool allowPlaceholder,
    required String? songRootPath,
  }) {
    final LyricsSavePlan plan = LyricsSavePlanner.planLocalMatch(
      directoryMode: _toPlannerDirectoryMode(saveMode),
      fileNameMode: _toPlannerFileNameMode(fileNameMode),
      localInfo: localInfo,
      lyricsFormat: lyricsFormat,
      fileNameFormat: fileNameFormat,
      lyricLangs: langs,
      saveRootPath: saveRootPath,
      lyricsInfo: cloudInfo,
      allowLyricsPlaceholder: allowPlaceholder,
      songRootPath: songRootPath,
    );
    if (plan.isSuccess) {
      return LocalMatchSavePathResolved(plan.displayPath);
    }
    return LocalMatchSavePathError(_legacySavePathErrorCode(plan.errorCode));
  }
}

int _legacySavePathErrorCode(LyricsSavePlanErrorCode? code) {
  return switch (code) {
    LyricsSavePlanErrorCode.missingSaveRoot => -1,
    LyricsSavePlanErrorCode.missingLyricsInfo => -2,
    LyricsSavePlanErrorCode.missingSongRoot => -3,
    LyricsSavePlanErrorCode.missingSongPath => -4,
    LyricsSavePlanErrorCode.songOutsideRoot => -4,
    null => -4,
  };
}

String _canonicalFilePath(String input) {
  final String normalized = p.normalize(p.absolute(input));
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
