import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../logging/runtime_logger.dart';
import 'cache_store.dart';
import 'cache_types.dart';
import 'lru_memory_cache.dart';
import 'sqlite_exception_classifier.dart';

/// 统一缓存门面：组合 L1（内存 LRU）+ L2（持久缓存）。
class CacheFacade {
  CacheFacade({
    required this._store,
    int memoryCapacity = 512,
    LddcRuntimeLogger logger = const LddcRuntimeLogger(),
  }) : _logger = logger.child('cache-facade'),
       _memory = LruMemoryCache<String, _MemoryEntry>(capacity: memoryCapacity);

  final CacheStore _store;
  final LddcRuntimeLogger _logger;
  final LruMemoryCache<String, _MemoryEntry> _memory;
  final Map<String, int> _ensuredVersions = <String, int>{};

  MemoryCacheStats get memoryStats => _memory.stats;

  Future<void> initialize() => _store.initialize();

  /// 读取缓存（先 L1 后 L2）。
  Future<Object?> get(
    String namespace,
    String key, {
    int cacheVersion = 1,
  }) async {
    final CachePolicy policy = CachePolicy(
      namespace: namespace,
      cacheVersion: cacheVersion,
    );
    await _ensurePolicyVersion(policy);
    final _MemoryEntry? l1Hit = _readL1(_compositeKey(namespace, key));
    if (l1Hit != null) {
      return l1Hit.value;
    }
    final CacheStoreEntry? l2Hit = await _store.getEntry(namespace, key);
    if (l2Hit == null) {
      return null;
    }
    _writeL1(
      _compositeKey(namespace, key),
      value: l2Hit.value,
      expiresAtMs: l2Hit.expiresAtMs,
    );
    return l2Hit.value;
  }

  /// 写入缓存（同时写 L1/L2）。
  Future<void> set(
    String namespace,
    String key,
    Object? value, {
    int cacheVersion = 1,
    Duration? ttl,
  }) async {
    final CachePolicy policy = CachePolicy(
      namespace: namespace,
      cacheVersion: cacheVersion,
      ttl: ttl,
    );
    await _ensurePolicyVersion(policy);
    await _store.set(namespace, key, value, ttl: ttl);
    _writeL1(
      _compositeKey(namespace, key),
      value: value,
      expiresAtMs: _expiresAtMs(ttl),
    );
  }

  /// 原子读取并写回缓存值，同时同步更新当前门面的 L1 副本。
  Future<Object?> updateAtomically(
    String namespace,
    String key,
    Object? Function(Object? current) update, {
    int cacheVersion = 1,
    Duration? ttl,
  }) async {
    final CachePolicy policy = CachePolicy(
      namespace: namespace,
      cacheVersion: cacheVersion,
      ttl: ttl,
    );
    await _ensurePolicyVersion(policy);
    final Object? value = await _store.updateAtomically(
      namespace,
      key,
      update,
      ttl: ttl,
    );
    // 并发事务的提交顺序与 Future 回调恢复顺序可能不同。若这里直接写 L1，较早
    // 提交的旧值可能在较晚恢复时覆盖新值；失效 L1 可确保下次读取以 L2 为准。
    _memory.remove(_compositeKey(namespace, key));
    return value;
  }

  Future<void> remove(
    String namespace,
    String key, {
    int cacheVersion = 1,
  }) async {
    final CachePolicy policy = CachePolicy(
      namespace: namespace,
      cacheVersion: cacheVersion,
    );
    await _ensurePolicyVersion(policy);
    await _store.remove(namespace, key);
    _memory.remove(_compositeKey(namespace, key));
  }

  Future<void> clearNamespace(String namespace, {int cacheVersion = 1}) async {
    final CachePolicy policy = CachePolicy(
      namespace: namespace,
      cacheVersion: cacheVersion,
    );
    await _ensurePolicyVersion(policy);
    await _store.clearNamespace(namespace);
    _clearL1Namespace(namespace);
  }

  Future<void> clearAll() async {
    await _store.clearAll();
    _memory.clear();
    _ensuredVersions.clear();
  }

  Future<CacheStats> stats({String? namespace}) {
    return _store.stats(namespace: namespace);
  }

  Stream<CacheStats> watchStats({String? namespace, bool emitCurrent = true}) {
    return _store.watchStats(namespace: namespace, emitCurrent: emitCurrent);
  }

