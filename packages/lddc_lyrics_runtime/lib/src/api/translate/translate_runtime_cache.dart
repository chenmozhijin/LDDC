import 'dart:convert';
import 'dart:collection';

import 'package:crypto/crypto.dart';

import '../../cache/cache_ttl.dart';

/// 单个翻译客户端拥有的进程内缓存，对齐Python版 `cache` 的 4 小时策略。
///
/// 缓存不使用 static 状态：同一个 TranslateApi 的三个 provider 共享一个实例，
/// 不同 runtime/ProviderContainer 之间完全隔离，关闭客户端时可确定释放全部条目。
final class TranslateRuntimeCache {
  TranslateRuntimeCache();

  static const int _maxEntries = 256;
  static const int _maxApproxBytes = 4 * 1024 * 1024;

  final LinkedHashMap<String, _CacheEntry> _entries =
      LinkedHashMap<String, _CacheEntry>();
  int _approxBytes = 0;
  bool _closed = false;

  /// 读取缓存值；命中过期条目时会自动清理。
  T? get<T>(List<Object?> keyParts) {
    _ensureOpen();
    final String key = _encodeKey(keyParts);
    final _CacheEntry? entry = _entries[key];
    if (entry == null) {
      return null;
    }
    final int nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (entry.expiresAtMs <= nowMs) {
      _entries.remove(key);
      _approxBytes -= entry.approxBytes;
      return null;
    }
    // LinkedHashMap 不会自动维护访问顺序，命中后重插到尾部表示最近使用。
    _entries
      ..remove(key)
      ..[key] = entry;
    return entry.value as T;
  }

  /// 写入缓存值；默认 TTL 对齐Python版翻译链路 4 小时。
  void set<T>(
    List<Object?> keyParts,
    T value, {
    Duration ttl = CacheTtl.translate,
  }) {
    _ensureOpen();
    final String key = _encodeKey(keyParts);
    final int expiresAtMs =
        DateTime.now().toUtc().millisecondsSinceEpoch + ttl.inMilliseconds;
    final _CacheEntry? old = _entries.remove(key);
    if (old != null) {
      _approxBytes -= old.approxBytes;
    }
    final int approxBytes = _estimateBytes(value);
    _entries[key] = _CacheEntry(
      value: value,
      expiresAtMs: expiresAtMs,
      approxBytes: approxBytes,
    );
    _approxBytes += approxBytes;
    _prune();
  }

  /// 清空当前客户端缓存；用于配置切换测试和显式资源释放。
  void clear() {
    _entries.clear();
    _approxBytes = 0;
  }

  /// 幂等释放实例持有的条目。
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    clear();
  }

  String _encodeKey(List<Object?> keyParts) {
    final String canonical = jsonEncode(keyParts);
    return sha1.convert(utf8.encode(canonical)).toString();
  }

  void _prune() {
    final int nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final MapEntry<String, _CacheEntry> entry in _entries.entries.toList(
      growable: false,
    )) {
      if (entry.value.expiresAtMs <= nowMs) {
        _entries.remove(entry.key);
        _approxBytes -= entry.value.approxBytes;
      }
    }
    while (_entries.length > _maxEntries || _approxBytes > _maxApproxBytes) {
      final MapEntry<String, _CacheEntry> eldest = _entries.entries.first;
      _entries.remove(eldest.key);
      _approxBytes -= eldest.value.approxBytes;
    }
    if (_approxBytes < 0) {
      _approxBytes = 0;
    }
  }

  int _estimateBytes(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is String) {
      return value.length * 2;
    }
    if (value is Iterable) {
      int total = 0;
      for (final Object? item in value) {
        total += _estimateBytes(item);
      }
      return total;
    }
    if (value is Map) {
      int total = 0;
      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        total += _estimateBytes(entry.key) + _estimateBytes(entry.value);
      }
      return total;
    }
    return value.toString().length * 2;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('TranslateRuntimeCache 已关闭');
    }
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.value,
    required this.expiresAtMs,
    required this.approxBytes,
  });

  final Object? value;
  final int expiresAtMs;
  final int approxBytes;
}
