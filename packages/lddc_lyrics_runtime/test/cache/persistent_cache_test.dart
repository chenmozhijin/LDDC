// ignore_for_file: avoid_slow_async_io
// 测试与生产缓存路径保持一致，使用异步文件状态检查覆盖非阻塞 IO 口径。

import 'dart:io';
import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  group('PersistentCacheStore', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lddc-cache-');
      dbFile = File(p.join(tempDir.path, 'cache.sqlite3'));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    PersistentCacheStore createStore() {
      return PersistentCacheStore(executor: NativeDatabase(dbFile));
    }

    Future<void> prepareNamespace(
      PersistentCacheStore store, {
      required String namespace,
      required int cacheVersion,
    }) async {
      await store.initialize();
      await store.ensureNamespaceVersion(namespace, cacheVersion);
    }

    test('cacheVersion 变化会清空命名空间缓存', () async {
      final PersistentCacheStore storeV1 = createStore();
      await prepareNamespace(storeV1, namespace: 'lddc.cache', cacheVersion: 1);
      await storeV1.set('lddc.cache', 'a', 1);
      await storeV1.dispose();

      final PersistentCacheStore storeV2 = createStore();
      await prepareNamespace(storeV2, namespace: 'lddc.cache', cacheVersion: 2);
      expect(await storeV2.get('lddc.cache', 'a'), isNull);
      final CacheStats stats = await storeV2.stats(namespace: 'lddc.cache');
      expect(stats.versionResets, 1);
      expect(stats.entryCount, 0);
      await storeV2.dispose();
    });

    test('TTL 到期后自动失效并删除', () async {
      final PersistentCacheStore store = createStore();
      await prepareNamespace(store, namespace: 'ttl.cache', cacheVersion: 1);
      await store.set(
        'ttl.cache',
        'k',
        'v',
        ttl: const Duration(milliseconds: 1),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final Object? value = await store.get('ttl.cache', 'k');
      final CacheStats stats = await store.stats(namespace: 'ttl.cache');

      expect(value, isNull);
      expect(stats.expired, 1);
      expect(stats.removals, 1);
      expect(stats.misses, 1);

      await store.dispose();
    });

    test('命名空间隔离与 clearNamespace 行为正确', () async {
      final PersistentCacheStore store = createStore();
      await prepareNamespace(store, namespace: 'cache.a', cacheVersion: 1);
      await prepareNamespace(store, namespace: 'cache.b', cacheVersion: 1);

      await store.set('cache.a', 'k1', 1);
      await store.set('cache.b', 'k1', 2);
      await store.clearNamespace('cache.a');

      expect(await store.get('cache.a', 'k1'), isNull);
      expect(await store.get('cache.b', 'k1'), 2);

      await store.dispose();
    });

    test('进程重启后仍可命中持久缓存', () async {
      final PersistentCacheStore store1 = createStore();
      await prepareNamespace(
        store1,
        namespace: 'restart.cache',
        cacheVersion: 1,
      );
      await store1.set('restart.cache', 'song', <String, Object?>{
        'id': 7,
        'name': 'test',
      });
      await store1.dispose();

      final PersistentCacheStore store2 = createStore();
      await prepareNamespace(
        store2,
        namespace: 'restart.cache',
        cacheVersion: 1,
      );
      expect(await store2.get('restart.cache', 'song'), <String, Object?>{
        'id': 7,
        'name': 'test',
      });
      final CacheStats stats = await store2.stats(namespace: 'restart.cache');
      expect(stats.hits, 1);

      await store2.dispose();
    });

    test('损坏 payload 时自动删除且不中断', () async {
      final PersistentCacheStore store1 = createStore();
      await prepareNamespace(
        store1,
        namespace: 'corrupt.cache',
        cacheVersion: 1,
      );
      await store1.set('corrupt.cache', 'broken', <String, Object?>{'x': 1});
      await store1.dispose();

      final sqlite3.Database rawDb = sqlite3.sqlite3.open(dbFile.path);
      rawDb.execute(
        "UPDATE cache_entries SET payload_type = 'json', payload_json = '{broken' WHERE namespace = ?",
        <Object>['corrupt.cache'],
      );
      rawDb.close();

      final PersistentCacheStore store2 = createStore();
      await prepareNamespace(
        store2,
        namespace: 'corrupt.cache',
        cacheVersion: 1,
      );
      expect(await store2.get('corrupt.cache', 'broken'), isNull);
      final CacheStats stats = await store2.stats(namespace: 'corrupt.cache');
      expect(stats.removals, 1);
      expect(stats.misses, 1);

      await store2.dispose();
    });

    test('统计项准确（hitRate/expired/versionResets/sizeBytes）', () async {
      final PersistentCacheStore store = createStore();
      await prepareNamespace(store, namespace: 'stats.cache', cacheVersion: 1);
      await store.set('stats.cache', 'a', 'alpha');
      await store.set(
        'stats.cache',
        'b',
        'beta',
        ttl: const Duration(milliseconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await store.get('stats.cache', 'a'), 'alpha');
      expect(await store.get('stats.cache', 'missing'), isNull);
      expect(await store.get('stats.cache', 'b'), isNull);
      await store.remove('stats.cache', 'a');

      final CacheStats stats = await store.stats(namespace: 'stats.cache');
      expect(stats.hits, 1);
      expect(stats.misses, 2);
      expect(stats.writes, 2);
      expect(stats.expired, 1);
      expect(stats.removals, 2);
      expect(stats.versionResets, 0);
      expect(stats.entryCount, 0);
      expect(stats.sizeBytes, 0);
      expect(stats.hitRate, 1 / 3);

      await store.dispose();
    });

    test('watchStats 默认先发当前快照再发变更', () async {
      final PersistentCacheStore store = createStore();
      await prepareNamespace(store, namespace: 'watch.cache', cacheVersion: 1);

      final Future<List<CacheStats>> eventsFuture = store
          .watchStats(namespace: 'watch.cache')
          .take(3)
          .toList();
      await Future<void>.delayed(Duration.zero);

      await store.set('watch.cache', 'a', 1);
      await store.get('watch.cache', 'a');

      final List<CacheStats> events = await eventsFuture;
      expect(events[0].writes, 0);
      expect(events[1].writes, 1);
      expect(events[2].hits, 1);

      await store.dispose();
    });

    test('watchStats 全局订阅会收到所有命名空间变更', () async {
      final PersistentCacheStore store = createStore();
      await prepareNamespace(store, namespace: 'watch.a', cacheVersion: 1);
      await prepareNamespace(store, namespace: 'watch.b', cacheVersion: 1);

      final Future<List<CacheStats>> eventsFuture = store
          .watchStats()
          .where((CacheStats stats) => stats.namespace == null)
          .take(3)
          .toList();
      await Future<void>.delayed(Duration.zero);

      await store.set('watch.a', 'a', 1);
      await store.set('watch.b', 'b', 2);

      final List<CacheStats> events = await eventsFuture;
      expect(events[0].writes, 0);
      expect(events[1].writes, 1);
      expect(events[2].writes, 2);

      await store.dispose();
    });

    test('clearAll 按命名空间记录实际删除数', () async {
      final PersistentCacheStore store = createStore();
      await prepareNamespace(store, namespace: 'clear.a', cacheVersion: 1);
      await prepareNamespace(store, namespace: 'clear.b', cacheVersion: 1);
      await store.set('clear.a', 'a1', 1);
      await store.set('clear.a', 'a2', 2);
      await store.set('clear.b', 'b1', 3);

      await store.clearAll();

      expect((await store.stats(namespace: 'clear.a')).removals, 2);
      expect((await store.stats(namespace: 'clear.b')).removals, 1);
      expect((await store.stats()).removals, 3);
      await store.dispose();
    });

    test('dispose 会等待进行中的初始化并阻止已释放实例重新打开', () async {
      final Completer<QueryExecutor> executorCompleter =
          Completer<QueryExecutor>();
      final PersistentCacheStore store = PersistentCacheStore(
        executorFactory: () => executorCompleter.future,
      );

      final Future<void> initialize = store.initialize();
      await Future<void>.delayed(Duration.zero);
      final Future<void> dispose = store.dispose();
      executorCompleter.complete(NativeDatabase.memory());

      await expectLater(initialize, throwsStateError);
      await dispose;
      await expectLater(store.initialize(), throwsStateError);
    });
  });
}
