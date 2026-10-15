import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../core/i18n/i18n.dart';
import '../core/logging/logging.dart';
import '../features/about/application/about_page_dependencies.dart';
import '../features/about/presentation/about_page.dart';
import '../features/batch_convert/application/batch_convert_dependencies.dart';
import '../features/batch_convert/application/batch_convert_input_picker.dart';
import '../features/batch_convert/application/batch_convert_overwrite_summary.dart';
import '../features/batch_convert/presentation/batch_convert_page.dart';
import '../features/library_link_manager/application/library_link_manager_usecase.dart';
import '../features/library_link_manager/presentation/library_link_manager_dependencies.dart';
import '../features/library_link_manager/presentation/library_link_manager_page.dart';
import '../features/local_match/application/local_match_dependencies.dart';
import '../features/local_match/application/local_match_input_picker.dart';
import '../features/local_match/presentation/local_match_page.dart';
import '../features/open_lyrics/application/open_lyrics_dependencies.dart';
import '../features/open_lyrics/application/open_lyrics_file_reader.dart';
import '../features/open_lyrics/application/open_lyrics_input_picker.dart';
import '../features/open_lyrics/application/open_lyrics_page_controller.dart';
import '../features/open_lyrics/presentation/open_lyrics_page.dart';
import '../features/search/application/search_workflow_host_mapper.dart';
import '../features/search/application/search_workflow_providers.dart';
import '../features/search/presentation/search_page.dart';
import '../features/settings/application/settings_page_dependencies.dart';
import '../features/settings/presentation/settings_page.dart';
import '../infra/storage/app_storage_paths.dart';
import '../infra/storage/file_lyrics_save_persistence.dart';
import '../platform/android/saf/android_saf_lyrics_save_persistence.dart';
import 'bootstrap/app_providers.dart';
import 'bootstrap/app_runtime_providers.dart';
import 'shell/app_shell_providers.dart';
import 'shell/app_shell_route.dart';

SearchWorkflowDependencies buildSearchWorkflowDependencies(WidgetRef ref) {
  final AndroidSafTreePort treePort = ref.watch(androidSafTreePortProvider);
  final lyricsApi = ref.watch(lyricsApiProvider);
  final configRepository = ref.watch(configRepositoryProvider);
  final appCapability = ref.watch(appCapabilityProvider);
  return SearchWorkflowDependencies(
    optionsResolver: () => configRepository.current.toSearchWorkflowOptions(),
    capabilities: appCapability.toSearchWorkflowCapabilities(),
    lyricsApi: lyricsApi,
    translateApi: ref.watch(translateApiProvider),
    mediaGateway: ref.watch(localMatchMediaGatewayProvider),
    filePicker: ref.watch(appFilePickerProvider),
    dragDropPort: ref.watch(dragDropPortProvider),
    androidSafTreePort: treePort,
    batchSaveUseCase: SearchBatchSaveLyricsUseCase(
      lyricsApi: lyricsApi,
      persistenceFactory: (String folder) =>
          FileLyricsSavePersistence(folder: folder),
    ),
    androidSafBatchSaveUseCase: SearchAndroidSafBatchSaveLyricsUseCase(
      lyricsApi: lyricsApi,
      persistenceFactory: (String treeUri) => AndroidSafLyricsSavePersistence(
        treePort: treePort,
        treeUri: treeUri,
        // 搜索页批量保存的语义是"扁平写到用户选定的树根"，等价于 specify 且保存根=该树。
        saveMode: LocalMatchSaveMode.specify,
        saveTreeUri: treeUri,
      ),
    ),
    fileSavePersistenceFactory: (String folder) =>
        FileLyricsSavePersistence(folder: folder),
    autoFetchUseCase: ref.watch(autoFetchUseCaseProvider),
  );
}

