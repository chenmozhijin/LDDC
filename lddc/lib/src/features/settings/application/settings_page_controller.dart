import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/capability/capability.dart';
import '../../../core/config/config.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'settings_page_dependencies.dart';
import 'settings_page_models.dart';

part 'settings_page_controller.g.dart';

// 依赖入口允许页面级 ProviderScope 覆写；必须显式传播 scope 元数据，
// 否则 Riverpod 3.4 会拒绝控制器读取子作用域中的依赖快照。
@Riverpod(keepAlive: true, dependencies: [settingsPageDependencies])
class SettingsPageController extends _$SettingsPageController {
  SettingsSection _activeSection = SettingsSection.save;
  PageActionState _action = const PageActionState();
  final OperationEpoch _configWriteEpoch = OperationEpoch();
  Future<void> _configWriteTail = Future<void>.value();

  @override
  PageViewState<SettingsPagePayload> build() {
    final SettingsPageDependencies dependencies = ref.watch(
      settingsPageDependenciesProvider,
    );
    final AppConfig config = dependencies.config;
    final AppCapability capability = dependencies.capability;
    if (_activeSection == SettingsSection.tools &&
        !_showDesktopTools(capability)) {
      _activeSection = SettingsSection.save;
    }
    return _compose(config, capability);
  }

  void setActiveSection(SettingsSection section) {
    if (_activeSection == section) {
      return;
    }
    _activeSection = section;
    _refreshFromSnapshot();
  }

  void setNotice(SettingsNoticeCode code) {
    _action = _action.copyWith(message: code.name);
    _refreshFromSnapshot();
  }

  void clearMessage() {
    _action = _action.copyWith(clearMessage: true);
    _refreshFromSnapshot();
  }

