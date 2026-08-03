import 'dart:async';

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('CacheFacade', () {
    test('buildCacheKey 对齐 typed/ignore/kwargs 排序语义', () {
      final String keyA = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        args: <Object?>[1, 'hello'],
        kwargs: <String, Object?>{'b': 2, 'a': 1},
        typed: true,
      );
      final String keyB = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        args: <Object?>[1, 'hello'],
        kwargs: <String, Object?>{'a': 1, 'b': 2},
        typed: true,
      );
      expect(keyA, keyB);

      final String numericUntypedInt = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        args: <Object?>[1],
        typed: false,
      );
      final String numericUntypedDouble = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        args: <Object?>[1.0],
        typed: false,
      );
      expect(numericUntypedInt, numericUntypedDouble);

      final String numericTypedInt = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        args: <Object?>[1],
        typed: true,
      );
      final String numericTypedDouble = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        args: <Object?>[1.0],
        typed: true,
      );
      expect(numericTypedInt, isNot(numericTypedDouble));

      final String ignoredArgKeyA = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        args: <Object?>['keyword', 1],
        ignoreArgs: const <Object>{1},
      );
      final String ignoredArgKeyB = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        args: <Object?>['keyword', 999],
        ignoreArgs: const <Object>{1},
      );
      expect(ignoredArgKeyA, ignoredArgKeyB);

      final String ignoredKwA = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        kwargs: <String, Object?>{'token': 'a', 'page': 1},
        ignoreArgs: const <Object>{'token'},
      );
      final String ignoredKwB = CacheFacade.buildCacheKey(
        functionIdentifier: 'core.api.search',
        kwargs: <String, Object?>{'token': 'b', 'page': 1},
        ignoreArgs: const <Object>{'token'},
      );
      expect(ignoredKwA, ignoredKwB);
    });

    test('cachedCallWithStatus 命中标记准确', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade facade = CacheFacade(store: store, memoryCapacity: 8);
      int callCount = 0;

      final CachePolicy policy = const CachePolicy(
        namespace: 'lyrics.search',
        cacheVersion: 1,
        typed: true,
        ignoreArgs: <Object>{'traceId'},
      );

      final CachedCallResult<Map<String, Object?>> first = await facade
          .cachedCallWithStatus<Map<String, Object?>>(
            functionIdentifier: 'LDDC.core.api.lyrics.search',
            policy: policy,
            args: <Object?>['Aimer'],
            kwargs: <String, Object?>{'page': 1, 'traceId': 'abc'},
            loader: () {
              callCount += 1;
              return <String, Object?>{'items': 1};
            },
          );
      expect(first.cached, isFalse);
      expect(callCount, 1);

      final CachedCallResult<Map<String, Object?>> second = await facade
          .cachedCallWithStatus<Map<String, Object?>>(
            functionIdentifier: 'LDDC.core.api.lyrics.search',
            policy: policy,
            args: <Object?>['Aimer'],
            kwargs: <String, Object?>{'traceId': 'changed', 'page': 1},
            loader: () {
              callCount += 1;
              return <String, Object?>{'items': 2};
            },
          );
      expect(second.cached, isTrue);
      expect(second.value, <String, Object?>{'items': 1});
      expect(callCount, 1);

      await facade.dispose();
    });

    test('TTL 到期后会重新执行 loader', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade facade = CacheFacade(store: store, memoryCapacity: 8);
      int callCount = 0;
      final CachePolicy policy = const CachePolicy(
        namespace: 'translate',
        cacheVersion: 1,
        ttl: Duration(milliseconds: 1),
      );

      final CachedCallResult<String> first = await facade
          .cachedCallWithStatus<String>(
            functionIdentifier: 'LDDC.core.api.translate',
            policy: policy,
            args: <Object?>['hello'],
            loader: () {
              callCount += 1;
              return '你好';
            },
          );
      expect(first.cached, isFalse);
      expect(callCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final CachedCallResult<String> second = await facade
          .cachedCallWithStatus<String>(
            functionIdentifier: 'LDDC.core.api.translate',
            policy: policy,
            args: <Object?>['hello'],
            loader: () {
              callCount += 1;
              return '你好2';
            },
          );
      expect(second.cached, isFalse);
      expect(second.value, '你好2');
      expect(callCount, 2);

      await facade.dispose();
    });

    test('cacheVersion 变化会触发 namespace 清空', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade facade = CacheFacade(store: store, memoryCapacity: 8);
      int callCount = 0;

      Future<CachedCallResult<int>> runWithVersion(int version) {
        return facade.cachedCallWithStatus<int>(
          functionIdentifier: 'LDDC.core.api.songlist',
          policy: CachePolicy(namespace: 'songlist', cacheVersion: version),
          args: const <Object?>['id-1'],
          loader: () {
            callCount += 1;
            return callCount;
          },
        );
      }

      final CachedCallResult<int> v1First = await runWithVersion(1);
      final CachedCallResult<int> v1Second = await runWithVersion(1);
      final CachedCallResult<int> v2First = await runWithVersion(2);
      expect(v1First.cached, isFalse);
      expect(v1Second.cached, isTrue);
      expect(v2First.cached, isFalse);
      expect(callCount, 2);

      final CacheStats stats = await facade.stats(namespace: 'songlist');
      expect(stats.versionResets, 1);

      await facade.dispose();
    });

    test('clearNamespace 会同步清理 L1 内存缓存', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade facade = CacheFacade(store: store, memoryCapacity: 8);
      int callCount = 0;
      final CachePolicy policy = const CachePolicy(namespace: 'lyrics.search');

      Future<CachedCallResult<int>> cachedCall() {
        return facade.cachedCallWithStatus<int>(
          functionIdentifier: 'LDDC.core.api.lyrics.search',
          policy: policy,
          args: const <Object?>['keyword'],
          loader: () {
            callCount += 1;
            return callCount;
          },
        );
      }

      expect((await cachedCall()).value, 1);
      expect((await cachedCall()).cached, isTrue);

      await facade.clearNamespace('lyrics.search');

      final CachedCallResult<int> afterClear = await cachedCall();
      expect(afterClear.cached, isFalse);
      expect(afterClear.value, 2);
      expect(callCount, 2);

      await facade.dispose();
    });

    test('clearAll 会清理全部 L1 与版本状态', () async {
      final PersistentCacheStore store = PersistentCacheStore(
        executor: NativeDatabase.memory(),
      );
      final CacheFacade facade = CacheFacade(store: store, memoryCapacity: 8);
      int callCount = 0;
      final CachePolicy policy = const CachePolicy(
        namespace: 'songlist',
        cacheVersion: 1,
      );

      Future<CachedCallResult<int>> cachedCall() {
        return facade.cachedCallWithStatus<int>(
          functionIdentifier: 'LDDC.core.api.songlist',
          policy: policy,
          args: const <Object?>['id-1'],
          loader: () {
            callCount += 1;
            return callCount;
          },
        );
      }

      expect((await cachedCall()).value, 1);
      expect((await cachedCall()).cached, isTrue);

      await facade.clearAll();

      final CachedCallResult<int> afterClear = await cachedCall();
      expect(afterClear.cached, isFalse);
      expect(afterClear.value, 2);
      expect(callCount, 2);

      await facade.dispose();
    });

    test('loader 成功但缓存写入 busy 时会返回结果并标记未命中', () async {
      final _ThrowingCacheStore store = _ThrowingCacheStore(
        setError: StateError('database is locked'),
      );
      final CacheFacade facade = CacheFacade(store: store, memoryCapacity: 8);

      final CachedCallResult<String> result = await facade
          .cachedCallWithStatus<String>(
            functionIdentifier: 'LDDC.core.api.lyrics.search',
            policy: const CachePolicy(namespace: 'lyrics.search'),
            args: const <Object?>['keyword'],
            loader: () => 'search-result',
          );

      expect(result.value, 'search-result');
      expect(result.cached, isFalse);
      expect(store.setCalls, 1);
      await facade.dispose();
    });

    test('loader 成功但缓存写入非 transient 错误时仍会抛出', () async {
      final _ThrowingCacheStore store = _ThrowingCacheStore(
        setError: StateError('payload encode failed'),
      );
      final CacheFacade facade = CacheFacade(store: store, memoryCapacity: 8);

      await expectLater(
        facade.cachedCallWithStatus<String>(
          functionIdentifier: 'LDDC.core.api.lyrics.search',
          policy: const CachePolicy(namespace: 'lyrics.search'),
          args: const <Object?>['keyword'],
          loader: () => 'search-result',
        ),
        throwsA(isA<StateError>()),
      );
      expect(store.setCalls, 1);
      await facade.dispose();
    });

    test('直接 set 持久写入失败时不会把未提交值留在 L1', () async {
      final _ThrowingCacheStore store = _ThrowingCacheStore(
        setError: StateError('persistent write failed'),
      );
      final CacheFacade facade = CacheFacade(store: store, memoryCapacity: 8);

      await expectLater(
        facade.set('settings', 'key', 'uncommitted'),
        throwsStateError,
      );

      expect(await facade.get('settings', 'key'), isNull);
      await facade.dispose();
    });
  });
}

class _ThrowingCacheStore extends CacheStore {
  _ThrowingCacheStore({required this.setError});

  final Object setError;
  int setCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> ensureNamespaceVersion(
    String namespace,
    int cacheVersion,
  ) async {}

  @override
  Future<CacheStoreEntry?> getEntry(String namespace, String key) async => null;

  @override
  Future<void> set(
    String namespace,
    String key,
    Object? value, {
    Duration? ttl,
  }) async {
    setCalls += 1;
    throw setError;
  }

  @override
  Future<Object?> updateAtomically(
    String namespace,
    String key,
    Object? Function(Object? current) update, {
    Duration? ttl,
  }) async {
    update(null);
    setCalls += 1;
    throw setError;
  }

  @override
  Future<void> remove(String namespace, String key) async {}

  @override
  Future<void> clearNamespace(String namespace) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<CacheStats> stats({String? namespace}) async {
    return CacheStats.empty.copyWith(namespace: namespace);
  }

  @override
  Stream<CacheStats> watchStats({String? namespace, bool emitCurrent = true}) {
    return const Stream<CacheStats>.empty();
  }

  @override
  Future<void> dispose() async {}
}
