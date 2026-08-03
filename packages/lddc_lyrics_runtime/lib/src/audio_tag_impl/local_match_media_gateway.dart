import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../audio_tag/audio_tag_port.dart';
import '../task/task.dart';
import 'audio_tag_background_executor.dart';
import 'audio_tag_metadata_mapper.dart';
import 'dart_taglib_audio_tag_port.dart';

/// 基于 `AudioTagPort` 的本地匹配媒体网关实现。
class LocalMatchMediaGatewayImpl implements LocalMatchMediaGateway {
  LocalMatchMediaGatewayImpl({
    AudioTagPort? audioTagPort,
    AndroidSafFdPort? androidSafFdPort,
    this._metadataMapper = const AudioTagMetadataMapper(),
  }) : _audioTagPort = audioTagPort ?? DartTaglibAudioTagPort(),
       _androidSafFdPort = androidSafFdPort ?? const _UnsupportedSafFdPort(),
       _useBackgroundForFilePaths = audioTagPort == null;

  final AudioTagPort _audioTagPort;
  final AndroidSafFdPort _androidSafFdPort;
  final AudioTagMetadataMapper _metadataMapper;
  final bool _useBackgroundForFilePaths;

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async {
    if (_useBackgroundForFilePaths &&
        AudioTagBackgroundExecutor.supportsBackgroundPath(audioPath)) {
      return AudioTagBackgroundExecutor.readSongInfos(audioPath);
    }
    final AudioTagMeta meta = _audioTagPort.readMeta(audioPath);
    return <SongInfo>[
      _metadataMapper.toSongInfo(songPath: audioPath, meta: meta),
    ];
  }

  @override
  Future<int?> readAudioDurationMs(String audioPath) async {
    if (_useBackgroundForFilePaths &&
        AudioTagBackgroundExecutor.supportsBackgroundPath(audioPath)) {
      return AudioTagBackgroundExecutor.readDurationMs(audioPath);
    }
    return _audioTagPort.readMeta(audioPath).durationMs;
  }

  @override
  Future<bool> hasLyricsTag(String songPath) async {
    int? resolvedFileDescriptor;
    String? resolvedFileDescriptorNameHint;
    bool shouldCloseResolvedFileDescriptor = false;
    try {
      if (_useBackgroundForFilePaths &&
          AudioTagBackgroundExecutor.supportsBackgroundPath(songPath)) {
        return await AudioTagBackgroundExecutor.hasLyricsTag(songPath);
      }
      if (_isContentUri(songPath)) {
        final AndroidSafOpenedFileDescriptor opened = await _androidSafFdPort
            .openReadOnlyFd(songPath);
        resolvedFileDescriptor = opened.fileDescriptor;
        resolvedFileDescriptorNameHint = opened.nameHint;
        shouldCloseResolvedFileDescriptor = true;
      }
      final AudioTagLyricsPayload payload = _audioTagPort.readLyrics(
        songPath,
        fileDescriptor: resolvedFileDescriptor,
        fileDescriptorNameHint: resolvedFileDescriptorNameHint,
      );
      return payload.hasLyrics;
    } on AudioTagException {
      return false;
    } on Exception {
      return false;
    } finally {
      if (shouldCloseResolvedFileDescriptor && resolvedFileDescriptor != null) {
        try {
          await _androidSafFdPort.closeFd(resolvedFileDescriptor);
        } catch (_) {
          // 读取已有歌词失败时默认“不跳过”，但 fd 关闭仍然尽力执行，避免 SAF 句柄泄漏。
        }
      }
    }
  }

