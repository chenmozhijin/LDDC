// ignore_for_file: avoid_slow_async_io
// Python版关联库备份/恢复需要检查主库和 WAL/SHM 文件，异步 stat 可避免大库维护时阻塞界面。

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

/// Python版关联库 schema 约束。
///
/// 校验器和修复器共用同一份字段、索引和计数 SQL，避免一边认为缺列、
/// 另一边却按另一套规则修复。新增字段时只改这里，测试也能集中暴露问题。
abstract final class _LocalSongLyricsDbSchema {
  static const String defaultTableName = 'songs';
  static const String compatibilityIndexName =
      'idx_title_artist_album_duration_song_path_track_number';
  static const Map<String, String> requiredColumnDefinitions = <String, String>{
    'title': "title TEXT NOT NULL DEFAULT ''",
    'artist': "artist TEXT NOT NULL DEFAULT ''",
    'album': "album TEXT NOT NULL DEFAULT ''",
    'duration': 'duration INTEGER NOT NULL DEFAULT -1',
    'song_path': "song_path TEXT NOT NULL DEFAULT ''",
    'track_number': "track_number TEXT NOT NULL DEFAULT ''",
    'lyrics_path': "lyrics_path TEXT DEFAULT ''",
    'config': "config TEXT DEFAULT '{}'",
  };
}

/// Python版关联库只读检查器。
///
/// Validator 和 Repair 都需要读取同一组统计信息。集中在这里后，字段集合、
/// 索引名和 config JSON 合法性不会因为两个服务各写一份 SQL 而漂移。
final class _LocalSongLyricsDbInspector {
  const _LocalSongLyricsDbInspector(this._db, this.tableName);

  final _LocalSongLyricsDbDatabase _db;
  final String tableName;

  Future<List<QueryRow>> columns() {
    return _db.customSelect('PRAGMA table_info($tableName)').get();
  }

  List<String> missingColumns(List<QueryRow> columns) {
    final Set<String> presentColumns = columns
        .map((QueryRow row) => row.read<String>('name'))
        .toSet();
    return _LocalSongLyricsDbSchema.requiredColumnDefinitions.keys
        .toSet()
        .difference(presentColumns)
        .toList(growable: false)
      ..sort();
  }

  Future<int> countRows() async {
    final QueryRow row = await _db
        .customSelect('SELECT COUNT(*) AS row_count FROM $tableName')
        .getSingle();
    return coerceInt(row.data['row_count']);
  }

  Future<int> countInvalidConfigs() async {
    final List<QueryRow> rows = await _db
        .customSelect('SELECT config FROM $tableName')
        .get();
    int invalidCount = 0;
    for (final QueryRow row in rows) {
      if (!isConfigValid(row.data['config'])) {
        invalidCount += 1;
      }
    }
    return invalidCount;
  }

  Future<int> countDuplicateGroups() async {
    final List<QueryRow> rows = await _db.customSelect('''
SELECT COUNT(*) AS duplicate_count
FROM (
  SELECT title, artist, album, duration, song_path, track_number
  FROM $tableName
  GROUP BY title, artist, album, duration, song_path, track_number
  HAVING COUNT(*) > 1
)
''').get();
    if (rows.isEmpty) {
      return 0;
    }
    return coerceInt(rows.first.data['duplicate_count']);
  }

  Future<bool> hasCompatibilityIndex() async {
    final List<QueryRow> rows = await _db
        .customSelect('PRAGMA index_list($tableName)')
        .get();
    for (final QueryRow row in rows) {
      if (row.data['name'] == _LocalSongLyricsDbSchema.compatibilityIndexName) {
        return true;
      }
    }
    return false;
  }

  bool isConfigValid(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return false;
    }
    try {
      return jsonDecode(raw) is Map;
    } on FormatException {
      return false;
    }
  }

  int coerceInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is BigInt) {
      return value.toInt();
    }
    if (value is double && value.isFinite) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  String coerceString(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }
}

