import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/config/config.dart';

void main() {
  group('ConfigDefaults', () {
    test('required defaults cover all migration required keys', () {
      expect(
        ConfigDefaults.requiredKeyDefaults.keys.toSet(),
        ConfigKey.requiredKeys,
      );
      expect(
        ConfigDefaults.hasAllRequiredKeys(ConfigDefaults.requiredKeyDefaults),
        isTrue,
      );
    });

    test('typed current defaults flatten to required key defaults', () {
      expect(
        ConfigDefaults.flattenRequired(ConfigDefaults.current),
        ConfigDefaults.requiredKeyDefaults,
      );
      expect(
        ConfigDefaults.current.schemaVersion,
        ConfigDefaults.currentSchemaVersion,
      );
    });

    test(
      'default save path stays pure until repository resolves platform path',
      () {
        expect(ConfigDefaults.defaultSavePath, isEmpty);
        expect(
          ConfigDefaults.requiredKeyDefaults[ConfigKey.storageDefaultSavePath],
          isEmpty,
        );
        expect(ConfigDefaults.current.storage.defaultSavePath, isEmpty);

        final AppConfig withResolvedPath =
            ConfigDefaults.currentWithDefaultSavePath('/music/lyrics');
        expect(withResolvedPath.storage.defaultSavePath, '/music/lyrics');
        expect(ConfigDefaults.current.storage.defaultSavePath, isEmpty);
      },
    );
  });
}
