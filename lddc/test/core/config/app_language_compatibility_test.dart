import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/config/app_config.dart';
import 'package:lddc/src/core/config/config_keys.dart';
import 'package:lddc/src/core/config/config_repository.dart';
import 'package:lddc/src/infra/storage/legacy_config_file_codec.dart';

void main() {
  const LegacyConfigFileCodec codec = LegacyConfigFileCodec();

  test('Python language 键可以迁移到 Flutter app.language', () {
    final Map<String, Object?> decoded = codec.decode(<String, Object?>{
      'language': 'zh-Hant',
      'future.option': <String, Object?>{'enabled': true},
    });

    expect(decoded[ConfigKey.appLanguage], 'zh-Hant');
    expect(decoded.containsKey('language'), isFalse);
    expect(decoded['future.option'], <String, Object?>{'enabled': true});
  });

  test('Flutter AppLanguage 值可以按 Python 格式写回', () {
    for (final AppLanguage language in AppLanguage.values) {
      final Map<String, Object?> decoded = codec.decode(<String, Object?>{
        'language': language.value,
      });
      expect(decoded[ConfigKey.appLanguage], language.value);

      final Map<String, Object?> encoded = codec.encode(decoded);
      expect(encoded['language'], language.value);
      expect(encoded.containsKey(ConfigKey.appLanguage), isFalse);
    }
  });

  test('新旧配置键同时存在时保留 Flutter 当前键', () {
    final Map<String, Object?> decoded = codec.decode(<String, Object?>{
      'language': 'zh-Hans',
      ConfigKey.appLanguage: 'en',
    });

    expect(decoded[ConfigKey.appLanguage], 'en');
    expect(decoded.containsKey('language'), isFalse);
  });

  test('非法 Python language 安全回退 auto 并记录诊断', () async {
    final List<(String, Map<String, Object?>)> diagnostics =
        <(String, Map<String, Object?>)>[];
    final DefaultConfigRepository repository = DefaultConfigRepository(
      storage: InMemoryConfigStorage(
        codec.decode(<String, Object?>{'language': 'not-a-locale'}),
      ),
      diagnosticSink: (String message, Map<String, Object?> fields) {
        diagnostics.add((message, fields));
      },
    );
    addTearDown(repository.dispose);

    final AppConfig config = await repository.load();

    expect(config.app.language, AppLanguage.auto);
    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.$2['value'], 'not-a-locale');
  });

  test('修改 Flutter 设置后仍保留 Python 未知嵌套键', () async {
    final Map<String, Object?> futureOption = <String, Object?>{
      'enabled': true,
      'values': <Object?>[1, 'two'],
    };
    final InMemoryConfigStorage storage = InMemoryConfigStorage(
      codec.decode(<String, Object?>{
        'language': 'ja',
        'future.option': futureOption,
      }),
    );
    final DefaultConfigRepository repository = DefaultConfigRepository(
      storage: storage,
    );
    addTearDown(repository.dispose);

    await repository.load();
    await repository.update(<String, Object?>{
      ConfigKey.appColorScheme: AppColorScheme.dark.value,
    });
    final Map<String, Object?> pythonValues = codec.encode(
      (await storage.read())!,
    );

    expect(pythonValues['language'], 'ja');
    expect(pythonValues['future.option'], futureOption);
    expect(pythonValues.containsKey(ConfigKey.appLanguage), isFalse);
  });
}
