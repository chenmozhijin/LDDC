import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'library_link_executor.dart';
import 'library_link_models.dart';

/// 关联库仓储接口。
///
/// 语义对齐Python版 `local_song_lyrics_db.py`：
/// - `set_song / set_songs`
/// - `query`
/// - `get_item / count / page`
/// - `del_item / del_items / del_all`
abstract interface class LibraryLinkRepository {
  Future<void> initialize();

  Future<LibraryLinkItem> setSong({
    required SongInfo song,
    String? lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  });

  Future<void> setSongs(Iterable<LibraryLinkUpsertItem> items);

  Future<void> replaceAll(Iterable<LibraryLinkUpsertItem> items);

  Future<void> rewriteItems(Iterable<LibraryLinkRewriteItem> items);

  Future<LibraryLinkItem?> query(SongInfo song);

  Future<LibraryLinkItem?> getItem(int id);

  Future<int> countItems({String searchText = ''});

  Future<List<LibraryLinkItem>> getPage({
    required int offset,
    required int limit,
    String searchText = '',
  });

  Future<void> delItem(int id);

  Future<void> delItems(Iterable<int> ids);

  Future<void> delAll();

  Stream<void> watchChanges({bool emitCurrent = false});

  Future<void> dispose();
}

/// Python版 `local_song_lyrics.db` 直连仓储。
class LocalSongLyricsDbRepository extends SqliteLibraryLinkRepository {
  LocalSongLyricsDbRepository({super.executor, super.executorFactory});
}

/// 基于 sqlite 的关联库仓储实现。
///
/// 桌面端正式主格式直接对齐Python版 `local_song_lyrics.db`：
/// - 表名固定为 `songs`
/// - 字段固定为 `title/artist/album/duration/song_path/track_number/lyrics_path/config`
/// - 空值哨兵规则与Python版一致
class SqliteLibraryLinkRepository implements LibraryLinkRepository {
  SqliteLibraryLinkRepository({
    QueryExecutor? executor,
    Future<QueryExecutor> Function()? executorFactory,
  }) : _providedExecutor = executor,
       _executorFactory = executorFactory;

  static const String tableName = 'songs';
  static const String _columns =
      'id, title, artist, album, duration, song_path, track_number, '
      'lyrics_path, config';

  final QueryExecutor? _providedExecutor;
  final Future<QueryExecutor> Function()? _executorFactory;

  _LibraryLinkDatabase? _db;
  bool _initialized = false;
  bool _disposed = false;
  Future<void> _operationBarrier = Future<void>.value();
  Future<void>? _disposeFuture;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Future<void> initialize() => _enqueue(_initializeIfNeeded);

  Future<void> _initializeIfNeeded() async {
    if (_initialized) {
      return;
    }
    final QueryExecutor executor =
        _providedExecutor ??
        await (_executorFactory ?? createDefaultLibraryLinkExecutor).call();
    final _LibraryLinkDatabase database = _LibraryLinkDatabase(executor);
    try {
      await _createSchema(database);
    } on Object {
      await database.close();
      rethrow;
    }
    _db = database;
    _initialized = true;
  }

