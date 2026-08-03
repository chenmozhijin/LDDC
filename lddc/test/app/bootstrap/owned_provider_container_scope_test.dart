import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/owned_provider_container_scope.dart';

void main() {
  testWidgets('替换和卸载根 Scope 时会依次释放其拥有的容器', (WidgetTester tester) async {
    int disposeCount = 0;
    final Provider<int> resourceProvider = Provider<int>((Ref ref) {
      ref.onDispose(() {
        disposeCount += 1;
      });
      return disposeCount;
    });
    final ProviderContainer first = ProviderContainer();
    final ProviderContainer second = ProviderContainer();
    first.read(resourceProvider);
    second.read(resourceProvider);

    await tester.pumpWidget(
      OwnedProviderContainerScope(
        container: first,
        child: const SizedBox(key: ValueKey<String>('owned-scope-child')),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('owned-scope-child')),
      findsOneWidget,
    );
    expect(disposeCount, 0);

    // 同一个 State 接管新容器时，旧容器已经不再被子树使用，应立即释放。
    await tester.pumpWidget(
      OwnedProviderContainerScope(
        container: second,
        child: const SizedBox(key: ValueKey<String>('owned-scope-child')),
      ),
    );
    expect(disposeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposeCount, 2);
  });
}
