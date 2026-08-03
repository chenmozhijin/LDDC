import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/resource/async_disposal_tracker.dart';

void main() {
  setUp(AsyncDisposalTracker.debugResetForTests);
  tearDown(AsyncDisposalTracker.debugResetForTests);

  test('drain 会等待关闭期间登记的后续任务', () async {
    final Completer<void> first = Completer<void>();
    final Completer<void> second = Completer<void>();
    AsyncDisposalTracker.track(first.future, owner: 'first');

    final Future<bool> drain = AsyncDisposalTracker.drain();
    first.complete();
    AsyncDisposalTracker.track(second.future, owner: 'second');
    await Future<void>.delayed(Duration.zero);

    expect(AsyncDisposalTracker.pendingCount, 1);
    second.complete();
    await expectLater(drain, completion(isTrue));
    expect(AsyncDisposalTracker.pendingCount, 0);
  });

  test('失败的关闭任务会被消费且不会阻塞其他资源', () async {
    AsyncDisposalTracker.track(
      Future<void>.error(StateError('close failed')),
      owner: 'failed',
    );
    AsyncDisposalTracker.track(Future<void>.value(), owner: 'completed');

    await expectLater(AsyncDisposalTracker.drain(), completion(isTrue));
    expect(AsyncDisposalTracker.pendingCount, 0);
  });

  test('超时会返回 false 并保留仍在执行的任务', () async {
    final Completer<void> pending = Completer<void>();
    AsyncDisposalTracker.track(pending.future, owner: 'pending');

    await expectLater(
      AsyncDisposalTracker.drain(timeout: const Duration(milliseconds: 1)),
      completion(isFalse),
    );
    expect(AsyncDisposalTracker.pendingCount, 1);

    pending.complete();
    await expectLater(AsyncDisposalTracker.drain(), completion(isTrue));
  });
}
