import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/config/config.dart';

void main() {
  group('ConfigMigrator', () {
    test('v0 配置可迁移到 v1 并完成 key 重映射', () {
      final Map<String, Object?> legacy = <String, Object?>{
        'lyrics_file_name_fmt': 'legacy_fmt',
        'default_save_path': 'D:\\Lyrics',
        'ID3_version': 'v2.4',
        'desktop_lyrics_rect': <double>[1, 2, 3, 4],
        'legacy.extra': 1,
      };

      final ConfigMigrationResult result = ConfigMigrator.migrate(legacy);
      final Map<String, Object?> migrated = result.values!;

      expect(result.sourceVersion, 0);
      expect(result.targetVersion, ConfigDefaults.currentSchemaVersion);
      expect(result.changed, isTrue);
      expect(
        migrated[configSchemaVersionKey],
        ConfigDefaults.currentSchemaVersion,
      );
      expect(migrated[ConfigKey.lyricsFileNameFormat], 'legacy_fmt');
      expect(migrated[ConfigKey.storageDefaultSavePath], 'D:\\Lyrics');
      expect(migrated[ConfigKey.lyricsId3Version], 'v2.4');
      expect(migrated[ConfigKey.desktopWindowRect], <double>[1, 2, 3, 4]);
      expect(migrated.containsKey('lyrics_file_name_fmt'), isFalse);
      expect(migrated.containsKey('desktop_lyrics_rect'), isFalse);
      expect(migrated['legacy.extra'], 1);
    });

    test('迁移链幂等：重复执行不再变更', () {
      final Map<String, Object?> legacy = <String, Object?>{
        'multi_search_sources': <String>['QM', 'KG'],
      };

      final ConfigMigrationResult first = ConfigMigrator.migrate(legacy);
      final ConfigMigrationResult second = ConfigMigrator.migrate(first.values);

      expect(second.changed, isFalse);
      expect(second.values, first.values);
    });

    test('高于当前支持版本的配置保持原样交给仓储无损处理', () {
      final Map<String, Object?> future = <String, Object?>{
        configSchemaVersionKey: ConfigDefaults.currentSchemaVersion + 1,
        'future.key': <String, Object?>{'nested': true},
      };

      final ConfigMigrationResult result = ConfigMigrator.migrate(future);

      expect(result.sourceVersion, ConfigDefaults.currentSchemaVersion + 1);
      expect(result.targetVersion, ConfigDefaults.currentSchemaVersion + 1);
      expect(result.changed, isFalse);
      expect(result.values, future);
    });
  });
}
