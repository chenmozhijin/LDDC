// ignore_for_file: avoid_slow_async_io
// 批量保存歌词时会高频检查目标文件是否存在，异步 stat 可以避免密集磁盘访问阻塞界面。

import 'dart:io';
import 'dart:typed_data';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 基于文件系统的歌词保存实现。
final class FileLyricsSavePersistence extends LyricsSavePersistencePort
    implements LyricsSaveExistencePort {
  FileLyricsSavePersistence({required this.folder});

  final String folder;

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    final String savePath = _buildSavePath(request);
    return BackgroundFileIo.writeBytes(path: savePath, bytes: bytes);
  }

  @override
  Future<bool> exists({required LyricsSaveRequest request}) async {
    return File(_buildSavePath(request)).exists();
  }

  String _buildSavePath(LyricsSaveRequest request) {
    return LyricsPathTemplateFormatter.buildPath(
      folder: folder,
      fileNameFormat: request.resolvedFileNameFormat,
      songInfo: request.songInfo,
      lyricLangs: request.lyricLangs,
    );
  }
}
