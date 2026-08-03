import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/app_feature_scopes.dart';
import 'package:lddc/src/app/bootstrap/app_bootstrap.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/features/settings/application/settings_page_models.dart';
import 'package:lddc/src/features/settings/presentation/widgets/settings_data_helpers.dart';
import 'package:lddc/src/features/settings/presentation/widgets/settings_section_components.dart';

void main() {
  test('重排 helper 按 Flutter onReorder 语义修正向下拖动索引', () {
    final List<SettingsOrderedToggleItem> items = <SettingsOrderedToggleItem>[
      _toggleItem('orig'),
      _toggleItem('ts'),
      _toggleItem('roma'),
      _toggleItem('extra'),
    ];

    expect(orderedValues(reorderItems(items, 0, 3)), <String>[
      'ts',
      'roma',
      'orig',
      'extra',
    ]);
    expect(orderedValues(reorderItems(items, 3, 1)), <String>[
      'orig',
      'extra',
      'ts',
      'roma',
    ]);
  });

  test('设置页 descriptor 覆盖来源、语言、翻译和日志枚举', () {
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('zh'));
    expect(descriptorValues(settingsLyricLangDescriptors(l10n)), <String>[
      'roma',
      'orig',
      'ts',
    ]);
    expect(descriptorValues(settingsSearchSourceDescriptors(l10n)), <String>[
      'QM',
      'KG',
      'NE',
      'LRCLIB',
    ]);
    expect(
      descriptorValues(settingsTranslateSourceDescriptors(l10n)),
      TranslateSource.values,
    );
    expect(
      descriptorValues(settingsTranslateTargetDescriptors(l10n)),
      TranslateTargetLang.values,
    );
    expect(
      descriptorValues(settingsAppLanguageDescriptors(l10n)),
      AppLanguage.values,
    );
    expect(
      settingsAppLanguageDescriptors(
        l10n,
      ).skip(1).map((SettingsValueDescriptor<AppLanguage> item) => item.label),
      <String>['简体中文', '繁體中文', 'English', 'Русский', '日本語', '한국어'],
    );
    expect(
      descriptorValues(settingsColorSchemeDescriptors(l10n)),
      AppColorScheme.values,
    );
    expect(descriptorValues(settingsLogLevelDescriptors), AppLogLevel.values);
  });

  testWidgets('受控文本字段在聚焦编辑时不会被外部重建覆盖，失焦后提交', (WidgetTester tester) async {
    final List<String> submitted = <String>[];
    String externalValue = 'saved';

    Widget buildField() {
      return MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              SettingsTextField(
                key: const ValueKey<String>('settings_test_text_field'),
                label: 'Base URL',
                initialValue: externalValue,
                onSubmitted: submitted.add,
              ),
              TextButton(
                key: const ValueKey<String>('settings_test_blur_target'),
                onPressed: () {},
                child: const Text('blur'),
              ),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(buildField());
    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'draft');
    await tester.pumpWidget(buildField());

    TextFormField textField = tester.widget<TextFormField>(
      find.byType(TextFormField),
    );
    expect(textField.controller?.text, 'draft');
    expect(submitted, isEmpty);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(submitted, <String>['draft']);

    externalValue = 'server';
    await tester.pumpWidget(buildField());
    textField = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(textField.controller?.text, 'server');
  });

  testWidgets('滑块拖动只更新本地显示，结束拖动时才写入配置', (WidgetTester tester) async {
    final List<double> submitted = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSliderField(
            label: '字号',
            value: 10,
            min: 8,
            max: 20,
            divisions: 12,
            valueLabel: '10 px',
            onChanged: submitted.add,
          ),
        ),
      ),
    );

    tester.widget<Slider>(find.byType(Slider)).onChanged?.call(12);
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider)).onChanged?.call(14);
    await tester.pump();

    expect(find.text('14 px'), findsOneWidget);
    expect(submitted, isEmpty);

    tester.widget<Slider>(find.byType(Slider)).onChangeEnd?.call(14);
    expect(submitted, <double>[14]);
  });

  testWidgets('桌面设置页使用单页锚点结构并显示工具入口', (WidgetTester tester) async {
    await _setViewport(tester, const Size(1280, 900));
    await AppBootstrap.ensureInitialized(
      configRepository: _FixedConfigRepository(ConfigDefaults.current),
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_anchor_bar')),
      findsOneWidget,
    );
    expect(find.text('设置'), findsNothing);
    expect(find.text('修改后立即生效。'), findsNothing);
    expect(find.text('管理默认保存路径、歌词文件名模板和 ID3 标签版本。'), findsNothing);
    expect(find.text('恢复默认保存路径'), findsNothing);
    expect(find.text('恢复本组默认值'), findsWidgets);
    expect(find.text('恢复默认设置'), findsOneWidget);
    expect(find.textContaining('Python版'), findsNothing);
    expect(find.text('桌面歌词字号'), findsNothing);
    expect(find.text('决定“聚合”搜索和本地匹配默认使用的歌词来源。'), findsOneWidget);
    expect(find.text('聚合搜索来源'), findsOneWidget);
    expect(find.textContaining('搜索页选择“聚合”时查询已勾选来源'), findsOneWidget);
    expect(find.text('默认显示语言'), findsOneWidget);
    expect(find.text('自动获取来源'), findsOneWidget);
    expect(find.text('匹配行为'), findsOneWidget);
    expect(find.text('LRC 导出'), findsOneWidget);
    expect(find.text('导出语言顺序'), findsOneWidget);
    expect(find.text('使用当前行时间'), findsOneWidget);
    expect(find.text('歌词来源'), findsOneWidget);
    expect(find.text('已播放颜色'), findsOneWidget);
    expect(find.text('未播放颜色'), findsOneWidget);
    expect(find.byTooltip('拖动调整优先级'), findsWidgets);
    expect(find.byTooltip('拖动调整顺序'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey<String>('settings_anchor_tools')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('settings_tools_open_association_manager'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('分组恢复入口需要确认且只写入当前分组配置', (WidgetTester tester) async {
    await _setViewport(tester, const Size(1280, 900));
    final _TrackingConfigRepository repository = _TrackingConfigRepository(
      _configWithCustomSavePath(r'D:\Changed'),
    );
    addTearDown(repository.dispose);
    await AppBootstrap.ensureInitialized(
      configRepository: repository,
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_restore_section_save')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('仅恢复“保存”分组中的设置项'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(repository.patches, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_restore_section_save')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();

    expect(repository.patches, hasLength(1));
    expect(
      repository.patches.single.keys,
      containsAll(<String>[
        ConfigKey.storageDefaultSavePath,
        ConfigKey.lyricsFileNameFormat,
        ConfigKey.lyricsId3Version,
      ]),
    );
    expect(
      repository.patches.single.keys,
      isNot(contains(ConfigKey.searchSources)),
    );
  });

  testWidgets('窄屏设置页改为分组概览并可进入工具详情', (WidgetTester tester) async {
    await _setViewport(tester, const Size(390, 844));
    await AppBootstrap.ensureInitialized(
      configRepository: _FixedConfigRepository(ConfigDefaults.current),
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_compact_overview_list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings_anchor_bar')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('settings_compact_entry_tools')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('settings_tools_open_association_manager'),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_compact_entry_tools')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_compact_detail')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('settings_tools_open_association_manager'),
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_compact_overview_list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings_compact_detail')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏搜索详情在两倍文字缩放下显示摘要、说明和拖拽语义', (WidgetTester tester) async {
    await _setViewport(tester, const Size(390, 844));
    await AppBootstrap.ensureInitialized(
      configRepository: _FixedConfigRepository(ConfigDefaults.current),
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp(textScaleFactor: 2));
    await tester.pumpAndSettle();

    final Finder searchEntry = find.byKey(
      const ValueKey<String>('settings_compact_entry_search'),
    );
    await tester.ensureVisible(searchEntry);
    await tester.tap(searchEntry);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_compact_detail')),
      findsOneWidget,
    );
    expect(find.text('决定“聚合”搜索和本地匹配默认使用的歌词来源。'), findsOneWidget);
    expect(find.text('聚合搜索来源'), findsOneWidget);
    expect(find.textContaining('本地匹配默认沿用此列表'), findsOneWidget);
    expect(find.byTooltip('拖动调整优先级'), findsNWidgets(4));
    await tester.ensureVisible(find.byTooltip('拖动调整优先级').first);
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('拖动调整优先级'), findsWidgets);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索来源复选框继续写入原有配置键', (WidgetTester tester) async {
    await _setViewport(tester, const Size(1280, 900));
    final _TrackingConfigRepository repository = _TrackingConfigRepository(
      ConfigDefaults.current,
    );
    addTearDown(repository.dispose);
    await AppBootstrap.ensureInitialized(
      configRepository: repository,
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('settings_anchor_search')),
    );
    await tester.pumpAndSettle();

    final Finder searchList = find.byKey(
      const ValueKey<String>('settings_search_sources'),
    );
    final Finder firstCheckbox = find
        .descendant(of: searchList, matching: find.byType(Checkbox))
        .first;
    await tester.tap(firstCheckbox);
    await tester.pumpAndSettle();

    expect(repository.patches, isNotEmpty);
    expect(repository.patches.last[ConfigKey.searchSources], <String>[
      'KG',
      'NE',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页在窄屏与宽屏之间切换时保持稳定并恢复目标分组', (WidgetTester tester) async {
    await _setViewport(tester, const Size(390, 844));
    await AppBootstrap.ensureInitialized(
      configRepository: _FixedConfigRepository(ConfigDefaults.current),
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_compact_overview_list')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings_compact_entry_tools')),
    );
    await tester.pumpAndSettle();

    await _setViewport(tester, const Size(1280, 900));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_anchor_bar')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('settings_tools_open_association_manager'),
      ),
      findsOneWidget,
    );

    await _setViewport(tester, const Size(390, 844));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_compact_overview_list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('settings_compact_detail')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏滚动动画遇到布局尺寸变化时不读取 dirty RenderObject', (
    WidgetTester tester,
  ) async {
    await _setViewport(tester, const Size(1280, 900));
    await AppBootstrap.ensureInitialized(
      configRepository: _FixedConfigRepository(ConfigDefaults.current),
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('settings_anchor_translate')),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 尺寸变化会在下一帧 layout 前先推进滚动动画。旧实现此时读取
    // context.size，会因 SettingsPage 已标记 NEEDS-LAYOUT 而触发断言。
    await _setViewport(tester, const Size(1260, 880));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('移动能力下隐藏工具分组', (WidgetTester tester) async {
    await _setViewport(tester, const Size(390, 844));
    await AppBootstrap.ensureInitialized(
      configRepository: _FixedConfigRepository(ConfigDefaults.current),
      capabilityOverride: _mobileCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_compact_entry_tools')),
      findsNothing,
    );
  });

  testWidgets('翻译设置仅显示当前翻译源对应字段', (WidgetTester tester) async {
    await _setViewport(tester, const Size(1280, 900));
    final AppConfig openAiConfig = AppConfig(
      schemaVersion: ConfigDefaults.current.schemaVersion,
      search: ConfigDefaults.current.search,
      lyrics: ConfigDefaults.current.lyrics,
      match: ConfigDefaults.current.match,
      translate: const TranslateConfig(
        source: TranslateSource.openai,
        targetLang: TranslateTargetLang.simplifiedChinese,
        openAi: OpenAiConfig(
          profile: OpenAiProfile.custom,
          baseUrl: 'https://example.test/v1',
          apiKey: 'key',
          model: 'gpt-test',
        ),
      ),
      desktop: ConfigDefaults.current.desktop,
      app: ConfigDefaults.current.app,
      storage: ConfigDefaults.current.storage,
      legacyExtras: ConfigDefaults.current.legacyExtras,
    );

    await AppBootstrap.ensureInitialized(
      configRepository: _FixedConfigRepository(openAiConfig),
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_anchor_translate')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextFormField &&
            widget.key ==
                const ValueKey<String>('settings_translate_openai_base_url'),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextFormField &&
            widget.key ==
                const ValueKey<String>('settings_translate_openai_model'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings_translate_openai_profile')),
    );
    await tester.pumpAndSettle();

    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.text('Kimi'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is Text && widget.data == 'key',
      ),
      findsNothing,
    );
  });

  testWidgets('非 OpenAI 翻译源不显示 OpenAI 专属字段', (WidgetTester tester) async {
    await _setViewport(tester, const Size(1280, 900));
    await AppBootstrap.ensureInitialized(
      configRepository: _FixedConfigRepository(ConfigDefaults.current),
      capabilityOverride: _desktopCapability(),
    );
    addTearDown(AppBootstrap.resetForTest);

    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('settings_anchor_translate')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('settings_translate_openai_base_url')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('settings_translate_openai_api_key')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('settings_translate_openai_model')),
      findsNothing,
    );
  });
}

