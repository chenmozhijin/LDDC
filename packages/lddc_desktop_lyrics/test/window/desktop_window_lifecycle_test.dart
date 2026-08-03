import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  final DesktopWindowLifecycleRegistryController registry =
      DesktopWindowLifecycleRegistryController.instance;

  setUp(registry.debugResetForTests);
  tearDown(registry.debugResetForTests);

  group('DesktopWindowLifecycleRegistryController', () {
    test('同一逻辑窗口会递增 generation，旧窗口关闭不会污染新窗口状态', () async {
      final DesktopWindowRef first = registry.registerWindow(
        role: DesktopWindowRole.selector,
        instanceId: 7,
        observedState: DesktopWindowObservedState.creating,
        desiredState: DesktopWindowDesiredState.hidden,
      );
      final DesktopWindowRef second = registry.registerWindow(
        role: DesktopWindowRole.selector,
        instanceId: 7,
        observedState: DesktopWindowObservedState.creating,
        desiredState: DesktopWindowDesiredState.hidden,
      );

      expect(first.generation, 1);
      expect(second.generation, 2);
      expect(
        registry.currentRef(role: DesktopWindowRole.selector, instanceId: 7),
        second,
      );

      registry.markClosed(first, reason: 'stale-close');

      expect(registry.snapshotForRef(first), isNull);
      expect(
        registry.currentRef(role: DesktopWindowRole.selector, instanceId: 7),
        second,
      );
      expect(
        registry.snapshotForRef(second)?.observedState,
        DesktopWindowObservedState.creating,
      );
    });

    test('awaitObservedClose 只会在当前 generation 关闭后完成', () async {
      final DesktopWindowRef ref = registry.registerWindow(
        role: DesktopWindowRole.floating,
        instanceId: 11,
        observedState: DesktopWindowObservedState.visible,
        desiredState: DesktopWindowDesiredState.visible,
      );

      bool completed = false;
      final Future<bool> waitFuture = registry
          .awaitObservedClose(ref, timeout: const Duration(milliseconds: 100))
          .then((bool value) {
            completed = true;
            return value;
          });

      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      registry.markClosed(ref, reason: 'closed');

      expect(await waitFuture, isTrue);
      expect(completed, isTrue);
      expect(registry.snapshotForRef(ref), isNull);
    });

    test('终态 generation 不会在 registry 中持续累积', () {
      for (int index = 0; index < 100; index += 1) {
        final DesktopWindowRef ref = registry.registerWindow(
          role: DesktopWindowRole.panel,
          instanceId: 21,
          panelId: 3,
        );
        registry.markClosed(ref, reason: 'stress-close');
        expect(registry.snapshotForRef(ref), isNull);
      }

      final DesktopWindowRef next = registry.registerWindow(
        role: DesktopWindowRole.panel,
        instanceId: 21,
        panelId: 3,
      );
      expect(next.generation, 101);
      expect(
        registry.currentRef(
          role: DesktopWindowRole.panel,
          instanceId: 21,
          panelId: 3,
        ),
        next,
      );
    });

    test('dispose 会完成等待者、关闭事件流并拒绝继续写入', () async {
      final DesktopWindowLifecycleRegistryController localRegistry =
          DesktopWindowLifecycleRegistryController();
      final Future<void> eventsDone = localRegistry.events.drain<void>();
      final DesktopWindowRef ref = localRegistry.registerWindow(
        role: DesktopWindowRole.floating,
        instanceId: 31,
        observedState: DesktopWindowObservedState.visible,
        desiredState: DesktopWindowDesiredState.visible,
      );
      final Future<bool> closeWaiter = localRegistry.awaitObservedClose(
        ref,
        timeout: const Duration(seconds: 1),
      );

      await localRegistry.dispose();

      expect(await closeWaiter, isTrue);
      await eventsDone;
      await localRegistry.dispose();
      expect(
        () => localRegistry.registerWindow(role: DesktopWindowRole.selector),
        throwsStateError,
      );
    });
  });
}