  Future<void> updateDefaultSavePath(String value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.storageDefaultSavePath: value.trim(),
    }, successCode: SettingsNoticeCode.defaultSavePathUpdated);
  }

  Future<void> pickDefaultSavePath() async {
    final SettingsPageDependencies dependencies = ref.read(
      settingsPageDependenciesProvider,
    );
    final String initialDirectory = dependencies.config.storage.defaultSavePath
        .trim();
    final String? selectedPath = await dependencies.pickDirectory(
      initialDirectory: initialDirectory.isEmpty ? null : initialDirectory,
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return;
    }
    await updateDefaultSavePath(selectedPath);
  }

  Future<void> restoreDefaultSavePath() {
    return _updateConfig(<String, Object?>{
      ConfigKey.storageDefaultSavePath:
          ConfigDefaults.current.storage.defaultSavePath,
    }, successCode: SettingsNoticeCode.defaultSavePathRestored);
  }

  Future<void> updateLyricsFileNameFormat(String value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.lyricsFileNameFormat: value.trim(),
    }, successCode: SettingsNoticeCode.lyricsFileNameFormatUpdated);
  }

  Future<void> updateId3Version(Id3Version value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.lyricsId3Version: value.value,
    }, successCode: SettingsNoticeCode.id3VersionUpdated);
  }

  Future<void> updateLyricsLangOrder(List<String> order) {
    if (order.isEmpty) {
      setNotice(SettingsNoticeCode.lyricsLangOrderEmpty);
      return Future<void>.value();
    }
    return _updateConfig(<String, Object?>{
      ConfigKey.lyricsLangOrder: order,
    }, successCode: SettingsNoticeCode.lyricsLangOrderUpdated);
  }

  Future<void> updateSkipInst(bool value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.matchSkipInst: value,
    }, successCode: SettingsNoticeCode.skipInstUpdated);
  }

  Future<void> updateAutoSelect(bool value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.matchAutoSelect: value,
    }, successCode: SettingsNoticeCode.autoSelectUpdated);
  }

  Future<void> updateAddEndTimestamp(bool value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.lyricsAddEndTimestamp: value,
    }, successCode: SettingsNoticeCode.addEndTimestampUpdated);
  }

  Future<void> updateMsDigits(int value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.lyricsMsDigits: value,
    }, successCode: SettingsNoticeCode.msDigitsUpdated);
  }

  Future<void> updateLastRefStyle(int value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.lyricsLastRefStyle: value,
    }, successCode: SettingsNoticeCode.lastRefStyleUpdated);
  }

  Future<void> updateTagInfoSource(int value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.lyricsTagInfoSource: value,
    }, successCode: SettingsNoticeCode.tagInfoSourceUpdated);
  }

  Future<void> updateDesktopSources(List<String> sources) {
    if (sources.isEmpty) {
      setNotice(SettingsNoticeCode.desktopSourcesEmpty);
      return Future<void>.value();
    }
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopSources: sources,
    }, successCode: SettingsNoticeCode.desktopSourcesUpdated);
  }

  Future<void> updateDesktopLangSelection({
    required List<String> selected,
    required List<String> order,
  }) {
    if (selected.isEmpty) {
      setNotice(SettingsNoticeCode.desktopDefaultLangsEmpty);
      return Future<void>.value();
    }
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopDefaultLangs: selected,
      ConfigKey.desktopLangOrder: order,
    }, successCode: SettingsNoticeCode.desktopLangsUpdated);
  }

  Future<void> updateDesktopFontFamily(String value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopFontFamily: value.trim(),
    }, successCode: SettingsNoticeCode.desktopFontFamilyUpdated);
  }

  Future<void> updateDesktopRefreshRate(int value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopRefreshRate: value,
    }, successCode: SettingsNoticeCode.desktopRefreshRateUpdated);
  }

  Future<void> updateDesktopPlayedColors(List<List<int>> colors) {
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopPlayedColors: colors,
    }, successCode: SettingsNoticeCode.desktopPlayedColorsUpdated);
  }

  Future<void> updateDesktopUnplayedColors(List<List<int>> colors) {
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopUnplayedColors: colors,
    }, successCode: SettingsNoticeCode.desktopUnplayedColorsUpdated);
  }

  Future<void> updateDesktopFontSize(double value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopFontSize: value,
    }, successCode: SettingsNoticeCode.desktopFontSizeUpdated);
  }

  Future<void> updateDesktopPanelFontSize(double value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopPanelFontSize: value,
    }, successCode: SettingsNoticeCode.desktopPanelFontSizeUpdated);
  }

  Future<void> updateDesktopShowFurigana(bool value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.desktopShowFurigana: value,
    }, successCode: SettingsNoticeCode.desktopShowFuriganaUpdated);
  }

  Future<void> updateTranslateSource(TranslateSource value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.translateSource: value.value,
    }, successCode: SettingsNoticeCode.translateSourceUpdated);
  }

  Future<void> updateTranslateTargetLang(TranslateTargetLang value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.translateTargetLang: value.value,
    }, successCode: SettingsNoticeCode.translateTargetLangUpdated);
  }

  Future<void> updateOpenAiProfile(OpenAiProfile value) {
    final OpenAiProfileSpec spec = OpenAiProfileSpec.of(value);
    final Map<String, Object?> patch = <String, Object?>{
      ConfigKey.translateOpenAiProfile: value.value,
    };
    if (spec.shouldFillDefaultBaseUrl) {
      // 预设代表“使用该供应商官方兼容入口”。切换时同步覆盖 Base URL，
      // 可以避免 profile 已经变更但请求仍发往旧端点；模型和密钥仍由用户控制。
      patch[ConfigKey.translateOpenAiBaseUrl] = spec.defaultBaseUrl;
    }
    return _updateConfig(
      patch,
      successCode: SettingsNoticeCode.openAiProfileUpdated,
    );
  }

  Future<void> updateOpenAiBaseUrl(String value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.translateOpenAiBaseUrl: value.trim(),
    }, successCode: SettingsNoticeCode.openAiBaseUrlUpdated);
  }

  Future<void> updateOpenAiApiKey(String value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.translateOpenAiApiKey: value.trim(),
    }, successCode: SettingsNoticeCode.openAiApiKeyUpdated);
  }

  Future<void> updateOpenAiModel(String value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.translateOpenAiModel: value.trim(),
    }, successCode: SettingsNoticeCode.openAiModelUpdated);
  }

  Future<void> updateSearchSources(List<String> sources) {
    if (sources.isEmpty) {
      setNotice(SettingsNoticeCode.searchSourcesEmpty);
      return Future<void>.value();
    }
    return _updateConfig(<String, Object?>{
      ConfigKey.searchSources: sources,
    }, successCode: SettingsNoticeCode.searchSourcesUpdated);
  }

  Future<void> updateAppLanguage(AppLanguage value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.appLanguage: value.value,
    }, successCode: SettingsNoticeCode.appLanguageUpdated);
  }

  Future<void> updateAppColorScheme(AppColorScheme value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.appColorScheme: value.value,
    }, successCode: SettingsNoticeCode.appColorSchemeUpdated);
  }

  Future<void> updateAppLogLevel(AppLogLevel value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.appLogLevel: value.value,
    }, successCode: SettingsNoticeCode.appLogLevelUpdated);
  }

  Future<void> updateAutoCheckUpdate(bool value) {
    return _updateConfig(<String, Object?>{
      ConfigKey.appAutoCheckUpdate: value,
    }, successCode: SettingsNoticeCode.autoCheckUpdateUpdated);
  }

  Future<void> restoreSectionDefaults(SettingsSection section) {
    final Map<String, Object?> defaults = ConfigDefaults.flattenRequired(
      ConfigDefaults.current,
    );
    final Map<String, Object?> patch = <String, Object?>{};
    for (final String key in _keysForSection(section)) {
      patch[key] = defaults[key];
    }
    if (patch.isEmpty) {
      // 工具分组只有“打开目录、清缓存”等即时动作，没有可持久化配置。
      // 直接返回提示可以避免制造一次无意义写入，也避免用户误以为设置文件发生了变化。
      setNotice(SettingsNoticeCode.sectionNoRestorableConfig);
      return Future<void>.value();
    }
    return _updateConfig(
      patch,
      successCode: SettingsNoticeCode.sectionDefaultsRestored,
    );
  }

  Future<void> restoreAllDefaults() {
    return _updateConfig(
      ConfigDefaults.flattenRequired(ConfigDefaults.current),
      successCode: SettingsNoticeCode.allDefaultsRestored,
    );
  }

  Future<void> openAssociationManager() async {
    await ref.read(settingsPageDependenciesProvider).openAssociationManager();
    setNotice(SettingsNoticeCode.associationManagerOpened);
  }

  Future<void> openLogDirectory() async {
    try {
      await ref.read(settingsPageDependenciesProvider).openLogDirectory();
      setNotice(SettingsNoticeCode.logDirectoryOpened);
    } catch (error, stackTrace) {
      _logFailure(
        action: 'openLogDirectory',
        error: error,
        stackTrace: stackTrace,
      );
      // 平台打开目录可能抛出任意对象，设置页只负责给用户保留明确失败提示。
      setNotice(SettingsNoticeCode.logDirectoryOpenFailed);
    }
  }

  Future<void> clearCache() async {
    try {
      await ref.read(settingsPageDependenciesProvider).clearCache();
      setNotice(SettingsNoticeCode.cacheCleared);
    } catch (error, stackTrace) {
      _logFailure(action: 'clearCache', error: error, stackTrace: stackTrace);
      // 缓存后端清理失败不应打断设置页，失败原因由日志链路继续追踪。
      setNotice(SettingsNoticeCode.cacheClearFailed);
    }
  }

  void _refreshFromSnapshot() {
    final SettingsPageDependencies dependencies = ref.read(
      settingsPageDependenciesProvider,
    );
    state = _compose(dependencies.config, dependencies.capability);
  }

  PageViewState<SettingsPagePayload> _compose(
    AppConfig config,
    AppCapability capability,
  ) {
    return PageViewState<SettingsPagePayload>(
      view: AsyncSuccess<SettingsPagePayload>(
        data: SettingsPagePayload(
          config: config,
          activeSection: _activeSection,
          showDesktopTools: _showDesktopTools(capability),
          visibleTranslateFields: _visibleTranslateFields(
            config.translate.source,
          ),
        ),
      ),
      action: _action,
      lastUpdatedAt: DateTime.now(),
    );
  }

  Future<void> _updateConfig(
    Map<String, Object?> patch, {
    required SettingsNoticeCode successCode,
  }) async {
    final int generation = _configWriteEpoch.next();
    final SettingsPageDependencies dependencies = ref.read(
      settingsPageDependenciesProvider,
    );
    final AppConfig current = dependencies.config;
    final AppCapability capability = dependencies.capability;
    state = PageViewState<SettingsPagePayload>(
      view: AsyncSuccess<SettingsPagePayload>(
        data: SettingsPagePayload(
          config: current,
          activeSection: _activeSection,
          showDesktopTools: _showDesktopTools(capability),
          visibleTranslateFields: _visibleTranslateFields(
            current.translate.source,
          ),
        ),
      ),
      action: const PageActionState(phase: PageActionPhase.running),
      lastUpdatedAt: DateTime.now(),
    );

    // 设置页可能连续提交多个字段，例如失焦保存、滑块结束、快速切换开关。
    // 串行写入能保证同一字段的最后一次操作最终落在后面；generation 则避免旧请求完成后覆盖新请求的页面提示。
    final Future<void> write = _configWriteTail.then((_) async {
      try {
        final AppConfig next = await ref
            .read(settingsPageDependenciesProvider)
            .updateConfig(patch);
        if (!_configWriteEpoch.isCurrent(generation)) {
          return;
        }
        _action = PageActionState(message: successCode.name);
        state = _compose(next, capability);
      } catch (error, stackTrace) {
        if (!_configWriteEpoch.isCurrent(generation)) {
          return;
        }
        _logFailure(
          action: 'updateConfig',
          error: error,
          stackTrace: stackTrace,
          fields: <String, Object?>{
            'patchKeys': patch.keys.toList(growable: false),
          },
        );
        // 配置仓储写入失败时回滚到旧快照，避免页面展示半更新状态。
        _action = PageActionState(
          message: SettingsNoticeCode.configWriteFailed.name,
        );
        state = _compose(current, capability);
      }
    });
    _configWriteTail = write.catchError((Object _) {});
    return write;
  }

  static bool _showDesktopTools(AppCapability capability) {
    return capability.multiWindow ||
        capability.systemTray ||
        capability.desktopPanelDetached ||
        capability.desktopPanelEmbedded ||
        capability.globalHotkey;
  }

  void _logFailure({
    required String action,
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    // controller 只提交结构化诊断，不直接依赖具体日志运行时；
    // app 层可写文件日志，测试层可捕获字段断言，用户界面仍展示稳定的短提示。
    ref
        .read(settingsPageDependenciesProvider)
        .logFailure(
          action: action,
          error: error,
          stackTrace: stackTrace,
          fields: fields,
        );
  }

  static Iterable<String> _keysForSection(SettingsSection section) {
    return switch (section) {
      SettingsSection.save => <String>[
        ConfigKey.storageDefaultSavePath,
        ConfigKey.lyricsFileNameFormat,
        ConfigKey.lyricsId3Version,
      ],
      SettingsSection.search => <String>[ConfigKey.searchSources],
      SettingsSection.desktopLyrics => <String>[
        ConfigKey.desktopSources,
        ConfigKey.desktopDefaultLangs,
        ConfigKey.desktopLangOrder,
        ConfigKey.desktopFontFamily,
        ConfigKey.desktopRefreshRate,
        ConfigKey.desktopPlayedColors,
        ConfigKey.desktopUnplayedColors,
        ConfigKey.desktopFontSize,
        ConfigKey.desktopShowFurigana,
        ConfigKey.desktopPanelFontSize,
      ],
      SettingsSection.lyrics => <String>[
        ConfigKey.lyricsLangOrder,
        ConfigKey.matchSkipInst,
        ConfigKey.matchAutoSelect,
        ConfigKey.lyricsAddEndTimestamp,
        ConfigKey.lyricsMsDigits,
        ConfigKey.lyricsLastRefStyle,
        ConfigKey.lyricsTagInfoSource,
      ],
      SettingsSection.translate => <String>[
        ConfigKey.translateSource,
        ConfigKey.translateTargetLang,
        ConfigKey.translateOpenAiProfile,
        ConfigKey.translateOpenAiBaseUrl,
        ConfigKey.translateOpenAiApiKey,
        ConfigKey.translateOpenAiModel,
      ],
      SettingsSection.app => <String>[
        ConfigKey.appLanguage,
        ConfigKey.appColorScheme,
        ConfigKey.appLogLevel,
        ConfigKey.appAutoCheckUpdate,
      ],
      SettingsSection.tools => const <String>[],
    };
  }

  static Set<SettingsTranslateField> _visibleTranslateFields(
    TranslateSource source,
  ) {
    return switch (source) {
      TranslateSource.openai => <SettingsTranslateField>{
        SettingsTranslateField.openAiProfile,
        SettingsTranslateField.openAiBaseUrl,
        SettingsTranslateField.openAiApiKey,
        SettingsTranslateField.openAiModel,
      },
      _ => const <SettingsTranslateField>{},
    };
  }
}
