import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../../core/about/about_ports.dart';
import '../../core/config/config.dart';
import '../../core/library_link/library_link.dart';
import '../../core/resource/async_disposal_tracker.dart';
import '../../core/storage/app_storage_paths_port.dart';
import '../../platform/android/saf/android_saf_content_adapter.dart';
import '../../platform/android/saf/android_saf_fd_adapter.dart';
import '../../platform/android/saf/android_saf_tree_adapter.dart';
import '../../platform/about/app_link_opener.dart';
import '../../platform/about/app_update_checker.dart';
import '../../platform/drag_drop/drag_drop_port.dart';
import '../../platform/files/app_file_picker.dart';
import '../../platform/files/app_path_opener.dart';
import 'app_runtime_providers.dart';

export 'app_runtime_providers.dart'
    show configRepositoryProvider, appConfigStreamProvider;

/// 全局缓存门面 Provider。
final Provider<CacheFacade> cacheFacadeProvider = Provider<CacheFacade>((
  Ref ref,
) {
  final CacheFacade cache = createDefaultCacheFacade(
    databasePathResolver: () async {
      // 缓存目录属于宿主应用策略；共享运行时只接收最终数据库路径，
      // 避免反向依赖 LDDC 的默认目录和配置文件。
      final file = await AppStoragePathsRegistry.current
          .resolveCacheDatabaseFile();
      return file.path;
    },
  );
  ref.onDispose(() {
    AsyncDisposalTracker.track(cache.dispose(), owner: 'cache-facade');
  });
  return cache;
});

/// 歌词请求预算 Provider。
final Provider<NetworkRequestBudget> lyricsRequestBudgetProvider =
    Provider<NetworkRequestBudget>((Ref ref) {
      return kDefaultLyricsRequestBudget;
    });

/// 翻译请求预算 Provider。
final Provider<NetworkRequestBudget> translateRequestBudgetProvider =
    Provider<NetworkRequestBudget>((Ref ref) {
      return kDefaultTranslateRequestBudget;
    });

/// 歌词源注册表 Provider，统一收口各来源注册逻辑。
final Provider<LyricsSourceRegistry> lyricsSourceRegistryProvider =
    Provider<LyricsSourceRegistry>((Ref ref) {
      final NetworkRequestBudget budget = ref.watch(
        lyricsRequestBudgetProvider,
      );
      final LyricsSourceRegistry registry = createDefaultLyricsSourceRegistry(
        cache: ref.watch(cacheFacadeProvider),
        enableQm: !kIsWeb,
        neDeviceIdPool: createBundledNeDeviceIdPool(),
        requestBudget: budget,
      );
      ref.onDispose(() {
        AsyncDisposalTracker.track(
          registry.close(),
          owner: 'lyrics-source-registry',
        );
      });
      return registry;
    });

/// 歌词聚合 API Provider。
final Provider<LyricsClient> lyricsApiProvider = Provider<LyricsClient>((
  Ref ref,
) {
  final NetworkRequestBudget budget = ref.watch(lyricsRequestBudgetProvider);
  return createDefaultLyricsClient(
    registry: ref.watch(lyricsSourceRegistryProvider),
    cache: ref.watch(cacheFacadeProvider),
    requestBudget: budget,
  );
});

/// 翻译 API Provider。
final Provider<TranslationClient> translateApiProvider =
    Provider<TranslationClient>((Ref ref) {
      final NetworkRequestBudget budget = ref.watch(
        translateRequestBudgetProvider,
      );
      final TranslationClient client = createDefaultTranslationClient(
        optionsResolver: () =>
            ref.read(configRepositoryProvider).current.toTranslationOptions(),
        requestBudget: budget,
      );
      ref.onDispose(() {
        AsyncDisposalTracker.track(client.close(), owner: 'translation-client');
      });
      return client;
    });

/// 公用文件选择器 Provider。
final Provider<AppFilePicker> appFilePickerProvider = Provider<AppFilePicker>((
  Ref ref,
) {
  return const AppFilePickerImpl();
});

