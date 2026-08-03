import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 拖放输入归一化后的不可变结果。
final class LocalMatchResolvedInputs {
  LocalMatchResolvedInputs({
    required List<LocalMatchSongEntry> entries,
    required List<String> paths,
    required List<String> errors,
    required this.cancelled,
  }) : entries = List<LocalMatchSongEntry>.unmodifiable(entries),
       paths = List<String>.unmodifiable(paths),
       errors = List<String>.unmodifiable(errors);

  final List<LocalMatchSongEntry> entries;
  final List<String> paths;
  final List<String> errors;
  final bool cancelled;
}

/// 输入归一化协调器，不持有队列、Provider 或页面生命周期。
final class LocalMatchInputCoordinator {
  const LocalMatchInputCoordinator({required this._songInfoResolver});

  final DroppedSongInfoResolver _songInfoResolver;

  List<String> normalizePaths(Iterable<String> paths) {
    return List<String>.unmodifiable(
      paths
          .map((String path) => path.trim())
          .where((String path) => path.isNotEmpty),
    );
  }

  Future<LocalMatchResolvedInputs> resolveDroppedItems({
    required List<DragDropItemDescriptor> items,
    required bool Function() shouldContinue,
  }) async {
    final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[];
    final List<String> paths = <String>[];
    final List<String> errors = <String>[];
    for (final DragDropItemDescriptor item in items) {
      if (!shouldContinue()) {
        return LocalMatchResolvedInputs(
          entries: entries,
          paths: paths,
          errors: errors,
          cancelled: true,
        );
      }
      switch (item.kind) {
        case DragDropItemKind.songInfoLike:
          final DragDropSongDescriptor? descriptor = item.song;
          if (descriptor == null) {
            continue;
          }
          try {
            final songInfo = await _songInfoResolver.resolve(
              path: descriptor.path,
              track: descriptor.track,
              index: descriptor.index,
            );
            if (!shouldContinue()) {
              return LocalMatchResolvedInputs(
                entries: entries,
                paths: paths,
                errors: errors,
                cancelled: true,
              );
            }
            entries.add(
              LocalMatchSongEntry(songInfo: songInfo, rootPath: null),
            );
          } on DroppedSongInfoResolveException catch (error) {
            errors.add(error.message);
          }
        case DragDropItemKind.localFile:
        case DragDropItemKind.directory:
          final String path = item.path.trim();
          if (path.isNotEmpty) {
            paths.add(path);
          }
      }
    }
    return LocalMatchResolvedInputs(
      entries: entries,
      paths: paths,
      errors: errors,
      cancelled: false,
    );
  }
}