class AppSearchPageScope extends ConsumerWidget {
  const AppSearchPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderScope(
      overrides: <Override>[
        searchWorkflowDependenciesProvider.overrideWithValue(
          buildSearchWorkflowDependencies(ref),
        ),
      ],
      child: const SearchPage(),
    );
  }
}

class AppLocalMatchPageScope extends ConsumerWidget {
  const AppLocalMatchPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AndroidSafTreePort treePort = ref.watch(androidSafTreePortProvider);
    final AndroidSafFdPort fdPort = ref.watch(androidSafFdPortProvider);
    final AndroidSafContentPort contentPort = ref.watch(
      androidSafContentPortProvider,
    );
    final LocalMatchInputPicker inputPicker = LocalMatchInputPickerImpl(
      filePicker: ref.watch(appFilePickerProvider),
      treePort: treePort,
    );
    final LocalMatchMediaGateway mediaGateway = ref.watch(
      localMatchMediaGatewayProvider,
    );
    final desktopGetInfosUseCase = LocalMatchGetInfosUseCase(
      mediaGateway: mediaGateway,
      audioMetadataPort: ref.watch(localMatchAudioMetadataPortProvider),
    );
    final androidGetInfosUseCase = AndroidSafLocalMatchGetInfosUseCase(
      treePort: treePort,
      contentPort: contentPort,
      audioMetadataPort: createAndroidSafAudioMetadataPort(safFdPort: fdPort),
    );
    final localMatchUseCase = LocalMatchUseCase(
      autoFetchExecutor: ref.watch(autoFetchUseCaseProvider).execute,
      mediaGateway: mediaGateway,
    );
    final androidBatchUseCase = AndroidSafLocalMatchBatchUseCase(
      getInfosUseCase: androidGetInfosUseCase,
      localMatchUseCase: localMatchUseCase,
    );

    return ProviderScope(
      overrides: <Override>[
        localMatchDependenciesProvider.overrideWithValue(
          LocalMatchDependencies(
            configRepository: ref.watch(configRepositoryProvider),
            capability: ref.watch(appCapabilityProvider),
            inputPicker: inputPicker,
            desktopGetInfosUseCase: desktopGetInfosUseCase,
            androidGetInfosUseCase: androidGetInfosUseCase,
            androidBatchUseCase: androidBatchUseCase,
            localMatchUseCase: localMatchUseCase,
            androidTreePort: treePort,
            androidFdPort: fdPort,
            androidContentPort: contentPort,
            pathOpener: ref.watch(appPathOpenerProvider),
            mediaGateway: mediaGateway,
            dragDropPort: ref.watch(dragDropPortProvider),
            androidLyricsPersistenceFactory: (songTree, saveTree, saveMode) =>
                AndroidSafLyricsSavePersistence(
                  treePort: treePort,
                  treeUri: songTree.uri,
                  saveMode: saveMode,
                  saveTreeUri: saveTree?.uri,
                  treeLabel: songTree.displayName ?? songTree.uri,
                  saveTreeLabel: saveTree?.displayName ?? saveTree?.uri ?? '',
                ),
            openInSearch: (songInfo, preferredSources) async {
              ref.read(appShellRouteListenableProvider).value =
                  AppShellRoute.search;
              await ref
                  .read(searchWorkflowControllerInstanceProvider)
                  .autoFetchFromSongInfo(
                    songInfo,
                    preferredSources: preferredSources,
                  );
            },
          ),
        ),
      ],
      child: const LocalMatchPage(),
    );
  }
}

class AppOpenLyricsPageScope extends ConsumerWidget {
  const AppOpenLyricsPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OpenLyricsInputPicker inputPicker = OpenLyricsInputPickerImpl(
      filePicker: ref.watch(appFilePickerProvider),
    );
    return ProviderScope(
      overrides: <Override>[
        openLyricsDependenciesProvider.overrideWithValue(
          OpenLyricsDependencies(
            configRepository: ref.watch(configRepositoryProvider),
            capability: ref.watch(appCapabilityProvider),
            lyricsApi: ref.watch(lyricsApiProvider),
            translateApi: ref.watch(translateApiProvider),
            mediaGateway: ref.watch(localMatchMediaGatewayProvider),
            inputPicker: inputPicker,
            fileReader: const OpenLyricsFileReaderImpl(),
            dragDropPort: ref.watch(dragDropPortProvider),
          ),
        ),
      ],
      child: const OpenLyricsPage(),
    );
  }
}

