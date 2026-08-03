import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  test('CacheFacade.updateAtomically 并发更新不丢失写入', () async {
    final CacheFacade cache = CacheFacade(
      store: PersistentCacheStore(executor: NativeDatabase.memory()),
    );

    await Future.wait(
      List<Future<Object?>>.generate(
        20,
        (_) => cache.updateAtomically(
          'atomic-test',
          'counter',
          (Object? current) => ((current as int?) ?? 0) + 1,
        ),
      ),
    );

    expect(await cache.get('atomic-test', 'counter'), 20);
    await cache.dispose();
  });

  test('原子回调抛错时事务不写入替代值', () async {
    final CacheFacade cache = CacheFacade(
      store: PersistentCacheStore(executor: NativeDatabase.memory()),
    );
    await cache.set('atomic-test', 'value', 7);

    await expectLater(
      () => cache.updateAtomically(
        'atomic-test',
        'value',
        (_) => throw StateError('abort'),
      ),
      throwsStateError,
    );

    expect(await cache.get('atomic-test', 'value'), 7);
    await cache.dispose();
  });
}
