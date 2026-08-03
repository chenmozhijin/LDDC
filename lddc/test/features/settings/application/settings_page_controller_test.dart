import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/features/settings/application/settings_page_controller.dart';
import 'package:lddc/src/features/settings/application/settings_page_dependencies.dart';
import 'package:lddc/src/features/settings/application/settings_page_models.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

void main() {
  group('SettingsPageController', () {
    test('默认分组为保存并按能力决定工具分组可见性', () {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(payload.activeSection, SettingsSection.save);
      expect(payload.showDesktopTools, isTrue);
    });

    test('切换分组并写入设置后，状态与配置同步更新', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);

      final SettingsPageController controller = container.read(
        settingsPageControllerProvider.notifier,
      );
      controller.setActiveSection(SettingsSection.search);
      await controller.updateSearchSources(<String>['QM', 'NE']);

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(payload.activeSection, SettingsSection.search);
      expect(payload.config.search.sources, <String>['QM', 'NE']);
    });

    test('翻译字段可见性会随翻译源切换', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);

      final SettingsPageController controller = container.read(
        settingsPageControllerProvider.notifier,
      );
      await controller.updateTranslateSource(TranslateSource.openai);

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(
        payload.visibleTranslateFields,
        contains(SettingsTranslateField.openAiBaseUrl),
      );
      expect(
        payload.visibleTranslateFields,
        contains(SettingsTranslateField.openAiApiKey),
      );
    });

    test('OpenAI 预设会同步填充官方 Base URL 且不覆盖模型', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        _configWithOpenAi(
          profile: OpenAiProfile.custom,
          baseUrl: 'https://custom.example/v1',
          model: 'user-model',
        ),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);

      final SettingsPageController controller = container.read(
        settingsPageControllerProvider.notifier,
      );
      await controller.updateOpenAiProfile(OpenAiProfile.deepSeek);
      SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(payload.config.translate.openAi.profile, OpenAiProfile.deepSeek);
      expect(
        payload.config.translate.openAi.baseUrl,
        'https://api.deepseek.com',
      );
      expect(payload.config.translate.openAi.model, 'user-model');

      await controller.updateOpenAiProfile(OpenAiProfile.kimi);
      payload = _payloadOf(container.read(settingsPageControllerProvider));
      expect(payload.config.translate.openAi.profile, OpenAiProfile.kimi);
      expect(
        payload.config.translate.openAi.baseUrl,
        'https://api.moonshot.cn/v1',
      );
      expect(payload.config.translate.openAi.model, 'user-model');

      await controller.updateOpenAiBaseUrl('https://gateway.example/v1');
      await controller.updateOpenAiProfile(OpenAiProfile.custom);
      payload = _payloadOf(container.read(settingsPageControllerProvider));
      expect(payload.config.translate.openAi.profile, OpenAiProfile.custom);
      expect(
        payload.config.translate.openAi.baseUrl,
        'https://gateway.example/v1',
      );
      expect(payload.config.translate.openAi.model, 'user-model');
    });

    test('桌面歌词颜色修改会写入配置', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);

      final SettingsPageController controller = container.read(
        settingsPageControllerProvider.notifier,
      );
      await controller.updateDesktopPlayedColors(<List<int>>[
        <int>[1, 2, 3],
        <int>[4, 5, 6],
      ]);
      await controller.updateDesktopUnplayedColors(<List<int>>[
        <int>[7, 8, 9],
      ]);

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(
        payload.config.desktop.playedColors
            .map((RgbColor color) => color.toTuple())
            .toList(growable: false),
        <List<int>>[
          <int>[1, 2, 3],
          <int>[4, 5, 6],
        ],
      );
      expect(
        payload.config.desktop.unplayedColors
            .map((RgbColor color) => color.toTuple())
            .toList(growable: false),
        <List<int>>[
          <int>[7, 8, 9],
        ],
      );
    });

    test('打开歌词关联管理器会调用注入的 app 导航能力', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      bool opened = false;
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(
          repository,
          openAssociationManager: () async {
            opened = true;
          },
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(settingsPageControllerProvider.notifier)
          .openAssociationManager();

      expect(opened, isTrue);
      expect(
        container.read(settingsPageControllerProvider).action.message,
        SettingsNoticeCode.associationManagerOpened.name,
      );
    });

    test('界面语言切换后配置同步更新', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);

      final SettingsPageController controller = container.read(
        settingsPageControllerProvider.notifier,
      );
      await controller.updateAppLanguage(AppLanguage.en);
      SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(payload.config.app.language, AppLanguage.en);

      await controller.updateAppLanguage(AppLanguage.zhHans);
      payload = _payloadOf(container.read(settingsPageControllerProvider));
      expect(payload.config.app.language, AppLanguage.zhHans);
    });

    test('选择默认保存目录会通过依赖回调写入配置', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(
          repository,
          pickDirectory: ({String? initialDirectory}) async => r'D:\Music',
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(settingsPageControllerProvider.notifier)
          .pickDefaultSavePath();

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(payload.config.storage.defaultSavePath, r'D:\Music');
      expect(
        container.read(settingsPageControllerProvider).action.message,
        SettingsNoticeCode.defaultSavePathUpdated.name,
      );
    });

    test('连续设置写入会串行执行并以最后一次提交为准', () async {
      final Completer<void> firstWrite = Completer<void>();
      final Completer<void> secondWrite = Completer<void>();
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
        updateBarriers: <Completer<void>>[firstWrite, secondWrite],
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);
      final SettingsPageController controller = container.read(
        settingsPageControllerProvider.notifier,
      );

      final Future<void> first = controller.updateDefaultSavePath(r'D:\old');
      await Future<void>.delayed(Duration.zero);
      final Future<void> second = controller.updateDefaultSavePath(r'D:\new');
      await Future<void>.delayed(Duration.zero);

      expect(repository.updateCount, 1);
      firstWrite.complete();
      await Future<void>.delayed(Duration.zero);
      expect(repository.updateCount, 2);
      secondWrite.complete();
      await Future.wait(<Future<void>>[first, second]);

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(payload.config.storage.defaultSavePath, r'D:\new');
      expect(
        container.read(settingsPageControllerProvider).action.message,
        SettingsNoticeCode.defaultSavePathUpdated.name,
      );
    });

    test('恢复单个分组只写回该分组默认值', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        _configWithOpenAi(
          profile: OpenAiProfile.deepSeek,
          baseUrl: 'https://api.deepseek.com',
          model: 'user-model',
        ),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);

      await container
          .read(settingsPageControllerProvider.notifier)
          .restoreSectionDefaults(SettingsSection.translate);

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(
        payload.config.translate.source,
        ConfigDefaults.current.translate.source,
      );
      expect(
        payload.config.translate.openAi.profile,
        ConfigDefaults.current.translate.openAi.profile,
      );
      expect(payload.config.translate.openAi.model, isNot('user-model'));
      expect(
        payload.config.search.sources,
        ConfigDefaults.current.search.sources,
      );
    });

    test('恢复桌面歌词分组会同步恢复颜色配置', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);
      final SettingsPageController controller = container.read(
        settingsPageControllerProvider.notifier,
      );

      await controller.updateDesktopPlayedColors(<List<int>>[
        <int>[1, 2, 3],
      ]);
      await controller.updateDesktopUnplayedColors(<List<int>>[
        <int>[4, 5, 6],
      ]);
      await controller.updateDesktopFontSize(66);
      await controller.restoreSectionDefaults(SettingsSection.desktopLyrics);

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(
        payload.config.desktop.playedColors
            .map((RgbColor color) => color.toTuple())
            .toList(growable: false),
        ConfigDefaults.current.desktop.playedColors
            .map((RgbColor color) => color.toTuple())
            .toList(growable: false),
      );
      expect(
        payload.config.desktop.unplayedColors
            .map((RgbColor color) => color.toTuple())
            .toList(growable: false),
        ConfigDefaults.current.desktop.unplayedColors
            .map((RgbColor color) => color.toTuple())
            .toList(growable: false),
      );
      expect(
        payload.config.desktop.fontSize,
        ConfigDefaults.current.desktop.fontSize,
      );
      expect(
        container.read(settingsPageControllerProvider).action.message,
        SettingsNoticeCode.sectionDefaultsRestored.name,
      );
    });

    test('恢复工具分组不会执行无意义配置写入', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository),
      );
      addTearDown(container.dispose);

      await container
          .read(settingsPageControllerProvider.notifier)
          .restoreSectionDefaults(SettingsSection.tools);

      expect(repository.updateCount, 0);
      expect(
        container.read(settingsPageControllerProvider).action.message,
        SettingsNoticeCode.sectionNoRestorableConfig.name,
      );
    });

    test('打开日志目录失败会保留稳定失败提示码', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final List<_DiagnosticRecord> diagnostics = <_DiagnosticRecord>[];
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(
          repository,
          diagnostics: diagnostics,
          openLogDirectory: () async {
            throw StateError('open failed');
          },
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(settingsPageControllerProvider.notifier)
          .openLogDirectory();

      expect(
        container.read(settingsPageControllerProvider).action.message,
        SettingsNoticeCode.logDirectoryOpenFailed.name,
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.action, 'openLogDirectory');
      expect(diagnostics.single.error, isA<StateError>());
    });

    test('清缓存失败会保留稳定失败提示码', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
      );
      final List<_DiagnosticRecord> diagnostics = <_DiagnosticRecord>[];
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(
          repository,
          diagnostics: diagnostics,
          clearCache: () async {
            throw StateError('clear failed');
          },
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(settingsPageControllerProvider.notifier)
          .clearCache();

      expect(
        container.read(settingsPageControllerProvider).action.message,
        SettingsNoticeCode.cacheClearFailed.name,
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.action, 'clearCache');
      expect(diagnostics.single.error, isA<StateError>());
    });

    test('设置写入失败会记录 patch key 诊断并回滚页面状态', () async {
      final _MemoryConfigRepository repository = _MemoryConfigRepository(
        ConfigDefaults.current,
        updateError: StateError('write failed'),
      );
      final List<_DiagnosticRecord> diagnostics = <_DiagnosticRecord>[];
      final ProviderContainer container = ProviderContainer(
        overrides: _settingsOverrides(repository, diagnostics: diagnostics),
      );
      addTearDown(container.dispose);

      await container
          .read(settingsPageControllerProvider.notifier)
          .updateDefaultSavePath(r'D:\broken');

      final SettingsPagePayload payload = _payloadOf(
        container.read(settingsPageControllerProvider),
      );
      expect(
        container.read(settingsPageControllerProvider).action.message,
        SettingsNoticeCode.configWriteFailed.name,
      );
      expect(
        payload.config.storage.defaultSavePath,
        ConfigDefaults.current.storage.defaultSavePath,
      );
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.action, 'updateConfig');
      expect(diagnostics.single.fields['patchKeys'], <String>[
        ConfigKey.storageDefaultSavePath,
      ]);
    });
  });
}