/// Python版 `local_song_lyrics.db` 校验报告。
class LocalSongLyricsDbValidationReport {
  const LocalSongLyricsDbValidationReport({
    required this.schemaReady,
    required this.rowCount,
    required this.invalidConfigCount,
    required this.duplicateGroupCount,
    required this.compatibilityIndexReady,
    this.missingColumns = const <String>[],
  });

  final bool schemaReady;
  final int rowCount;
  final int invalidConfigCount;
  final int duplicateGroupCount;
  final bool compatibilityIndexReady;
  final List<String> missingColumns;
}

/// Python版 `local_song_lyrics.db` 修复报告。
class LocalSongLyricsDbRepairReport {
  const LocalSongLyricsDbRepairReport({
    required this.createdSchema,
    required this.normalizedNullFieldCount,
    required this.repairedConfigCount,
    required this.removedDuplicateCount,
    required this.validation,
  });

  final bool createdSchema;
  final int normalizedNullFieldCount;
  final int repairedConfigCount;
  final int removedDuplicateCount;
  final LocalSongLyricsDbValidationReport validation;
}

/// Python版关联库备份结果。
class LocalSongLyricsDbBackupResult {
  const LocalSongLyricsDbBackupResult({
    required this.backupPath,
    this.warnings = const <String>[],
  });

  final String backupPath;
  final List<String> warnings;
}

/// Python版关联库校验器。
class LocalSongLyricsDbValidator {
  LocalSongLyricsDbValidator({
    required QueryExecutor executor,
    this.tableName = _LocalSongLyricsDbSchema.defaultTableName,
  }) : _db = _LocalSongLyricsDbDatabase(executor);

  final String tableName;
  final _LocalSongLyricsDbDatabase _db;
  late final _LocalSongLyricsDbInspector _inspector =
      _LocalSongLyricsDbInspector(_db, tableName);

  Future<LocalSongLyricsDbValidationReport> validate() async {
    final List<QueryRow> columns = await _inspector.columns();
    if (columns.isEmpty) {
      return LocalSongLyricsDbValidationReport(
        schemaReady: false,
        rowCount: 0,
        invalidConfigCount: 0,
        duplicateGroupCount: 0,
        compatibilityIndexReady: false,
        missingColumns: _LocalSongLyricsDbSchema.requiredColumnDefinitions.keys
            .toList(growable: false),
      );
    }

    final List<String> missingColumns = _inspector.missingColumns(columns);
    final bool schemaReady = missingColumns.isEmpty;
    if (!schemaReady) {
      return LocalSongLyricsDbValidationReport(
        schemaReady: false,
        rowCount: 0,
        invalidConfigCount: 0,
        duplicateGroupCount: 0,
        compatibilityIndexReady: false,
        missingColumns: missingColumns,
      );
    }

    final int rowCount = await _inspector.countRows();
    final int invalidConfigCount = await _inspector.countInvalidConfigs();
    final int duplicateGroupCount = await _inspector.countDuplicateGroups();
    final bool compatibilityIndexReady = await _inspector
        .hasCompatibilityIndex();

    return LocalSongLyricsDbValidationReport(
      schemaReady: true,
      rowCount: rowCount,
      invalidConfigCount: invalidConfigCount,
      duplicateGroupCount: duplicateGroupCount,
      compatibilityIndexReady: compatibilityIndexReady,
      missingColumns: const <String>[],
    );
  }

  Future<void> dispose() => _db.close();
}

/// Python版关联库修复器。
class LocalSongLyricsDbRepairService {
  LocalSongLyricsDbRepairService({
    required QueryExecutor executor,
    this.tableName = _LocalSongLyricsDbSchema.defaultTableName,
  }) : _db = _LocalSongLyricsDbDatabase(executor);

  final String tableName;
  final _LocalSongLyricsDbDatabase _db;
  late final _LocalSongLyricsDbInspector _inspector =
      _LocalSongLyricsDbInspector(_db, tableName);

