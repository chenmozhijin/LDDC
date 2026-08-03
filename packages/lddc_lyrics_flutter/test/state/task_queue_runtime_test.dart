import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  test('replaceAll 遇到重复 id 直接失败，避免队列快照被静默污染', () {
    final TaskQueueRuntime<_Item> runtime = TaskQueueRuntime<_Item>(
      idOf: (_Item item) => item.id,
    );
    addTearDown(runtime.dispose);

    expect(
      () => runtime.replaceAll(const <_Item>[_Item('a'), _Item('a')]),
      throwsArgumentError,
    );
  });

  test('replaceAll 后置重复 id 失败时不会部分修改既有 entry', () {
    final TaskQueueRuntime<_Item> runtime = TaskQueueRuntime<_Item>(
      idOf: (_Item item) => item.id,
    );
    addTearDown(runtime.dispose);
    runtime.replaceAll(const <_Item>[_Item('a', value: 1)]);
    final TaskQueueBinding<_Item> binding = runtime.binding('a')!;
    final int revision = runtime.revisionListenable.value;

    expect(
      () => runtime.replaceAll(const <_Item>[
        _Item('a', value: 2),
        _Item('a', value: 3),
      ]),
      throwsArgumentError,
    );

    expect(binding.itemListenable.value.value, 1);
    expect(runtime.snapshot.single.value, 1);
    expect(runtime.revisionListenable.value, revision);
  });

  test('binding 对同一 entry 保持稳定且仅内容变化不通知顺序监听器', () {
    final TaskQueueRuntime<_Item> runtime = TaskQueueRuntime<_Item>(
      idOf: (_Item item) => item.id,
    );
    addTearDown(runtime.dispose);
    runtime.replaceAll(const <_Item>[_Item('a', value: 1)]);
    final TaskQueueBinding<_Item> binding = runtime.binding('a')!;
    int orderNotifications = 0;
    runtime.orderListenable.addListener(() {
      orderNotifications += 1;
    });

    runtime.replaceAll(const <_Item>[_Item('a', value: 2)]);

    expect(runtime.binding('a'), same(binding));
    expect(binding.itemListenable.value.value, 2);
    expect(orderNotifications, 0);
  });

  test('replaceAll 移除条目时释放该行的全部 notifier', () {
    final TaskQueueRuntime<_Item> runtime = TaskQueueRuntime<_Item>(
      idOf: (_Item item) => item.id,
    );
    addTearDown(runtime.dispose);
    runtime.replaceAll(const <_Item>[_Item('a')]);
    final TaskQueueBinding<_Item> binding = runtime.binding('a')!;

    runtime.replaceAll(const <_Item>[]);

    expect(() => binding.itemListenable.addListener(() {}), throwsFlutterError);
    expect(
      () => binding.selectedListenable.addListener(() {}),
      throwsFlutterError,
    );
    expect(
      () => binding.focusedListenable.addListener(() {}),
      throwsFlutterError,
    );
  });

  test('replaceAll 会清理不存在条目的选择和焦点', () {
    final TaskQueueRuntime<_Item> runtime = TaskQueueRuntime<_Item>(
      idOf: (_Item item) => item.id,
    );
    addTearDown(runtime.dispose);

    runtime.replaceAll(const <_Item>[_Item('a'), _Item('b')]);
    runtime.setSelectedIds(<String>{'a', 'b'});
    runtime.setFocusedId('b');
    runtime.replaceAll(const <_Item>[_Item('a')]);

    expect(runtime.order, <String>['a']);
    expect(runtime.binding('a')!.selectedListenable.value, isTrue);
    expect(runtime.binding('a')!.focusedListenable.value, isFalse);
  });
}

class _Item {
  const _Item(this.id, {this.value = 0});

  final String id;
  final int value;
}
