import 'config_defaults.dart';
import 'config_legacy_keys.dart';

/// 配置版本号字段名。
const String configSchemaVersionKey = 'schemaVersion';

/// 配置迁移步骤定义：声明起止版本并执行 map 级转换。
abstract interface class ConfigMigrationStep {
  int get fromVersion;

  int get toVersion;

  Map<String, Object?> migrate(Map<String, Object?> input);
}

/// 配置迁移执行结果。
class ConfigMigrationResult {
  const ConfigMigrationResult({
    required this.values,
    required this.sourceVersion,
    required this.targetVersion,
    required this.changed,
  });

  final Map<String, Object?>? values;
  final int sourceVersion;
  final int targetVersion;
  final bool changed;
}

/// 迁移链执行器：按版本顺序串行执行迁移步骤。
class ConfigMigrator {
  ConfigMigrator._();

  static final List<ConfigMigrationStep> _defaultSteps = <ConfigMigrationStep>[
    _V0ToV1ConfigMigration(),
  ];

  /// 将原始配置迁移到当前 schema。
  static ConfigMigrationResult migrate(
    Map<String, Object?>? raw, {
    List<ConfigMigrationStep>? steps,
  }) {
    if (raw == null) {
      return const ConfigMigrationResult(
        values: null,
        sourceVersion: 0,
        targetVersion: ConfigDefaults.currentSchemaVersion,
        changed: false,
      );
    }

    final Map<String, Object?> working = Map<String, Object?>.from(raw);
    final List<ConfigMigrationStep> migrationSteps = steps ?? _defaultSteps;
    final int sourceVersion = _readVersion(working[configSchemaVersionKey]);
    int currentVersion = sourceVersion;
    bool changed = false;

    while (currentVersion < ConfigDefaults.currentSchemaVersion) {
      final ConfigMigrationStep step = _findStep(
        migrationSteps,
        currentVersion,
      );
      final Map<String, Object?> migrated = step.migrate(working);
      working
        ..clear()
        ..addAll(migrated);
      currentVersion = step.toVersion;
      changed = true;
    }

    if (working[configSchemaVersionKey] != currentVersion) {
      working[configSchemaVersionKey] = currentVersion;
      changed = true;
    }

    return ConfigMigrationResult(
      values: working,
      sourceVersion: sourceVersion,
      targetVersion: currentVersion,
      changed: changed,
    );
  }

  static ConfigMigrationStep _findStep(
    List<ConfigMigrationStep> steps,
    int fromVersion,
  ) {
    for (final ConfigMigrationStep step in steps) {
      if (step.fromVersion == fromVersion) {
        return step;
      }
    }
    throw StateError('Missing migration step: v$fromVersion -> ?');
  }

  static int _readVersion(Object? value) {
    if (value is int && value >= 0) {
      return value;
    }
    if (value is double && value.isFinite && value >= 0) {
      return value.toInt();
    }
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null && parsed >= 0) {
        return parsed;
      }
    }
    return 0;
  }
}

/// `v0 -> v1` 迁移：
/// - Python版配置键重映射到 Flutter 点分 key
/// - 补齐 `schemaVersion`
/// - 同时存在新旧 key 时优先保留新 key
class _V0ToV1ConfigMigration implements ConfigMigrationStep {
  @override
  int get fromVersion => 0;

  @override
  int get toVersion => 1;

  @override
  Map<String, Object?> migrate(Map<String, Object?> input) {
    final Map<String, Object?> migrated = Map<String, Object?>.from(input);
    for (final MapEntry<String, String> entry
        in LegacyConfigKeyMap.legacyToCurrent.entries) {
      if (!migrated.containsKey(entry.value) &&
          migrated.containsKey(entry.key)) {
        migrated[entry.value] = migrated[entry.key];
      }
      migrated.remove(entry.key);
    }
    migrated[configSchemaVersionKey] = toVersion;
    return migrated;
  }
}