  Future<LocalSongLyricsDbRepairReport> repair() async {
    final bool createdSchema = await _ensureSchema();
    final int normalizedNullFieldCount = await _normalizeNullFields();
    final int repairedConfigCount = await _repairInvalidConfigs();
    final int removedDuplicateCount = await _collapseDuplicateRows();
    await _ensureCompatibilityIndex();
    final LocalSongLyricsDbValidationReport validation =
        await _validateAfterRepair();
    return LocalSongLyricsDbRepairReport(
      createdSchema: createdSchema,
      normalizedNullFieldCount: normalizedNullFieldCount,
      repairedConfigCount: repairedConfigCount,
      removedDuplicateCount: removedDuplicateCount,
      validation: validation,
    );
  }

  Future<void> dispose() => _db.close();

  Future<bool> _ensureSchema() async {
    final List<QueryRow> columns = await _inspector.columns();
    if (columns.isEmpty) {
      await _db.customStatement('''
CREATE TABLE IF NOT EXISTS $tableName (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  artist TEXT NOT NULL DEFAULT '',
  album TEXT NOT NULL DEFAULT '',
  duration INTEGER NOT NULL DEFAULT -1,
  song_path TEXT NOT NULL DEFAULT '',
  track_number TEXT NOT NULL DEFAULT '',
  lyrics_path TEXT DEFAULT '',
  config TEXT DEFAULT '{}',
  UNIQUE (title, artist, album, duration, song_path, track_number)
)
''');
      return true;
    }

    final Set<String> missingColumns = _inspector
        .missingColumns(columns)
        .toSet();
    for (final MapEntry<String, String> column
        in _LocalSongLyricsDbSchema.requiredColumnDefinitions.entries) {
      if (!missingColumns.contains(column.key)) {
        continue;
      }
      await _db.customStatement(
        'ALTER TABLE $tableName ADD COLUMN ${column.value}',
      );
    }
    return false;
  }

  Future<int> _normalizeNullFields() {
    return _db.customUpdate('''
UPDATE $tableName
SET title = COALESCE(title, ''),
    artist = COALESCE(artist, ''),
    album = COALESCE(album, ''),
    duration = COALESCE(duration, -1),
    song_path = COALESCE(song_path, ''),
    track_number = COALESCE(track_number, ''),
    lyrics_path = COALESCE(lyrics_path, ''),
    config = COALESCE(config, '{}')
WHERE title IS NULL
   OR artist IS NULL
   OR album IS NULL
   OR duration IS NULL
   OR song_path IS NULL
   OR track_number IS NULL
   OR lyrics_path IS NULL
   OR config IS NULL
''');
  }

  Future<int> _repairInvalidConfigs() async {
    final List<QueryRow> rows = await _db
        .customSelect('SELECT id, config FROM $tableName ORDER BY id ASC')
        .get();
    int repairedCount = 0;
    for (final QueryRow row in rows) {
      final int id = _inspector.coerceInt(row.data['id']);
      if (id <= 0) {
        continue;
      }
      if (_inspector.isConfigValid(row.data['config'])) {
        continue;
      }
      repairedCount += await _db.customUpdate(
        '''
UPDATE $tableName
SET config = ?1
WHERE id = ?2
''',
        variables: <Variable>[Variable<String>('{}'), Variable<int>(id)],
      );
    }
    return repairedCount;
  }

  Future<int> _collapseDuplicateRows() async {
    final List<QueryRow> rows = await _db.customSelect('''
SELECT title, artist, album, duration, song_path, track_number
FROM $tableName
GROUP BY title, artist, album, duration, song_path, track_number
HAVING COUNT(*) > 1
''').get();
    int removedCount = 0;
    for (final QueryRow row in rows) {
      final List<QueryRow> duplicates = await _db
          .customSelect(
            '''
SELECT id
FROM $tableName
WHERE title = ?1
  AND artist = ?2
  AND album = ?3
  AND duration = ?4
  AND song_path = ?5
  AND track_number = ?6
ORDER BY id DESC
            ''',
            variables: <Variable>[
              Variable<String>(_inspector.coerceString(row.data['title'])),
              Variable<String>(_inspector.coerceString(row.data['artist'])),
              Variable<String>(_inspector.coerceString(row.data['album'])),
              Variable<int>(_inspector.coerceInt(row.data['duration'])),
              Variable<String>(_inspector.coerceString(row.data['song_path'])),
              Variable<String>(
                _inspector.coerceString(row.data['track_number']),
              ),
            ],
          )
          .get();
      if (duplicates.length <= 1) {
        continue;
      }
      for (final QueryRow duplicate in duplicates.skip(1)) {
        removedCount += await _db.customUpdate(
          '''
DELETE FROM $tableName
WHERE id = ?1
''',
          variables: <Variable>[
            Variable<int>(_inspector.coerceInt(duplicate.data['id'])),
          ],
        );
      }
    }
    return removedCount;
  }

