import 'dart:async';
import 'dart:collection';

/// 内存缓存统计快照。
class MemoryCacheStats {
  const MemoryCacheStats({
    required this.capacity,
    required this.size,
    required this.hits,
    required this.misses,
    required this.writes,
    required this.evictions,
    required this.removals,
  });

  final int capacity;
  final int size;
  final int hits;
  final int misses;
  final int writes;
  final int evictions;
  final int removals;

  /// 热路径命中率（`hits / (hits + misses)`）。
  double get hitRate {
    final int totalReads = hits + misses;
    if (totalReads == 0) {
      return 0;
    }
    return hits / totalReads;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MemoryCacheStats &&
            capacity == other.capacity &&
            size == other.size &&
            hits == other.hits &&
            misses == other.misses &&
            writes == other.writes &&
            evictions == other.evictions &&
            removals == other.removals);
  }

  @override
  int get hashCode =>
      Object.hash(capacity, size, hits, misses, writes, evictions, removals);
}

/// 通用内存 LRU 缓存。
///
/// 设计目标：
/// - `O(1)` 读取/写入
/// - 淘汰最久未使用项
/// - 提供命中统计与变化流，满足“可观测”要求
class LruMemoryCache<K, V extends Object> {
  LruMemoryCache({required int capacity})
    : _capacity = _validateCapacity(capacity);

  final int _capacity;
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();
  final StreamController<MemoryCacheStats> _statsController =
      StreamController<MemoryCacheStats>.broadcast();

  int _hits = 0;
  int _misses = 0;
  int _writes = 0;
  int _evictions = 0;
  int _removals = 0;
  bool _disposed = false;

  int get capacity => _capacity;
  int get size => _entries.length;

  /// 当前统计快照。
  MemoryCacheStats get stats {
    _ensureActive();
    return _snapshot();
  }

  /// 读取缓存，命中后自动刷新为最近使用项。
  V? get(K key) {
    _ensureActive();
    final V? value = _entries.remove(key);
    if (value == null) {
      _misses += 1;
      _emitStats();
      return null;
    }
    _entries[key] = value;
    _hits += 1;
    _emitStats();
    return value;
  }

  /// 写入缓存，必要时触发 LRU 淘汰。
  void set(K key, V value) {
    _ensureActive();
    _writes += 1;
    if (_entries.containsKey(key)) {
      _entries.remove(key);
      _entries[key] = value;
      _emitStats();
      return;
    }
    if (_entries.length >= _capacity) {
      final K oldestKey = _entries.keys.first;
      _entries.remove(oldestKey);
      _evictions += 1;
    }
    _entries[key] = value;
    _emitStats();
  }

  /// 不命中时计算并写入，再返回最新值。
  V getOrSet(K key, V Function() producer) {
    _ensureActive();
    final V? cached = get(key);
    if (cached != null) {
      return cached;
    }
    final V produced = producer();
    set(key, produced);
    return produced;
  }

  /// 移除缓存项，返回旧值（若存在）。
  V? remove(K key) {
    _ensureActive();
    final V? removed = _entries.remove(key);
    if (removed != null) {
      _removals += 1;
      _emitStats();
    }
    return removed;
  }

  /// 清空缓存数据（保留统计计数）。
  void clear() {
    _ensureActive();
    if (_entries.isEmpty) {
      return;
    }
    _entries.clear();
    _emitStats();
  }

  bool containsKey(K key) {
    _ensureActive();
    return _entries.containsKey(key);
  }

  /// 以 LRU -> MRU 顺序返回 key 快照（便于测试与调试）。
  List<K> orderedKeys() {
    _ensureActive();
    return _entries.keys.toList(growable: false);
  }

  /// 订阅统计变化流。
  Stream<MemoryCacheStats> watchStats({bool emitCurrent = true}) async* {
    _ensureActive();
    if (emitCurrent) {
      yield _snapshot();
    }
    yield* _statsController.stream;
  }

  /// 释放资源。
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _entries.clear();
    await _statsController.close();
  }

  static int _validateCapacity(int capacity) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', '必须大于 0');
    }
    return capacity;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('LruMemoryCache 已释放');
    }
  }

  MemoryCacheStats _snapshot() {
    return MemoryCacheStats(
      capacity: _capacity,
      size: _entries.length,
      hits: _hits,
      misses: _misses,
      writes: _writes,
      evictions: _evictions,
      removals: _removals,
    );
  }

  void _emitStats() {
    _statsController.add(_snapshot());
  }
}
