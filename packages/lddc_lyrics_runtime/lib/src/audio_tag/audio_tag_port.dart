import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// ID3 标签版本。
enum Id3Version {
  v23('v2.3'),
  v24('v2.4');

  const Id3Version(this.value);

  final String value;
}

/// 音频元数据（最小集合）。
class AudioTagMeta {
  const AudioTagMeta({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.trackNumber,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final int? trackNumber;
}

/// 读取到的歌词载荷。
class AudioTagLyricsPayload {
  AudioTagLyricsPayload({
    required this.plainText,
    required List<AudioTagSyncedTrack> syncedTracks,
  }) : syncedTracks = List<AudioTagSyncedTrack>.unmodifiable(syncedTracks);

  final String? plainText;
  final List<AudioTagSyncedTrack> syncedTracks;

  bool get hasLyrics {
    if (plainText != null && plainText!.trim().isNotEmpty) {
      return true;
    }
    for (final AudioTagSyncedTrack track in syncedTracks) {
      for (final AudioTagSyncedEntry entry in track.entries) {
        if (entry.text.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }
}

/// 同步歌词轨道（对齐 ID3 SYLT 的最小语义）。
class AudioTagSyncedTrack {
  AudioTagSyncedTrack({
    required this.language,
    required this.description,
    required List<AudioTagSyncedEntry> entries,
  }) : entries = List<AudioTagSyncedEntry>.unmodifiable(entries);

  final String language;
  final String description;
  final List<AudioTagSyncedEntry> entries;
}

/// 同步歌词条目（毫秒 + 文本）。
class AudioTagSyncedEntry {
  const AudioTagSyncedEntry({required this.timeMs, required this.text});

  final int timeMs;
  final String text;
}

/// 标签写回请求。
class AudioTagWriteRequest {
  const AudioTagWriteRequest({
    required this.songPath,
    required this.plainLyricsText,
    required this.lyrics,
    required this.id3Version,
    this.fileDescriptor,
    this.fileDescriptorNameHint,
    this.onSaveCriticalSectionEntered,
  });

  final String songPath;
  final String plainLyricsText;
  final Lyrics lyrics;
  final Id3Version id3Version;
  final int? fileDescriptor;
  final String? fileDescriptorNameHint;

  /// 后台 worker 用来感知“已进入 native 保存临界区”的内部回调。
  ///
  /// 进入该阶段后强杀 isolate 可能留下半写文件，因此只能返回“结果未知”并停止
  /// 后续批量任务。普通同步调用不需要传入。
  final void Function()? onSaveCriticalSectionEntered;
}

/// 标签错误码。
enum AudioTagErrorCode {
  formatUnsupported,
  frameUnsupported,
  readFailed,
  writeFailed,
}

/// 标签异常。
class AudioTagException implements Exception {
  const AudioTagException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
    this.writeResultUnknown = false,
  });

  final AudioTagErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
  final Map<String, Object?> context;

  /// 写标签进入 native 保存临界区后不能强杀 isolate。
  ///
  /// 该标记让上层停止后续批量任务，同时把当前文件报告为“写入结果未知”，
  /// 避免把可能仍在写入的文件误判成确定失败或继续批量覆盖其他文件。
  final bool writeResultUnknown;

  @override
  String toString() => 'AudioTagException($code): $message';
}

/// 音频标签端口。
abstract interface class AudioTagPort {
  AudioTagMeta readMeta(String songPath);

  bool hasLyrics(String songPath);

  AudioTagLyricsPayload readLyrics(
    String songPath, {
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  });

  void writeLyrics(AudioTagWriteRequest request);
}
