import 'dart:collection';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

Map<String, Object?> _snapshotConfig(Map<dynamic, dynamic> raw) {
  if (raw.isEmpty) {
    return const <String, Object?>{};
  }
  final Set<Object> ancestors = HashSet<Object>.identity();
  return Map<String, Object?>.unmodifiable(_snapshotMap(raw, ancestors));
}

Map<String, Object?> _snapshotMap(
  Map<dynamic, dynamic> raw,
  Set<Object> ancestors,
) {
  if (!ancestors.add(raw)) {
    throw ArgumentError.value(raw, 'configSnapshot', '关联配置不能包含循环 Map/List');
  }
  try {
    return <String, Object?>{
      for (final MapEntry<dynamic, dynamic> entry in raw.entries)
        entry.key.toString(): _snapshotValue(entry.value, ancestors),
    };
  } finally {
    ancestors.remove(raw);
  }
}

Object? _snapshotValue(Object? value, Set<Object> ancestors) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(_snapshotMap(value, ancestors));
  }
  if (value is List) {
    if (!ancestors.add(value)) {
      throw ArgumentError.value(value, 'configSnapshot', '关联配置不能包含循环 Map/List');
    }
    try {
      return List<Object?>.unmodifiable(
        value.map((Object? item) => _snapshotValue(item, ancestors)),
      );
    } finally {
      ancestors.remove(value);
    }
  }
  return value.toString();
}

/// 歌词关联唯一键，语义对齐Python版 `songs` 唯一约束：
/// `(title, artist, album, duration, song_path, track_number)`。
class LibraryLinkKey {
  const LibraryLinkKey({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.songPath,
    required this.trackNumber,
  });

  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String songPath;
  final String trackNumber;

  /// 从歌曲信息生成唯一键。
  ///
  /// 空值与哨兵规则对齐Python版：
  /// - 文本空值 -> `''`
  /// - 时长空值 -> `-1`
  /// - `song_path` 使用 `file://` URL 语义
  factory LibraryLinkKey.fromSong(SongInfo song) {
    return LibraryLinkKey(
      title: song.title ?? '',
      artist: song.artistText,
      album: song.album ?? '',
      durationMs: song.durationMs ?? -1,
      // 关联库使用六字段严格匹配。这里再次走共享规范化入口，可以防止直接
      // 构造 SongInfo 的调用方把 file:// URL 当成 path 后生成双前缀键。
      songPath: songPathToUrl(song.path) ?? '',
      trackNumber: song.id ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LibraryLinkKey &&
            title == other.title &&
            artist == other.artist &&
            album == other.album &&
            durationMs == other.durationMs &&
            songPath == other.songPath &&
            trackNumber == other.trackNumber);
  }

  @override
  int get hashCode =>
      Object.hash(title, artist, album, durationMs, songPath, trackNumber);
}

/// 关联写入输入模型。
class LibraryLinkUpsertItem {
  LibraryLinkUpsertItem({
    required this.song,
    this.lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) : configSnapshot = _snapshotConfig(configSnapshot);

  final SongInfo song;
  final String? lyricsPath;
  final Map<String, Object?> configSnapshot;
}

/// 目录迁移等批量改写操作的原子单元。
///
/// `originalId` 指向需要删除的旧记录，`upsert` 是迁移后的新记录。
/// 仓储实现必须在同一个事务中完成删除旧记录和写入新记录，避免页面层
/// 先写新记录后删除旧记录失败，留下同一歌曲的双份关联。
class LibraryLinkRewriteItem {
  const LibraryLinkRewriteItem({
    required this.originalId,
    required this.upsert,
  });

  final int originalId;
  final LibraryLinkUpsertItem upsert;
}

/// 关联记录实体。
class LibraryLinkItem {
  LibraryLinkItem({
    required this.id,
    required this.song,
    required this.key,
    this.lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) : configSnapshot = _snapshotConfig(configSnapshot);

  final int id;
  final SongInfo song;
  final LibraryLinkKey key;
  final String? lyricsPath;
  final Map<String, Object?> configSnapshot;
}