Widget _buildApp({double textScaleFactor = 1}) {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        );
      },
      home: const Scaffold(body: AppSettingsPageScope()),
    ),
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
}

class _FixedConfigRepository implements ConfigRepository {
  _FixedConfigRepository(this._config);

  final AppConfig _config;

  @override
  AppConfig get current => _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<AppConfig> refreshFromStorage() async => _config;

  @override
  Future<AppConfig> update(Map<String, Object?> patch) async => _config;

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield _config;
    }
  }
}

class _TrackingConfigRepository implements ConfigRepository {
  _TrackingConfigRepository(this._config);

  final StreamController<AppConfig> _controller =
      StreamController<AppConfig>.broadcast();
  final List<Map<String, Object?>> patches = <Map<String, Object?>>[];
  AppConfig _config;

  @override
  AppConfig get current => _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<AppConfig> refreshFromStorage() async => _config;

  @override
  Future<AppConfig> update(Map<String, Object?> patch) async {
    patches.add(Map<String, Object?>.from(patch));
    final DefaultConfigRepository repository = DefaultConfigRepository(
      storage: InMemoryConfigStorage(ConfigDefaults.flattenRequired(_config)),
    );
    try {
      await repository.load();
      _config = await repository.update(patch);
    } finally {
      await repository.dispose();
    }
    _controller.add(_config);
    return _config;
  }

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield _config;
    }
    yield* _controller.stream;
  }

  Future<void> dispose() => _controller.close();
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

AppCapability _mobileCapability() {
  return const AppCapability(
    multiWindow: false,
    desktopPanelDetached: false,
    desktopPanelEmbedded: false,
    systemTray: false,
    globalHotkey: false,
    audioTagWrite: true,
    directoryRecursiveScan: true,
    androidSafTreeAccess: true,
    androidCueTrackResolve: true,
    webFileSystemAccess: false,
    webTaglibWasmReady: false,
  );
}

AppConfig _configWithCustomSavePath(String savePath) {
  final AppConfig base = ConfigDefaults.current;
  return AppConfig(
    schemaVersion: base.schemaVersion,
    search: base.search,
    lyrics: base.lyrics,
    match: base.match,
    translate: base.translate,
    desktop: base.desktop,
    app: base.app,
    storage: StorageConfig(defaultSavePath: savePath),
    legacyExtras: base.legacyExtras,
  );
}

SettingsOrderedToggleItem _toggleItem(String value) {
  return SettingsOrderedToggleItem(value: value, label: value, selected: true);
}
