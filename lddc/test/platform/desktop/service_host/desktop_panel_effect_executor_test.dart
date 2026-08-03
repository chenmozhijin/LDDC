import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import '../../../support/desktop_service_host_exports.dart';
import '../../../support/desktop_service_test_support.dart';

void main() {
  group('DesktopPanelEffectExecutor', () {
    test('只会下发 panel 内容快照同步', () async {
      final _FakePanelHost panelHost = _FakePanelHost();
      final DesktopPanelEffectExecutor executor = DesktopPanelEffectExecutor(
        windowBackend: _FakeWindowBackend(panelHost),
      );
      final DesktopPanelWindowSnapshot snapshot = DesktopPanelWindowSnapshot(
        session: DesktopPanelSessionSnapshot(),
        anchor: DesktopPanelAnchorSnapshot(syncRevision: 1),
        sceneRef: DesktopSceneRef(
          sceneId: '1:1',
          sceneRevision: 1,
          checksum: 'aaaa',
        ),
      );

      await executor.executeAll(<DesktopSessionEffect>[
        DesktopSyncPanelsEffect(
          instanceId: 1,
          panelIds: const <int>[7, 8],
          snapshot: snapshot,
        ),
        const DesktopClearTaskEffect(taskKey: 'auto_fetch'),
      ]);

      await waitForCondition(() => panelHost.calls.length >= 2);
      expect(panelHost.calls, <String>['sync:1:7:true', 'sync:1:8:true']);
    });

    test('同一 panel 的快照会 latest-wins', () async {
      final _BlockingSyncPanelHost panelHost = _BlockingSyncPanelHost();
      final DesktopPanelEffectExecutor executor = DesktopPanelEffectExecutor(
        windowBackend: _FakeWindowBackend(panelHost),
      );
      final DesktopPanelWindowSnapshot snapshotA = DesktopPanelWindowSnapshot(
        session: DesktopPanelSessionSnapshot(),
        anchor: DesktopPanelAnchorSnapshot(syncRevision: 1),
        sceneRef: DesktopSceneRef(
          sceneId: '2:1',
          sceneRevision: 1,
          checksum: 'bbbb',
        ),
      );
      final DesktopPanelWindowSnapshot snapshotB = DesktopPanelWindowSnapshot(
        session: DesktopPanelSessionSnapshot(),
        anchor: DesktopPanelAnchorSnapshot(syncRevision: 2),
        sceneRef: DesktopSceneRef(
          sceneId: '2:2',
          sceneRevision: 2,
          checksum: 'cccc',
        ),
      );

      await executor.execute(
        DesktopSyncPanelsEffect(
          instanceId: 2,
          panelIds: const <int>[3],
          snapshot: snapshotA,
        ),
      );
      await executor.execute(
        DesktopSyncPanelsEffect(
          instanceId: 2,
          panelIds: const <int>[3],
          snapshot: snapshotB,
        ),
      );

      panelHost.completeFirstSync();
      await waitForCondition(() => panelHost.calls.length >= 2);

      expect(panelHost.calls, <String>['sync:2:3:1', 'sync:2:3:2']);
    });

    test('明确失败不会自动重放，下一份新快照仍可继续同步', () async {
      final _FailFirstSyncPanelHost panelHost = _FailFirstSyncPanelHost();
      final DesktopPanelEffectExecutor executor = DesktopPanelEffectExecutor(
        windowBackend: _FakeWindowBackend(panelHost),
      );
      final DesktopPanelWindowSnapshot snapshotA = DesktopPanelWindowSnapshot(
        session: DesktopPanelSessionSnapshot(),
        anchor: DesktopPanelAnchorSnapshot(syncRevision: 5),
        sceneRef: DesktopSceneRef(
          sceneId: '3:5',
          sceneRevision: 5,
          checksum: 'dddd',
        ),
      );
      final DesktopPanelWindowSnapshot snapshotB = DesktopPanelWindowSnapshot(
        session: DesktopPanelSessionSnapshot(),
        anchor: DesktopPanelAnchorSnapshot(syncRevision: 6),
        sceneRef: DesktopSceneRef(
          sceneId: '3:6',
          sceneRevision: 6,
          checksum: 'eeee',
        ),
      );

      await executor.execute(
        DesktopSyncPanelsEffect(
          instanceId: 3,
          panelIds: const <int>[9],
          snapshot: snapshotA,
        ),
      );

      await waitForCondition(() => panelHost.calls.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(panelHost.calls, <String>['sync:3:9:5']);

      await executor.execute(
        DesktopSyncPanelsEffect(
          instanceId: 3,
          panelIds: const <int>[9],
          snapshot: snapshotB,
        ),
      );
      await waitForCondition(() => panelHost.calls.length >= 2);
      expect(panelHost.calls, <String>['sync:3:9:5', 'sync:3:9:6']);
    });
  });
}

class _FakeWindowBackend implements DesktopWindowBackend {
  _FakeWindowBackend(this.panelHost);

  @override
  final DesktopFloatingWindowHostPort floatingHost =
      const DesktopNoopFloatingWindowHost();

  @override
  final DesktopSelectorWindowHostPort selectorHost =
      const DesktopNoopSelectorWindowHost();

  @override
  final _BasePanelHost panelHost;
}

abstract class _BasePanelHost implements DesktopPanelWindowHostPort {
  final List<String> calls = <String>[];

  @override
  void setIntentHandler(DesktopPanelWindowIntentHandler? handler) {}

  @override
  Future<void> createPanel({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    DesktopPanelWindowSnapshot? initialSnapshot,
    PanelSurfaceUpdate? initialSurface,
  }) async {}

  @override
  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {}

  @override
  Future<void> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {}
}

class _FakePanelHost extends _BasePanelHost {
  @override
  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  }) async {
    calls.add(
      'sync:$instanceId:${panelIds.single}:${snapshot.sceneRef != null}',
    );
  }
}

class _BlockingSyncPanelHost extends _BasePanelHost {
  final Completer<void> _firstSyncCompleter = Completer<void>();
  bool _firstSyncSeen = false;

  void completeFirstSync() {
    if (_firstSyncCompleter.isCompleted) {
      return;
    }
    _firstSyncCompleter.complete();
  }

  @override
  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  }) async {
    calls.add(
      'sync:$instanceId:${panelIds.single}:${snapshot.anchor.syncRevision}',
    );
    if (_firstSyncSeen) {
      return;
    }
    _firstSyncSeen = true;
    await _firstSyncCompleter.future;
  }
}

class _FailFirstSyncPanelHost extends _BasePanelHost {
  bool _firstSyncSeen = false;

  @override
  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  }) async {
    calls.add(
      'sync:$instanceId:${panelIds.single}:${snapshot.anchor.syncRevision}',
    );
    if (!_firstSyncSeen) {
      _firstSyncSeen = true;
      throw StateError('panel channel unavailable');
    }
  }
}
