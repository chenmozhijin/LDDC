import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 基于 Android SAF 树目录的歌词保存实现。
final class AndroidSafLyricsSavePersistence extends LyricsSavePersistencePort
    implements LyricsSaveExistencePort {
  AndroidSafLyricsSavePersistence({
    required AndroidSafTreePort treePort,
    required this.treeUri,
  }) : _treePort = treePort;

  final AndroidSafTreePort _treePort;
  final String treeUri;
  Map<String, _SafDocumentInfo>? _existingDocuments;

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    final String fileName = _buildFileName(request);
    final AndroidSafWriteDocumentResult result = await _treePort.writeDocument(
      treeUri: treeUri,
      displayName: fileName,
      mimeType: _resolveMimeType(request.lyricsFormat),
      bytes: bytes,
    );
    final Map<String, _SafDocumentInfo> cached =
        _existingDocuments ?? await _loadExistingDocuments();
    cached[result.displayName] = _SafDocumentInfo(
      uri: result.uri,
      displayName: result.displayName,
    );
    _existingDocuments = cached;
    return result.uri;
  }

  @override
  Future<bool> exists({required LyricsSaveRequest request}) async {
    final Map<String, _SafDocumentInfo> documents =
        _existingDocuments ?? await _loadExistingDocuments();
    return documents.containsKey(_buildFileName(request));
  }

  String _buildFileName(LyricsSaveRequest request) {
    return LyricsPathTemplateFormatter.buildFileName(
      fileNameFormat: request.resolvedFileNameFormat,
      songInfo: request.songInfo,
      lyricLangs: request.lyricLangs,
    );
  }

  Future<Map<String, _SafDocumentInfo>> _loadExistingDocuments() async {
    final Map<String, _SafDocumentInfo> documents =
        <String, _SafDocumentInfo>{};
    int offset = 0;
    while (true) {
      final AndroidSafTreePage page = await _treePort.listChildrenPage(
        uri: treeUri,
        offset: offset,
        limit: 128,
      );
      for (final AndroidSafTreeEntry entry in page.entries) {
        if (!entry.isFile) {
          continue;
        }
        documents[entry.displayName] = _SafDocumentInfo(
          uri: entry.uri,
          displayName: entry.displayName,
          sizeBytes: entry.sizeBytes,
          lastModifiedMs: entry.lastModifiedMs,
        );
      }
      final int? nextOffset = page.nextOffset;
      if (nextOffset == null) {
        break;
      }
      offset = nextOffset;
    }
    _existingDocuments = documents;
    return documents;
  }

  String _resolveMimeType(LyricsFormat format) {
    return switch (format) {
      LyricsFormat.json => 'application/json',
      LyricsFormat.ass => 'text/x-ssa',
      LyricsFormat.srt => 'application/x-subrip',
      _ => 'text/plain',
    };
  }
}

class _SafDocumentInfo {
  const _SafDocumentInfo({
    required this.uri,
    required this.displayName,
    this.sizeBytes,
    this.lastModifiedMs,
  });

  final String uri;
  final String displayName;
  final int? sizeBytes;
  final int? lastModifiedMs;
}
