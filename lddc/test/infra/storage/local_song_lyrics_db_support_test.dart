// ignore_for_file: avoid_slow_async_io
// 关联库维护测试覆盖异步备份和旁路文件处理，临时目录清理保持同一非阻塞口径。

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/infra/storage/local_song_lyrics_db_support.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  group('LocalSongLyricsDbValidator', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lddc-local-song-lyrics-db-',
      );
      dbFile = File(p.join(tempDir.path, 'local_song_lyrics.db'));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('缺少表时会报告 schema 未就绪', () async {
      final sqlite3.Database db = sqlite3.sqlite3.open(dbFile.path);
      db.close();

      final LocalSongLyricsDbValidator validator = LocalSongLyricsDbValidator(
        executor: NativeDatabase(dbFile),
      );
      final LocalSongLyricsDbValidationReport report = await validator
          .validate();
      await validator.dispose();

      expect(report.schemaReady, isFalse);
      expect(report.missingColumns, isNotEmpty);
    });

    test('能识别损坏 config 与重复键', () async {
      final sqlite3.Database db = sqlite3.sqlite3.open(dbFile.path);
      _createRelaxedSchema(db);
      db.execute(
        '''
INSERT INTO songs (
  title, artist, album, duration, song_path, track_number, lyrics_path, config
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
''',
        <Object>[
          '夜曲',
          '周杰伦',
          '十一月的萧邦',
          236000,
          'file://D:/music/yequ.mp3',
          '1',
          r'D:\lyrics\yequ.lrc',
          '{broken',
        ],
      );
      db.execute(
        '''
INSERT INTO songs (
  title, artist, album, duration, song_path, track_number, lyrics_path, config
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
''',
        <Object>[
          '夜曲',
          '周杰伦',
          '十一月的萧邦',
          236000,
          'file://D:/music/yequ.mp3',
          '1',
          r'D:\lyrics\yequ-2.lrc',
          jsonEncode(<String, Object?>{'offset': 120}),
        ],
      );
      db.close();

      final LocalSongLyricsDbValidator validator = LocalSongLyricsDbValidator(
        executor: NativeDatabase(dbFile),
      );
      final LocalSongLyricsDbValidationReport report = await validator
          .validate();
      await validator.dispose();

      expect(report.schemaReady, isTrue);
      expect(report.rowCount, 2);
      expect(report.invalidConfigCount, 1);
      expect(report.duplicateGroupCount, 1);
      expect(report.compatibilityIndexReady, isFalse);
    });
  });

  group('LocalSongLyricsDbRepairService', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lddc-local-song-lyrics-repair-',
      );
      dbFile = File(p.join(tempDir.path, 'local_song_lyrics.db'));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('repair 会创建Python版 schema', () async {
      final sqlite3.Database db = sqlite3.sqlite3.open(dbFile.path);
      db.close();

      final LocalSongLyricsDbRepairService repairService =
          LocalSongLyricsDbRepairService(executor: NativeDatabase(dbFile));
      final LocalSongLyricsDbRepairReport report = await repairService.repair();
      await repairService.dispose();

      expect(report.createdSchema, isTrue);
      expect(report.validation.schemaReady, isTrue);
      expect(report.validation.compatibilityIndexReady, isTrue);
    });

    test('repair 会修复损坏 config、归一化空值并去重', () async {
      final sqlite3.Database db = sqlite3.sqlite3.open(dbFile.path);
      _createRelaxedSchema(db);
      db.execute(
        '''
INSERT INTO songs (
  title, artist, album, duration, song_path, track_number, lyrics_path, config
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
''',
        <Object?>[
          '晴天',
          '周杰伦',
          '叶惠美',
          269000,
          'file://D:/music/qt.mp3',
          '1',
          null,
          '{broken',
        ],
      );
      db.execute(
        '''
INSERT INTO songs (
  title, artist, album, duration, song_path, track_number, lyrics_path, config
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
''',
        <Object?>[
          '晴天',
          '周杰伦',
          '叶惠美',
          269000,
          'file://D:/music/qt.mp3',
          '1',
          r'D:\lyrics\qt-2.lrc',
          jsonEncode(<String, Object?>{'offset': 100}),
        ],
      );
      db.close();

      final LocalSongLyricsDbRepairService repairService =
          LocalSongLyricsDbRepairService(executor: NativeDatabase(dbFile));
      final LocalSongLyricsDbRepairReport report = await repairService.repair();
      await repairService.dispose();

      expect(report.repairedConfigCount, 1);
      expect(report.removedDuplicateCount, 1);
      expect(report.validation.invalidConfigCount, 0);
      expect(report.validation.duplicateGroupCount, 0);

      final sqlite3.Database repaired = sqlite3.sqlite3.open(dbFile.path);
      final sqlite3.Row row = repaired
          .select('SELECT lyrics_path, config FROM songs LIMIT 1')
          .first;
      repaired.close();

      expect(row['lyrics_path'], r'D:\lyrics\qt-2.lrc');
      expect(jsonDecode(row['config'] as String), <String, Object?>{
        'offset': 100,
      });
    });

    test('repair 会补齐Python版库中已存在表的缺失列', () async {
      final sqlite3.Database db = sqlite3.sqlite3.open(dbFile.path);
      db.execute('''
CREATE TABLE songs (
  id INTEGER PRIMARY KEY,
  title TEXT,
  artist TEXT,
  album TEXT,
  duration INTEGER,
  song_path TEXT
)
''');
      db.execute(
        '''
INSERT INTO songs (title, artist, album, duration, song_path)
VALUES (?1, ?2, ?3, ?4, ?5)
''',
        <Object>['夜曲', '周杰伦', '十一月的萧邦', 236000, 'yequ.mp3'],
      );
      db.close();

      final LocalSongLyricsDbRepairService repairService =
          LocalSongLyricsDbRepairService(executor: NativeDatabase(dbFile));
      final LocalSongLyricsDbRepairReport report = await repairService.repair();
      await repairService.dispose();

      expect(report.createdSchema, isFalse);
      expect(report.validation.schemaReady, isTrue);
      expect(report.validation.missingColumns, isEmpty);
      expect(report.validation.invalidConfigCount, 0);

      final sqlite3.Database repaired = sqlite3.sqlite3.open(dbFile.path);
      final sqlite3.Row row = repaired
          .select('SELECT track_number, lyrics_path, config FROM songs')
          .first;
      repaired.close();

      expect(row['track_number'], '');
      expect(row['lyrics_path'], '');
      expect(jsonDecode(row['config'] as String), <String, Object?>{});
    });

    test('repair 保留真实库中出现的 CUE、非正时长、空轨号和 config 扩展键', () async {
      final sqlite3.Database db = sqlite3.sqlite3.open(dbFile.path);
      _createRelaxedSchema(db);
      const String insert = '''
INSERT INTO songs (
  title, artist, album, duration, song_path, track_number, lyrics_path, config
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
''';
      db.execute(insert, <Object>[
        'Synthetic CUE',
        'Unit Alpha',
        'Fixture Collection',
        281253,
        'fixture://disc.cue',
        '1',
        'fixture://disc.lrc',
        '{}',
      ]);
      db.execute(insert, <Object>[
        'Synthetic Duration',
        'Unit Beta',
        'Fixture Collection',
        -1,
        'fixture://duration.flac',
        '2',
        '',
        jsonEncode(<String, Object?>{'inst': true, 'offset': -125}),
      ]);
      db.execute(insert, <Object>[
        'Synthetic Track',
        'Unit Gamma',
        'Fixture Collection',
        180000,
        'fixture://track.flac',
        '',
        '',
        jsonEncode(<String, Object?>{
          'langs': <String>['orig', 'ts'],
          'disable_auto_search': true,
        }),
      ]);
      db.close();

      final LocalSongLyricsDbRepairService repairService =
          LocalSongLyricsDbRepairService(executor: NativeDatabase(dbFile));
      final LocalSongLyricsDbRepairReport report = await repairService.repair();
      await repairService.dispose();

      expect(report.repairedConfigCount, 0);
      expect(report.removedDuplicateCount, 0);
      expect(report.validation.rowCount, 3);

      final sqlite3.Database repaired = sqlite3.sqlite3.open(dbFile.path);
      final List<sqlite3.Row> rows = repaired.select(
        'SELECT duration, song_path, track_number, config FROM songs ORDER BY id',
      );
      repaired.close();

      expect(rows[0]['song_path'], 'fixture://disc.cue');
      expect(rows[1]['duration'], -1);
      expect(rows[2]['track_number'], '');
      expect(jsonDecode(rows[1]['config'] as String), <String, Object?>{
        'inst': true,
        'offset': -125,
      });
      expect(jsonDecode(rows[2]['config'] as String), <String, Object?>{
        'langs': <String>['orig', 'ts'],
        'disable_auto_search': true,
      });
    });
  });

  group('LocalSongLyricsDbBackupService', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lddc-local-song-lyrics-backup-',
      );
      dbFile = File(p.join(tempDir.path, 'local_song_lyrics.db'));
      await dbFile.writeAsString('seed');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('backup/restore 可往返', () async {
      const LocalSongLyricsDbBackupService service =
          LocalSongLyricsDbBackupService();
      final String backupPath = await service.backup(dbPath: dbFile.path);
      await dbFile.writeAsString('dirty');
      await service.restore(backupPath: backupPath, dbPath: dbFile.path);

      expect(await dbFile.readAsString(), 'seed');
    });

    test('backupWithReport 会备份 WAL/SHM 旁路文件并记录 warning', () async {
      await File('${dbFile.path}-wal').writeAsString('wal');
      await File('${dbFile.path}-shm').writeAsString('shm');
      const LocalSongLyricsDbBackupService service =
          LocalSongLyricsDbBackupService();

      final LocalSongLyricsDbBackupResult result = await service
          .backupWithReport(dbPath: dbFile.path);

      expect(result.warnings, hasLength(2));
      expect(await File('${result.backupPath}-wal').readAsString(), 'wal');
      expect(await File('${result.backupPath}-shm').readAsString(), 'shm');
    });
  });
}

void _createRelaxedSchema(sqlite3.Database db) {
  db.execute('''
CREATE TABLE IF NOT EXISTS songs (
  id INTEGER PRIMARY KEY,
  title TEXT,
  artist TEXT,
  album TEXT,
  duration INTEGER,
  song_path TEXT,
  track_number TEXT,
  lyrics_path TEXT,
  config TEXT
)
''');
}