List<Override> _settingsOverrides(
  _MemoryConfigRepository repository, {
  AppCapability? capability,
  SettingsDirectoryPicker? pickDirectory,
  Future<void> Function()? openAssociationManager,
  Future<void> Function()? openLogDirectory,
  Future<void> Function()? clearCache,
  List<_DiagnosticRecord>? diagnostics,
}) {
  return <Override>[
    settingsPageDependenciesProvider.overrideWithValue(
      SettingsPageDependencies(
        config: repository.current,
        capability: capability ?? _desktopCapability(),
        updateConfig: repository.update,
        pickDirectory:
            pickDirectory ?? ({String? initialDirectory}) async => null,
        openAssociationManager: openAssociationManager ?? () async {},
        openLogDirectory: openLogDirectory ?? () async {},
        clearCache: clearCache ?? () async {},
        logFailure:
            ({
              required String action,
              required Object error,
              required StackTrace stackTrace,
              required Map<String, Object?> fields,
            }) {
              diagnostics?.add(
                _DiagnosticRecord(
                  action: action,
                  error: error,
                  stackTrace: stackTrace,
                  fields: fields,
                ),
              );
            },
      ),
    ),
  ];
}

SettingsPagePayload _payloadOf(PageViewState<SettingsPagePayload> state) {
  final Object view = state.view;
  if (view is AsyncSuccess<SettingsPagePayload>) {
    return view.data;
  }
  if (view is AsyncPartial<SettingsPagePayload>) {
    return view.data;
  }
  throw StateError('unexpected view state: $view');
}