  /// 对齐 Python版 `cached_call` 的外部行为：命中直接返回，未命中时调用 loader 并写回缓存。
  /// 这是跨实现缓存语义兼容，不表示内部实现需要复刻 Python 版。
  Future<T> cachedCall<T>({
    required String functionIdentifier,
    required FutureOr<T> Function() loader,
    CachePolicy policy = const CachePolicy(),
    List<Object?> args = const <Object?>[],
    Map<String, Object?> kwargs = const <String, Object?>{},
  }) async {
    final CachedCallResult<T> result = await cachedCallWithStatus<T>(
      functionIdentifier: functionIdentifier,
      loader: loader,
      policy: policy,
      args: args,
      kwargs: kwargs,
    );
    return result.value;
  }

  /// 对齐 Python版 `cached_call_with_status` 的外部行为：返回 `(value, cached)`。
  Future<CachedCallResult<T>> cachedCallWithStatus<T>({
    required String functionIdentifier,
    required FutureOr<T> Function() loader,
    CachePolicy policy = const CachePolicy(),
    List<Object?> args = const <Object?>[],
    Map<String, Object?> kwargs = const <String, Object?>{},
  }) async {
    await _ensurePolicyVersion(policy);
    final String key = buildCacheKey(
      functionIdentifier: functionIdentifier,
      args: args,
      kwargs: kwargs,
      typed: policy.typed,
      ignoreArgs: policy.ignoreArgs,
    );
    final String l1Key = _compositeKey(policy.namespace, key);
    final _MemoryEntry? l1Hit = _readL1(l1Key);
    if (l1Hit != null) {
      return CachedCallResult<T>(value: l1Hit.value as T, cached: true);
    }

    final CacheStoreEntry? l2Hit = await _store.getEntry(policy.namespace, key);
    if (l2Hit != null) {
      _writeL1(l1Key, value: l2Hit.value, expiresAtMs: l2Hit.expiresAtMs);
      return CachedCallResult<T>(value: l2Hit.value as T, cached: true);
    }

    final T produced = await Future<T>.value(loader());
    final int? expiresAt = _expiresAtMs(policy.ttl);
    try {
      await _store.set(policy.namespace, key, produced, ttl: policy.ttl);
      _writeL1(l1Key, value: produced, expiresAtMs: expiresAt);
    } on Object catch (error, stackTrace) {
      if (!_isTransientCacheWriteFailure(error)) {
        rethrow;
      }
      _logger.info(
        'cache write skipped after loader success'
        ' namespace=${policy.namespace}'
        ' function=$functionIdentifier'
        ' error=$error stack=$stackTrace',
      );
    }
    return CachedCallResult<T>(value: produced, cached: false);
  }

  /// 构建缓存键：与Python版 `_buildcache_key` 语义对齐。
  ///
  /// 语义：
  /// - base: `functionIdentifier`
  /// - args: 过滤 ignore 中的位置索引
  /// - kwargs: 过滤 ignore 中的关键字并按 key 排序
  /// - typed: 追加参数类型签名
  static String buildCacheKey({
    required String functionIdentifier,
    List<Object?> args = const <Object?>[],
    Map<String, Object?> kwargs = const <String, Object?>{},
    bool typed = true,
    Set<Object> ignoreArgs = const <Object>{},
  }) {
    final Set<int> ignoredIndexes = <int>{};
    final Set<String> ignoredNames = <String>{};
    for (final Object item in ignoreArgs) {
      if (item is int) {
        ignoredIndexes.add(item);
      } else if (item is String) {
        ignoredNames.add(item);
      }
    }

    final List<Object?> filteredArgs = <Object?>[];
    for (int index = 0; index < args.length; index += 1) {
      if (ignoredIndexes.contains(index)) {
        continue;
      }
      filteredArgs.add(args[index]);
    }

    final List<MapEntry<String, Object?>> sortedKwargs =
        kwargs.entries
            .where(
              (MapEntry<String, Object?> entry) =>
                  !ignoredNames.contains(entry.key),
            )
            .toList(growable: false)
          ..sort((MapEntry<String, Object?> a, MapEntry<String, Object?> b) {
            return a.key.compareTo(b.key);
          });

    final List<Object?> keyPayload = <Object?>[functionIdentifier];
    for (final Object? arg in filteredArgs) {
      keyPayload.add(_canonicalForKey(arg));
    }
    for (final MapEntry<String, Object?> entry in sortedKwargs) {
      keyPayload.add(<Object?>[entry.key, _canonicalForKey(entry.value)]);
    }
    if (typed) {
      for (final Object? arg in filteredArgs) {
        keyPayload.add(_typeName(arg));
      }
      for (final MapEntry<String, Object?> entry in sortedKwargs) {
        keyPayload.add(_typeName(entry.value));
      }
    }
    return jsonEncode(keyPayload);
  }

