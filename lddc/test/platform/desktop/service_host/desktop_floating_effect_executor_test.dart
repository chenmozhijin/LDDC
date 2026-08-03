import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../../support/desktop_service_host_exports.dart';
import '../../../support/desktop_service_test_support.dart';

void main() {
  group('DesktopFloatingEffectExecutor', () {
    test('会把实例状态同步为浮窗快照并显示窗口', () async {
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final DesktopFloatingEffectExecutor executor =
          DesktopFloatingEffectExecutor(
            windowBackend: _FakeWindowBackend(floatingHost),
          );

      await executor.syncState(
        DesktopSessionState.initial().copyWith(
          instanceId: 7,
          isPlaying: true,
          playbackSync: const DesktopPlaybackSyncState(
            pluginPlaybackTimeMs: 4200,
            pluginSendTimeMs: 123450,
            hostReceivedAtMs: 123456,
            isPlaying: true,
            syncRevision: 7,
            songToken: '1',
          ),
          config: DesktopSessionConfigState(
            defaultLangs: <String>['orig', 'ts'],
            playedColors: <RgbColor>[
              RgbColor(18, 52, 86),
              RgbColor(101, 67, 33),
            ],
            unplayedColors: <RgbColor>[
              RgbColor(204, 0, 0),
              RgbColor(255, 204, 0),
            ],
            fontFamily: 'Noto Sans CJK SC',
            fontSize: 34,
            showFurigana: false,
            refreshRate: 75,
            windowRect: WindowRect(left: 10, top: 20, width: 400, height: 120),
          ),
          lyricsRuntime: DesktopLyricsRuntimeState(
            song: SongInfo(
              source: Source.local,
              title: 'Song',
              artist: SongArtist(<String>['Artist']),
              album: 'Album',
              id: '1',
            ),
            lyrics: Lyrics(
              songInfo: SongInfo(
                source: Source.ne,
                title: 'Song',
                artist: SongArtist(<String>['Artist']),
                album: 'Album',
                id: '1',
              ),
              source: Source.ne,
              types: const <String, LyricsType>{'orig': LyricsType.verbatim},
            ),
          ),
        ),
      );

      await waitForCondition(() => floatingHost.showCalls.isNotEmpty);
      expect(floatingHost.showCalls, <int>[7]);
      expect(floatingHost.hideCalls, isEmpty);
      expect(floatingHost.snapshots.single.instanceId, 7);
      expect(floatingHost.snapshots.single.snapshot.flags.visible, isTrue);
      expect(floatingHost.snapshots.single.snapshot.session.songTitle, 'Song');
      expect(floatingHost.snapshots.single.snapshot.session.refreshRate, 75);
      expect(
        floatingHost.snapshots.single.snapshot.session.playedColors.map(
          (RgbColor color) => color.toTuple(),
        ),
        <List<int>>[
          <int>[18, 52, 86],
          <int>[101, 67, 33],
        ],
      );
      expect(
        floatingHost.snapshots.single.snapshot.session.fontFamily,
        'Noto Sans CJK SC',
      );
      expect(floatingHost.snapshots.single.snapshot.session.fontSize, 34);
      expect(
        floatingHost.snapshots.single.snapshot.session.showFurigana,
        isFalse,
      );
      expect(
        floatingHost.snapshots.single.snapshot.initialWindowRect?.width,
        400,
      );
      expect(
        floatingHost.snapshots.single.snapshot.anchor?.hostReceivedAtMs,
        123456,
      );
      expect(
        floatingHost.snapshots.single.snapshot.anchor?.pluginPlaybackTimeMs,
        4200,
      );
      expect(floatingHost.snapshots.single.snapshot.anchor?.syncRevision, 7);
      expect(
        floatingHost.snapshots.single.snapshot.session.infoBadge.source,
        Source.ne,
      );
      expect(
        floatingHost.snapshots.single.snapshot.session.infoBadge.lyricsType,
        LyricsType.verbatim,
      );
    });

    test('空实例状态会隐藏浮窗', () async {
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final DesktopFloatingEffectExecutor executor =
          DesktopFloatingEffectExecutor(
            windowBackend: _FakeWindowBackend(floatingHost),
          );

      await executor.syncState(
        DesktopSessionState.initial().copyWith(instanceId: 3),
      );

      await waitForCondition(() => floatingHost.hideCalls.isNotEmpty);
      expect(floatingHost.showCalls, isEmpty);
      expect(floatingHost.hideCalls, <int>[3]);
      expect(floatingHost.snapshots.single.snapshot.flags.visible, isFalse);
    });

    test('布局应用会等待 host 自身生命周期且不会被外层提前销毁', () async {
      final _DelayedApplyFloatingHost floatingHost =
          _DelayedApplyFloatingHost();
      final DesktopFloatingEffectExecutor executor =
          DesktopFloatingEffectExecutor(
            windowBackend: _FakeWindowBackend(floatingHost),
          );

      final Stopwatch stopwatch = Stopwatch()..start();
      await executor.syncState(
        DesktopSessionState.initial().copyWith(
          instanceId: 9,
          lyricsRuntime: DesktopLyricsRuntimeState(
            staticDisplayLines: <String>['first'],
          ),
        ),
      );
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
      await waitForCondition(() => floatingHost.applyCalls == 1);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(floatingHost.destroyCalls, isEmpty);
      floatingHost.completeApply();
      await waitForCondition(() => floatingHost.showCalls.contains(9));
    });

    test('明确应用失败后只销毁重建并重放一次', () async {
      final _FailOnceFloatingHost floatingHost = _FailOnceFloatingHost();
      final DesktopFloatingEffectExecutor executor =
          DesktopFloatingEffectExecutor(
            windowBackend: _FakeWindowBackend(floatingHost),
          );

      await executor.syncState(
        DesktopSessionState.initial().copyWith(
          instanceId: 10,
          lyricsRuntime: DesktopLyricsRuntimeState(
            staticDisplayLines: <String>['welcome'],
          ),
        ),
      );

      await waitForCondition(() => floatingHost.applyCalls == 2);
      expect(floatingHost.destroyCalls, <int>[10]);
      expect(floatingHost.showCalls, <int>[10]);
    });

    test('连续明确失败只尝试两次 apply 且只重建一次', () async {
      final _FailAlwaysFloatingHost floatingHost = _FailAlwaysFloatingHost();
      final DesktopFloatingEffectExecutor executor =
          DesktopFloatingEffectExecutor(
            windowBackend: _FakeWindowBackend(floatingHost),
          );

      await executor.syncState(
        DesktopSessionState.initial().copyWith(
          instanceId: 11,
          lyricsRuntime: DesktopLyricsRuntimeState(
            staticDisplayLines: <String>['welcome'],
          ),
        ),
      );

      await waitForCondition(() => floatingHost.applyCalls == 2);
      expect(floatingHost.destroyCalls, <int>[11]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(floatingHost.applyCalls, 2);
    });

    test('destroyInstance 会等待浮窗真正销毁后再返回', () async {
      final _DelayedDestroyFloatingHost floatingHost =
          _DelayedDestroyFloatingHost();
      final DesktopFloatingEffectExecutor executor =
          DesktopFloatingEffectExecutor(
            windowBackend: _FakeWindowBackend(floatingHost),
          );

      await executor.syncState(
        DesktopSessionState.initial().copyWith(
          instanceId: 12,
          lyricsRuntime: DesktopLyricsRuntimeState(
            staticDisplayLines: <String>['alive'],
          ),
        ),
      );
      await waitForCondition(() => floatingHost.showCalls.contains(12));

      bool destroyFinished = false;
      final Future<void> destroyFuture = executor.destroyInstance(12).then((_) {
        destroyFinished = true;
      });

      await waitForCondition(() => floatingHost.destroyCalls.contains(12));
      expect(destroyFinished, isFalse);

      floatingHost.completeDestroy(instanceId: 12);
      await destroyFuture;
      expect(destroyFinished, isTrue);
    });
  });
}

class _FakeWindowBackend implements DesktopWindowBackend {
  _FakeWindowBackend(this.floatingHost);

  @override
  final _FakeFloatingHost floatingHost;

  @override
  final DesktopSelectorWindowHostPort selectorHost =
      const DesktopNoopSelectorWindowHost();

  @override
  final DesktopPanelWindowHostPort panelHost =
      const DesktopNoopPanelWindowHost();
}

class _FakeFloatingHost implements DesktopFloatingWindowHostPort {
  final List<int> showCalls = <int>[];
  final List<int> hideCalls = <int>[];
  final List<int> destroyCalls = <int>[];
  final List<({int instanceId, DesktopFloatingWindowSnapshot snapshot})>
  snapshots = <({int instanceId, DesktopFloatingWindowSnapshot snapshot})>[];

  @override
  void setIntentHandler(DesktopFloatingWindowIntentHandler? handler) {}

  @override
  Future<void> destroyFloatingWindow({required int instanceId}) async {
    destroyCalls.add(instanceId);
  }

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    snapshots.add((instanceId: instanceId, snapshot: snapshot));
    if (snapshot.flags.visible) {
      showCalls.add(instanceId);
    } else {
      hideCalls.add(instanceId);
    }
  }

  @override
  Future<bool> flushFloatingGeometry({required int instanceId}) async => true;
}