  Future<void> _ensureCompatibilityIndex() {
    return _db.customStatement('''
CREATE INDEX IF NOT EXISTS ${_LocalSongLyricsDbSchema.compatibilityIndexName}
ON $tableName (title, artist, album, duration, song_path, track_number)
''');
  }

  Future<LocalSongLyricsDbValidationReport> _validateAfterRepair() async {
    final int rowCount = await _inspector.countRows();
    final int invalidConfigCount = await _inspector.countInvalidConfigs();
    final int duplicateGroupCount = await _inspector.countDuplicateGroups();
    final bool compatibilityIndexReady = await _inspector
        .hasCompatibilityIndex();
    return LocalSongLyricsDbValidationReport(
      schemaReady: true,
      rowCount: rowCount,
      invalidConfigCount: invalidConfigCount,
      duplicateGroupCount: duplicateGroupCount,
      compatibilityIndexReady: compatibilityIndexReady,
    );
  }
}

/// Python版关联库备份服务。
class LocalSongLyricsDbBackupService {
  const LocalSongLyricsDbBackupService();

  Future<String> backup({required String dbPath, String? backupPath}) async {
    final LocalSongLyricsDbBackupResult result = await backupWithReport(
      dbPath: dbPath,
      backupPath: backupPath,
    );
    return result.backupPath;
  }

  Future<LocalSongLyricsDbBackupResult> backupWithReport({
    required String dbPath,
    String? backupPath,
  }) async {
    final File source = File(dbPath);
    if (!await source.exists()) {
      throw StateError('数据库文件不存在：$dbPath');
    }
    final String resolvedBackupPath = backupPath ?? '$dbPath.lddc_backup';
    final File target = File(resolvedBackupPath);
    final Directory parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await source.copy(target.path);
    final List<String> warnings = <String>[];
    for (final String suffix in <String>['-wal', '-shm']) {
      final File sidecar = File('$dbPath$suffix');
      if (!await sidecar.exists()) {
        continue;
      }
      await sidecar.copy('${target.path}$suffix');
      warnings.add('检测到 SQLite $suffix 旁路文件，已随主库一起备份。');
    }
    return LocalSongLyricsDbBackupResult(
      backupPath: target.path,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  Future<void> restore({
    required String backupPath,
    required String dbPath,
  }) async {
    final File backup = File(backupPath);
    if (!await backup.exists()) {
      throw StateError('备份文件不存在：$backupPath');
    }
    final File target = File(dbPath);
    final Directory parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await backup.copy(target.path);
    for (final String suffix in <String>['-wal', '-shm']) {
      final File sidecarBackup = File('$backupPath$suffix');
      if (await sidecarBackup.exists()) {
        await sidecarBackup.copy('$dbPath$suffix');
      }
    }
  }
}

/// 手写 Drift runtime 适配器，不是 `.g.dart` 生成文件。
///
/// Python版关联库需要读取既有 SQLite 表结构，当前实现直接执行自定义 SQL，
/// 只借用 Drift 的 executor 与连接生命周期，因此不会声明 Dart table 类。
final class _LocalSongLyricsDbDatabase extends GeneratedDatabase {
  _LocalSongLyricsDbDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const <TableInfo<Table, dynamic>>[];
}
