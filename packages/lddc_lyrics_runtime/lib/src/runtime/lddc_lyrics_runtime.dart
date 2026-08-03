import 'dart:async';

import '../api/lyrics_sources/ne_device_ids.dart';
import '../api/lyrics_sources/qm_request_executor.dart';
import '../cache/cache_facade.dart';
import '../cache/cache_store.dart';
import '../logging/runtime_logger.dart';
import '../lyrics_source/lyrics_client.dart';
import '../lyrics_source/lyrics_source_registry.dart';
import '../network/request_budget.dart';
import '../translate/translation_client.dart';
import '../translate/translation_options.dart';
import 'default_runtime_factories.dart';

/// 无 UI 歌词运行时的便利组合根。
///
/// 调用方显式提供缓存存储与翻译配置，不读取 LDDC 配置文件、数据库路径或默认目录。
/// QM 客户端和 NE 设备池属于宿主能力：传入后由本 runtime 接管并在 close 时释放。
final class LddcLyricsRuntime {
  LddcLyricsRuntime._({
    required this.lyrics,
    required this.translation,
    required this._lyricsRegistry,
    required this._cache,
  });

  final LyricsClient lyrics;
  final TranslationClient translation;
  final LyricsSourceRegistry _lyricsRegistry;
  final CacheFacade _cache;
  Future<void>? _closeFuture;

  bool get isClosed => _closeFuture != null;

  /// 使用现有来源实现创建独立运行时。
  ///
  /// KG、Lrclib 与本地来源始终启用；QM/NE 只在宿主提供其必要能力时启用，避免
  /// runtime 猜测资产位置或持久目录。所有创建的 provider 都由 registry 唯一拥有。
  static Future<LddcLyricsRuntime> create({
    required CacheStore cacheStore,
    required TranslationOptionsResolver translationOptionsResolver,
    QmApiClient? qmClient,
    NeDeviceIdPool? neDeviceIdPool,
    NetworkRequestBudget lyricsRequestBudget = kDefaultLyricsRequestBudget,
    NetworkRequestBudget translateRequestBudget =
        kDefaultTranslateRequestBudget,
    int memoryCacheCapacity = 512,
    LddcRuntimeLogger logger = const LddcRuntimeLogger(),
  }) async {
    if (memoryCacheCapacity <= 0) {
      throw ArgumentError.value(
        memoryCacheCapacity,
        'memoryCacheCapacity',
        '必须大于 0',
      );
    }
    final CacheFacade cache = CacheFacade(
      store: cacheStore,
      memoryCapacity: memoryCacheCapacity,
      logger: logger,
    );
    LyricsSourceRegistry? lyricsRegistry;
    TranslationClient? translation;
    try {
      await cache.initialize();
      lyricsRegistry = createDefaultLyricsSourceRegistry(
        cache: cache,
        qmClient: qmClient,
        neDeviceIdPool: neDeviceIdPool,
        requestBudget: lyricsRequestBudget,
        logger: logger,
      );
      translation = createDefaultTranslationClient(
        optionsResolver: translationOptionsResolver,
        requestBudget: translateRequestBudget,
      );
      return LddcLyricsRuntime._(
        lyrics: createDefaultLyricsClient(
          registry: lyricsRegistry,
          cache: cache,
          requestBudget: lyricsRequestBudget,
        ),
        translation: translation,
        lyricsRegistry: lyricsRegistry,
        cache: cache,
      );
    } on Object {
      await _closeAll(<Future<void> Function()>[
        if (lyricsRegistry != null) lyricsRegistry.close,
        if (translation != null) translation.close,
        cache.dispose,
      ]);
      rethrow;
    }
  }

  /// 幂等释放来源 HTTP、翻译 HTTP、缓存流和持久存储。
  Future<void> close() {
    final Future<void>? active = _closeFuture;
    if (active != null) {
      return active;
    }
    final Future<void> closing = _closeAll(<Future<void> Function()>[
      _lyricsRegistry.close,
      translation.close,
      _cache.dispose,
    ]);
    _closeFuture = closing;
    return closing;
  }
}

Future<void> _closeAll(List<Future<void> Function()> closers) async {
  Object? firstError;
  StackTrace? firstStackTrace;
  for (final Future<void> Function() close in closers) {
    try {
      await close();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  if (firstError != null && firstStackTrace != null) {
    Error.throwWithStackTrace(firstError, firstStackTrace);
  }
}