  @override
  Future<String?> readAudioLyricsText({
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    int? resolvedFileDescriptor = fileDescriptor;
    String? resolvedFileDescriptorNameHint = fileDescriptorNameHint;
    bool shouldCloseResolvedFileDescriptor = false;
    try {
      if (_useBackgroundForFilePaths &&
          AudioTagBackgroundExecutor.supportsBackgroundPath(
            songPath,
            fileDescriptor: resolvedFileDescriptor,
          )) {
        return await AudioTagBackgroundExecutor.readLyricsText(songPath);
      }
      if (resolvedFileDescriptor == null && _isContentUri(songPath)) {
        final AndroidSafOpenedFileDescriptor opened = await _androidSafFdPort
            .openReadOnlyFd(songPath);
        resolvedFileDescriptor = opened.fileDescriptor;
        resolvedFileDescriptorNameHint = opened.nameHint;
        shouldCloseResolvedFileDescriptor = true;
      }
      final AudioTagLyricsPayload payload = _audioTagPort.readLyrics(
        songPath,
        fileDescriptor: resolvedFileDescriptor,
        fileDescriptorNameHint: resolvedFileDescriptorNameHint,
      );
      final String? plainText = payload.plainText?.trim();
      return plainText == null || plainText.isEmpty ? null : payload.plainText;
    } on AudioTagException catch (error) {
      throw LocalMatchTagReadException.fromAudioTagException(
        error,
        songPath: songPath,
        fileDescriptor: resolvedFileDescriptor,
        fileDescriptorNameHint: resolvedFileDescriptorNameHint,
      );
    } on Exception catch (error, stackTrace) {
      throw LocalMatchTagReadException(
        error.toString(),
        cause: error,
        stackTrace: stackTrace,
        songPath: songPath,
        fileDescriptor: resolvedFileDescriptor,
        fileDescriptorNameHint: resolvedFileDescriptorNameHint,
      );
    } finally {
      if (shouldCloseResolvedFileDescriptor && resolvedFileDescriptor != null) {
        try {
          await _androidSafFdPort.closeFd(resolvedFileDescriptor);
        } catch (_) {
          // fd 关闭失败不覆盖主链路结果，避免误报读取失败。
        }
      }
    }
  }

  @override
  Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    int? resolvedFileDescriptor = fileDescriptor;
    String? resolvedFileDescriptorNameHint = fileDescriptorNameHint;
    bool shouldCloseResolvedFileDescriptor = false;
    try {
      if (_useBackgroundForFilePaths &&
          AudioTagBackgroundExecutor.supportsBackgroundPath(
            songPath,
            fileDescriptor: resolvedFileDescriptor,
          )) {
        await AudioTagBackgroundExecutor.writeLyricsTag(
          songPath: songPath,
          lyricsText: lyricsText,
          lyrics: lyrics,
          id3Version: id3Version,
        );
        return;
      }
      if (resolvedFileDescriptor == null && _isContentUri(songPath)) {
        final AndroidSafOpenedFileDescriptor opened = await _androidSafFdPort
            .openReadWriteFd(songPath);
        resolvedFileDescriptor = opened.fileDescriptor;
        resolvedFileDescriptorNameHint = opened.nameHint;
        shouldCloseResolvedFileDescriptor = true;
      }
      _audioTagPort.writeLyrics(
        AudioTagWriteRequest(
          songPath: songPath,
          plainLyricsText: lyricsText,
          lyrics: lyrics,
          id3Version: id3Version,
          fileDescriptor: resolvedFileDescriptor,
          fileDescriptorNameHint: resolvedFileDescriptorNameHint,
        ),
      );
    } on AudioTagException catch (error) {
      throw LocalMatchTagWriteException.fromAudioTagException(
        error,
        songPath: songPath,
        fileDescriptor: resolvedFileDescriptor,
        fileDescriptorNameHint: resolvedFileDescriptorNameHint,
      );
    } on LocalMatchTagWriteException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw LocalMatchTagWriteException(
        error.toString(),
        cause: error,
        stackTrace: stackTrace,
        songPath: songPath,
        fileDescriptor: resolvedFileDescriptor,
        fileDescriptorNameHint: resolvedFileDescriptorNameHint,
      );
    } finally {
      if (shouldCloseResolvedFileDescriptor && resolvedFileDescriptor != null) {
        try {
          await _androidSafFdPort.closeFd(resolvedFileDescriptor);
        } catch (_) {
          // fd 关闭失败不覆盖主链路结果，避免误报写入失败。
        }
      }
    }
  }

  static bool _isContentUri(String path) => path.startsWith('content://');
}

/// 默认 fd 端口只负责给出明确错误。
///
/// infra 层不能直接创建 Android MethodChannel 适配器；真实 fd 能力必须由 app 层
/// 注入，这样桌面/测试路径不会意外加载 Android 平台通道，也能避免 fd 生命周期失控。
final class _UnsupportedSafFdPort implements AndroidSafFdPort {
  const _UnsupportedSafFdPort();

  @override
  Future<void> closeFd(int fileDescriptor) async {}

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadOnlyFd(String uri) {
    throw UnsupportedError('当前运行环境未注入 Android SAF fd 读取能力');
  }

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadWriteFd(String uri) {
    throw UnsupportedError('当前运行环境未注入 Android SAF fd 写入能力');
  }
}
