import 'dart:io';
import 'dart:typed_data';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

const int defaultOpenLyricsMaxBytes = 16 * 1024 * 1024;

final class OpenLyricsFileTooLargeException implements Exception {
  const OpenLyricsFileTooLargeException({
    required this.name,
    required this.sizeBytes,
    required this.maxBytes,
  });

  final String name;
  final int sizeBytes;
  final int maxBytes;

  @override
  String toString() {
    return '歌词文件过大：$name，大小 ${_formatBytes(sizeBytes)}，上限 ${_formatBytes(maxBytes)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

abstract interface class OpenLyricsFileReader {
  Future<Uint8List> readPickedFile(PickedFileHandle file);

  Future<Uint8List> readLocalPath(String path);
}

final class OpenLyricsFileReaderImpl implements OpenLyricsFileReader {
  const OpenLyricsFileReaderImpl({this.maxBytes = defaultOpenLyricsMaxBytes});

  final int maxBytes;

  @override
  Future<Uint8List> readPickedFile(PickedFileHandle file) async {
    _checkKnownLength(name: file.name, length: await file.length());
    final Uint8List bytes = await file.readAsBytes();
    // 有些移动端或虚拟文件句柄无法提前给出长度，读完后仍要复查，
    // 避免异常大文件长期保存在页面 state 中。
    _checkLoadedBytes(name: file.name, bytes: bytes);
    return bytes;
  }

  @override
  Future<Uint8List> readLocalPath(String path) async {
    final File file = File(path);
    _checkKnownLength(name: path, length: await file.length());
    final Uint8List bytes = await file.readAsBytes();
    _checkLoadedBytes(name: path, bytes: bytes);
    return bytes;
  }

  void _checkKnownLength({required String name, required int? length}) {
    if (length == null) {
      return;
    }
    if (length > maxBytes) {
      throw OpenLyricsFileTooLargeException(
        name: name,
        sizeBytes: length,
        maxBytes: maxBytes,
      );
    }
  }

  void _checkLoadedBytes({required String name, required Uint8List bytes}) {
    if (bytes.lengthInBytes > maxBytes) {
      throw OpenLyricsFileTooLargeException(
        name: name,
        sizeBytes: bytes.lengthInBytes,
        maxBytes: maxBytes,
      );
    }
  }
}
