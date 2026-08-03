import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../audio_tag/audio_tag_port.dart';
import '../task/local_match_usecase.dart';
import 'audio_tag_metadata_mapper.dart';
import 'dart_taglib_audio_tag_port.dart';

/// 本地匹配后台元数据读取实现。
///
/// Provider 注入这个端口后，扫描大量本地音频时不会在 UI isolate 上同步调用 FFI。
final class AudioTagBackgroundMetadataPort
    implements LocalMatchAudioMetadataPort {
  const AudioTagBackgroundMetadataPort();

  @override
  Future<List<SongInfo>> readSongInfos(String songPath) {
    return AudioTagBackgroundExecutor.readSongInfos(songPath);
  }

  @override
  Future<int?> readDurationMs(String songPath) {
    return AudioTagBackgroundExecutor.readDurationMs(songPath);
  }
}

/// 后台音频标签 worker runner。
///
/// 生产实现使用可控 isolate；测试可替换 runner 来稳定覆盖超时、kill 和写入临界区
/// 这些很难用真实 taglib 触发的边界。
abstract interface class AudioTagBackgroundWorkerRunner {
  Future<Object?> runRead({
    required String operation,
    required Map<String, Object?> payload,
    required Duration timeout,
  });

  Future<void> runWrite({
    required Map<String, Object?> payload,
    required Duration timeout,
  });
}

/// 桌面音频标签后台执行入口。
///
/// 同步 taglib/FFI 调用会长时间占用 UI isolate，这里统一后移到后台。
final class AudioTagBackgroundExecutor {
  AudioTagBackgroundExecutor._();

  static const Duration _readTimeout = Duration(seconds: 12);
  static const Duration _writeTimeout = Duration(seconds: 20);
  static const AudioTagMetadataMapper _metadataMapper =
      AudioTagMetadataMapper();
  static AudioTagBackgroundWorkerRunner _workerRunner =
      const _IsolateAudioTagBackgroundWorkerRunner();

  static void debugSetWorkerRunnerForTest(
    AudioTagBackgroundWorkerRunner runner,
  ) {
    _workerRunner = runner;
  }

  static void debugResetWorkerRunnerForTest() {
    _workerRunner = const _IsolateAudioTagBackgroundWorkerRunner();
  }

