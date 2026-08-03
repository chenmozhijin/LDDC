import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
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
      persistenceFactory: (String treeUri) =>
          AndroidSafLyricsSavePersistence(treePort: treePort, treeUri: treeUri),
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
            androidLyricsPersistenceFactory: (tree) =>
                AndroidSafLyricsSavePersistence(
                  treePort: treePort,
                  treeUri: tree.uri,
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
    final BatchConvertInputPicker inputPicker = BatchConvertInputPickerImpl(
      filePicker: ref.watch(appFilePickerProvider),
    );
    return ProviderScope(
      overrides: <Override>[
        batchConvertDependenciesProvider.overrideWithValue(
          BatchConvertDependencies(
            capability: ref.watch(appCapabilityProvider),
            configRepository: ref.watch(configRepositoryProvider),
            inputPicker: inputPicker,
            useCase: ref.watch(batchConvertUseCaseProvider),
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
      return AlertDialog(
        title: const Text('确认覆盖文件'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('本次转换会覆盖已有文件。确认后会继续执行，取消则不会开始转换。'),
              const SizedBox(height: 12),
              if (summary.sourceOverwriteCount > 0)
                Text('覆盖源歌词文件：${summary.sourceOverwriteCount} 项'),
              if (summary.existingTargetCount > 0)
                Text('覆盖已存在的目标文件：${summary.existingTargetCount} 项'),
              if (summary.duplicateTargetGroupCount > 0)
                Text('多个条目写入同一目标：${summary.duplicateTargetGroupCount} 组'),
              if (summary.samplePaths.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  '示例路径',
                  style: Theme.of(dialogContext).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                for (final String path in summary.samplePaths)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续转换'),
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
