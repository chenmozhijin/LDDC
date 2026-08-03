import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 歌词保存请求。
class LyricsSaveRequest {
  LyricsSaveRequest({
    required this.songInfo,
    required List<String> lyricLangs,
    required this.lyricsFormat,
    required this.fileNameFormat,
  }) : lyricLangs = List<String>.unmodifiable(lyricLangs);

  final SongInfo songInfo;
  final List<String> lyricLangs;
  final LyricsFormat lyricsFormat;
  final String fileNameFormat;

  /// 实际写入时使用的文件名模板，包含歌词格式扩展名。
  String get resolvedFileNameFormat => '$fileNameFormat${lyricsFormat.ext}';
}

/// 歌词写入端口。
///
/// 由上层只传入“写什么”，由不同实现决定“写到哪里”。
abstract class LyricsSavePersistencePort {
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  });

  Future<String> saveText({
    required LyricsSaveRequest request,
    required String text,
  }) {
    return saveBytes(
      request: request,
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
  }
}

/// 可选的“目标是否已存在”查询端口。
///
/// 仅在上层需要复用统一保存策略做“跳过已存在歌词”判定时使用。
abstract interface class LyricsSaveExistencePort {
  Future<bool> exists({required LyricsSaveRequest request});
}