  static bool supportsBackgroundPath(String songPath, {int? fileDescriptor}) {
    return (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        fileDescriptor == null &&
        !songPath.startsWith('content://') &&
        (songPath.isNotEmpty);
  }

  static Future<List<SongInfo>> readSongInfos(String songPath) async {
    final Object? result = await _workerRunner.runRead(
      operation: 'readSongInfos',
      payload: <String, Object?>{'songPath': songPath},
      timeout: _readTimeout,
    );
    final List<Object?> rawInfos = List<Object?>.from(result! as List<Object?>);
    return rawInfos
        .map<SongInfo>(
          (Object? info) =>
              SongInfo.fromMap(Map<String, Object?>.from(info! as Map)),
        )
        .toList(growable: false);
  }

  static Future<int?> readDurationMs(String songPath) async {
    final Object? result = await _workerRunner.runRead(
      operation: 'readDurationMs',
      payload: <String, Object?>{'songPath': songPath},
      timeout: _readTimeout,
    );
    return result as int?;
  }

  static Future<bool> hasLyricsTag(String songPath) async {
    final Object? result = await _workerRunner.runRead(
      operation: 'hasLyricsTag',
      payload: <String, Object?>{'songPath': songPath},
      timeout: _readTimeout,
    );
    return result == true;
  }

  static Future<String?> readLyricsText(String songPath) async {
    final Object? result = await _workerRunner.runRead(
      operation: 'readLyricsText',
      payload: <String, Object?>{'songPath': songPath},
      timeout: _readTimeout,
    );
    return result as String?;
  }

  static Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
  }) async {
    final Map<String, Object?> payload = _serializeWriteRequest(
      songPath: songPath,
      lyricsText: lyricsText,
      lyrics: lyrics,
      id3Version: id3Version,
    );
    await _workerRunner.runWrite(payload: payload, timeout: _writeTimeout);
  }

  static Map<String, Object?> _serializeWriteRequest({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
  }) {
    return <String, Object?>{
      'songPath': songPath,
      'lyricsText': lyricsText,
      'id3Version': id3Version.value,
      'tagLyrics': _serializeLyricsForTagWrite(lyrics),
    };
  }

  static AudioTagWriteRequest _deserializeWriteRequest(
    Map<String, Object?> payload, {
    void Function()? onSaveCriticalSectionEntered,
  }) {
    return AudioTagWriteRequest(
      songPath: payload['songPath']! as String,
      plainLyricsText: payload['lyricsText']! as String,
      lyrics: _deserializeLyricsForTagWrite(
        songPath: payload['songPath']! as String,
        payload: Map<String, Object?>.from(
          payload['tagLyrics']! as Map<Object?, Object?>,
        ),
      ),
      id3Version: payload['id3Version'] == Id3Version.v24.value
          ? Id3Version.v24
          : Id3Version.v23,
      onSaveCriticalSectionEntered: onSaveCriticalSectionEntered,
    );
  }

  static Map<String, Object?> _serializeLyricsForTagWrite(Lyrics lyrics) {
    final LyricsData orig = lyrics['orig'] ?? const <LyricsLine>[];
    return <String, Object?>{
      // 后台写标签只需要 orig 的逐字时间轴来生成 SYLT。
      // 不再跨 isolate 搬运完整 Lyrics，避免把翻译/罗马音/标签元数据全部序列化。
      'orig': orig.map<Map<String, Object?>>(_serializeLine).toList(),
    };
  }

  static Lyrics _deserializeLyricsForTagWrite({
    required String songPath,
    required Map<String, Object?> payload,
  }) {
    final List<Object?> rawOrig = List<Object?>.from(
      payload['orig']! as List<Object?>,
    );
    final LyricsData orig = rawOrig
        .map<LyricsLine>(
          (Object? item) => _deserializeLine(
            Map<String, Object?>.from(item! as Map<Object?, Object?>),
          ),
        )
        .toList(growable: false);
    return Lyrics(
      songInfo: SongInfo(source: Source.local, path: songPath),
      source: Source.local,
      data: <String, LyricsData>{'orig': orig},
      types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
    );
  }

  static Map<String, Object?> _serializeLine(LyricsLine line) {
    return <String, Object?>{
      'startMs': line.startMs,
      'endMs': line.endMs,
      'words': line.words
          .map<Map<String, Object?>>(_serializeWord)
          .toList(growable: false),
    };
  }

  static LyricsLine _deserializeLine(Map<String, Object?> payload) {
    return LyricsLine(
      startMs: payload['startMs'] as int?,
      endMs: payload['endMs'] as int?,
      words: (payload['words']! as List<Object?>)
          .map<LyricsWord>(
            (Object? item) => _deserializeWord(
              Map<String, Object?>.from(item! as Map<Object?, Object?>),
            ),
          )
          .toList(growable: false),
    );
  }

  static Map<String, Object?> _serializeWord(LyricsWord word) {
    return <String, Object?>{
      'startMs': word.startMs,
      'endMs': word.endMs,
      'text': word.text,
    };
  }

  static LyricsWord _deserializeWord(Map<String, Object?> payload) {
    return LyricsWord(
      startMs: payload['startMs'] as int?,
      endMs: payload['endMs'] as int?,
      text: payload['text']! as String,
    );
  }
}

