import 'dart:typed_data';

/// 缓存策略：用于描述一次缓存调用的行为约束。
class CachePolicy {
  const CachePolicy({
    this.namespace = 'default',
    this.cacheVersion = 1,
    this.ttl,
    this.typed = true,
    this.ignoreArgs = const <Object>{},
  });

  final String namespace;
  final int cacheVersion;
  final Duration? ttl;
  final bool typed;

  /// 忽略参数集合：支持位置参数索引（`int`）和关键字参数名（`String`）。
  final Set<Object> ignoreArgs;
}

/// 缓存命中状态包装结果，与Python版 `cached_call_with_status` 语义对齐。
class CachedCallResult<T> {
  const CachedCallResult({required this.value, required this.cached});

  final T value;
  final bool cached;
}

/// 缓存统计快照。
class CacheStats {
  const CacheStats({
    required this.namespace,
    required this.entryCount,
    required this.sizeBytes,
    required this.hits,
    required this.misses,
    required this.writes,
    required this.removals,
    required this.expired,
    required this.versionResets,
  });

  /// `null` 表示全局聚合统计。
  final String? namespace;
  final int entryCount;
  final int sizeBytes;
  final int hits;
  final int misses;
  final int writes;
  final int removals;
  final int expired;
  final int versionResets;

  double get hitRate {
    final int totalReads = hits + misses;
    if (totalReads == 0) {
      return 0;
    }
    return hits / totalReads;
  }

  CacheStats copyWith({
    String? namespace,
    int? entryCount,
    int? sizeBytes,
    int? hits,
    int? misses,
    int? writes,
    int? removals,
    int? expired,
    int? versionResets,
  }) {
    return CacheStats(
      namespace: namespace ?? this.namespace,
      entryCount: entryCount ?? this.entryCount,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      hits: hits ?? this.hits,
      misses: misses ?? this.misses,
      writes: writes ?? this.writes,
      removals: removals ?? this.removals,
      expired: expired ?? this.expired,
      versionResets: versionResets ?? this.versionResets,
    );
  }

  static const CacheStats empty = CacheStats(
    namespace: null,
    entryCount: 0,
    sizeBytes: 0,
    hits: 0,
    misses: 0,
    writes: 0,
    removals: 0,
    expired: 0,
    versionResets: 0,
  );
}

/// 持久层读取结果，携带 value 与过期时间信息，便于 L1 回填。
class CacheStoreEntry {
  const CacheStoreEntry({required this.value, this.expiresAtMs});

  final Object? value;
  final int? expiresAtMs;
}

/// 缓存值支持范围：
/// - JSON 原语 / Map / List
/// - 二进制 `Uint8List`
bool isSupportedCacheValue(Object? value) {
  if (value == null || value is bool || value is String) {
    return true;
  }
  if (value is num) {
    return value.isFinite;
  }
  if (value is Uint8List) {
    return true;
  }
  if (value is List) {
    for (final Object? item in value) {
      if (!isSupportedCacheValue(item)) {
        return false;
      }
    }
    return true;
  }
  if (value is Map) {
    for (final MapEntry<dynamic, dynamic> entry in value.entries) {
      if (entry.key is! String) {
        return false;
      }
      if (!isSupportedCacheValue(entry.value)) {
        return false;
      }
    }
    return true;
  }
  return false;
}
