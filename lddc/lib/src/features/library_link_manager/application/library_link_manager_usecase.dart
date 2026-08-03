import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

typedef LibraryLinkFileExists = Future<bool> Function(String path);

class LibraryLinkClearInvalidResult {
  const LibraryLinkClearInvalidResult({required this.deletedIds});

  final Set<int> deletedIds;

  int get count => deletedIds.length;
}

class LibraryLinkRewriteDirectoryResult {
  const LibraryLinkRewriteDirectoryResult({required this.originalIds});

  final Set<int> originalIds;

  int get count => originalIds.length;
}

class LibraryLinkManagerUseCase {
  const LibraryLinkManagerUseCase({
    required LibraryLinkRepository repository,
    required LibraryLinkFileExists fileExists,
    int batchSize = 200,
  }) : _repository = repository,
       _fileExists = fileExists,
       _batchSize = batchSize;

  final LibraryLinkRepository _repository;
  final LibraryLinkFileExists _fileExists;
  final int _batchSize;

  Future<LibraryLinkClearInvalidResult> clearInvalid() async {
    final List<int> invalidIds = <int>[];
    await _forEachStoredItemBatch((LibraryLinkItem item) async {
      final String? songPath = item.song.path;
      final String? lyricsPath = item.lyricsPath;
      final bool invalidSong =
          songPath != null &&
          songPath.isNotEmpty &&
          !await _fileExists(songPath);
      final bool invalidLyrics =
          lyricsPath != null &&
          lyricsPath.isNotEmpty &&
          !await _fileExists(lyricsPath);
      if (invalidSong || invalidLyrics) {
        invalidIds.add(item.id);
      }
    });
    if (invalidIds.isNotEmpty) {
      await _repository.delItems(invalidIds);
    }
    return LibraryLinkClearInvalidResult(deletedIds: invalidIds.toSet());
  }

  Future<LibraryLinkRewriteDirectoryResult> rewriteDirectory({
    required String oldDir,
    required String newDir,
  }) async {
    final List<LibraryLinkRewriteItem> rewrites = <LibraryLinkRewriteItem>[];
    await _forEachStoredItemBatch((LibraryLinkItem item) async {
      final SongInfo song = await _migrateSongPath(
        item.song,
        oldDir: oldDir,
        newDir: newDir,
      );
      final String? lyricsPath = await _migratePath(
        item.lyricsPath,
        oldDir: oldDir,
        newDir: newDir,
      );
      if (song.path == item.song.path && lyricsPath == item.lyricsPath) {
        return;
      }
      rewrites.add(
        LibraryLinkRewriteItem(
          originalId: item.id,
          upsert: LibraryLinkUpsertItem(
            song: song,
            lyricsPath: lyricsPath,
            configSnapshot: item.configSnapshot,
          ),
        ),
      );
    });
    if (rewrites.isNotEmpty) {
      await _repository.rewriteItems(rewrites);
    }
    return LibraryLinkRewriteDirectoryResult(
      originalIds: rewrites
          .map((LibraryLinkRewriteItem item) => item.originalId)
          .toSet(),
    );
  }

  Future<String> buildBackupJson() async {
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    final StringBuffer buffer = StringBuffer('[');
    bool first = true;
    await _forEachStoredItemBatch((LibraryLinkItem item) async {
      if (first) {
        buffer.writeln();
      } else {
        buffer.writeln(',');
      }
      buffer.write(
        _indentJsonBlock(encoder.convert(_serializeBackupItem(item))),
      );
      first = false;
    });
    if (!first) {
      buffer.writeln();
    }
    buffer.write(']');
    return buffer.toString();
  }

  Future<int> restoreFromJsonBytes(
    Uint8List bytes, {
    required String invalidBackupFormatMessage,
  }) async {
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    final List<LibraryLinkUpsertItem> items = _parseBackupItems(
      decoded,
      invalidBackupFormatMessage: invalidBackupFormatMessage,
    );
    await _repository.replaceAll(items);
    return items.length;
  }

