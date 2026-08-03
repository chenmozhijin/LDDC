import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/config/config_defaults.dart';
import 'package:lddc/src/core/config/config_legacy_keys.dart';
import 'package:lddc/src/core/config/config_migration.dart';
import 'package:lddc/src/infra/storage/legacy_config_file_codec.dart';

void main() {
  const LegacyConfigFileCodec codec = LegacyConfigFileCodec();

  test('Python 默认 config.json 经 Flutter 编解码后逐项无损', () {
    final Map<String, Object?> pythonConfig = _readPythonDefaultConfig();

    final Map<String, Object?> decoded = codec.decode(pythonConfig);
    final Map<String, Object?> encoded = codec.encode(decoded);

    expect(
      decoded[configSchemaVersionKey],
      ConfigDefaults.currentSchemaVersion,
    );
    expect(encoded, pythonConfig);
    for (final String legacyKey in pythonConfig.keys) {
      final String? currentKey = LegacyConfigKeyMap.legacyToCurrent[legacyKey];
      if (currentKey == null) {
        continue;
      }
      expect(decoded.containsKey(legacyKey), isFalse);
      expect(decoded[currentKey], pythonConfig[legacyKey]);
    }
  });

  test('编解码器深拷贝 Python 嵌套配置，不会修改调用方原始对象', () {
    final Map<String, Object?> pythonConfig = _readPythonDefaultConfig();
    final List<Object?> originalColors =
        pythonConfig['desktop_lyrics_played_colors']! as List<Object?>;

    final Map<String, Object?> decoded = codec.decode(pythonConfig);
    final List<Object?> decodedColors =
        decoded[LegacyConfigKeyMap
                .legacyToCurrent['desktop_lyrics_played_colors']]!
            as List<Object?>;
    (decodedColors.first! as List<Object?>)[0] = 99;

    expect((originalColors.first! as List<Object?>).first, 0);
  });
}

Map<String, Object?> _readPythonDefaultConfig() {
  final Object? payload = jsonDecode(
    File('test/data/python_default_config.json').readAsStringSync(),
  );
  return Map<String, Object?>.from(payload! as Map<dynamic, dynamic>);
}
