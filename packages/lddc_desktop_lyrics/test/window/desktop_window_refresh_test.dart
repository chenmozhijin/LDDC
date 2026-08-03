import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  group('resolveDesktopWindowRefreshState', () {
    test('显式配置优先于显示器刷新率', () {
      final DesktopWindowRefreshState state = resolveDesktopWindowRefreshState(
        configuredRefreshRate: 75,
        displaySnapshot: const DesktopWindowDisplaySnapshot(
          displayId: 3,
          refreshRate: 144,
        ),
      );

      expect(state.effectiveRefreshRate, 75);
      expect(state.source, DesktopWindowRefreshSource.configured);
      expect(state.displayId, 3);
    });

    test('自动模式跟随当前显示器刷新率', () {
      final DesktopWindowRefreshState state = resolveDesktopWindowRefreshState(
        configuredRefreshRate: -1,
        displaySnapshot: const DesktopWindowDisplaySnapshot(
          displayId: 7,
          refreshRate: 59.94,
        ),
      );

      expect(state.effectiveRefreshRate, 60);
      expect(state.source, DesktopWindowRefreshSource.display);
      expect(state.displayId, 7);
    });

    test('显示器信息不可用时回退 60Hz', () {
      final DesktopWindowRefreshState state = resolveDesktopWindowRefreshState(
        configuredRefreshRate: -1,
        displaySnapshot: null,
      );

      expect(state.effectiveRefreshRate, kDesktopFallbackRefreshRate);
      expect(state.source, DesktopWindowRefreshSource.fallback);
    });

    test('非法配置值不会误判为自动模式', () {
      final DesktopWindowRefreshState state = resolveDesktopWindowRefreshState(
        configuredRefreshRate: 0,
        displaySnapshot: const DesktopWindowDisplaySnapshot(
          displayId: 1,
          refreshRate: 144,
        ),
      );

      expect(state.effectiveRefreshRate, kDesktopFallbackRefreshRate);
      expect(state.source, DesktopWindowRefreshSource.fallback);
    });
  });

  group('DesktopWindowRefreshController', () {
    test('非 immediate 配置更新不会同步读取显示器快照', () {
      int providerCallCount = 0;
      final DesktopWindowRefreshController controller =
          DesktopWindowRefreshController(() {
            providerCallCount += 1;
            return const DesktopWindowDisplaySnapshot(
              displayId: 2,
              refreshRate: 144,
            );
          });
      addTearDown(controller.dispose);

      controller.updateConfiguredRefreshRate(-1, immediate: false);

      expect(providerCallCount, 0);
      expect(controller.state, const DesktopWindowRefreshState.fallback());
    });

    test('显式配置更新时会立即切到用户设置', () {
      final DesktopWindowRefreshController controller =
          DesktopWindowRefreshController(
            () => const DesktopWindowDisplaySnapshot(
              displayId: 2,
              refreshRate: 144,
            ),
          );
      addTearDown(controller.dispose);

      controller.updateConfiguredRefreshRate(90, immediate: true);

      expect(controller.state.effectiveRefreshRate, 90);
      expect(controller.state.source, DesktopWindowRefreshSource.configured);
    });

    testWidgets('自动模式重算会做去抖合并', (WidgetTester tester) async {
      DesktopWindowDisplaySnapshot display = const DesktopWindowDisplaySnapshot(
        displayId: 1,
        refreshRate: 120,
      );
      final DesktopWindowRefreshController controller =
          DesktopWindowRefreshController(() => display);
      addTearDown(controller.dispose);

      int notifyCount = 0;
      controller.addListener(() {
        notifyCount += 1;
      });

      controller.updateConfiguredRefreshRate(-1, immediate: true);
      expect(controller.state.effectiveRefreshRate, 120);
      expect(notifyCount, 1);

      display = const DesktopWindowDisplaySnapshot(
        displayId: 5,
        refreshRate: 144,
      );
      controller.scheduleResolve();
      controller.scheduleResolve();
      await tester.pump(const Duration(milliseconds: 119));

      expect(controller.state.effectiveRefreshRate, 120);
      expect(notifyCount, 1);

      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.state.effectiveRefreshRate, 144);
      expect(controller.state.displayId, 5);
      expect(notifyCount, 2);
    });
  });

  group('DesktopPlaybackTickerCoordinator', () {
    testWidgets('非法刷新率会回退而不是除零', (WidgetTester tester) async {
      int tickCount = 0;
      final DesktopPlaybackTickerCoordinator coordinator =
          DesktopPlaybackTickerCoordinator(
            vsync: tester,
            shouldTick: () => true,
            tickPlaybackTime: () => ++tickCount,
            resolveRefreshRate: () => 0,
          );

      coordinator.syncTicker();
      await tester.pump(const Duration(milliseconds: 17));
      coordinator.dispose();

      expect(tester.takeException(), isNull);
      expect(tickCount, greaterThanOrEqualTo(1));
    });
  });
}