class _MemoryConfigRepository implements ConfigRepository {
  _MemoryConfigRepository(
    this._current, {
    List<Completer<void>>? updateBarriers,
    this.updateError,
  }) : _updateBarriers = updateBarriers ?? <Completer<void>>[];

  final StreamController<AppConfig> _controller =
      StreamController<AppConfig>.broadcast();
  AppConfig _current;
  int updateCount = 0;
  final List<Completer<void>> _updateBarriers;
  final Object? updateError;

  @override
  AppConfig get current => _current;

  @override
  Future<AppConfig> load() async => _current;

  @override
  Future<AppConfig> refreshFromStorage() async => _current;

  @override
  Future<AppConfig> update(Map<String, Object?> patch) async {
    updateCount += 1;
    if (_updateBarriers.isNotEmpty) {
      await _updateBarriers.removeAt(0).future;
    }
    final Object? error = updateError;
    if (error != null) {
      throw error;
    }
    final DefaultConfigRepository repository = DefaultConfigRepository(
      storage: InMemoryConfigStorage(ConfigDefaults.flattenRequired(_current)),
    );
    await repository.load();
    _current = await repository.update(patch);
    _controller.add(_current);
    return _current;
  }

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield _current;
    }
    yield* _controller.stream;
  }
}

class _DiagnosticRecord {
  const _DiagnosticRecord({
    required this.action,
    required this.error,
    required this.stackTrace,
    required this.fields,
  });

  final String action;
  final Object error;
  final StackTrace stackTrace;
  final Map<String, Object?> fields;
}

AppCapability _desktopCapability() {
  return const AppCapability(
    multiWindow: true,
    desktopPanelDetached: true,
    desktopPanelEmbedded: true,
    systemTray: true,
    globalHotkey: true,
    audioTagWrite: true,
    directoryRecursiveScan: true,
    androidSafTreeAccess: false,
    androidCueTrackResolve: false,
    webFileSystemAccess: false,
    webTaglibWasmReady: false,
  );
}

AppConfig _configWithOpenAi({
  required OpenAiProfile profile,
  required String baseUrl,
  required String model,
}) {
  final AppConfig base = ConfigDefaults.current;
  return AppConfig(
    schemaVersion: base.schemaVersion,
    search: base.search,
    lyrics: base.lyrics,
    match: base.match,
    translate: TranslateConfig(
      source: TranslateSource.openai,
      targetLang: base.translate.targetLang,
      openAi: OpenAiConfig(
        profile: profile,
        baseUrl: baseUrl,
        apiKey: 'sk-test',
        model: model,
      ),
    ),
    desktop: base.desktop,
    app: base.app,
    storage: base.storage,
    legacyExtras: base.legacyExtras,
  );
}
