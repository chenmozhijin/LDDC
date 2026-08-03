import 'dart:async';
import 'dart:collection';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'lyrics_source_provider.dart';

/// 歌词源注册表：负责管理云端与本地 provider。
class LyricsSourceRegistry {
  final Map<Source, LyricsCloudSourceProvider> _cloudProviders =
      <Source, LyricsCloudSourceProvider>{};
  LyricsLocalSourceProvider? _localProvider;
  Future<void>? _closeFuture;

  void registerCloudProvider(LyricsCloudSourceProvider provider) {
    registerCloudProviders(<LyricsCloudSourceProvider>[provider]);
  }

  void registerCloudProviders(Iterable<LyricsCloudSourceProvider> providers) {
    _ensureOpen();
    final List<LyricsCloudSourceProvider> snapshot = providers.toList(
      growable: false,
    );
    final Set<Source> sources = <Source>{};

    // 先完整校验再修改注册表。这样惰性 Iterable 在遍历中抛错、批次内部重复，
    // 或与现有来源冲突时，都不会留下只注册了一半且无人负责关闭的 provider。
    for (final LyricsCloudSourceProvider provider in snapshot) {
      final Source source = provider.source;
      if (source == Source.local || source == Source.multi) {
        throw const LddcApiParamsException('不支持将 Local/MULTI 注册为云端歌词源');
      }
      if (!sources.add(source) || _cloudProviders.containsKey(source)) {
        throw LddcApiParamsException('歌词源重复注册: ${source.value}');
      }
    }

    for (final LyricsCloudSourceProvider provider in snapshot) {
      _cloudProviders[provider.source] = provider;
    }
  }

  void registerLocalProvider(LyricsLocalSourceProvider provider) {
    _ensureOpen();
    if (_localProvider != null) {
      throw const LddcApiParamsException('本地歌词解析 provider 重复注册');
    }
    _localProvider = provider;
  }

  bool hasCloudProvider(Source source) => _cloudProviders.containsKey(source);

  LyricsCloudSourceProvider requireCloudProvider(Source source) {
    final LyricsCloudSourceProvider? provider = _cloudProviders[source];
    if (provider == null) {
      throw LddcApiParamsException('未注册歌词源: ${source.value}');
    }
    return provider;
  }

  LyricsLocalSourceProvider requireLocalProvider() {
    final LyricsLocalSourceProvider? provider = _localProvider;
    if (provider == null) {
      throw const LddcApiParamsException('未注册本地歌词解析 provider');
    }
    return provider;
  }

  Map<Source, LyricsCloudSourceProvider> get cloudProviders =>
      UnmodifiableMapView<Source, LyricsCloudSourceProvider>(_cloudProviders);

  LyricsLocalSourceProvider? get localProvider => _localProvider;

  /// 释放注册表拥有的 provider 资源。
  ///
  /// 使用 `Set` 去重是为了处理同一个 provider 被多个来源别名复用的情况，避免
  /// 重复关闭同一个底层 HTTP 连接池。
  Future<void> close() {
    final Future<void>? activeClose = _closeFuture;
    if (activeClose != null) {
      return activeClose;
    }

    final Completer<void> completer = Completer<void>();
    _closeFuture = completer.future;

    // 在第一次 await 前同步摘除全部资源。关闭过程中即使外部仍持有注册表引用，
    // 也无法再注册新 provider 或触发 Map 并发修改。
    final List<Object> providers = <Object>[
      ..._cloudProviders.values,
      if (_localProvider case final LyricsLocalSourceProvider local) local,
    ];
    _cloudProviders.clear();
    _localProvider = null;

    unawaited(_completeClose(providers, completer));
    return completer.future;
  }

  Future<void> _completeClose(
    List<Object> providers,
    Completer<void> completer,
  ) async {
    try {
      await _closeProviders(providers);
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  Future<void> _closeProviders(List<Object> providers) async {
    final Set<Object> closed = LinkedHashSet<Object>.identity();
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final Object provider in providers) {
      if (provider is ClosableLyricsSourceProvider) {
        final ClosableLyricsSourceProvider closable = provider;
        if (closed.add(closable)) {
          try {
            await closable.close();
          } catch (error, stackTrace) {
            firstError ??= error;
            firstStackTrace ??= stackTrace;
          }
        }
      }
    }
    if (firstError != null && firstStackTrace != null) {
      // 即使某个 provider 关闭失败，也已经尽力关闭了后续 provider 并清空注册表；
      // 最后再抛出第一个错误，调用方仍能看到真实失败原因。
      Error.throwWithStackTrace(firstError, firstStackTrace);
    }
  }

  void _ensureOpen() {
    if (_closeFuture != null) {
      throw StateError('LyricsSourceRegistry 已关闭');
    }
  }
}
