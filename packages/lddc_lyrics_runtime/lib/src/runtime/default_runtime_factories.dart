import '../api/lyrics_sources/kg_provider.dart';
import '../api/lyrics_sources/kg_request_executor.dart';
import '../api/lyrics_sources/local_provider.dart';
import '../api/lyrics_sources/lrclib_provider.dart';
import '../api/lyrics_sources/lrclib_request_executor.dart';
import '../api/lyrics_sources/ne_device_ids.dart';
import '../api/lyrics_sources/ne_provider.dart';
import '../api/lyrics_sources/ne_request_executor.dart';
import '../api/lyrics_sources/qm_device_identity_repository.dart';
import '../api/lyrics_sources/qm_provider.dart';
import '../api/lyrics_sources/qm_request_executor.dart';
import '../api/translate/translate_provider_initializer.dart';
import '../audio_tag/audio_tag_port.dart';
import '../audio_tag_impl/dart_taglib_audio_tag_port.dart';
import '../audio_tag_impl/android_saf_audio_metadata_reader.dart';
import '../audio_tag_impl/audio_tag_background_executor.dart';
import '../audio_tag_impl/local_match_media_gateway.dart';
import '../cache/cache_executor.dart';
import '../cache/cache_facade.dart';
import '../cache/cache_store.dart';
import '../cache/persistent_cache_store.dart';
import '../logging/runtime_logger.dart';
import '../lyrics_source/lyrics_api.dart';
import '../lyrics_source/lyrics_client.dart';
import '../lyrics_source/lyrics_source_provider.dart';
import '../lyrics_source/lyrics_source_registry.dart';
import '../network/request_budget.dart';
import '../task/android_saf_ports.dart';
import '../task/local_match_usecase.dart';
import '../translate/translate_api.dart';
import '../translate/translate_registry.dart';
import '../translate/translation_client.dart';
import '../translate/translation_options.dart';

typedef RuntimeDatabasePathResolver = Future<String> Function();

/// 创建默认 SQLite 缓存存储，但只向宿主暴露 CacheStore 端口。
CacheStore createDefaultCacheStore({
  required RuntimeDatabasePathResolver databasePathResolver,
}) {
  return PersistentCacheStore(
    executorFactory: () async {
      final String databasePath = await databasePathResolver();
      return createCacheExecutor(databasePath: databasePath);
    },
  );
}

/// 创建带有有界 L1 缓存的默认缓存门面。
CacheFacade createDefaultCacheFacade({
  required RuntimeDatabasePathResolver databasePathResolver,
  int memoryCapacity = 512,
  LddcRuntimeLogger logger = const LddcRuntimeLogger(),
}) {
  return CacheFacade(
    store: createDefaultCacheStore(databasePathResolver: databasePathResolver),
    memoryCapacity: memoryCapacity,
    logger: logger,
  );
}