  @override
  Future<LibraryLinkItem> setSong({
    required SongInfo song,
    String? lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) {
    return _enqueueSnapshot(
      () => LibraryLinkUpsertItem(
        song: song,
        lyricsPath: lyricsPath,
        configSnapshot: configSnapshot,
      ),
      _setSong,
    );
  }

  Future<LibraryLinkItem> _setSong(LibraryLinkUpsertItem item) async {
    await _initializeIfNeeded();
    final LibraryLinkKey key = LibraryLinkKey.fromSong(item.song);
    await _db!.transaction(() async {
      await _replaceRow(
        song: item.song,
        key: key,
        lyricsPath: item.lyricsPath,
        configSnapshot: item.configSnapshot,
      );
    });
    final LibraryLinkItem? result = await _queryByKey(key);
    if (result == null) {
      throw StateError('写入关联库后未找到对应记录');
    }
    _changes.add(null);
    return result;
  }

  @override
  Future<void> setSongs(Iterable<LibraryLinkUpsertItem> items) {
    return _enqueueSnapshot(() => items.toList(growable: false), _setSongs);
  }

  Future<void> _setSongs(List<LibraryLinkUpsertItem> upserts) async {
    if (upserts.isEmpty) {
      return;
    }
    _ensureUniqueBatchKeys(upserts);
    await _initializeIfNeeded();
    await _db!.transaction(() async {
      for (final LibraryLinkUpsertItem item in upserts) {
        await _replaceRow(
          song: item.song,
          key: LibraryLinkKey.fromSong(item.song),
          lyricsPath: item.lyricsPath,
          configSnapshot: item.configSnapshot,
        );
      }
    });
    _changes.add(null);
  }

  @override
  Future<void> replaceAll(Iterable<LibraryLinkUpsertItem> items) {
    return _enqueueSnapshot(() => items.toList(growable: false), _replaceAll);
  }

  Future<void> _replaceAll(List<LibraryLinkUpsertItem> upserts) async {
    _ensureUniqueBatchKeys(upserts);
    await _initializeIfNeeded();
    await _db!.transaction(() async {
      await _db!.customUpdate('DELETE FROM $tableName');
      for (final LibraryLinkUpsertItem item in upserts) {
        await _replaceRow(
          song: item.song,
          key: LibraryLinkKey.fromSong(item.song),
          lyricsPath: item.lyricsPath,
          configSnapshot: item.configSnapshot,
        );
      }
    });
    _changes.add(null);
  }

  @override
  Future<void> rewriteItems(Iterable<LibraryLinkRewriteItem> items) {
    return _enqueueSnapshot(() => items.toList(growable: false), _rewriteItems);
  }

  Future<void> _rewriteItems(List<LibraryLinkRewriteItem> rewrites) async {
    if (rewrites.isEmpty) {
      return;
    }
    _ensureUniqueRewriteIds(rewrites);
    _ensureUniqueBatchKeys(
      rewrites
          .map((LibraryLinkRewriteItem item) => item.upsert)
          .toList(growable: false),
    );
    await _initializeIfNeeded();
    await _db!.transaction(() async {
      for (final LibraryLinkRewriteItem item in rewrites) {
        await _db!.customUpdate(
          '''
DELETE FROM $tableName
WHERE id = ?1
''',
          variables: <Variable>[Variable<int>(item.originalId)],
        );
      }
      for (final LibraryLinkRewriteItem item in rewrites) {
        await _replaceRow(
          song: item.upsert.song,
          key: LibraryLinkKey.fromSong(item.upsert.song),
          lyricsPath: item.upsert.lyricsPath,
          configSnapshot: item.upsert.configSnapshot,
        );
      }
    });
    _changes.add(null);
  }

  @override
  Future<LibraryLinkItem?> query(SongInfo song) {
    final LibraryLinkKey key = LibraryLinkKey.fromSong(song);
    return _enqueue(() async {
      await _initializeIfNeeded();
      return _queryByKey(key);
    });
  }

  @override
  Future<LibraryLinkItem?> getItem(int id) {
    return _enqueue(() async {
      await _initializeIfNeeded();
      final QueryRow? row = await _db!
          .customSelect(
            '''
SELECT $_columns
FROM $tableName
WHERE id = ?1
LIMIT 1
''',
            variables: <Variable>[Variable<int>(id)],
          )
          .getSingleOrNull();
      return row == null ? null : _rowToItem(row);
    });
  }

  @override
  Future<int> countItems({String searchText = ''}) {
    return _enqueue(() async {
      await _initializeIfNeeded();
      final String normalizedSearchText = searchText.trim();
      final QueryRow row = await _db!
          .customSelect(
            '''
SELECT COUNT(*) AS total
FROM $tableName
WHERE ?1 = ''
   OR instr(lower(title), lower(?1)) > 0
   OR instr(lower(artist), lower(?1)) > 0
   OR instr(lower(album), lower(?1)) > 0
   OR instr(lower(song_path), lower(?1)) > 0
   OR instr(lower(COALESCE(lyrics_path, '')), lower(?1)) > 0
''',
            variables: <Variable>[Variable<String>(normalizedSearchText)],
          )
          .getSingle();
      return row.read<int>('total');
    });
  }

  @override
  Future<List<LibraryLinkItem>> getPage({
    required int offset,
    required int limit,
    String searchText = '',
  }) {
    return _enqueue(() async {
      if (offset < 0) {
        throw ArgumentError.value(offset, 'offset', '分页 offset 不能小于 0');
      }
      if (limit <= 0) {
        throw ArgumentError.value(limit, 'limit', '分页 limit 必须大于 0');
      }
      await _initializeIfNeeded();
      final String normalizedSearchText = searchText.trim();
      final List<QueryRow> rows = await _db!
          .customSelect(
            '''
SELECT $_columns
FROM $tableName
WHERE ?1 = ''
   OR instr(lower(title), lower(?1)) > 0
   OR instr(lower(artist), lower(?1)) > 0
   OR instr(lower(album), lower(?1)) > 0
   OR instr(lower(song_path), lower(?1)) > 0
   OR instr(lower(COALESCE(lyrics_path, '')), lower(?1)) > 0
ORDER BY id ASC
LIMIT ?2 OFFSET ?3
''',
            variables: <Variable>[
              Variable<String>(normalizedSearchText),
              Variable<int>(limit),
              Variable<int>(offset),
            ],
          )
          .get();
      return rows.map(_rowToItem).toList(growable: false);
    });
  }

  @override
  Future<void> delItem(int id) {
    return _enqueue(() async {
      await _initializeIfNeeded();
      final int changed = await _db!.customUpdate(
        '''
DELETE FROM $tableName
WHERE id = ?1
''',
        variables: <Variable>[Variable<int>(id)],
      );
      if (changed > 0) {
        _changes.add(null);
      }
    });
  }

  @override
  Future<void> delItems(Iterable<int> ids) {
    return _enqueueSnapshot(
      () => ids.toSet().toList(growable: false),
      _delItems,
    );
  }

  Future<void> _delItems(List<int> idList) async {
    if (idList.isEmpty) {
      return;
    }
    await _initializeIfNeeded();
    int changed = 0;
    await _db!.transaction(() async {
      for (final int id in idList) {
        changed += await _db!.customUpdate(
          '''
DELETE FROM $tableName
WHERE id = ?1
''',
          variables: <Variable>[Variable<int>(id)],
        );
      }
    });
    if (changed > 0) {
      _changes.add(null);
    }
  }

  @override
  Future<void> delAll() {
    return _enqueue(() async {
      await _initializeIfNeeded();
      final int changed = await _db!.customUpdate('DELETE FROM $tableName');
      if (changed > 0) {
        _changes.add(null);
      }
    });
  }

  @override
  Stream<void> watchChanges({bool emitCurrent = false}) async* {
    await initialize();
    if (emitCurrent) {
      yield null;
    }
    yield* _changes.stream;
  }

  @override
  Future<void> dispose() {
    final Future<void>? existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposed = true;
    final Future<void> future = _dispose();
    _disposeFuture = future;
    return future;
  }

  Future<void> _dispose() async {
    await _operationBarrier;
    try {
      await _changes.close();
    } finally {
      try {
        await _db?.close();
      } finally {
        _db = null;
        _initialized = false;
      }
    }
  }

  Future<void> _createSchema(_LibraryLinkDatabase database) async {
    await database.customStatement('''
CREATE TABLE IF NOT EXISTS $tableName (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album TEXT NOT NULL,
  duration INTEGER NOT NULL,
  song_path TEXT NOT NULL,
  track_number TEXT NOT NULL,
  lyrics_path TEXT,
  config TEXT,
  UNIQUE (title, artist, album, duration, song_path, track_number)
)
''');
    await database.customStatement('''
CREATE INDEX IF NOT EXISTS idx_title_artist_album_duration_song_path_track_number
ON $tableName (title, artist, album, duration, song_path, track_number)
''');
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_disposed) {
      return Future<T>.error(StateError('SqliteLibraryLinkRepository 已释放'));
    }
    final Future<T> result = _operationBarrier.then((_) => operation());
    _operationBarrier = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<T> _enqueueSnapshot<S, T>(
    S Function() createSnapshot,
    Future<T> Function(S snapshot) operation,
  ) {
    if (_disposed) {
      return Future<T>.error(StateError('SqliteLibraryLinkRepository 已释放'));
    }
    try {
      final S snapshot = createSnapshot();
      return _enqueue(() => operation(snapshot));
    } on Object catch (error, stackTrace) {
      return Future<T>.error(error, stackTrace);
    }
  }

  void _ensureUniqueBatchKeys(List<LibraryLinkUpsertItem> items) {
    final Set<LibraryLinkKey> seen = <LibraryLinkKey>{};
    for (final LibraryLinkUpsertItem item in items) {
      final LibraryLinkKey key = LibraryLinkKey.fromSong(item.song);
      if (!seen.add(key)) {
        // 批量恢复/迁移如果同批出现重复唯一键，保留首个或末个都会让 id 和
        // 选择状态变得不可预测；这里直接拒绝，让调用方先修正备份或迁移计划。
        throw ArgumentError.value(key, 'items', '同一批关联记录包含重复歌曲唯一键');
      }
    }
  }

  void _ensureUniqueRewriteIds(List<LibraryLinkRewriteItem> items) {
    final Set<int> seen = <int>{};
    for (final LibraryLinkRewriteItem item in items) {
      if (!seen.add(item.originalId)) {
        throw ArgumentError.value(
          item.originalId,
          'items',
          '同一批关联记录改写包含重复原始 id',
        );
      }
    }
  }

  Future<void> _replaceRow({
    required SongInfo song,
    required LibraryLinkKey key,
    required String? lyricsPath,
    required Map<String, Object?> configSnapshot,
  }) async {
    final String title = key.title;
    final String artist = key.artist;
    final String album = key.album;
    final int duration = key.durationMs;
    final String songPath = key.songPath;
    final String trackNumber = key.trackNumber;
    final String configJson = jsonEncode(configSnapshot);

    // 这里显式删除旧记录再插入，避免依赖表上一定存在Python版唯一约束。
    await _db!.customUpdate(
      '''
DELETE FROM $tableName
WHERE title = ?1
  AND artist = ?2
  AND album = ?3
  AND duration = ?4
  AND song_path = ?5
  AND track_number = ?6
''',
      variables: <Variable>[
        Variable<String>(title),
        Variable<String>(artist),
        Variable<String>(album),
        Variable<int>(duration),
        Variable<String>(songPath),
        Variable<String>(trackNumber),
      ],
    );
    await _db!.customInsert(
      '''
INSERT INTO $tableName (
  title, artist, album, duration, song_path, track_number, lyrics_path, config
) VALUES (
  ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8
)
''',
      variables: <Variable>[
        Variable<String>(title),
        Variable<String>(artist),
        Variable<String>(album),
        Variable<int>(duration),
        Variable<String>(songPath),
        Variable<String>(trackNumber),
        Variable<String>(_normalizeText(lyricsPath)),
        Variable<String>(configJson),
      ],
    );
  }

  Future<LibraryLinkItem?> _queryByKey(LibraryLinkKey key) async {
    final QueryRow? row = await _db!
        .customSelect(
          '''
SELECT $_columns
FROM $tableName
WHERE title = ?1
  AND artist = ?2
  AND album = ?3
  AND duration = ?4
  AND song_path = ?5
  AND track_number = ?6
ORDER BY id DESC
LIMIT 1
''',
          variables: <Variable>[
            Variable<String>(key.title),
            Variable<String>(key.artist),
            Variable<String>(key.album),
            Variable<int>(key.durationMs),
            Variable<String>(key.songPath),
            Variable<String>(key.trackNumber),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _rowToItem(row);
  }

  LibraryLinkItem _rowToItem(QueryRow row) {
    final int id = _asInt(row.data['id']) ?? 0;
    final String title = _normalizeText(_asString(row.data['title']));
    final String artist = _normalizeText(_asString(row.data['artist']));
    final String album = _normalizeText(_asString(row.data['album']));
    final int duration = _asInt(row.data['duration']) ?? -1;
    final String songPath = _normalizeText(_asString(row.data['song_path']));
    final String trackNumber = _normalizeText(
      _asString(row.data['track_number']),
    );
    final SongInfo song = SongInfo.fromMap(<String, Object?>{
      'source': Source.local.value,
      'title': _emptyToNull(title),
      'artist': _emptyToNull(artist),
      'album': _emptyToNull(album),
      'duration': duration > 0 ? duration : null,
      'path': _emptyToNull(songPath),
      'id': _emptyToNull(trackNumber),
    });
    return LibraryLinkItem(
      id: id,
      song: song,
      key: LibraryLinkKey(
        title: title,
        artist: artist,
        album: album,
        durationMs: duration,
        songPath: songPath,
        trackNumber: trackNumber,
      ),
      lyricsPath: _emptyToNull(_asString(row.data['lyrics_path'])),
      configSnapshot: _decodeConfig(row.data['config']),
    );
  }

  Map<String, Object?> _decodeConfig(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, Object?>{
          for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
      }
      return const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  String _normalizeText(String? value) {
    if (value == null || value.isEmpty) {
      return '';
    }
    return value;
  }

  String? _emptyToNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  String? _asString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is BigInt) {
      return value.toInt();
    }
    if (value is double && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

/// 手写 Drift runtime 适配器，不是 `.g.dart` 生成文件。
///
/// 关联库仓储使用自定义 SQL 管理Python版兼容表结构，只借用 Drift executor、
/// transaction 与 close 语义；`allTables` 为空不代表这里可以按生成文件跳过审查。
final class _LibraryLinkDatabase extends GeneratedDatabase {
  _LibraryLinkDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const <TableInfo<Table, dynamic>>[];
}
