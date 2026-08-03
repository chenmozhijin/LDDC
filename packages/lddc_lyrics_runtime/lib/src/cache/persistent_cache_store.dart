import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'cache_store.dart';
import 'cache_types.dart';
import 'sqlite_exception_classifier.dart';

/// 基于 sqlite 的持久缓存实现（drift 作为数据访问层）。
///
/// 目标：
/// - 命名空间隔离
/// - TTL 到期惰性删除
/// - `cacheVersion` 变化事务清理
/// - 统计可观测（命中率、容量、版本重置次数等）
class PersistentCacheStore extends CacheStore {
  PersistentCacheStore({QueryExecutor? executor, this._executorFactory})
    : _providedExecutor = executor;

  final QueryExecutor? _providedExecutor;
  final Future<QueryExecutor> Function()? _executorFactory;

  _RawCacheDatabase? _db;
  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initializeFuture;

  final StreamController<CacheStats> _statsController =
      StreamController<CacheStats>.broadcast();
  final Map<String, _RuntimeCounters> _namespaceCounters =
      <String, _RuntimeCounters>{};
  final _RuntimeCounters _globalCounters = _RuntimeCounters();

  static const String _metaTable = 'cache_meta';
  static const String _entryTable = 'cache_entries';

  @override
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('PersistentCacheStore 已释放');
    }
    if (_initialized) {
      return;
    }
    final Future<void>? activeInitialize = _initializeFuture;
    if (activeInitialize != null) {
      await activeInitialize;
      return;
    }
    final Future<void> initializeFuture = _initialize();
    _initializeFuture = initializeFuture;
    try {
      await initializeFuture;
    } finally {
      if (!_initialized) {
        _initializeFuture = null;
      }
    }
  }

  Future<void> _initialize() async {
    final QueryExecutor? providedExecutor = _providedExecutor;
    final Future<QueryExecutor> Function()? executorFactory = _executorFactory;
    if (providedExecutor == null && executorFactory == null) {
      throw StateError('PersistentCacheStore 必须注入 executor 或 executorFactory');
    }
    final QueryExecutor executor =
        providedExecutor ?? await executorFactory!.call();
    final _RawCacheDatabase database = _RawCacheDatabase(executor);
    _db = database;
    try {
      if (_disposed) {
        throw StateError('PersistentCacheStore 已释放');
      }
      await _configureDatabase();
      await _runWithBusyRetry(_createSchema);
      if (_disposed) {
        throw StateError('PersistentCacheStore 已释放');
      }
      _initialized = true;
      await _emitStats(namespace: null);
    } catch (_) {
      if (identical(_db, database)) {
        _db = null;
      }
      _initialized = false;
      await database.close();
      rethrow;
    }
  }

  @override
  Future<void> ensureNamespaceVersion(
    String namespace,
    int cacheVersion,
  ) async {
    await initialize();
    final QueryRow? row = await _db!
        .customSelect(
          '''
SELECT cache_version
FROM $_metaTable
WHERE namespace = ?1
LIMIT 1
''',
          variables: <Variable>[Variable<String>(namespace)],
        )
        .getSingleOrNull();

    final int now = _nowMs();
    if (row == null) {
      await _upsertMeta(
        namespace: namespace,
        cacheVersion: cacheVersion,
        now: now,
      );
      await _emitStats(namespace: namespace);
      return;
    }

    final int storedVersion = _asInt(row.data['cache_version']) ?? 0;
    if (storedVersion == cacheVersion) {
      await _upsertMeta(
        namespace: namespace,
        cacheVersion: cacheVersion,
        now: now,
      );
      await _emitStats(namespace: namespace);
      return;
    }

    await _db!.transaction(() async {
      final int removedCount = await _deleteNamespaceRows(namespace);
      final _RuntimeCounters counters = _countersFor(namespace);
      counters.removals += removedCount;
      counters.versionResets += 1;
      _globalCounters.removals += removedCount;
      _globalCounters.versionResets += 1;
      await _upsertMeta(
        namespace: namespace,
        cacheVersion: cacheVersion,
        now: _nowMs(),
      );
    });
    await _emitStats(namespace: namespace);
  }

  @override
  Future<CacheStoreEntry?> getEntry(String namespace, String key) async {
    await initialize();
    final String keyHash = _hashKey(key);
    final QueryRow? row = await _db!
        .customSelect(
          '''
SELECT payload_type, payload_blob, payload_json, expires_at_ms
FROM $_entryTable
WHERE namespace = ?1 AND key_hash = ?2 AND key_debug = ?3
LIMIT 1
''',
          variables: <Variable>[
            Variable<String>(namespace),
            Variable<String>(keyHash),
            Variable<String>(key),
          ],
        )
        .getSingleOrNull();

    final _RuntimeCounters counters = _countersFor(namespace);
    if (row == null) {
      counters.misses += 1;
      _globalCounters.misses += 1;
      await _emitStats(namespace: namespace);
      return null;
    }

    final int now = _nowMs();
    final int? expiresAt = _asInt(row.data['expires_at_ms']);
    if (expiresAt != null && now > expiresAt) {
      final int removed = await _db!.customUpdate(
        '''
DELETE FROM $_entryTable
WHERE namespace = ?1 AND key_hash = ?2 AND key_debug = ?3
''',
        variables: <Variable>[
          Variable<String>(namespace),
          Variable<String>(keyHash),
          Variable<String>(key),
        ],
      );
      if (removed > 0) {
        counters.expired += 1;
        counters.removals += removed;
        _globalCounters.expired += 1;
        _globalCounters.removals += removed;
      }
      counters.misses += 1;
      _globalCounters.misses += 1;
      await _emitStats(namespace: namespace);
      return null;
    }

    final Object? value;
    try {
      value = _decodePayload(
        payloadType: row.data['payload_type'],
        payloadBlob: row.data['payload_blob'],
        payloadJson: row.data['payload_json'],
      );
    } catch (_) {
      final int removed = await _db!.customUpdate(
        '''
DELETE FROM $_entryTable
WHERE namespace = ?1 AND key_hash = ?2 AND key_debug = ?3
''',
        variables: <Variable>[
          Variable<String>(namespace),
          Variable<String>(keyHash),
          Variable<String>(key),
        ],
      );
      if (removed > 0) {
        counters.removals += removed;
        _globalCounters.removals += removed;
      }
      counters.misses += 1;
      _globalCounters.misses += 1;
      await _emitStats(namespace: namespace);
      return null;
    }

    await _db!.customUpdate(
      '''
UPDATE $_entryTable
SET accessed_at_ms = ?1
WHERE namespace = ?2 AND key_hash = ?3 AND key_debug = ?4
''',
      variables: <Variable>[
        Variable<int>(now),
        Variable<String>(namespace),
        Variable<String>(keyHash),
        Variable<String>(key),
      ],
    );

    counters.hits += 1;
    _globalCounters.hits += 1;
    await _emitStats(namespace: namespace);
    return CacheStoreEntry(value: value, expiresAtMs: expiresAt);
  }

  @override
  Future<void> set(
    String namespace,
    String key,
    Object? value, {
    Duration? ttl,
  }) async {
    await initialize();
    if (!isSupportedCacheValue(value)) {
      throw ArgumentError.value(value, 'value', '缓存值类型不受支持');
    }
    final int now = _nowMs();
    final int? expiresAt = ttl == null ? null : now + ttl.inMilliseconds;
    final _EncodedPayload encoded = _encodePayload(value);
    final String keyHash = _hashKey(key);
    await _runWithBusyRetry(
      () => _db!.customInsert(
        '''
INSERT INTO $_entryTable (
  namespace, key_hash, key_debug, payload_type, payload_blob, payload_json,
  expires_at_ms, created_at_ms, updated_at_ms, accessed_at_ms, size_bytes
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
ON CONFLICT(namespace, key_hash) DO UPDATE SET
  key_debug = excluded.key_debug,
  payload_type = excluded.payload_type,
  payload_blob = excluded.payload_blob,
  payload_json = excluded.payload_json,
  expires_at_ms = excluded.expires_at_ms,
  updated_at_ms = excluded.updated_at_ms,
  accessed_at_ms = excluded.accessed_at_ms,
  size_bytes = excluded.size_bytes
''',
        variables: <Variable>[
          Variable<String>(namespace),
          Variable<String>(keyHash),
          Variable<String>(key),
          Variable<String>(encoded.payloadType),
          Variable<Uint8List>(encoded.payloadBlob),
          Variable<String>(encoded.payloadJson),
          Variable<int>(expiresAt),
          Variable<int>(now),
          Variable<int>(now),
          Variable<int>(now),
          Variable<int>(encoded.sizeBytes),
        ],
      ),
    );
    final _RuntimeCounters counters = _countersFor(namespace);
    counters.writes += 1;
    _globalCounters.writes += 1;
    await _emitStats(namespace: namespace);
  }

  @override
  Future<Object?> updateAtomically(
    String namespace,
    String key,
    Object? Function(Object? current) update, {
    Duration? ttl,
  }) async {
    await initialize();
    final String keyHash = _hashKey(key);
    Object? updatedValue;
    bool hadValue = false;
    await _runWithBusyRetry(
      () => _db!.transaction(() async {
        final QueryRow? row = await _db!
            .customSelect(
              '''
SELECT payload_type, payload_blob, payload_json, expires_at_ms
FROM $_entryTable
WHERE namespace = ?1 AND key_hash = ?2 AND key_debug = ?3
LIMIT 1
''',
              variables: <Variable>[
                Variable<String>(namespace),
                Variable<String>(keyHash),
                Variable<String>(key),
              ],
            )
            .getSingleOrNull();
        final int now = _nowMs();
        Object? current;
        if (row != null) {
          final int? expiresAt = _asInt(row.data['expires_at_ms']);
          if (expiresAt == null || now <= expiresAt) {
            try {
              current = _decodePayload(
                payloadType: row.data['payload_type'],
                payloadBlob: row.data['payload_blob'],
                payloadJson: row.data['payload_json'],
              );
              hadValue = true;
            } catch (_) {
              // 损坏值按未命中处理，随后由 update 回调生成合法替代值。
            }
          }
        }
        updatedValue = update(current);
        if (!isSupportedCacheValue(updatedValue)) {
          throw ArgumentError.value(updatedValue, 'updatedValue', '缓存值类型不受支持');
        }
        final _EncodedPayload encoded = _encodePayload(updatedValue);
        final int? expiresAt = ttl == null ? null : now + ttl.inMilliseconds;
        await _db!.customInsert(
          '''
INSERT INTO $_entryTable (
  namespace, key_hash, key_debug, payload_type, payload_blob, payload_json,
  expires_at_ms, created_at_ms, updated_at_ms, accessed_at_ms, size_bytes
) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
ON CONFLICT(namespace, key_hash) DO UPDATE SET
  key_debug = excluded.key_debug,
  payload_type = excluded.payload_type,
  payload_blob = excluded.payload_blob,
  payload_json = excluded.payload_json,
  expires_at_ms = excluded.expires_at_ms,
  updated_at_ms = excluded.updated_at_ms,
  accessed_at_ms = excluded.accessed_at_ms,
  size_bytes = excluded.size_bytes
''',
          variables: <Variable>[
            Variable<String>(namespace),
            Variable<String>(keyHash),
            Variable<String>(key),
            Variable<String>(encoded.payloadType),
            Variable<Uint8List>(encoded.payloadBlob),
            Variable<String>(encoded.payloadJson),
            Variable<int>(expiresAt),
            Variable<int>(now),
            Variable<int>(now),
            Variable<int>(now),
            Variable<int>(encoded.sizeBytes),
          ],
        );
      }),
    );
    final _RuntimeCounters counters = _countersFor(namespace);
    if (hadValue) {
      counters.hits += 1;
      _globalCounters.hits += 1;
    } else {
      counters.misses += 1;
      _globalCounters.misses += 1;
    }
    counters.writes += 1;
    _globalCounters.writes += 1;
    await _emitStats(namespace: namespace);
    return updatedValue;
  }

  @override
  Future<void> remove(String namespace, String key) async {
    await initialize();
    final String keyHash = _hashKey(key);
    final int removed = await _db!.customUpdate(
      '''
DELETE FROM $_entryTable
WHERE namespace = ?1 AND key_hash = ?2 AND key_debug = ?3
''',
      variables: <Variable>[
        Variable<String>(namespace),
        Variable<String>(keyHash),
        Variable<String>(key),
      ],
    );
    if (removed > 0) {
      final _RuntimeCounters counters = _countersFor(namespace);
      counters.removals += removed;
      _globalCounters.removals += removed;
    }
    await _emitStats(namespace: namespace);
  }

  @override
  Future<void> clearNamespace(String namespace) async {
    await initialize();
    final int removed = await _deleteNamespaceRows(namespace);
    if (removed > 0) {
      final _RuntimeCounters counters = _countersFor(namespace);
      counters.removals += removed;
      _globalCounters.removals += removed;
    }
    await _emitStats(namespace: namespace);
  }

  @override
  Future<void> clearAll() async {
    await initialize();
    final ({int total, Map<String, int> byNamespace}) removed = await _db!
        .transaction(() async {
          final List<QueryRow> rows = await _db!.customSelect('''
SELECT namespace, COUNT(*) AS entry_count
FROM $_entryTable
GROUP BY namespace
''').get();
          final Map<String, int> byNamespace = <String, int>{};
          int total = 0;
          for (final QueryRow row in rows) {
            final Object? namespaceRaw = row.data['namespace'];
            final int count = _asInt(row.data['entry_count']) ?? 0;
            if (namespaceRaw is String && count > 0) {
              byNamespace[namespaceRaw] = count;
              total += count;
            }
          }
          await _db!.customUpdate('DELETE FROM $_entryTable');
          await _db!.customUpdate('DELETE FROM $_metaTable');
          return (total: total, byNamespace: byNamespace);
        });
    if (removed.total > 0) {
      _globalCounters.removals += removed.total;
      for (final MapEntry<String, int> entry in removed.byNamespace.entries) {
        _countersFor(entry.key).removals += entry.value;
      }
    }
    await _emitStats(namespace: null);
  }

  @override
  Future<CacheStats> stats({String? namespace}) async {
    await initialize();
    final QueryRow row;
    if (namespace == null) {
      row = await _db!.customSelect('''
SELECT COUNT(*) AS entry_count, COALESCE(SUM(size_bytes), 0) AS size_bytes
FROM $_entryTable
''').getSingle();
    } else {
      row = await _db!
          .customSelect(
            '''
SELECT COUNT(*) AS entry_count, COALESCE(SUM(size_bytes), 0) AS size_bytes
FROM $_entryTable
WHERE namespace = ?1
''',
            variables: <Variable>[Variable<String>(namespace)],
          )
          .getSingle();
    }

    final int entryCount = _asInt(row.data['entry_count']) ?? 0;
    final int sizeBytes = _asInt(row.data['size_bytes']) ?? 0;
    final _RuntimeCounters counters = namespace == null
        ? _globalCounters
        : _countersFor(namespace);
    return CacheStats(
      namespace: namespace,
      entryCount: entryCount,
      sizeBytes: sizeBytes,
      hits: counters.hits,
      misses: counters.misses,
      writes: counters.writes,
      removals: counters.removals,
      expired: counters.expired,
      versionResets: counters.versionResets,
    );
  }

  @override
  Stream<CacheStats> watchStats({
    String? namespace,
    bool emitCurrent = true,
  }) async* {
    if (emitCurrent) {
      yield await stats(namespace: namespace);
    }
    yield* _statsController.stream.where((CacheStats event) {
      return event.namespace == namespace;
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final Future<void>? activeInitialize = _initializeFuture;
    if (activeInitialize != null) {
      try {
        await activeInitialize;
      } catch (_) {
        // 初始化失败路径已经负责关闭自己创建的数据库执行器。
      }
    }
    await _statsController.close();
    await _db?.close();
    _db = null;
    _initialized = false;
    _initializeFuture = null;
    _namespaceCounters.clear();
  }

  Future<void> _configureDatabase() async {
    await _runWithBusyRetry(
      () => _db!.customStatement('PRAGMA busy_timeout = 5000'),
    );
    await _runWithBusyRetry(
      () => _db!.customStatement('PRAGMA journal_mode = WAL'),
    );
    await _runWithBusyRetry(
      () => _db!.customStatement('PRAGMA synchronous = NORMAL'),
    );
  }

  Future<void> _createSchema() async {
    await _db!.customStatement('''
CREATE TABLE IF NOT EXISTS $_metaTable (
  namespace TEXT NOT NULL PRIMARY KEY,
  cache_version INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
)
''');
    await _db!.customStatement('''
CREATE TABLE IF NOT EXISTS $_entryTable (
  namespace TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  key_debug TEXT NOT NULL,
  payload_type TEXT NOT NULL,
  payload_blob BLOB,
  payload_json TEXT,
  expires_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  accessed_at_ms INTEGER NOT NULL,
  size_bytes INTEGER NOT NULL,
  PRIMARY KEY (namespace, key_hash)
)
''');
    await _db!.customStatement('''
CREATE INDEX IF NOT EXISTS idx_cache_entries_namespace_expire
ON $_entryTable (namespace, expires_at_ms)
''');
    await _db!.customStatement('''
CREATE INDEX IF NOT EXISTS idx_cache_entries_namespace_accessed
ON $_entryTable (namespace, accessed_at_ms)
''');
  }

  Future<void> _upsertMeta({
    required String namespace,
    required int cacheVersion,
    required int now,
  }) {
    return _db!.customInsert(
      '''
INSERT INTO $_metaTable (namespace, cache_version, updated_at_ms)
VALUES (?1, ?2, ?3)
ON CONFLICT(namespace) DO UPDATE SET
  cache_version = excluded.cache_version,
  updated_at_ms = excluded.updated_at_ms
''',
      variables: <Variable>[
        Variable<String>(namespace),
        Variable<int>(cacheVersion),
        Variable<int>(now),
      ],
    );
  }

  Future<int> _deleteNamespaceRows(String namespace) {
    return _db!.customUpdate(
      '''
DELETE FROM $_entryTable
WHERE namespace = ?1
''',
      variables: <Variable>[Variable<String>(namespace)],
    );
  }

  Future<void> _emitStats({required String? namespace}) async {
    if (_disposed || _statsController.isClosed) {
      return;
    }
    final CacheStats scoped = await stats(namespace: namespace);
    if (_disposed || _statsController.isClosed) {
      return;
    }
    _statsController.add(scoped);
    if (namespace != null) {
      final CacheStats global = await stats(namespace: null);
      if (!_disposed && !_statsController.isClosed) {
        _statsController.add(global);
      }
    }
  }

  _RuntimeCounters _countersFor(String namespace) {
    return _namespaceCounters.putIfAbsent(namespace, _RuntimeCounters.new);
  }

  _EncodedPayload _encodePayload(Object? value) {
    if (value is Uint8List) {
      return _EncodedPayload(
        payloadType: 'bytes',
        // 缓存写入必须隔离调用方持有的 Uint8List；否则调用方在 await 后复用/修改原数组，
        // 可能让已经提交给数据库的缓存内容跟着变化，排查起来会非常困难。
        payloadBlob: Uint8List.fromList(value),
        payloadJson: null,
        sizeBytes: value.length,
      );
    }
    final String json = jsonEncode(value);
    return _EncodedPayload(
      payloadType: 'json',
      payloadBlob: null,
      payloadJson: json,
      sizeBytes: utf8.encode(json).length,
    );
  }

  Object? _decodePayload({
    required Object? payloadType,
    required Object? payloadBlob,
    required Object? payloadJson,
  }) {
    final String type = payloadType is String ? payloadType : '';
    if (type == 'bytes') {
      if (payloadBlob is Uint8List) {
        return payloadBlob;
      }
      if (payloadBlob is List<int>) {
        // sqlite/web 后端有时以普通 List<int> 返回 BLOB，这里只做类型收敛。
        return Uint8List.fromList(payloadBlob);
      }
      throw const FormatException('invalid bytes payload');
    }
    if (type == 'json') {
      if (payloadJson is! String) {
        throw const FormatException('invalid json payload');
      }
      return jsonDecode(payloadJson);
    }
    throw const FormatException('unsupported payload type');
  }

  String _hashKey(String key) {
    return sha256.convert(utf8.encode(key)).toString();
  }

  int _nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  int? _asInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is BigInt) {
      return raw.toInt();
    }
    if (raw is double && raw.isFinite) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  Future<T> _runWithBusyRetry<T>(Future<T> Function() operation) async {
    const List<Duration> delays = <Duration>[
      Duration(milliseconds: 20),
      Duration(milliseconds: 80),
      Duration(milliseconds: 200),
    ];
    for (int attempt = 0; ; attempt += 1) {
      try {
        return await operation();
      } on Object catch (error) {
        if (!_isTransientSqliteBusy(error) || attempt >= delays.length) {
          rethrow;
        }
        await Future<void>.delayed(delays[attempt]);
      }
    }
  }

  bool _isTransientSqliteBusy(Object error) {
    if (isTransientSqliteBusyError(error)) {
      return true;
    }
    final String message = error.toString().toLowerCase();
    return message.contains('database is locked') ||
        message.contains('database is busy');
  }
}

final class _EncodedPayload {
  const _EncodedPayload({
    required this.payloadType,
    required this.payloadBlob,
    required this.payloadJson,
    required this.sizeBytes,
  });

  final String payloadType;
  final Uint8List? payloadBlob;
  final String? payloadJson;
  final int sizeBytes;
}

final class _RuntimeCounters {
  int hits = 0;
  int misses = 0;
  int writes = 0;
  int removals = 0;
  int expired = 0;
  int versionResets = 0;
}

/// 手写 Drift runtime 适配器，不是 `.g.dart` 生成文件。
///
/// 这里用 `customSelect/customInsert/customUpdate` 自己维护 SQL schema，只借用
/// Drift 的 executor、事务和关闭生命周期；`allTables` 为空是有意为之。
final class _RawCacheDatabase extends GeneratedDatabase {
  _RawCacheDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables =>
      const <TableInfo<Table, dynamic>>[];
}