/// 公用拖拽解析 Provider。
final Provider<DragDropPort> dragDropPortProvider = Provider<DragDropPort>((
  Ref ref,
) {
  if (kIsWeb) {
    return const UnsupportedDragDropPort();
  }
  if (defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.macOS &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return const UnsupportedDragDropPort();
  }
  return const DragDropPortImpl(enableDiagnostics: true);
});

/// 通用路径打开 Provider。
final Provider<AppPathOpener> appPathOpenerProvider = Provider<AppPathOpener>((
  Ref ref,
) {
  return AppPathOpenerImpl();
});

/// 通用外链打开 Provider。
final Provider<AppLinkOpener> appLinkOpenerProvider = Provider<AppLinkOpener>((
  Ref ref,
) {
  return createAppLinkOpener();
});

/// 应用更新检查 Provider。
final Provider<AppUpdatePort> appUpdatePortProvider = Provider<AppUpdatePort>((
  Ref ref,
) {
  final AppUpdatePort port = createAppUpdatePort();
  if (port is CloseableAppUpdatePort) {
    ref.onDispose(() {
      AsyncDisposalTracker.track(port.close(), owner: 'app-update-port');
    });
  }
  return port;
});

/// 关联库仓储 Provider。
///
/// 关联库管理器是设置页的子页面，不属于桌面窗口专属能力；桌面歌词服务和
/// 普通设置页都通过这个 Provider 共享同一仓储，避免 app 层反向依赖
/// desktop window providers。
final Provider<LibraryLinkRepository> libraryLinkRepositoryProvider =
    Provider<LibraryLinkRepository>((Ref ref) {
      final LocalSongLyricsDbRepository repository =
          LocalSongLyricsDbRepository();
      ref.onDispose(() {
        AsyncDisposalTracker.track(
          repository.dispose(),
          owner: 'library-link-repository',
        );
      });
      return repository;
    });

/// 自动获取用例 Provider。
final Provider<AutoFetchUseCase> autoFetchUseCaseProvider =
    Provider<AutoFetchUseCase>((Ref ref) {
      return AutoFetchUseCase(
        gateway: LyricsApiAutoFetchGateway(
          lyricsApi: ref.watch(lyricsApiProvider),
        ),
      );
    });

/// Android SAF 端口由 app 层统一提供，业务 Scope 只依赖抽象接口。
final Provider<AndroidSafTreePort> androidSafTreePortProvider =
    Provider<AndroidSafTreePort>((Ref ref) {
      return const AndroidSafTreeAdapter();
    });

final Provider<AndroidSafFdPort> androidSafFdPortProvider =
    Provider<AndroidSafFdPort>((Ref ref) {
      return const AndroidSafFdAdapter();
    });

final Provider<AndroidSafContentPort> androidSafContentPortProvider =
    Provider<AndroidSafContentPort>((Ref ref) {
      return const AndroidSafContentAdapter();
    });

/// 本地媒体网关 Provider（用于标签读取与写回）。
final Provider<LocalMatchMediaGateway> localMatchMediaGatewayProvider =
    Provider<LocalMatchMediaGateway>((Ref ref) {
      return createDefaultLocalMatchMediaGateway(
        androidSafFdPort: ref.watch(androidSafFdPortProvider),
      );
    });

/// 桌面目录扫描使用的音频元数据端口。
///
/// 生产环境默认在后台 isolate 中读取 taglib；integration 可以把它替换为与媒体
/// 网关共享的内存实现，确保扫描、标签读取和标签写回观察同一份夹具数据。
final Provider<LocalMatchAudioMetadataPort>
localMatchAudioMetadataPortProvider = Provider<LocalMatchAudioMetadataPort>((
  Ref ref,
) {
  return createDefaultBackgroundAudioMetadataPort();
});

/// 批量转换工作流 Provider。
final Provider<BatchConvertUseCase> batchConvertUseCaseProvider =
    Provider<BatchConvertUseCase>((Ref ref) {
      return BatchConvertUseCase(
        localProvider: createDefaultLocalLyricsProvider(),
      );
    });