class _DelayedApplyFloatingHost extends _FakeFloatingHost {
  final Completer<void> _applyCompleter = Completer<void>();
  int applyCalls = 0;

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    applyCalls += 1;
    await _applyCompleter.future;
    await super.applyFloatingSnapshot(
      instanceId: instanceId,
      snapshot: snapshot,
    );
  }

  void completeApply() => _applyCompleter.complete();
}

class _FailOnceFloatingHost extends _FakeFloatingHost {
  int applyCalls = 0;

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    applyCalls += 1;
    if (applyCalls == 1) {
      throw StateError('channel unavailable');
    }
    await super.applyFloatingSnapshot(
      instanceId: instanceId,
      snapshot: snapshot,
    );
  }
}

class _FailAlwaysFloatingHost extends _FakeFloatingHost {
  int applyCalls = 0;

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    applyCalls += 1;
    throw StateError('channel unavailable');
  }
}

class _DelayedDestroyFloatingHost extends _FakeFloatingHost {
  final Map<int, Completer<void>> _destroyCompleters = <int, Completer<void>>{};

  @override
  Future<void> destroyFloatingWindow({required int instanceId}) {
    destroyCalls.add(instanceId);
    return (_destroyCompleters[instanceId] ??= Completer<void>()).future;
  }

  void completeDestroy({required int instanceId}) {
    final Completer<void> completer = _destroyCompleters[instanceId] ??=
        Completer<void>();
    if (!completer.isCompleted) {
      completer.complete();
    }
  }
}
