// ignore_for_file: avoid_slow_async_io
// 旧数据接管会访问配置、数据库和备份文件，所有文件状态检查都保持异步，避免迁移期间阻塞 UI isolate。

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';

import '../../core/config/config.dart';
import 'legacy_config_file_codec.dart';
import 'local_song_lyrics_db_support.dart';

/// 配置迁移报告。
class LegacyConfigMigrationReport {
  const LegacyConfigMigrationReport({
    required this.sourceVersion,
    required this.targetVersion,
    required this.changed,
    this.skippedReason,
  });

  final int sourceVersion;
  final int targetVersion;
  final bool changed;
  final String? skippedReason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sourceVersion': sourceVersion,
      'targetVersion': targetVersion,
      'changed': changed,
      'skippedReason': skippedReason,
    };
  }
}

/// Python版关联库维护报告。
class LocalSongLyricsDbMaintenanceReport {
  const LocalSongLyricsDbMaintenanceReport({
    required this.backupPath,
    required this.repair,
    this.warnings = const <String>[],
  });

  final String backupPath;
  final LocalSongLyricsDbRepairReport repair;
  final List<String> warnings;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backupPath': backupPath,
      'warnings': warnings,
      'createdSchema': repair.createdSchema,
      'normalizedNullFieldCount': repair.normalizedNullFieldCount,
      'repairedConfigCount': repair.repairedConfigCount,
      'removedDuplicateCount': repair.removedDuplicateCount,
      'validation': <String, Object?>{
        'schemaReady': repair.validation.schemaReady,
        'rowCount': repair.validation.rowCount,
        'invalidConfigCount': repair.validation.invalidConfigCount,
        'duplicateGroupCount': repair.validation.duplicateGroupCount,
        'compatibilityIndexReady': repair.validation.compatibilityIndexReady,
        'missingColumns': repair.validation.missingColumns,
      },
    };
  }
}

/// 迁移/接管执行报告。
///
/// 该报告会落盘到 `migration_report.json`，用于诊断Python版配置与Python版关联库接管是否成功。
class LegacyDataMigrationReport {
  const LegacyDataMigrationReport({
    required this.success,
    required this.startedAtUtc,
    required this.finishedAtUtc,
    required this.rollbackApplied,
    required this.config,
    required this.library,
    required this.warningCount,
    this.errorMessage,
  });

  final bool success;
  final String startedAtUtc;
  final String finishedAtUtc;
  final bool rollbackApplied;
  final LegacyConfigMigrationReport config;
  final LocalSongLyricsDbMaintenanceReport library;
  final int warningCount;
  final String? errorMessage;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'success': success,
      'startedAtUtc': startedAtUtc,
      'finishedAtUtc': finishedAtUtc,
      'rollbackApplied': rollbackApplied,
      'warningCount': warningCount,
      'errorMessage': errorMessage,
      'config': config.toJson(),
      'library': library.toJson(),
    };
  }
}

/// 迁移异常，携带结构化报告方便上层展示与记录。
class LegacyDataMigrationException implements Exception {
  const LegacyDataMigrationException(this.report);

  final LegacyDataMigrationReport report;

  @override
  String toString() =>
      'LegacyDataMigrationException(success=${report.success}, error=${report.errorMessage})';
}

typedef LocalSongLyricsDbMaintenanceRunner =
    Future<LocalSongLyricsDbMaintenanceReport> Function({
      required String libraryDbPath,
    });

/// 旧数据接管编排器（含失败回滚）。
///
/// 流程已改为：
/// 1. 备份 `config.json` 与 `local_song_lyrics.db`
/// 2. 执行配置迁移
/// 3. 执行Python版关联库校验/修复
/// 4. 写入报告
/// 5. 任一步失败则回滚
class LegacyDataMigrationRunner {
  LegacyDataMigrationRunner({
    LocalSongLyricsDbMaintenanceRunner? libraryMaintenanceRunner,
    LegacyConfigFileCodec? configFileCodec,
  }) : _libraryMaintenanceRunner =
           libraryMaintenanceRunner ?? _defaultLibraryMaintenanceRunner,
       _configFileCodec = configFileCodec ?? const LegacyConfigFileCodec();

  final LocalSongLyricsDbMaintenanceRunner _libraryMaintenanceRunner;
  final LegacyConfigFileCodec _configFileCodec;

  Future<LegacyDataMigrationReport> run({
    required String legacyConfigPath,
    required String libraryDbPath,
    required String reportPath,
    bool throwOnFailure = false,
  }) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final List<_FileBackupEntry> backups = <_FileBackupEntry>[
      _FileBackupEntry(originalPath: legacyConfigPath),
      _FileBackupEntry(originalPath: libraryDbPath),
    ];

    LegacyConfigMigrationReport configReport =
        const LegacyConfigMigrationReport(
          sourceVersion: ConfigDefaults.currentSchemaVersion,
          targetVersion: ConfigDefaults.currentSchemaVersion,
          changed: false,
          skippedReason: 'not_started',
        );
    LocalSongLyricsDbMaintenanceReport libraryReport =
        const LocalSongLyricsDbMaintenanceReport(
          backupPath: '',
          warnings: <String>[],
          repair: LocalSongLyricsDbRepairReport(
            createdSchema: false,
            normalizedNullFieldCount: 0,
            repairedConfigCount: 0,
            removedDuplicateCount: 0,
            validation: LocalSongLyricsDbValidationReport(
              schemaReady: false,
              rowCount: 0,
              invalidConfigCount: 0,
              duplicateGroupCount: 0,
              compatibilityIndexReady: false,
            ),
          ),
        );
    bool rollbackApplied = false;

