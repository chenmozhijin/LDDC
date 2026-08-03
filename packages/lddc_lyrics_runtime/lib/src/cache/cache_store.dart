import 'cache_types.dart';

/// 持久缓存存储端口，负责命名空间数据读写与统计。
abstract class CacheStore {
  Future<void> initialize();

  Future<void> ensureNamespaceVersion(String namespace, int cacheVersion);

  Future<CacheStoreEntry?> getEntry(String namespace, String key);

  Future<Object?> get(String namespace, String key) async {
    final CacheStoreEntry? entry = await getEntry(namespace, key);
    return entry?.value;
  }

  Future<void> set(
    String namespace,
    String key,
    Object? value, {
    Duration? ttl,
  });

  /// 在存储后端的同一个短事务中读取、计算并写回一个值。
  ///
  /// [update] 必须是同步纯计算，严禁在回调中启动网络或其他异步任务，否则会
  /// 扩大数据库锁窗口。返回值会作为新的缓存值写入并返回给调用方。
  Future<Object?> updateAtomically(
    String namespace,
    String key,
    Object? Function(Object? current) update, {
    Duration? ttl,
  });

  Future<void> remove(String namespace, String key);

  Future<void> clearNamespace(String namespace);

  Future<void> clearAll();

  Future<CacheStats> stats({String? namespace});

  Stream<CacheStats> watchStats({String? namespace, bool emitCurrent = true});

  Future<void> dispose();
}