/// 创建并注册默认歌词来源。
///
/// 返回的 registry 唯一拥有内部 HTTP/provider；宿主应在自身生命周期结束时调用
/// close。QM 只有在显式启用或注入客户端时才创建，保持 Web 与轻量 runtime 行为。
LyricsSourceRegistry createDefaultLyricsSourceRegistry({
  required CacheFacade cache,
  QmApiClient? qmClient,
  bool enableQm = false,
  NeDeviceIdPool? neDeviceIdPool,
  NetworkRequestBudget requestBudget = kDefaultLyricsRequestBudget,
  LddcRuntimeLogger logger = const LddcRuntimeLogger(),
}) {
  final QmApiClient? resolvedQmClient =
      qmClient ??
      (enableQm
          ? QmApiClientImpl(
              identityRepository: QmDeviceIdentityRepository(cache: cache),
              timeout: requestBudget.timeout,
              logger: logger,
            )
          : null);
  final KgRequestExecutorImpl kgExecutor = KgRequestExecutorImpl(
    timeout: requestBudget.timeout,
  );
  final NeRequestExecutorImpl? neExecutor = neDeviceIdPool == null
      ? null
      : NeRequestExecutorImpl(
          deviceIdPool: neDeviceIdPool,
          timeout: requestBudget.timeout,
        );
  final LrclibRequestExecutorImpl lrclibExecutor = LrclibRequestExecutorImpl(
    timeout: requestBudget.timeout,
  );
  final LyricsSourceRegistry registry = LyricsSourceRegistry();
  registry
    ..registerCloudProviders(<LyricsCloudSourceProvider>[
      if (resolvedQmClient != null) QmLyricsProvider(client: resolvedQmClient),
      KgLyricsProvider(requestExecutor: kgExecutor, close: kgExecutor.close),
      if (neExecutor != null)
        NeLyricsProvider(
          requestExecutor: neExecutor.execute,
          close: neExecutor.close,
        ),
      LrclibLyricsProvider(
        requestExecutor: lrclibExecutor.execute,
        close: lrclibExecutor.close,
      ),
    ])
    ..registerLocalProvider(LocalLyricsProvider());
  return registry;
}

/// 创建只暴露稳定 LyricsClient 契约的歌词聚合客户端。
LyricsClient createDefaultLyricsClient({
  required LyricsSourceRegistry registry,
  required CacheFacade cache,
  NetworkRequestBudget requestBudget = kDefaultLyricsRequestBudget,
}) {
  return LyricsApi(
    registry: registry,
    cache: cache,
    requestBudget: requestBudget,
  );
}

/// 创建由调用方独占、可幂等关闭的默认翻译客户端。
TranslationClient createDefaultTranslationClient({
  required TranslationOptionsResolver optionsResolver,
  NetworkRequestBudget requestBudget = kDefaultTranslateRequestBudget,
}) {
  return TranslateApi(
    registry: TranslateRegistry(),
    optionsResolver: optionsResolver,
    requestBudget: requestBudget,
    initializer: (registry, cache) async {
      registerDefaultTranslateProviders(
        registry,
        cache: cache,
        budget: requestBudget,
      );
    },
  );
}

/// 创建默认 Taglib 端口，隐藏 native backend 具体实现。
AudioTagPort createDefaultAudioTagPort() => DartTaglibAudioTagPort();

/// 创建本地匹配媒体网关，宿主只依赖 LocalMatchMediaGateway 端口。
LocalMatchMediaGateway createDefaultLocalMatchMediaGateway({
  AndroidSafFdPort? androidSafFdPort,
}) {
  return LocalMatchMediaGatewayImpl(androidSafFdPort: androidSafFdPort);
}

/// 创建桌面文件路径使用的后台 Taglib 元数据端口。
LocalMatchAudioMetadataPort createDefaultBackgroundAudioMetadataPort() {
  return const AudioTagBackgroundMetadataPort();
}

/// 创建 Android SAF 文件描述符元数据端口。
AndroidSafAudioMetadataPort createAndroidSafAudioMetadataPort({
  required AndroidSafFdPort safFdPort,
}) {
  return AndroidSafAudioMetadataReader(safFdPort: safFdPort);
}

/// 创建默认本地歌词解析 provider，供只需要本地转换的用例装配。
LyricsLocalSourceProvider createDefaultLocalLyricsProvider() {
  return LocalLyricsProvider();
}

/// 创建独立 LRCLIB provider；调用方在结束时通过 ClosableLyricsSourceProvider
/// 关闭其 HTTP 连接池。
LyricsCloudSourceProvider createDefaultLrclibLyricsProvider({
  NetworkRequestBudget requestBudget = kDefaultLyricsRequestBudget,
}) {
  final LrclibRequestExecutorImpl executor = LrclibRequestExecutorImpl(
    timeout: requestBudget.timeout,
  );
  return LrclibLyricsProvider(
    requestExecutor: executor.execute,
    close: executor.close,
  );
}