  Future<int> exportLyrics({required String saveDir}) async {
    int exported = 0;
    await _forEachStoredItemBatch((LibraryLinkItem item) async {
      final String? lyricsPath = item.lyricsPath;
      if (lyricsPath == null || lyricsPath.isEmpty) {
        return;
      }
      if (!await _fileExists(lyricsPath)) {
        return;
      }
      final File source = File(lyricsPath);
      final String baseName = _sanitizeFileName(
        [
              if (item.song.artistText.trim().isNotEmpty) item.song.artistText,
              if ((item.song.title ?? '').trim().isNotEmpty) item.song.title!,
            ].join(' - ').trim().isEmpty
            ? 'lyrics_${item.id}'
            : [
                if (item.song.artistText.trim().isNotEmpty)
                  item.song.artistText,
                if ((item.song.title ?? '').trim().isNotEmpty) item.song.title!,
              ].join(' - '),
      );
      final String targetPath = p.join(
        saveDir,
        '$baseName${p.extension(source.path)}',
      );
      await source.copy(targetPath);
      exported += 1;
    });
    return exported;
  }

  Future<void> _forEachStoredItemBatch(
    Future<void> Function(LibraryLinkItem item) onItem,
  ) async {
    final int totalCount = await _repository.countItems();
    for (int offset = 0; offset < totalCount; offset += _batchSize) {
      final int limit = (totalCount - offset) < _batchSize
          ? (totalCount - offset)
          : _batchSize;
      final List<LibraryLinkItem> items = await _repository.getPage(
        offset: offset,
        limit: limit,
      );
      for (final LibraryLinkItem item in items) {
        await onItem(item);
      }
    }
  }

  Map<String, Object?> _serializeBackupItem(LibraryLinkItem item) {
    return <String, Object?>{
      'title': item.song.title,
      'artist': item.song.artistText.isEmpty ? null : item.song.artistText,
      'album': item.song.album,
      'duration': item.song.durationMs,
      'song_path': item.song.path,
      'track_number': item.song.id,
      'lyrics_path': item.lyricsPath,
      'config': item.configSnapshot,
    };
  }

  String _indentJsonBlock(String json) {
    return json.split('\n').map((String line) => '  $line').join('\n');
  }

  Future<SongInfo> _migrateSongPath(
    SongInfo song, {
    required String oldDir,
    required String newDir,
  }) async {
    final String? nextPath = await _migratePath(
      song.path,
      oldDir: oldDir,
      newDir: newDir,
    );
    if (nextPath == song.path) {
      return song;
    }
    return song.copyWith(path: nextPath);
  }

  Future<String?> _migratePath(
    String? originalPath, {
    required String oldDir,
    required String newDir,
  }) async {
    final String? normalized = originalPath?.trim();
    if (normalized == null || normalized.isEmpty) {
      return originalPath;
    }
    final String oldRoot = p.normalize(oldDir);
    final String candidate = p.normalize(normalized);
    if (!p.isWithin(oldRoot, candidate) && oldRoot != candidate) {
      return originalPath;
    }
    final String relative = p.relative(candidate, from: oldRoot);
    final String nextPath = p.normalize(p.join(newDir, relative));
    return await _fileExists(nextPath) ? nextPath : originalPath;
  }

  List<LibraryLinkUpsertItem> _parseBackupItems(
    Object? decoded, {
    required String invalidBackupFormatMessage,
  }) {
    if (decoded is! List) {
      throw FormatException(invalidBackupFormatMessage);
    }
    final List<LibraryLinkUpsertItem> items = <LibraryLinkUpsertItem>[];
    for (int index = 0; index < decoded.length; index += 1) {
      final Object? rawItem = decoded[index];
      if (rawItem is! Map) {
        throw FormatException(
          '$invalidBackupFormatMessage：第 ${index + 1} 条不是对象',
        );
      }
      final Object? rawConfig = rawItem['config'];
      if (rawConfig != null && rawConfig is! Map) {
        throw FormatException(
          '$invalidBackupFormatMessage：第 ${index + 1} 条 config 不是对象',
        );
      }
      // 恢复关联库属于破坏性操作。先把所有记录解析成受控 upsert 结构，
      // 再交给仓储事务替换，避免坏备份导致“先清空，后失败”的半恢复状态。
      items.add(
        LibraryLinkUpsertItem(
          song: SongInfo.fromMap(<String, Object?>{
            'source': Source.local.value,
            'title': rawItem['title'],
            'artist': rawItem['artist'],
            'album': rawItem['album'],
            'duration': rawItem['duration'],
            'path': rawItem['song_path'],
            'id': rawItem['track_number'],
          }),
          lyricsPath: rawItem['lyrics_path']?.toString(),
          configSnapshot: rawConfig == null
              ? const <String, Object?>{}
              : Map<String, Object?>.from(rawConfig as Map),
        ),
      );
    }
    return items;
  }

  String _sanitizeFileName(String input) {
    return input.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }
}
