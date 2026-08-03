import 'dart:async';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../network/request_budget.dart';
import '../api/translate/translate_runtime_cache.dart';
import 'translate_provider.dart';
import 'translate_registry.dart';
import 'translation_client.dart';
import 'translation_options.dart';
import 'translation_progress.dart';

/// 翻译 API 聚合门面，对齐Python版 `core/api/translate/__init__.py`。
class TranslateApi implements TranslationClient {
  TranslateApi({
    required this._registry,
    required this._optionsResolver,
    this._initializer,
    this._requestBudget = kDefaultTranslateRequestBudget,
    TranslateRuntimeCache? cache,
  }) : _cache = cache ?? TranslateRuntimeCache();

  final TranslateRegistry _registry;
  final TranslationOptionsResolver _optionsResolver;
  final Future<void> Function(
    TranslateRegistry registry,
    TranslateRuntimeCache cache,
  )?
  _initializer;
  final NetworkRequestBudget _requestBudget;
  final TranslateRuntimeCache _cache;

  bool _initialized = false;
  Future<void>? _initFuture;
  Future<void>? _closeFuture;

  /// 幂等初始化：并发场景下只执行一次注册。
  @override
  Future<void> init() {
    if (_closeFuture != null) {
      return Future<void>.error(StateError('TranslateApi 已关闭'));
    }
    if (_initialized) {
      return Future<void>.value();
    }
    final Future<void>? inflight = _initFuture;
    if (inflight != null) {
      return inflight;
    }

    final Future<void> initialization = _initialize();
    _initFuture = initialization;
    return initialization;
  }

  Future<void> _initialize() async {
    try {
      final Future<void> Function(
        TranslateRegistry registry,
        TranslateRuntimeCache cache,
      )?
      initializer = _initializer;
      if (initializer != null) {
        await initializer(_registry, _cache);
      }
      _initialized = true;
    } catch (_) {
      // 初始化失败后清除单飞 Future，允许网络或配置恢复后再次尝试。
      _initFuture = null;
      rethrow;
    }
  }

  /// 按当前配置源分派翻译请求。
  ///
  /// 对齐Python版语义：
  /// - 每次调用均读取当前配置中的 `translate.source`
  /// - 仅做源分派与可用性校验，具体翻译逻辑由 provider 承担
  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) async {
    await init();
    final TranslationOptions options = _optionsResolver();
    final TranslateSource source = options.source;
    final TranslateProvider provider = _registry.requireProvider(source);
    if (!provider.isAvailable(options)) {
      throw LddcTranslateException('翻译源 ${source.value} 当前不可用');
    }
    try {
      return await retryTimedOutRequest<LyricsData>(() async {
        if (source == TranslateSource.openai &&
            provider is OpenAiProgressTranslateProvider) {
          return await provider.translateLyricsWithProgress(
            lyrics,
            options: options,
            onOpenAiProgress: onOpenAiProgress,
          );
        }
        return await provider.translateLyrics(lyrics, options: options);
      }, maxAttempts: _requestBudget.retryCount);
    } on TimeoutException catch (error, stackTrace) {
      throw LddcTranslateException(
        '翻译源 ${source.value} 请求超时: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> close() {
    final Future<void>? active = _closeFuture;
    if (active != null) {
      return active;
    }
    final Future<void> closing = _close();
    _closeFuture = closing;
    return closing;
  }

  Future<void> _close() async {
    // 初始化可能正在注册 provider；等待它离开临界区后再关闭，避免注册表清空后
    // 晚到 initializer 重新放入持有 HTTP 连接的 provider。
    try {
      await _initFuture;
    } catch (_) {
      // 初始化错误已由原调用者观察；关闭流程仍必须继续回收已部分创建的资源。
    }
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _registry.close();
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _cache.close();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null && firstStackTrace != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace);
    }
  }
}
