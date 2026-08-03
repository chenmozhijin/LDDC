import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/config/config.dart';

/// 测试用存储：用于断言仓储是否触发回写。
class _RecordingConfigStorage implements ConfigStorage {
  _RecordingConfigStorage([Map<String, Object?>? seed])
    : _values = seed == null ? null : Map<String, Object?>.from(seed);

  Map<String, Object?>? _values;
  int writeCount = 0;
  bool failNextRead = false;

  Map<String, Object?>? get lastWritten =>
      _values == null ? null : Map<String, Object?>.from(_values!);

  @override
  Future<Map<String, Object?>?> read() async {
    if (failNextRead) {
      failNextRead = false;
      throw StateError('模拟配置读取失败');
    }
    final Map<String, Object?>? values = _values;
    if (values == null) {
      return null;
    }
    return Map<String, Object?>.from(values);
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    _values = Map<String, Object?>.from(values);
    writeCount += 1;
  }

  void replace(Map<String, Object?> values) {
    _values = Map<String, Object?>.from(values);
  }
}

class _ControlledWriteConfigStorage implements ConfigStorage {
  _ControlledWriteConfigStorage(Map<String, Object?> seed)
    : _values = Map<String, Object?>.from(seed);

  Map<String, Object?> _values;
  final List<Map<String, Object?>> writes = <Map<String, Object?>>[];
  final List<Completer<void>> _releases = <Completer<void>>[];

  @override
  Future<Map<String, Object?>?> read() async {
    return Map<String, Object?>.from(_values);
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    final Map<String, Object?> snapshot = Map<String, Object?>.from(values);
    final Completer<void> release = Completer<void>();
    writes.add(snapshot);
    _releases.add(release);
    await release.future;
    _values = snapshot;
  }

  void releaseWrite(int index) {
    _releases[index].complete();
  }
}

class _FailOnceConfigStorage implements ConfigStorage {
  _FailOnceConfigStorage(Map<String, Object?> seed)
    : _values = Map<String, Object?>.from(seed);

  Map<String, Object?> _values;
  bool failNextWrite = true;

  @override
  Future<Map<String, Object?>?> read() async {
    return Map<String, Object?>.from(_values);
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟配置写入失败');
    }
    _values = Map<String, Object?>.from(values);
  }
}