final class _IsolateAudioTagBackgroundWorkerRunner
    implements AudioTagBackgroundWorkerRunner {
  const _IsolateAudioTagBackgroundWorkerRunner();

  @override
  Future<Object?> runRead({
    required String operation,
    required Map<String, Object?> payload,
    required Duration timeout,
  }) {
    return _runWorker(
      operation: operation,
      payload: payload,
      timeout: timeout,
      isWrite: false,
    );
  }

  @override
  Future<void> runWrite({
    required Map<String, Object?> payload,
    required Duration timeout,
  }) async {
    await _runWorker(
      operation: 'writeLyricsTag',
      payload: payload,
      timeout: timeout,
      isWrite: true,
    );
  }

  Future<Object?> _runWorker({
    required String operation,
    required Map<String, Object?> payload,
    required Duration timeout,
    required bool isWrite,
  }) async {
    final ReceivePort resultPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final Completer<Object?> completer = Completer<Object?>();
    late final Isolate isolate;
    Timer? timeoutTimer;
    StreamSubscription<Object?>? resultSubscription;
    StreamSubscription<Object?>? errorSubscription;
    StreamSubscription<Object?>? exitSubscription;
    bool enteredWriteCriticalSection = false;
    bool detachRunningWriteWorker = false;

    void completeErrorOnce(Object error, [StackTrace? stackTrace]) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }

    void completeOnce(Object? value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }

    Future<void> cleanup() async {
      timeoutTimer?.cancel();
      await resultSubscription?.cancel();
      await errorSubscription?.cancel();
      await exitSubscription?.cancel();
      resultPort.close();
      errorPort.close();
      exitPort.close();
    }

    isolate = await Isolate.spawn<Map<String, Object?>>(
      _audioTagWorkerMain,
      <String, Object?>{
        'replyPort': resultPort.sendPort,
        'operation': operation,
        'payload': payload,
      },
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
      errorsAreFatal: true,
    );

    timeoutTimer = Timer(timeout, () {
      if (isWrite && enteredWriteCriticalSection) {
        detachRunningWriteWorker = true;
        completeErrorOnce(
          AudioTagException(
            code: AudioTagErrorCode.writeFailed,
            message: '后台写入歌词标签超时，写入结果未知: ${payload['songPath']}',
            cause: TimeoutException('后台写入歌词标签超时', timeout),
            context: <String, Object?>{
              'songPath': payload['songPath'],
              'phase': 'saveCriticalSection',
            },
            writeResultUnknown: true,
          ),
        );
        return;
      }
      isolate.kill(priority: Isolate.immediate);
      completeErrorOnce(
        TimeoutException(
          isWrite
              ? '后台写入歌词标签超时: ${payload['songPath']}'
              : '后台读取音频标签超时: ${payload['songPath']}',
          timeout,
        ),
      );
    });

    resultSubscription = resultPort.listen((Object? message) {
      if (message is! Map) {
        completeErrorOnce(StateError('音频标签 worker 返回了未知消息'));
        return;
      }
      final Map<String, Object?> map = Map<String, Object?>.from(message);
      switch (map['type']) {
        case 'saveCriticalSection':
          enteredWriteCriticalSection = true;
        case 'result':
          completeOnce(map['value']);
        case 'error':
          completeErrorOnce(_deserializeWorkerError(map));
        default:
          completeErrorOnce(StateError('音频标签 worker 返回了未知类型: ${map['type']}'));
      }
    });
    errorSubscription = errorPort.listen((Object? error) {
      completeErrorOnce(StateError('音频标签 worker 异常退出: $error'));
    });
    exitSubscription = exitPort.listen((Object? _) {
      if (!completer.isCompleted) {
        completeErrorOnce(StateError('音频标签 worker 未返回结果就退出'));
      }
    });

    try {
      return await completer.future;
    } finally {
      // 写入临界区超时后不 kill isolate，让 native save 自行收尾；当前 isolate 与
      // 监听端口解耦，避免批量任务继续等待一个结果未知的文件。
      if (!detachRunningWriteWorker) {
        isolate.kill(priority: Isolate.beforeNextEvent);
      }
      await cleanup();
    }
  }

  Object _deserializeWorkerError(Map<String, Object?> map) {
    final String? codeValue = map['code'] as String?;
    if (codeValue != null) {
      final AudioTagErrorCode code = AudioTagErrorCode.values.firstWhere(
        (AudioTagErrorCode item) => item.name == codeValue,
        orElse: () => AudioTagErrorCode.readFailed,
      );
      return AudioTagException(
        code: code,
        message: map['message']?.toString() ?? '音频标签 worker 失败',
        cause: map['cause'],
        stackTrace: map['stackTrace'] == null
            ? null
            : StackTrace.fromString(map['stackTrace'].toString()),
      );
    }
    return StateError(map['message']?.toString() ?? '音频标签 worker 失败');
  }
}

void _audioTagWorkerMain(Map<String, Object?> args) {
  final SendPort replyPort = args['replyPort']! as SendPort;
  final String operation = args['operation']! as String;
  final Map<String, Object?> payload = Map<String, Object?>.from(
    args['payload']! as Map<Object?, Object?>,
  );
  final DartTaglibAudioTagPort port = DartTaglibAudioTagPort();
  try {
    final String songPath = payload['songPath']! as String;
    switch (operation) {
      case 'readSongInfos':
        final AudioTagMeta meta = port.readMeta(songPath);
        replyPort.send(<String, Object?>{
          'type': 'result',
          'value': <Map<String, Object?>>[
            AudioTagBackgroundExecutor._metadataMapper
                .toSongInfo(songPath: songPath, meta: meta)
                .toMap(),
          ],
        });
      case 'readDurationMs':
        replyPort.send(<String, Object?>{
          'type': 'result',
          'value': port.readMeta(songPath).durationMs,
        });
      case 'hasLyricsTag':
        replyPort.send(<String, Object?>{
          'type': 'result',
          'value': port.readLyrics(songPath).hasLyrics,
        });
      case 'readLyricsText':
        replyPort.send(<String, Object?>{
          'type': 'result',
          'value': port.readLyrics(songPath).plainText,
        });
      case 'writeLyricsTag':
        port.writeLyrics(
          AudioTagBackgroundExecutor._deserializeWriteRequest(
            payload,
            onSaveCriticalSectionEntered: () {
              replyPort.send(<String, Object?>{'type': 'saveCriticalSection'});
            },
          ),
        );
        replyPort.send(<String, Object?>{'type': 'result'});
      default:
        throw StateError('未知音频标签 worker 操作: $operation');
    }
  } on AudioTagException catch (error) {
    replyPort.send(<String, Object?>{
      'type': 'error',
      'code': error.code.name,
      'message': error.message,
      'cause': error.cause?.toString(),
      'stackTrace': error.stackTrace?.toString(),
    });
  } catch (error, stackTrace) {
    replyPort.send(<String, Object?>{
      'type': 'error',
      'message': '${error.runtimeType}: $error',
      'stackTrace': stackTrace.toString(),
    });
  }
}
