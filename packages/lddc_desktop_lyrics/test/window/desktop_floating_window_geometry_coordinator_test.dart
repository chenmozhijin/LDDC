import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  test('用户 resize 期间立即接受最新布局且不反向修改窗口尺寸', () async {
    final List<Rect> appliedBounds = <Rect>[];
    final DesktopFloatingWindowGeometryCoordinator coordinator =
        DesktopFloatingWindowGeometryCoordinator(
          isMounted: () => true,
          setBounds: (Rect bounds) async => appliedBounds.add(bounds),
          awaitViewportStableBounds: () async =>
              const Rect.fromLTWH(0, 0, 800, 240),
          awaitNextFrame: () async {},
          reapplyFlags: ({bool force = false}) async {},
          scheduleRefreshRateResolve: ({bool immediate = false}) {},
          commitMetrics: (double fontSize) async => true,
          resolveSessionFontSize: () => 30,
        );
    addTearDown(coordinator.dispose);
    coordinator.beginContentRevision(1);
    coordinator.onWindowResize();

    final bool accepted = await coordinator.handleFrameCandidate(
      const DesktopFloatingFrameMetrics(
        contentRevision: 1,
        layoutRevision: 2,
        resolvedFontSize: 42,
        preferredHeight: 220,
      ),
    );

    expect(accepted, isTrue);
    expect(appliedBounds, isEmpty);
    expect(coordinator.state.lastResolvedFontSize, 42);
  });

  test('自动窗口高度等于歌词精确高度加控制栏真实高度', () async {
    Rect currentBounds = const Rect.fromLTWH(10, 20, 800, 120);
    final List<Rect> appliedBounds = <Rect>[];
    final DesktopFloatingWindowGeometryCoordinator coordinator =
        DesktopFloatingWindowGeometryCoordinator(
          isMounted: () => true,
          setBounds: (Rect bounds) async {
            currentBounds = bounds;
            appliedBounds.add(bounds);
          },
          awaitViewportStableBounds: () async => currentBounds,
          awaitNextFrame: () async {},
          reapplyFlags: ({bool force = false}) async {},
          scheduleRefreshRateResolve: ({bool immediate = false}) {},
          commitMetrics: (double fontSize) async => true,
          resolveSessionFontSize: () => 30,
        );
    addTearDown(coordinator.dispose);
    coordinator.beginContentRevision(1);
    coordinator.updateControlChromeHeight(68);

    final bool accepted = await coordinator.handleFrameCandidate(
      const DesktopFloatingFrameMetrics(
        contentRevision: 1,
        layoutRevision: 1,
        resolvedFontSize: 30,
        preferredHeight: 140,
      ),
    );

    expect(accepted, isTrue);
    expect(appliedBounds, hasLength(1));
    expect(appliedBounds.single.height, 208);
  });

  test('自动高度执行前读取实时位置且只替换高度', () async {
    Rect currentBounds = const Rect.fromLTWH(40, 60, 800, 120);
    final List<Rect> appliedBounds = <Rect>[];
    int boundsReads = 0;
    final DesktopFloatingWindowGeometryCoordinator coordinator =
        DesktopFloatingWindowGeometryCoordinator(
          isMounted: () => true,
          setBounds: (Rect bounds) async {
            currentBounds = bounds;
            appliedBounds.add(bounds);
          },
          awaitViewportStableBounds: () async {
            boundsReads += 1;
            if (boundsReads == 2) {
              currentBounds = const Rect.fromLTWH(420, 260, 800, 120);
            }
            return currentBounds;
          },
          awaitNextFrame: () async {},
          reapplyFlags: ({bool force = false}) async {},
          scheduleRefreshRateResolve: ({bool immediate = false}) {},
          commitMetrics: (double fontSize) async => true,
          resolveSessionFontSize: () => 30,
        );
    addTearDown(coordinator.dispose);
    coordinator.beginContentRevision(1);

    final bool accepted = await coordinator.handleFrameCandidate(
      const DesktopFloatingFrameMetrics(
        contentRevision: 1,
        layoutRevision: 1,
        resolvedFontSize: 30,
        preferredHeight: 220,
      ),
    );

    expect(accepted, isTrue);
    expect(appliedBounds.single.left, 420);
    expect(appliedBounds.single.top, 260);
    expect(appliedBounds.single.width, 800);
    expect(appliedBounds.single.height, 220);
  });

  test('自动高度不写配置，用户移动和 flush 共用确认提交链', () async {
    Rect currentBounds = const Rect.fromLTWH(10, 20, 800, 120);
    int commits = 0;
    final DesktopFloatingWindowGeometryCoordinator coordinator =
        DesktopFloatingWindowGeometryCoordinator(
          isMounted: () => true,
          setBounds: (Rect bounds) async => currentBounds = bounds,
          awaitViewportStableBounds: () async => currentBounds,
          awaitNextFrame: () async {},
          reapplyFlags: ({bool force = false}) async {},
          scheduleRefreshRateResolve: ({bool immediate = false}) {},
          commitMetrics: (double fontSize) async {
            commits += 1;
            return true;
          },
          resolveSessionFontSize: () => 30,
        );
    addTearDown(coordinator.dispose);
    coordinator.beginContentRevision(1);
    const DesktopFloatingFrameMetrics metrics = DesktopFloatingFrameMetrics(
      contentRevision: 1,
      layoutRevision: 1,
      resolvedFontSize: 30,
      preferredHeight: 220,
    );

    expect(await coordinator.handleFrameCandidate(metrics), isTrue);
    await coordinator.handleFrameCommitted(metrics);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(commits, 0);

    coordinator.onWindowMove();
    expect(await coordinator.flushGeometry(), isTrue);
    expect(commits, 1);
  });

  test('只有 onWindowMove 事件也会通过唯一 debounce 持久化位置', () async {
    int commits = 0;
    final DesktopFloatingWindowGeometryCoordinator coordinator =
        DesktopFloatingWindowGeometryCoordinator(
          isMounted: () => true,
          setBounds: (Rect bounds) async {},
          awaitViewportStableBounds: () async =>
              const Rect.fromLTWH(320, 180, 800, 160),
          awaitNextFrame: () async {},
          reapplyFlags: ({bool force = false}) async {},
          scheduleRefreshRateResolve: ({bool immediate = false}) {},
          commitMetrics: (double fontSize) async {
            commits += 1;
            return true;
          },
          resolveSessionFontSize: () => 30,
        );
    addTearDown(coordinator.dispose);

    coordinator.onWindowMove();
    await Future<void>.delayed(const Duration(milliseconds: 180));

    expect(commits, 1);
  });
}
