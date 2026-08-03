import 'dart:collection';

import 'translation_options.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'translate_provider.dart';

/// 翻译源注册表：管理 `TranslateSource -> TranslateProvider` 映射。
class TranslateRegistry {
  final Map<TranslateSource, TranslateProvider> _providers =
      <TranslateSource, TranslateProvider>{};
  Future<void>? _closeFuture;

  void registerProvider(TranslateProvider provider) {
    _ensureOpen();
    if (_providers.containsKey(provider.source)) {
      throw LddcTranslateException('翻译源重复注册: ${provider.source.value}');
    }
    _providers[provider.source] = provider;
  }

  void registerProviders(Iterable<TranslateProvider> providers) {
    for (final TranslateProvider provider in providers) {
      registerProvider(provider);
    }
  }

  bool hasProvider(TranslateSource source) => _providers.containsKey(source);

  TranslateProvider requireProvider(TranslateSource source) {
    final TranslateProvider? provider = _providers[source];
    if (provider == null) {
      throw LddcTranslateException('未注册翻译源: ${source.value}');
    }
    return provider;
  }

  Map<TranslateSource, TranslateProvider> get providers =>
      UnmodifiableMapView<TranslateSource, TranslateProvider>(_providers);

  /// 释放注册表拥有的翻译 provider 资源。
  ///
  /// 同一个 provider 理论上可能被测试或后续别名复用，因此关闭时按对象去重。
  Future<void> close() {
    final Future<void>? active = _closeFuture;
    if (active != null) {
      return active;
    }
    final List<TranslateProvider> providers = _providers.values.toList(
      growable: false,
    );
    // 在首个 await 前摘除所有 provider，阻止关闭期间的晚到请求继续取得连接。
    _providers.clear();
    final Future<void> closing = _closeProviders(providers);
    _closeFuture = closing;
    return closing;
  }

  Future<void> _closeProviders(List<TranslateProvider> providers) async {
    final Set<Object> closed = LinkedHashSet<Object>.identity();
    final List<({Object error, StackTrace stackTrace})> failures =
        <({Object error, StackTrace stackTrace})>[];
    for (final TranslateProvider provider in providers) {
      if (provider is ClosableTranslateProvider) {
        final ClosableTranslateProvider closable =
            provider as ClosableTranslateProvider;
        if (closed.add(closable)) {
          try {
            await closable.close();
          } catch (error, stackTrace) {
            failures.add((error: error, stackTrace: stackTrace));
          }
        }
      }
    }
    if (failures.isNotEmpty) {
      // 关闭失败不能阻断后续 provider 释放；注册表清空后再把真实错误交给调用方。
      final failure = failures.first;
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  void _ensureOpen() {
    if (_closeFuture != null) {
      throw StateError('TranslateRegistry 已关闭');
    }
  }
}