void main() {
  group('DefaultConfigRepository', () {
    test('load 使用默认配置初始化空存储', () async {
      final _RecordingConfigStorage storage = _RecordingConfigStorage();
      int resolverCalls = 0;
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
        defaultSavePathResolver: () async {
          resolverCalls += 1;
          return '/music/lyrics';
        },
      );

      final List<AppConfig> concurrentLoads = await Future.wait(
        <Future<AppConfig>>[repository.load(), repository.load()],
      );
      final AppConfig config = concurrentLoads.first;
      final AppConfig loadedAgain = await repository.load();

      expect(config.schemaVersion, ConfigDefaults.currentSchemaVersion);
      expect(config.search.sources, ConfigDefaults.current.search.sources);
      expect(
        config.lyrics.fileNameFormat,
        ConfigDefaults.current.lyrics.fileNameFormat,
      );
      expect(config.storage.defaultSavePath, '/music/lyrics');
      expect(config.legacyExtras, isEmpty);
      expect(identical(config, loadedAgain), isTrue);
      expect(identical(config, concurrentLoads.last), isTrue);
      expect(resolverCalls, 1);
      expect(storage.writeCount, 1);
      expect(
        storage.lastWritten?[ConfigKey.storageDefaultSavePath],
        '/music/lyrics',
      );

      await repository.dispose();
    });

    test('高版本配置加载时不回写，显式更新仅覆盖目标键', () async {
      final Map<String, Object?> futureValue = <String, Object?>{
        'nested': <Object?>[true, 'kept'],
      };
      final _RecordingConfigStorage storage = _RecordingConfigStorage(
        <String, Object?>{
          'schemaVersion': 7,
          ConfigKey.lyricsMsDigits: 2,
          ConfigKey.desktopWindowRect: <double>[10, 20, 300, 120],
          ConfigKey.matchSkipInst: 'invalid',
          ConfigKey.translateTargetLang: 'KOREAN',
          ConfigKey.appColorScheme: 'FUTURE_THEME',
          'future.custom': futureValue,
        },
      );
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
      );

      final AppConfig config = await repository.load();

      expect(config.schemaVersion, 7);
      expect(config.lyrics.msDigits, 2);
      expect(config.desktop.windowRect, isNotNull);
      expect(config.desktop.windowRect!.left, 10);
      expect(config.match.skipInst, isTrue);
      expect(config.translate.targetLang, TranslateTargetLang.korean);
      expect(config.app.colorScheme, AppColorScheme.auto);
      expect(config.legacyExtras['future.custom'], futureValue);
      expect(storage.writeCount, 0);

      final AppConfig updated = await repository.update(<String, Object?>{
        ConfigKey.appLanguage: 'en',
      });

      expect(updated.schemaVersion, 7);
      expect(updated.app.language, AppLanguage.en);
      expect(storage.writeCount, 1);
      expect(storage.lastWritten?[configSchemaVersionKey], 7);
      expect(storage.lastWritten?[ConfigKey.appLanguage], 'en');
      expect(storage.lastWritten?[ConfigKey.appColorScheme], 'FUTURE_THEME');
      expect(storage.lastWritten?['future.custom'], futureValue);

      await repository.dispose();
    });

    test('load 会迁移 v0 配置并回写 v1 结果', () async {
      final _RecordingConfigStorage storage = _RecordingConfigStorage(
        <String, Object?>{
          'lyrics_file_name_fmt': 'legacy_fmt',
          'default_save_path': 'D:\\Lyrics',
          'multi_search_sources': <String>['NE', 'QM'],
          'legacy.custom': 'keep',
        },
      );
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
      );

      final AppConfig config = await repository.load();

      expect(config.schemaVersion, ConfigDefaults.currentSchemaVersion);
      expect(config.lyrics.fileNameFormat, 'legacy_fmt');
      expect(config.storage.defaultSavePath, 'D:\\Lyrics');
      expect(config.search.sources, <String>['NE', 'QM']);
      expect(config.legacyExtras['legacy.custom'], 'keep');

      expect(storage.writeCount, 1);
      expect(
        storage.lastWritten?[configSchemaVersionKey],
        ConfigDefaults.currentSchemaVersion,
      );
      expect(storage.lastWritten?.containsKey('lyrics_file_name_fmt'), isFalse);
      expect(
        storage.lastWritten?[ConfigKey.lyricsFileNameFormat],
        'legacy_fmt',
      );

      await repository.dispose();
    });

    test('legacy_extras 在多次读写中保持快照且不丢失', () async {
      final Map<String, Object?> legacyMap = <String, Object?>{'k': 'v'};
      final List<Object?> legacyList = <Object?>['a', 1];
      final _RecordingConfigStorage storage =
          _RecordingConfigStorage(<String, Object?>{
            ConfigKey.lyricsMsDigits: 3,
            'legacy.map': legacyMap,
            'legacy.list': legacyList,
          });
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
      );

      final AppConfig loaded = await repository.load();
      legacyMap['k'] = 'changed';
      legacyList.add('x');

      final Map<Object?, Object?> loadedMap =
          loaded.legacyExtras['legacy.map']! as Map<Object?, Object?>;
      final List<Object?> loadedList =
          loaded.legacyExtras['legacy.list']! as List<Object?>;
      expect(loadedMap['k'], 'v');
      expect(loadedList, <Object?>['a', 1]);

      await repository.update(<String, Object?>{ConfigKey.appLanguage: 'en'});

      final DefaultConfigRepository reloadedRepository =
          DefaultConfigRepository(storage: storage);
      final AppConfig reloaded = await reloadedRepository.load();
      final Map<Object?, Object?> reloadedMap =
          reloaded.legacyExtras['legacy.map']! as Map<Object?, Object?>;
      final List<Object?> reloadedList =
          reloaded.legacyExtras['legacy.list']! as List<Object?>;
      expect(reloadedMap['k'], 'v');
      expect(reloadedList, <Object?>['a', 1]);

      await repository.dispose();
      await reloadedRepository.dispose();
    });

    test('update 支持受控 key 级 patch 并持久化', () async {
      final InMemoryConfigStorage storage = InMemoryConfigStorage();
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
      );
      await repository.load();

      final AppConfig updated = await repository.update(<String, Object?>{
        ConfigKey.appLanguage: 'en',
        ConfigKey.lyricsMsDigits: 2,
      });

      expect(updated.app.language, AppLanguage.en);
      expect(updated.lyrics.msDigits, 2);

      final DefaultConfigRepository nextRepository = DefaultConfigRepository(
        storage: storage,
      );
      final AppConfig reloaded = await nextRepository.load();
      expect(reloaded.app.language, AppLanguage.en);
      expect(reloaded.lyrics.msDigits, 2);

      await repository.dispose();
      await nextRepository.dispose();
    });

    test('OpenAI 新预设可读取写回且不新增 reasoning 配置键', () async {
      final InMemoryConfigStorage storage =
          InMemoryConfigStorage(<String, Object?>{
            ConfigKey.translateOpenAiProfile: 'DEEPSEEK',
            ConfigKey.translateOpenAiBaseUrl: 'https://api.deepseek.com',
            ConfigKey.translateOpenAiApiKey: 'sk-demo',
            ConfigKey.translateOpenAiModel: 'deepseek-v4-flash',
          });
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
      );

      AppConfig config = await repository.load();
      expect(config.translate.openAi.profile, OpenAiProfile.deepSeek);
      expect(config.translate.openAi.baseUrl, 'https://api.deepseek.com');

      config = await repository.update(<String, Object?>{
        ConfigKey.translateOpenAiProfile: 'KIMI',
        ConfigKey.translateOpenAiBaseUrl: 'https://api.moonshot.cn/v1',
      });
      expect(config.translate.openAi.profile, OpenAiProfile.kimi);
      expect(config.translate.openAi.baseUrl, 'https://api.moonshot.cn/v1');

      final Map<String, Object?> written =
          (await storage.read()) ?? <String, Object?>{};
      expect(written[ConfigKey.translateOpenAiProfile], 'KIMI');
      expect(
        written.keys.where(
          (String key) => key.contains('reasoning') || key.contains('thinking'),
        ),
        isEmpty,
      );

      await repository.dispose();
    });

    test('update 拒绝新增未知 legacyExtras 键', () async {
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: InMemoryConfigStorage(),
      );
      await repository.load();

      await expectLater(
        repository.update(<String, Object?>{'legacy.runtime': 123}),
        throwsA(isA<ArgumentError>()),
      );

      await repository.dispose();
    });

    test('update 拒绝由业务调用方修改 schemaVersion', () async {
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: InMemoryConfigStorage(),
      );
      await repository.load();

      await expectLater(
        repository.update(<String, Object?>{configSchemaVersionKey: 99}),
        throwsA(isA<ArgumentError>()),
      );

      await repository.dispose();
    });

    test('watch 会先输出当前快照再输出变更快照', () async {
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: InMemoryConfigStorage(),
      );

      final Future<List<AppConfig>> eventsFuture = repository
          .watch()
          .take(2)
          .toList();
      await Future<void>.delayed(Duration.zero);

      await repository.update(<String, Object?>{
        ConfigKey.appLogLevel: 'ERROR',
      });

      final List<AppConfig> events = await eventsFuture;
      expect(events[0].app.logLevel, AppLogLevel.info);
      expect(events[1].app.logLevel, AppLogLevel.error);

      await repository.dispose();
    });

    test('update 写入失败时不发布内存状态，后续操作仍可重试', () async {
      final _FailOnceConfigStorage storage =
          _FailOnceConfigStorage(<String, Object?>{
            configSchemaVersionKey: ConfigDefaults.currentSchemaVersion,
            ...ConfigDefaults.requiredKeyDefaults,
          });
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
      );
      await repository.load();

      await expectLater(
        repository.update(<String, Object?>{ConfigKey.appLanguage: 'en'}),
        throwsStateError,
      );
      expect(repository.current.app.language, AppLanguage.auto);
      expect(
        (await storage.read())?[ConfigKey.appLanguage],
        AppLanguage.auto.value,
      );

      final AppConfig retried = await repository.update(<String, Object?>{
        ConfigKey.appLanguage: 'en',
      });
      expect(retried.app.language, AppLanguage.en);
      expect(repository.current.app.language, AppLanguage.en);

      await repository.dispose();
    });

    test('并发 update 按调用顺序持久化，并隔离调用方后续修改', () async {
      final _ControlledWriteConfigStorage storage =
          _ControlledWriteConfigStorage(<String, Object?>{
            configSchemaVersionKey: ConfigDefaults.currentSchemaVersion,
            ...ConfigDefaults.requiredKeyDefaults,
          });
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
      );
      await repository.load();

      final Future<AppConfig> first = repository.update(<String, Object?>{
        ConfigKey.appLanguage: 'en',
      });
      while (storage.writes.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repository.current.app.language, AppLanguage.auto);
      final List<String> sources = <String>['NE'];
      final Future<AppConfig> second = repository.update(<String, Object?>{
        ConfigKey.searchSources: sources,
      });
      sources[0] = 'QM';
      await Future<void>.delayed(Duration.zero);

      // 第二次写必须等第一次完整提交，避免较慢的旧快照最后覆盖持久存储。
      expect(storage.writes, hasLength(1));
      storage.releaseWrite(0);
      await first;
      while (storage.writes.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      storage.releaseWrite(1);
      await second;

      final Map<String, Object?> persisted = (await storage.read())!;
      expect(persisted[ConfigKey.appLanguage], 'en');
      expect(persisted[ConfigKey.searchSources], <String>['NE']);
      expect(repository.current.app.language, AppLanguage.en);
      expect(repository.current.search.sources, <String>['NE']);
      await repository.dispose();
    });

    test('refreshFromStorage 同步其它 engine 的落盘配置并发布事件', () async {
      final _RecordingConfigStorage storage = _RecordingConfigStorage(
        <String, Object?>{
          configSchemaVersionKey: ConfigDefaults.currentSchemaVersion,
          ...ConfigDefaults.requiredKeyDefaults,
          'future.selector.option': <String, Object?>{'kept': true},
        },
      );
      final DefaultConfigRepository mainRepository = DefaultConfigRepository(
        storage: storage,
      );
      final DefaultConfigRepository selectorRepository =
          DefaultConfigRepository(storage: storage);
      await mainRepository.load();
      await selectorRepository.load();
      final Future<AppConfig> selectorEvent = selectorRepository
          .watch(emitCurrent: false)
          .first;
      await Future<void>.delayed(Duration.zero);

      await mainRepository.update(<String, Object?>{
        ConfigKey.searchSources: <String>['NE'],
        ConfigKey.translateSource: 'OPENAI',
      });
      final AppConfig refreshed = await selectorRepository.refreshFromStorage();

      expect(refreshed.search.sources, <String>['NE']);
      expect(refreshed.translate.source, TranslateSource.openai);
      expect(
        refreshed.legacyExtras['future.selector.option'],
        <String, Object?>{'kept': true},
      );
      expect(await selectorEvent, same(refreshed));
      await mainRepository.dispose();
      await selectorRepository.dispose();
    });

    test('refreshFromStorage 读取失败时保留旧快照且后续可重试', () async {
      final _RecordingConfigStorage storage =
          _RecordingConfigStorage(<String, Object?>{
            configSchemaVersionKey: ConfigDefaults.currentSchemaVersion,
            ...ConfigDefaults.requiredKeyDefaults,
          });
      final DefaultConfigRepository repository = DefaultConfigRepository(
        storage: storage,
      );
      final AppConfig previous = await repository.load();
      storage.replace(<String, Object?>{
        configSchemaVersionKey: ConfigDefaults.currentSchemaVersion,
        ...ConfigDefaults.requiredKeyDefaults,
        ConfigKey.searchSources: <String>['KG'],
      });
      storage.failNextRead = true;

      await expectLater(
        repository.refreshFromStorage(),
        throwsA(isA<StateError>()),
      );
      expect(repository.current, same(previous));

      final AppConfig retried = await repository.refreshFromStorage();
      expect(retried.search.sources, <String>['KG']);
      await repository.dispose();
    });
  });
}
