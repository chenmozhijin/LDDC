import 'package:test/test.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('LruMemoryCache', () {
    test('非法容量在 release 语义下也会立即拒绝', () {
      expect(
        () => LruMemoryCache<String, int>(capacity: 0),
        throwsArgumentError,
      );
    });

    test('读写统计可观测', () async {
      final LruMemoryCache<String, int> cache = LruMemoryCache<String, int>(
        capacity: 2,
      );

      cache.set('a', 1);
      cache.set('b', 2);

      expect(cache.get('a'), 1);
      expect(cache.get('missing'), isNull);

      final MemoryCacheStats stats = cache.stats;
      expect(stats.size, 2);
      expect(stats.writes, 2);
      expect(stats.hits, 1);
      expect(stats.misses, 1);
      expect(stats.hitRate, 0.5);

      await cache.dispose();
    });

    test('命中后会刷新 LRU 顺序并淘汰最旧项', () async {
      final LruMemoryCache<String, int> cache = LruMemoryCache<String, int>(
        capacity: 2,
      );
      cache
        ..set('a', 1)
        ..set('b', 2);

      expect(cache.get('a'), 1);
      cache.set('c', 3);

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('c'), isTrue);
      expect(cache.orderedKeys(), <String>['a', 'c']);
      expect(cache.stats.evictions, 1);

      await cache.dispose();
    });

    test('getOrSet 仅在未命中时计算', () async {
      final LruMemoryCache<String, String> cache =
          LruMemoryCache<String, String>(capacity: 1);
      int callCount = 0;

      final String first = cache.getOrSet('key', () {
        callCount += 1;
        return 'value';
      });
      final String second = cache.getOrSet('key', () {
        callCount += 1;
        return 'value2';
      });

      expect(first, 'value');
      expect(second, 'value');
      expect(callCount, 1);
      expect(cache.stats.writes, 1);
      expect(cache.stats.misses, 1);
      expect(cache.stats.hits, 1);

      await cache.dispose();
    });

    test('watchStats 默认先发当前快照再发增量', () async {
      final LruMemoryCache<String, int> cache = LruMemoryCache<String, int>(
        capacity: 2,
      );

      final Future<List<MemoryCacheStats>> eventsFuture = cache
          .watchStats()
          .take(3)
          .toList();
      await Future<void>.delayed(Duration.zero);

      cache.set('a', 1);
      cache.get('a');

      final List<MemoryCacheStats> events = await eventsFuture;
      expect(events[0].size, 0);
      expect(events[0].writes, 0);
      expect(events[1].size, 1);
      expect(events[1].writes, 1);
      expect(events[2].hits, 1);

      await cache.dispose();
    });

    test('remove/clear 行为稳定', () async {
      final LruMemoryCache<String, int> cache = LruMemoryCache<String, int>(
        capacity: 2,
      );
      cache
        ..set('a', 1)
        ..set('b', 2);

      expect(cache.remove('missing'), isNull);
      expect(cache.remove('a'), 1);
      expect(cache.stats.removals, 1);
      expect(cache.size, 1);

      cache.clear();
      expect(cache.size, 0);

      await cache.dispose();
    });

    test('dispose 会清空条目、保持幂等并拒绝后续访问', () async {
      final LruMemoryCache<String, int> cache = LruMemoryCache<String, int>(
        capacity: 2,
      )..set('a', 1);

      await cache.dispose();
      await cache.dispose();

      expect(cache.size, 0);
      expect(() => cache.get('a'), throwsStateError);
      expect(() => cache.stats, throwsStateError);
    });
  });
}
