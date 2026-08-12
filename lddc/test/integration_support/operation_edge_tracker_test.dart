import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/operation_edge_tracker.dart';

void main() {
  test('初始未活动状态不能被误判为操作完成', () {
    final OperationEdgeTracker tracker = OperationEdgeTracker();

    tracker.observe(wasActive: false, isActive: false);

    expect(tracker.started, isFalse);
    expect(tracker.completed, isFalse);
  });

  test('只有同一次操作的进入和退出边沿都出现后才算完成', () {
    final OperationEdgeTracker tracker = OperationEdgeTracker();

    tracker
      ..observe(wasActive: false, isActive: true)
      ..observe(wasActive: true, isActive: true);

    expect(tracker.started, isTrue);
    expect(tracker.completed, isFalse);

    tracker.observe(wasActive: true, isActive: false);

    expect(tracker.completed, isTrue);
  });

  test('没有观察到进入边沿时，单独的退出状态不能完成操作', () {
    final OperationEdgeTracker tracker = OperationEdgeTracker();

    tracker.observe(wasActive: true, isActive: false);

    expect(tracker.started, isFalse);
    expect(tracker.completed, isFalse);
  });

  test('操作完成后重复的稳定状态不会改变已经收敛的结果', () {
    final OperationEdgeTracker tracker = OperationEdgeTracker();

    tracker
      ..observe(wasActive: false, isActive: true)
      ..observe(wasActive: true, isActive: false)
      ..observe(wasActive: false, isActive: false);

    expect(tracker.started, isTrue);
    expect(tracker.completed, isTrue);
  });
}
