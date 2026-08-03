// ignore_for_file: avoid_slow_async_io
// 迁移测试覆盖异步备份、回滚和报告写入流程，因此临时文件检查也使用异步 API。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:lddc/src/infra/storage/legacy_data_migration_runner.dart';

void main() {
  group('LegacyDataMigrationRunner', () {
    late Directory tempDir;
    late File configFile;
    late File libraryDbFile;
    late File reportFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lddc-mig-runner-');
      configFile = File(p.join(tempDir.path, 'config.json'));
      libraryDbFile = File(p.join(tempDir.path, 'local_song_lyrics.db'));
      reportFile = File(p.join(tempDir.path, 'migration_report.json'));

      await configFile.writeAsString(
        jsonEncode(<String, Object?>{
          'lyrics_file_name_fmt': 'legacy_fmt',
          'default_save_path': r'D:\Lyrics',
        }),
      );
      _createLegacyDb(libraryDbFile.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('成功接管会输出报告且不触发回滚', () async {
      final LegacyDataMigrationRunner runner = LegacyDataMigrationRunner();

      final LegacyDataMigrationReport report = await runner.run(
        legacyConfigPath: configFile.path,
        libraryDbPath: libraryDbFile.path,
        reportPath: reportFile.path,
      );

      expect(report.success, isTrue);
      expect(report.rollbackApplied, isFalse);
      expect(report.config.changed, isTrue);
      expect(report.library.repair.validation.rowCount, 1);
      expect(report.library.repair.validation.schemaReady, isTrue);
      expect(report.library.backupPath, endsWith('.lddc_backup'));
      expect(await reportFile.exists(), isTrue);

      final Map<String, Object?> migratedConfig = Map<String, Object?>.from(
        jsonDecode(await configFile.readAsString()) as Map<dynamic, dynamic>,
      );
      expect(migratedConfig['lyrics_file_name_fmt'], 'legacy_fmt');
      expect(migratedConfig['default_save_path'], r'D:\Lyrics');
      expect(migratedConfig.containsKey('lyrics.fileNameFormat'), isFalse);
      expect(migratedConfig.containsKey('schemaVersion'), isFalse);

      final Map<String, Object?> reportJson = Map<String, Object?>.from(
        jsonDecode(await reportFile.readAsString()) as Map<dynamic, dynamic>,
      );
      expect(reportJson['success'], isTrue);
      expect(reportJson['rollbackApplied'], isFalse);
      final Map<String, Object?> libraryJson = Map<String, Object?>.from(
        reportJson['library'] as Map<dynamic, dynamic>,
      );
      expect(libraryJson['warnings'], isEmpty);
    });

    test('接管失败会回滚并写入失败报告', () async {
      final String originalConfigText = await configFile.readAsString();
      await libraryDbFile.writeAsString('before');

      final LegacyDataMigrationRunner runner = LegacyDataMigrationRunner(
        libraryMaintenanceRunner: ({required String libraryDbPath}) async {
          await File(libraryDbPath).writeAsString('dirty');
          throw StateError('mock maintenance failure');
        },
      );

      final LegacyDataMigrationReport report = await runner.run(
        legacyConfigPath: configFile.path,
        libraryDbPath: libraryDbFile.path,
        reportPath: reportFile.path,
      );

      expect(report.success, isFalse);
      expect(report.rollbackApplied, isTrue);
      expect(report.errorMessage, contains('mock maintenance failure'));
      expect(await configFile.readAsString(), originalConfigText);
      expect(await libraryDbFile.readAsString(), 'before');
      expect(await reportFile.exists(), isTrue);

      final Map<String, Object?> reportJson = Map<String, Object?>.from(
        jsonDecode(await reportFile.readAsString()) as Map<dynamic, dynamic>,
      );
      expect(reportJson['success'], isFalse);
      expect(reportJson['rollbackApplied'], isTrue);
    });

    test('接管会修复损坏 config JSON', () async {
      final sqlite3.Database db = sqlite3.sqlite3.open(libraryDbFile.path);
      db.execute('UPDATE songs SET config = ?1', <Object>['{broken']);
      db.close();

      final LegacyDataMigrationRunner runner = LegacyDataMigrationRunner();
      final LegacyDataMigrationReport report = await runner.run(
        legacyConfigPath: configFile.path,
        libraryDbPath: libraryDbFile.path,
        reportPath: reportFile.path,
      );

      expect(report.success, isTrue);
      expect(report.library.repair.repairedConfigCount, 1);

      final sqlite3.Database repaired = sqlite3.sqlite3.open(
        libraryDbFile.path,
      );
      final sqlite3.Row row = repaired.select('SELECT config FROM songs').first;
      repaired.close();
      expect(jsonDecode(row['config'] as String), <String, Object?>{});
    });

    test('接管报告会记录 WAL/SHM 备份 warning', () async {
      await File('${libraryDbFile.path}-wal').writeAsString('wal');
      await File('${libraryDbFile.path}-shm').writeAsString('shm');

      final LegacyDataMigrationRunner runner = LegacyDataMigrationRunner();
      final LegacyDataMigrationReport report = await runner.run(
        legacyConfigPath: configFile.path,
        libraryDbPath: libraryDbFile.path,
        reportPath: reportFile.path,
      );

      expect(report.success, isTrue);
      expect(report.library.warnings, hasLength(2));
      expect(report.warningCount, greaterThanOrEqualTo(2));

      final Map<String, Object?> reportJson = Map<String, Object?>.from(
        jsonDecode(await reportFile.readAsString()) as Map<dynamic, dynamic>,
      );
      final Map<String, Object?> libraryJson = Map<String, Object?>.from(
        reportJson['library'] as Map<dynamic, dynamic>,
      );
      expect(libraryJson['warnings'], hasLength(2));
    });
  });
}

void _createLegacyDb(String dbPath) {
  final sqlite3.Database db = sqlite3.sqlite3.open(dbPath);
  db.execute('''
CREATE TABLE IF NOT EXISTS songs (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  album TEXT NOT NULL,
  duration INTEGER NOT NULL,
  song_path TEXT NOT NULL,
  track_number TEXT NOT NULL,
  lyrics_path TEXT,
  config TEXT
)
''');
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
      r'file://D:\music\yequ.mp3',
      '1',
      r'D:\lyrics\yequ.lrc',
      jsonEncode(<String, Object?>{'offset': 120}),
    ],
  );
  db.close();
}
