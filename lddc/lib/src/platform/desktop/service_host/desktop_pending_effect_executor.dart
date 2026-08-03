import 'dart:io';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../../core/library_link/library_link.dart';
import '../../../core/logging/logging.dart';
import 'desktop_service_coordinator.dart';
import 'desktop_session_reducer.dart';

const String _autoFetchTaskKey = 'auto_fetch';
final AppLogger _pendingEffectLogger = AppLogger.scope('pending-effect');

/// 挂起 effect 执行后的跟进动作。
sealed class DesktopPendingEffectFollowUp {
  const DesktopPendingEffectFollowUp();
}

/// 远端歌词 JSON 已成功落盘。
class DesktopRemoteLyricsSavedFollowUp extends DesktopPendingEffectFollowUp {
  const DesktopRemoteLyricsSavedFollowUp({
    required this.instanceId,
    required this.lyricsPath,
    required this.lyricsRevision,
  });

  final int instanceId;
  final String lyricsPath;
  final int lyricsRevision;
}

/// 关联库查询 / 本地歌词加载完成后的后续动作。
class DesktopLibraryLinkResolvedFollowUp extends DesktopPendingEffectFollowUp {
  const DesktopLibraryLinkResolvedFollowUp({
    required this.instanceId,
    required this.song,
    required this.selectionRevision,
    this.libraryLink,
    this.linkedLyrics,
    this.lyricsPath,
    this.skipLinkedLyricsLoad = false,
  });

  final int instanceId;
  final SongInfo song;
  final int selectionRevision;
  final LibraryLinkItem? libraryLink;
  final Lyrics? linkedLyrics;
  final String? lyricsPath;
  final bool skipLinkedLyricsLoad;
}

/// 自动获取完成后的后续动作。
class DesktopAutoFetchResolvedFollowUp extends DesktopPendingEffectFollowUp {
  const DesktopAutoFetchResolvedFollowUp({
    required this.instanceId,
    required this.song,
    required this.selectionRevision,
    this.result,
    this.errorMessage,
    this.treatAsInstrumental = false,
  });

  final int instanceId;
  final SongInfo song;
  final int selectionRevision;
  final AutoFetchResult? result;
  final String? errorMessage;
  final bool treatAsInstrumental;
}

/// 延时恢复默认 `artist-title` 文本。
class DesktopRestoreArtistTitleFollowUp extends DesktopPendingEffectFollowUp {
  const DesktopRestoreArtistTitleFollowUp({
    required this.instanceId,
    required this.song,
    required this.lyricsRevision,
  });

  final int instanceId;
  final SongInfo song;
  final int lyricsRevision;
}

/// 一次挂起 effect 执行结果。
class DesktopPendingEffectExecutionResult {
  const DesktopPendingEffectExecutionResult({
    required this.instanceId,
    this.followUps = const <DesktopPendingEffectFollowUp>[],
    this.unhandledEffects = const <DesktopSessionEffect>[],
  });

  final int instanceId;
  final List<DesktopPendingEffectFollowUp> followUps;
  final List<DesktopSessionEffect> unhandledEffects;
}

/// 执行桌面主机待处理的 IO effect。
///
/// 当前只接两类已进入主线的持久化动作：
/// - 远端歌词另存为 JSON；
/// - 关联库写回；
/// 其他 effect 透传给上层协调器处理，executor 不吞掉未知动作，便于调用方保留
/// 明确的重试、降级或日志策略。
final class DesktopPendingEffectExecutor {
  DesktopPendingEffectExecutor({
    required LibraryLinkRepository libraryLinkRepository,
    required DesktopLinkedLyricsLoader loadLinkedLyrics,
    required DesktopAutoFetchRunner runAutoFetch,
    DesktopAutoSaveDirectoryResolver? resolveAutoSaveDirectory,
    LyricsSavePersistencePort Function(String folder)?
    fileSavePersistenceFactory,
  }) : _libraryLinkRepository = libraryLinkRepository,
       _loadLinkedLyrics = loadLinkedLyrics,
       _runAutoFetch = runAutoFetch,
       _resolveAutoSaveDirectory =
           resolveAutoSaveDirectory ?? _missingAutoSaveDirectoryResolver,
       _fileSavePersistenceFactory =
           fileSavePersistenceFactory ?? _missingFileSavePersistenceFactory;

  final LibraryLinkRepository _libraryLinkRepository;
  final DesktopLinkedLyricsLoader _loadLinkedLyrics;
  final DesktopAutoFetchRunner _runAutoFetch;
  final DesktopAutoSaveDirectoryResolver _resolveAutoSaveDirectory;
  final LyricsSavePersistencePort Function(String folder)
  _fileSavePersistenceFactory;
  final Map<(int, String), int> _taskGenerations = <(int, String), int>{};
  bool _disposed = false;