class AppLibraryLinkManagerPageScope extends ConsumerWidget {
  const AppLibraryLinkManagerPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(libraryLinkRepositoryProvider);
    // 关联库清理/迁移会批量检查路径。这里保留异步 IO，避免把
    // File.existsSync() 带回 UI isolate；lint 建议同步版本不适用于交互链路。
    // ignore: avoid_slow_async_io
    Future<bool> fileExists(String path) => File(path).exists();
    return ProviderScope(
      overrides: <Override>[
        libraryLinkManagerDependenciesProvider.overrideWithValue(
          LibraryLinkManagerDependencies(
            repository: repository,
            filePicker: ref.watch(appFilePickerProvider),
            useCase: LibraryLinkManagerUseCase(
              repository: repository,
              fileExists: fileExists,
            ),
            returnToSettings: () async {
              ref.read(appShellRouteListenableProvider).value =
                  AppShellRoute.settings;
            },
          ),
        ),
      ],
      child: const LibraryLinkManagerPage(),
    );
  }
}

class AppBatchConvertPageScope extends ConsumerWidget {
  const AppBatchConvertPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 安卓端"选择保存目录"实际是选择 SAF 授权树，因此选择器需要树端口；
    // 桌面端该端口不会被调用（能力门在 controller 里判断）。
    final BatchConvertInputPicker inputPicker = BatchConvertInputPickerImpl(
      filePicker: ref.watch(appFilePickerProvider),
      treePort: ref.watch(androidSafTreePortProvider),
    );
    return ProviderScope(
      overrides: <Override>[
        batchConvertDependenciesProvider.overrideWithValue(
          BatchConvertDependencies(
            capability: ref.watch(appCapabilityProvider),
            configRepository: ref.watch(configRepositoryProvider),
            inputPicker: inputPicker,
            useCase: ref.watch(batchConvertUseCaseProvider),
            // 安卓端"导入文件夹"扫描 SAF 授权树：与保存树选择共用同一个树端口。
            androidLyricsScanUseCase: ref.watch(
              androidSafLyricsScanUseCaseProvider,
            ),
            // 与 use case 共用同一份 IO：SAF 目标的存在性预检只能由它完成。
            fileIo: ref.watch(batchConvertFileIoProvider),
            pathOpener: ref.watch(appPathOpenerProvider),
            dragDropPort: ref.watch(dragDropPortProvider),
            openInOpenLyrics: (String lyricsPath) async {
              ref.read(appShellRouteListenableProvider).value =
                  AppShellRoute.openLyrics;
              await ref
                  .read(openLyricsPageControllerProvider.notifier)
                  .openExternalLyricsFile(lyricsPath);
            },
            confirmOverwrite: (BatchConvertOverwriteSummary summary) {
              return _confirmBatchConvertOverwrite(context, summary);
            },
          ),
        ),
      ],
      child: const BatchConvertPage(),
    );
  }
}