  Future<void> dispose() async {
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      await _memory.dispose();
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }
    try {
      await _store.dispose();
    } catch (error, stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    } finally {
      _ensuredVersions.clear();
    }
    if (failure != null && failureStackTrace != null) {
      Error.throwWithStackTrace(failure, failureStackTrace);
    }
  }

  bool _isTransientCacheWriteFailure(Object error) {
    if (isTransientSqliteBusyError(error)) {
      return true;
    }
    final String message = error.toString().toLowerCase();
    return message.contains('database is locked') ||
        message.contains('database is busy');
  }

  Future<void> _ensurePolicyVersion(CachePolicy policy) async {
    await _store.initialize();
    final int? cachedVersion = _ensuredVersions[policy.namespace];
    if (cachedVersion != null && cachedVersion != policy.cacheVersion) {
      _clearL1Namespace(policy.namespace);
    }
    if (cachedVersion == policy.cacheVersion) {
      return;
    }
    await _store.ensureNamespaceVersion(policy.namespace, policy.cacheVersion);
    _ensuredVersions[policy.namespace] = policy.cacheVersion;
  }

  String _compositeKey(String namespace, String key) => '$namespace::$key';

  _MemoryEntry? _readL1(String key) {
    final _MemoryEntry? entry = _memory.get(key);
    if (entry == null) {
      return null;
    }
    final int? expiresAt = entry.expiresAtMs;
    if (expiresAt != null &&
        DateTime.now().toUtc().millisecondsSinceEpoch > expiresAt) {
      _memory.remove(key);
      return null;
    }
    return entry;
  }

  void _writeL1(
    String key, {
    required Object? value,
    required int? expiresAtMs,
  }) {
    _memory.set(key, _MemoryEntry(value: value, expiresAtMs: expiresAtMs));
  }

  void _clearL1Namespace(String namespace) {
    final String prefix = '$namespace::';
    for (final String key in _memory.orderedKeys()) {
      if (key.startsWith(prefix)) {
        _memory.remove(key);
      }
    }
  }

  int? _expiresAtMs(Duration? ttl) {
    return ttl == null
        ? null
        : DateTime.now().toUtc().millisecondsSinceEpoch + ttl.inMilliseconds;
  }

  static Object? _canonicalForKey(Object? value) {
    if (value == null || value is bool || value is String) {
      return value;
    }
    if (value is num) {
      return _normalizeNumber(value);
    }
    if (value is Uint8List) {
      return <String, Object?>{'__bytes__': base64Encode(value)};
    }
    if (value is List) {
      return value.map(_canonicalForKey).toList(growable: false);
    }
    if (value is Set) {
      final List<String> items =
          value
              .map((Object? item) => jsonEncode(_canonicalForKey(item)))
              .toList(growable: false)
            ..sort();
      return <String, Object?>{'__set__': items};
    }
    if (value is Map) {
      final List<List<Object?>> pairs = <List<Object?>>[];
      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        final String key = entry.key.toString();
        pairs.add(<Object?>[key, _canonicalForKey(entry.value)]);
      }
      pairs.sort((List<Object?> a, List<Object?> b) {
        return (a.first as String).compareTo(b.first as String);
      });
      return <String, Object?>{'__map__': pairs};
    }
    return <String, Object?>{'__str__': value.toString()};
  }

  static Object _normalizeNumber(num value) {
    if (value is double) {
      if (!value.isFinite) {
        return value.toString();
      }
      if (value == value.truncateToDouble()) {
        return value.toInt();
      }
      return value;
    }
    return value;
  }

  static String _typeName(Object? value) {
    return value == null ? 'Null' : value.runtimeType.toString();
  }
}

final class _MemoryEntry {
  const _MemoryEntry({required this.value, required this.expiresAtMs});

  final Object? value;
  final int? expiresAtMs;
}