  static final RegExp _instrumentalTitlePattern = RegExp(
    r'伴奏|纯音乐|inst\.?(?:rumental)|off ?vocal(?: ?[Vv]er.)?',
    caseSensitive: false,
  );

  Future<DesktopPendingEffectExecutionResult> executeBatch(
    DesktopPendingEffectBatch batch,
  ) async {
    if (_disposed) {
      throw StateError('DesktopPendingEffectExecutor 已释放');
    }
    final List<DesktopPendingEffectFollowUp> followUps =
        <DesktopPendingEffectFollowUp>[];
    final List<DesktopSessionEffect> unhandledEffects =
        <DesktopSessionEffect>[];

    for (final DesktopSessionEffect effect in batch.effects) {
      switch (effect) {
        case DesktopClearTaskEffect():
          _incrementTaskGeneration(batch.instanceId, effect.taskKey);
          break;
        case DesktopQueryLibraryLinkEffect():
          followUps.add(
            DesktopLibraryLinkResolvedFollowUp(
              instanceId: batch.instanceId,
              song: effect.song,
              selectionRevision: effect.selectionRevision,
              libraryLink: await _libraryLinkRepository.query(effect.song),
            ),
          );
          break;
        case DesktopLoadLinkedLyricsEffect():
          followUps.add(
            await _loadLibraryLyricsFollowUp(
              instanceId: batch.instanceId,
              song: effect.song,
              lyricsPath: effect.lyricsPath,
              selectionRevision: effect.selectionRevision,
            ),
          );
          break;
        case DesktopStartAutoFetchEffect():
          final DesktopAutoFetchResolvedFollowUp? followUp =
              await _runAutoFetchFollowUp(
                instanceId: batch.instanceId,
                request: effect.request,
                selectionRevision: effect.selectionRevision,
              );
          if (followUp != null) {
            followUps.add(followUp);
          }
          break;
        case DesktopRestoreArtistTitleEffect():
          final DesktopRestoreArtistTitleFollowUp? followUp =
              await _scheduleRestoreArtistTitleFollowUp(
                instanceId: batch.instanceId,
                effect: effect,
              );
          if (followUp != null) {
            followUps.add(followUp);
          }
          break;
        case DesktopSaveRemoteLyricsEffect():
          try {
            followUps.add(
              DesktopRemoteLyricsSavedFollowUp(
                instanceId: batch.instanceId,
                lyricsPath: await _saveRemoteLyrics(effect),
                lyricsRevision: effect.lyricsRevision,
              ),
            );
          } on Exception catch (error, stackTrace) {
            _pendingEffectLogger.info(
              'save remote lyrics failed instance=${batch.instanceId}'
              ' error=$error stack=$stackTrace',
            );
          }
          break;
        case DesktopPersistLibraryLinkEffect():
          await _persistLibraryLink(effect);
          break;
        default:
          unhandledEffects.add(effect);
      }
    }

    return DesktopPendingEffectExecutionResult(
      instanceId: batch.instanceId,
      followUps: followUps,
      unhandledEffects: unhandledEffects,
    );
  }

  void clearInstance(int instanceId) {
    _taskGenerations.removeWhere(
      ((int, String) key, _) => key.$1 == instanceId,
    );
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _taskGenerations.clear();
  }

  Future<void> _persistLibraryLink(DesktopPersistLibraryLinkEffect effect) {
    return _libraryLinkRepository.setSong(
      song: effect.song,
      lyricsPath: effect.lyricsPath,
      configSnapshot: effect.configSnapshot,
    );
  }

  Future<DesktopLibraryLinkResolvedFollowUp> _loadLibraryLyricsFollowUp({
    required int instanceId,
    required SongInfo song,
    required String lyricsPath,
    required int selectionRevision,
  }) async {
    try {
      final Lyrics lyrics = await _loadLinkedLyrics(lyricsPath);
      return DesktopLibraryLinkResolvedFollowUp(
        instanceId: instanceId,
        song: song,
        selectionRevision: selectionRevision,
        linkedLyrics: lyrics,
        lyricsPath: lyricsPath,
      );
    } on Exception {
      return DesktopLibraryLinkResolvedFollowUp(
        instanceId: instanceId,
        song: song,
        selectionRevision: selectionRevision,
        skipLinkedLyricsLoad: true,
      );
    }
  }