Future<bool> _confirmBatchConvertOverwrite(
  BuildContext context,
  BatchConvertOverwriteSummary summary,
) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final l10n = dialogContext.l10n;
      // 行高随系统字号缩放；列表用固定行高才能惰性滚动，缩放后文字也不会被裁掉。
      final double rowExtent = MediaQuery.textScalerOf(dialogContext).scale(24);
      // 对话框必须给出**显式有界尺寸**：AlertDialog 会对内容做固有尺寸（intrinsic）测量，
      // 而 ListView 无法提供固有尺寸（会在 performLayout 断言失败）。同时限制成屏幕比例，
      // 保证小屏/大字号下按钮仍然可达。
      final Size screen = MediaQuery.sizeOf(dialogContext);
      final double dialogWidth = (screen.width * 0.82).clamp(260.0, 460.0);
      final double dialogHeight = (screen.height * 0.5).clamp(180.0, 460.0);
      return AlertDialog(
        title: Text(l10n.batchConvertOverwriteDialogTitle),
        content: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 说明与计数放在可滚动区：大字号时不会把清单挤到 0 高。
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(l10n.batchConvertOverwriteDialogMessage),
                      const SizedBox(height: 12),
                      if (summary.sourceOverwriteCount > 0)
                        Text(
                          l10n.batchConvertOverwriteSourceCount(
                            summary.sourceOverwriteCount,
                          ),
                        ),
                      if (summary.existingTargetCount > 0)
                        Text(
                          l10n.batchConvertOverwriteExistingTargetCount(
                            summary.existingTargetCount,
                          ),
                        ),
                      if (summary.duplicateTargetGroupCount > 0)
                        Text(
                          l10n.batchConvertOverwriteDuplicateTargetCount(
                            summary.duplicateTargetGroupCount,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (summary.overwritePaths.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  l10n.batchConvertOverwritePathsLabel,
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                // 覆盖清单逐条列出（可能上千条）：固定行高 + ListView.builder 只构建可见行，
                // 不做一次性测量；父级已给有界高度，因此这里不再用 shrinkWrap。
                Expanded(
                  child: ListView.builder(
                    itemExtent: rowExtent,
                    itemCount: summary.overwritePaths.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Text(
                        summary.overwritePaths[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.batchConvertOverwriteContinue),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}

class AppSettingsPageScope extends ConsumerWidget {
  const AppSettingsPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // SettingsPage 只理解 feature 依赖对象；app 层在这里集中注入导航、
    // 文件选择、缓存清理和日志目录打开能力，避免 feature 反向依赖运行时实现。
    return ProviderScope(
      overrides: <Override>[
        settingsPageDependenciesProvider.overrideWithValue(
          SettingsPageDependencies(
            config: ref.watch(appConfigSnapshotProvider),
            capability: ref.watch(appCapabilityProvider),
            updateConfig: ref.read(configRepositoryProvider).update,
            pickDirectory: ({String? initialDirectory}) {
              return ref
                  .read(appFilePickerProvider)
                  .pickDirectory(initialDirectory: initialDirectory);
            },
            openAssociationManager: () async {
              ref.read(appShellRouteListenableProvider).value =
                  AppShellRoute.associationManager;
            },
            openLogDirectory: () async {
              final String path =
                  (await AppStoragePaths().resolveLogDirectory()).path;
              await ref.read(appPathOpenerProvider).openDirectory(path);
            },
            clearCache: ref.read(cacheFacadeProvider).clearAll,
            logFailure:
                ({
                  required String action,
                  required Object error,
                  required StackTrace stackTrace,
                  required Map<String, Object?> fields,
                }) {
                  AppLogger.scope('settings').error(
                    '设置页操作失败',
                    fields: <String, Object?>{
                      'action': action,
                      'error': error.toString(),
                      'stackTrace': stackTrace.toString(),
                      ...fields,
                    },
                  );
                },
          ),
        ),
      ],
      child: const SettingsPage(),
    );
  }
}

class AppAboutPageScope extends ConsumerWidget {
  const AppAboutPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderScope(
      overrides: <Override>[
        aboutPageDependenciesProvider.overrideWithValue(
          AboutPageDependencies(
            configRepository: ref.watch(configRepositoryProvider),
            linkOpener: ref.watch(appLinkOpenerProvider),
            updatePort: ref.watch(appUpdatePortProvider),
          ),
        ),
      ],
      child: const AboutPage(),
    );
  }
}