    try {
      for (final _FileBackupEntry backup in backups) {
        await backup.create();
      }

      configReport = await _migrateConfigFile(legacyConfigPath);
      libraryReport = await _libraryMaintenanceRunner(
        libraryDbPath: libraryDbPath,
      );

      final LegacyDataMigrationReport report = LegacyDataMigrationReport(
        success: true,
        startedAtUtc: startedAt.toIso8601String(),
        finishedAtUtc: DateTime.now().toUtc().toIso8601String(),
        rollbackApplied: false,
        config: configReport,
        library: libraryReport,
        warningCount:
            libraryReport.repair.repairedConfigCount +
            libraryReport.repair.removedDuplicateCount +
            libraryReport.warnings.length,
      );
      await _writeReport(reportPath, report);
      return report;
    } catch (error) {
      rollbackApplied = await _restoreBackups(backups);
      final LegacyDataMigrationReport report = LegacyDataMigrationReport(
        success: false,
        startedAtUtc: startedAt.toIso8601String(),
        finishedAtUtc: DateTime.now().toUtc().toIso8601String(),
        rollbackApplied: rollbackApplied,
        config: configReport,
        library: libraryReport,
        warningCount:
            libraryReport.repair.repairedConfigCount +
            libraryReport.repair.removedDuplicateCount +
            libraryReport.warnings.length,
        errorMessage: error.toString(),
      );
      await _writeReport(reportPath, report);
      if (throwOnFailure) {
        throw LegacyDataMigrationException(report);
      }
      return report;
    } finally {
      for (final _FileBackupEntry backup in backups) {
        await backup.cleanup();
      }
    }
  }

  Future<LegacyConfigMigrationReport> _migrateConfigFile(
    String configPath,
  ) async {
    final File file = File(configPath);
    if (!await file.exists()) {
      return LegacyConfigMigrationReport(
        sourceVersion: ConfigDefaults.currentSchemaVersion,
        targetVersion: ConfigDefaults.currentSchemaVersion,
        changed: false,
        skippedReason: 'config_file_not_found',
      );
    }

    final String raw = await file.readAsString();
    final Map<String, Object?>? data = raw.trim().isEmpty
        ? null
        : _decodeConfigJson(raw);
    final ConfigMigrationResult result = ConfigMigrator.migrate(data);
    if (result.values != null) {
      final JsonEncoder encoder = const JsonEncoder.withIndent('    ');
      await file.writeAsString(
        encoder.convert(_configFileCodec.encode(result.values!)),
      );
    }
    return LegacyConfigMigrationReport(
      sourceVersion: result.sourceVersion,
      targetVersion: result.targetVersion,
      changed: result.changed,
    );
  }

  Map<String, Object?> _decodeConfigJson(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('config.json 顶层必须为对象');
    }
    return _normalizeMap(decoded);
  }

  Future<void> _writeReport(
    String reportPath,
    LegacyDataMigrationReport report,
  ) async {
    final File file = File(reportPath);
    final Directory parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(report.toJson()));
  }

  Future<bool> _restoreBackups(List<_FileBackupEntry> backups) async {
    bool restored = true;
    for (final _FileBackupEntry backup in backups) {
      restored = await backup.restore() && restored;
    }
    return restored;
  }

  Map<String, Object?> _normalizeMap(Map<dynamic, dynamic> raw) {
    final Map<String, Object?> normalized = <String, Object?>{};
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      normalized[entry.key.toString()] = _normalizeJsonValue(entry.value);
    }
    return normalized;
  }

  Object? _normalizeJsonValue(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Map) {
      return _normalizeMap(value);
    }
    if (value is List) {
      return value.map(_normalizeJsonValue).toList(growable: false);
    }
    return value.toString();
  }

  static Future<LocalSongLyricsDbMaintenanceReport>
  _defaultLibraryMaintenanceRunner({required String libraryDbPath}) async {
    final LocalSongLyricsDbBackupService backupService =
        const LocalSongLyricsDbBackupService();
    final File dbFile = File(libraryDbPath);
    final bool dbExists = await dbFile.exists();
    final LocalSongLyricsDbBackupResult? backupResult = dbExists
        ? await backupService.backupWithReport(dbPath: libraryDbPath)
        : null;
    final LocalSongLyricsDbRepairService repairService =
        LocalSongLyricsDbRepairService(
          executor: NativeDatabase(File(libraryDbPath)),
        );
    try {
      final LocalSongLyricsDbRepairReport repair = await repairService.repair();
      return LocalSongLyricsDbMaintenanceReport(
        backupPath: backupResult?.backupPath ?? '',
        warnings: backupResult?.warnings ?? const <String>[],
        repair: repair,
      );
    } finally {
      await repairService.dispose();
    }
  }
}

/// 单文件备份条目。
///
/// 备份策略：
/// - 若原文件存在：复制到 `${path}.lddc_mig_backup`
/// - 若原文件不存在：记录缺失，回滚时删除迁移中创建的新文件
class _FileBackupEntry {
  _FileBackupEntry({required this.originalPath})
    : backupPath = '$originalPath.lddc_mig_backup';

  final String originalPath;
  final String backupPath;
  bool _created = false;
  bool _originalExisted = false;

  Future<void> create() async {
    final File original = File(originalPath);
    _originalExisted = await original.exists();
    if (_originalExisted) {
      final File backup = File(backupPath);
      await original.copy(backup.path);
      _created = true;
    }
  }

  Future<bool> restore() async {
    try {
      final File original = File(originalPath);
      final File backup = File(backupPath);
      if (_created && await backup.exists()) {
        await backup.copy(original.path);
        return true;
      }
      if (!_originalExisted && await original.exists()) {
        await original.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cleanup() async {
    if (!_created) {
      return;
    }
    final File backup = File(backupPath);
    if (await backup.exists()) {
      await backup.delete();
    }
  }
}