  Future<DesktopAutoFetchResolvedFollowUp?> _runAutoFetchFollowUp({
    required int instanceId,
    required AutoFetchRequest request,
    required int selectionRevision,
  }) async {
    // 每次启动都占用新代际，使同一实例后发的自动获取天然覆盖先发任务。
    // generation 从 1 开始后，clearInstance 删除键得到的默认值 0 也能可靠
    // 使仍在等待网络响应的首次任务失效。
    final int generation = _incrementTaskGeneration(
      instanceId,
      _autoFetchTaskKey,
    );
    try {
      final AutoFetchResult result = await _runAutoFetch(request);
      if (!_isTaskGenerationCurrent(
        instanceId: instanceId,
        taskKey: _autoFetchTaskKey,
        generation: generation,
      )) {
        return null;
      }
      return DesktopAutoFetchResolvedFollowUp(
        instanceId: instanceId,
        song: request.info,
        selectionRevision: selectionRevision,
        result: result,
      );
    } on Exception catch (error) {
      if (!_isTaskGenerationCurrent(
        instanceId: instanceId,
        taskKey: _autoFetchTaskKey,
        generation: generation,
      )) {
        return null;
      }
      return DesktopAutoFetchResolvedFollowUp(
        instanceId: instanceId,
        song: request.info,
        selectionRevision: selectionRevision,
        errorMessage: error.toString(),
        treatAsInstrumental: _instrumentalTitlePattern.hasMatch(
          request.info.title ?? '',
        ),
      );
    }
  }

  Future<DesktopRestoreArtistTitleFollowUp?>
  _scheduleRestoreArtistTitleFollowUp({
    required int instanceId,
    required DesktopRestoreArtistTitleEffect effect,
  }) async {
    final int generation = _incrementTaskGeneration(instanceId, effect.taskKey);
    await Future<void>.delayed(Duration(milliseconds: effect.delayMs));
    if (!_isTaskGenerationCurrent(
      instanceId: instanceId,
      taskKey: effect.taskKey,
      generation: generation,
    )) {
      return null;
    }
    return DesktopRestoreArtistTitleFollowUp(
      instanceId: instanceId,
      song: effect.song,
      lyricsRevision: effect.lyricsRevision,
    );
  }

  Future<String> _saveRemoteLyrics(DesktopSaveRemoteLyricsEffect effect) async {
    final Directory autoSaveDir = await _resolveAutoSaveDirectory();
    await autoSaveDir.create(recursive: true);
    final LyricsSavePersistencePort persistence = _fileSavePersistenceFactory(
      autoSaveDir.path,
    );
    return persistence.saveText(
      request: LyricsSaveRequest(
        songInfo: effect.lyrics.songInfo,
        lyricLangs: effect.lyrics.data.keys.toList(growable: false),
        lyricsFormat: LyricsFormat.json,
        fileNameFormat: _normalizeFileNameFormat(effect.suggestedFileName),
      ),
      text: convert2(lyrics: effect.lyrics, lyricsFormat: LyricsFormat.json),
    );
  }

  String _normalizeFileNameFormat(String suggestedFileName) {
    final String trimmed = suggestedFileName.trim();
    if (trimmed.isEmpty) {
      return 'lyrics';
    }
    if (trimmed.endsWith(LyricsFormat.json.ext)) {
      return trimmed.substring(
        0,
        trimmed.length - LyricsFormat.json.ext.length,
      );
    }
    return trimmed;
  }

  int _incrementTaskGeneration(int instanceId, String taskKey) {
    final (int, String) key = (instanceId, taskKey);
    final int nextGeneration = (_taskGenerations[key] ?? 0) + 1;
    _taskGenerations[key] = nextGeneration;
    return nextGeneration;
  }

  int _taskGeneration(int instanceId, String taskKey) {
    return _taskGenerations[(instanceId, taskKey)] ?? 0;
  }

  bool _isTaskGenerationCurrent({
    required int instanceId,
    required String taskKey,
    required int generation,
  }) {
    return !_disposed && _taskGeneration(instanceId, taskKey) == generation;
  }
}

typedef DesktopLinkedLyricsLoader = Future<Lyrics> Function(String lyricsPath);
typedef DesktopAutoFetchRunner =
    Future<AutoFetchResult> Function(AutoFetchRequest request);
typedef DesktopAutoSaveDirectoryResolver = Future<Directory> Function();

Future<Directory> _missingAutoSaveDirectoryResolver() async {
  // 自动保存目录是宿主路径策略，必须由 app 组合根注入。保留按需失败可以让只
  // 处理查询/自动获取的轻量测试和消费者无需伪造文件系统对象。
  throw StateError('DesktopPendingEffectExecutor 未注入自动保存目录解析器');
}

LyricsSavePersistencePort _missingFileSavePersistenceFactory(String folder) {
  // 保存实现属于 infra 层，platform 层不能自行创建具体持久化对象。只有真正执行
  // 远端歌词保存时才失败，使不涉及保存的 effect 测试仍可只注入其所需端口。
  throw StateError('DesktopPendingEffectExecutor 未注入歌词保存持久化工厂');
}
