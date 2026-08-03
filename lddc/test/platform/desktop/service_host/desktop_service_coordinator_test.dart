import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_exit_guard.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_main_window_navigation.dart';
import '../../../support/desktop_service_host_exports.dart';
import '../../../support/desktop_service_test_support.dart';

void main() {
  group('DesktopServiceCoordinator', () {
    test('会消费 selector lyrics_selected 并回写 session 与待处理 effect', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: panelHost,
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);

      coordinator.upsertSession(_session(instanceId: 1));
      final Future<DesktopPendingEffectBatch> pendingFuture =
          coordinator.pendingEffects.first;

      final DesktopCoordinatorApplyResult? applyResult = await coordinator
          .handleSelectorIntent(
            DesktopSelectorLyricsSelectedIntent(
              instanceId: 1,
              lyrics: _lyrics(source: Source.local),
              path: r'D:\lyrics\song.lrc',
              langs: const <String>['orig'],
              offsetMs: 200,
            ),
          );

      expect(applyResult, isNotNull);
      expect(
        coordinator.sessionFor(1)?.lyricsRuntime.lyrics?.source,
        Source.local,
      );
      expect(
        coordinator.sessionFor(1)?.lyricsRuntime.lyricsPath,
        r'D:\lyrics\song.lrc',
      );
      await waitForCondition(
        () => selectorHost.calls.contains('refresh:1:Artist - Song'),
      );
      expect(selectorHost.calls, contains('refresh:1:Artist - Song'));
      final DesktopPendingEffectBatch pending = await pendingFuture;
      expect(
        pending.effects.any((DesktopSessionEffect effect) {
          return effect is DesktopPersistLibraryLinkEffect;
        }),
        isTrue,
      );
      await waitForCondition(() => floatingHost.showCalls.isNotEmpty);
      expect(floatingHost.showCalls, isNotEmpty);
    });

    test('远端歌词选择会保留 saveRemoteLyrics 待上层处理', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: _FakePanelHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);

      coordinator.upsertSession(_session(instanceId: 2));
      final DesktopCoordinatorApplyResult? result = await coordinator
          .handleSelectorIntent(
            DesktopSelectorLyricsSelectedIntent(
              instanceId: 2,
              lyrics: _lyrics(source: Source.qm),
              langs: const <String>['orig', 'ts'],
            ),
          );

      expect(result, isNotNull);
      expect(
        result!.pendingEffects.any((DesktopSessionEffect effect) {
          return effect is DesktopSaveRemoteLyricsEffect;
        }),
        isTrue,
      );
    });

    test('bindSelectorIntents 后会自动消费选择器意图流', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: _FakePanelHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);

      coordinator.upsertSession(_session(instanceId: 3));
      coordinator.bindSelectorIntents();
      final Future<DesktopPendingEffectBatch> pendingFuture =
          coordinator.pendingEffects.first;
      selectorHost.emit(
        DesktopSelectorLyricsSelectedIntent(
          instanceId: 3,
          lyrics: _lyrics(source: Source.local),
          path: r'D:\lyrics\auto.lrc',
          langs: const <String>['orig'],
        ),
      );

      final DesktopPendingEffectBatch pending = await pendingFuture;
      expect(pending.instanceId, 3);
      await waitForCondition(
        () =>
            coordinator.sessionFor(3)?.lyricsRuntime.lyricsPath ==
            r'D:\lyrics\auto.lrc',
      );
      expect(
        coordinator.sessionFor(3)?.lyricsRuntime.lyricsPath,
        r'D:\lyrics\auto.lrc',
      );
    });

    test('metrics_committed 持久化位置但不反向覆盖活动 session', () async {
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final DefaultConfigRepository repository = DefaultConfigRepository();
      final DesktopSessionReducer reducer = DesktopSessionReducer();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: reducer,
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: _FakeWindowBackend(
            selectorHost: _FakeSelectorHost(),
            panelHost: _FakePanelHost(),
            floatingHost: floatingHost,
          ),
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(
          windowBackend: _FakeWindowBackend(
            selectorHost: _FakeSelectorHost(),
            panelHost: _FakePanelHost(),
            floatingHost: floatingHost,
          ),
        ),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: _FakeWindowBackend(
            selectorHost: _FakeSelectorHost(),
            panelHost: _FakePanelHost(),
            floatingHost: floatingHost,
          ),
        ),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await repository.dispose();
      });

      await repository.load();
      coordinator.upsertSession(_session(instanceId: 5));
      coordinator.bindConfigWatch(repository: repository);
      coordinator.bindFloatingIntents(repository: repository);
      await Future<void>.delayed(Duration.zero);
      expect(
        await floatingHost.emitAndWait(
          const DesktopFloatingMetricsCommittedIntent(
            instanceId: 5,
            windowRect: WindowRect(left: 12, top: 34, width: 456, height: 168),
            fontSize: 27,
          ),
        ),
        isTrue,
      );
      expect(reducer.config.windowRect?.left, 12);
      expect(reducer.config.windowRect?.top, 34);

      await waitForCondition(
        () =>
            coordinator.sessionFor(5)?.config.fontSize == 27 &&
            repository.current.desktop.windowRect?.height == 168,
      );

      expect(repository.current.desktop.fontSize, 27);
      expect(repository.current.desktop.windowRect?.width, 456);
      expect(coordinator.sessionFor(5)?.config.fontSize, 27);
      expect(coordinator.sessionFor(5)?.config.windowRect, isNull);
    });

    test('metrics_committed 对小于半像素的窗口矩形抖动不重复写配置', () async {
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final DefaultConfigRepository repository = DefaultConfigRepository();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await repository.dispose();
      });

      await repository.load();
      await repository.update(<String, Object?>{
        ConfigKey.desktopWindowRect: <double>[12, 34, 456, 168],
        ConfigKey.desktopFontSize: 27.0,
      });
      coordinator.upsertSession(_session(instanceId: 5));
      coordinator.bindConfigWatch(repository: repository);
      coordinator.bindFloatingIntents(repository: repository);
      await Future<void>.delayed(Duration.zero);
      final int snapshotCount = floatingHost.snapshots.length;

      floatingHost.emit(
        const DesktopFloatingMetricsCommittedIntent(
          instanceId: 5,
          windowRect: WindowRect(
            left: 12.2,
            top: 34.3,
            width: 456.4,
            height: 168.49,
          ),
          fontSize: 27.05,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(repository.current.desktop.fontSize, 27.0);
      expect(repository.current.desktop.windowRect?.left, 12);
      expect(repository.current.desktop.windowRect?.height, 168);
      expect(floatingHost.snapshots.length, snapshotCount);
    });

    test('metrics_committed 超过窗口矩形容差时仍会写入配置', () async {
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final DefaultConfigRepository repository = DefaultConfigRepository();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await repository.dispose();
      });

      await repository.load();
      await repository.update(<String, Object?>{
        ConfigKey.desktopWindowRect: <double>[12, 34, 456, 168],
        ConfigKey.desktopFontSize: 27.0,
      });
      coordinator.upsertSession(_session(instanceId: 5));
      coordinator.bindConfigWatch(repository: repository);
      coordinator.bindFloatingIntents(repository: repository);
      await Future<void>.delayed(Duration.zero);
      final int snapshotCount = floatingHost.snapshots.length;

      floatingHost.emit(
        const DesktopFloatingMetricsCommittedIntent(
          instanceId: 5,
          windowRect: WindowRect(left: 12.7, top: 34, width: 456, height: 168),
          fontSize: 27.0,
        ),
      );

      await waitForCondition(
        () => repository.current.desktop.windowRect?.left == 12.7,
      );
      expect(repository.current.desktop.windowRect?.top, 34);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(floatingHost.snapshots.length, snapshotCount);
    });

    test('bindFloatingIntents 后隐藏按钮 action 会进入主窗口并隐藏浮窗', () async {
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final DefaultConfigRepository repository = DefaultConfigRepository();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await repository.dispose();
      });

      coordinator.upsertSession(_session(instanceId: 26));
      coordinator.bindFloatingIntents(repository: repository);
      floatingHost.emit(
        const DesktopFloatingActionWindowIntent(
          instanceId: 26,
          action: DesktopWindowActionType.toggleFloatingVisibility,
        ),
      );

      await waitForCondition(
        () =>
            coordinator.sessionFor(26)?.uiState.floatingVisibilityMode ==
            DesktopFloatingVisibilityMode.forcedHidden,
      );
      await waitForCondition(() => floatingHost.hideCalls.contains(26));
      expect(floatingHost.hideCalls, contains(26));
    });

    test('bindFloatingIntents 后播放/上一首/下一首 action 会进入回控发送器', () async {
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final DefaultConfigRepository repository = DefaultConfigRepository();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await repository.dispose();
      });
      final List<({int instanceId, DesktopControlCommandTask task})> commands =
          <({int instanceId, DesktopControlCommandTask task})>[];
      coordinator.attachControlCommandSender(({
        required int instanceId,
        required DesktopControlCommandTask task,
      }) {
        commands.add((instanceId: instanceId, task: task));
        return Future<bool>.value(true);
      });

      coordinator.upsertSession(_session(instanceId: 27));
      coordinator.bindFloatingIntents(repository: repository);
      for (final DesktopPlaybackControlTask task
          in const <DesktopPlaybackControlTask>[
            DesktopPlaybackControlTask.play,
            DesktopPlaybackControlTask.previous,
            DesktopPlaybackControlTask.next,
          ]) {
        floatingHost.emit(
          DesktopFloatingActionWindowIntent(
            instanceId: 27,
            action: DesktopWindowActionType.controlCommand,
            controlTask: task,
          ),
        );
      }

      await waitForCondition(() => commands.length == 3);
      expect(commands, <({int instanceId, DesktopControlCommandTask task})>[
        (instanceId: 27, task: DesktopControlCommandTask.play),
        (instanceId: 27, task: DesktopControlCommandTask.prev),
        (instanceId: 27, task: DesktopControlCommandTask.next),
      ]);
    });

    test('bindPendingEffects 后会自动保存远端歌词并回写关联库', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final _FakeLibraryLinkRepository repository =
          _FakeLibraryLinkRepository();
      final _FakeLyricsSavePersistence persistence =
          _FakeLyricsSavePersistence();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: panelHost,
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
        pendingEffectExecutor: DesktopPendingEffectExecutor(
          libraryLinkRepository: repository,
          loadLinkedLyrics: (String lyricsPath) async =>
              _lyrics(source: Source.local),
          runAutoFetch: (AutoFetchRequest request) async =>
              throw UnimplementedError(),
          resolveAutoSaveDirectory: () async => Directory.systemTemp,
          fileSavePersistenceFactory: (String folder) {
            persistence.folder = folder;
            return persistence;
          },
        ),
      );
      addTearDown(coordinator.dispose);

      coordinator.upsertSession(_session(instanceId: 4));
      coordinator.bindPendingEffects();
      final Completer<void> repositorySaved = Completer<void>();
      repository.onSetSong = () {
        if (!repositorySaved.isCompleted) {
          repositorySaved.complete();
        }
      };

      await coordinator.handleSelectorIntent(
        DesktopSelectorLyricsSelectedIntent(
          instanceId: 4,
          lyrics: _lyrics(source: Source.qm),
          langs: const <String>['orig', 'ts'],
        ),
      );
      await repositorySaved.future;

      await waitForCondition(
        () => coordinator.sessionFor(4)?.lyricsRuntime.lyricsPath != null,
      );
      expect(
        coordinator.sessionFor(4)?.lyricsRuntime.lyricsPath,
        endsWith(r'Artist - Song｜QM(1).json'),
      );
      expect(repository.savedLyricsPath, endsWith(r'Artist - Song｜QM(1).json'));
      expect(jsonDecode(persistence.savedText!)['info']['source'], 'QM');
      expect(floatingHost.snapshots.last.snapshot.session.songTitle, 'Song');
    });

    test('bindPendingEffects 会查询关联库并读取本地歌词', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final _FakeLibraryLinkRepository repository =
          _FakeLibraryLinkRepository();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: panelHost,
        floatingHost: floatingHost,
      );
      final DesktopSessionReducer reducer = DesktopSessionReducer();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: reducer,
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
        pendingEffectExecutor: DesktopPendingEffectExecutor(
          libraryLinkRepository: repository,
          loadLinkedLyrics: (String lyricsPath) async {
            expect(lyricsPath, r'D:\lyrics\linked.lrc');
            return _lyrics(source: Source.local);
          },
          runAutoFetch: (AutoFetchRequest request) async =>
              throw UnimplementedError(),
        ),
      );
      addTearDown(coordinator.dispose);
      coordinator.bindPendingEffects();

      final DesktopReducerResult changeResult = reducer.handleChangMusic(
        DesktopSessionState.initial(),
        const DesktopChangMusicMessage(
          instanceId: 7,
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          path: r'D:\music\song.flac',
          track: '1',
        ),
      );
      final SongInfo song = changeResult.state.lyricsRuntime.song!;
      repository.queryResult = LibraryLinkItem(
        id: 7,
        song: song,
        key: LibraryLinkKey.fromSong(song),
        lyricsPath: r'D:\lyrics\linked.lrc',
        configSnapshot: const <String, Object?>{
          'langs': <String>['ts', 'orig'],
          'offset': 120,
        },
      );

      await coordinator.applyReducerResult(instanceId: 7, result: changeResult);
      await waitForCondition(
        () => coordinator.sessionFor(7)?.lyricsRuntime.lyrics != null,
      );

      final DesktopSessionState? session = coordinator.sessionFor(7);
      expect(session?.lyricsRuntime.lyrics?.source, Source.local);
      expect(session?.lyricsRuntime.lyricsPath, r'D:\lyrics\linked.lrc');
      expect(session?.config.offsetMs, 120);
      expect(session?.config.selectedLangs, const <String>['orig', 'ts']);
      expect(floatingHost.showCalls, contains(7));
    });

    test('bindPendingEffects 会在未命中关联库时自动搜词并更新浮窗', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final _FakeLibraryLinkRepository repository =
          _FakeLibraryLinkRepository();
      final _FakeLyricsSavePersistence persistence =
          _FakeLyricsSavePersistence();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: panelHost,
        floatingHost: floatingHost,
      );
      final DesktopSessionReducer reducer = DesktopSessionReducer();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: reducer,
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
        pendingEffectExecutor: DesktopPendingEffectExecutor(
          libraryLinkRepository: repository,
          loadLinkedLyrics: (String lyricsPath) async =>
              throw UnimplementedError(),
          runAutoFetch: (AutoFetchRequest request) async => AutoFetchResult(
            lyrics: _lyrics(source: Source.qm),
            matchedSongInfo: request.info,
            score: 90,
          ),
          resolveAutoSaveDirectory: () async => Directory.systemTemp,
          fileSavePersistenceFactory: (String folder) {
            persistence.folder = folder;
            return persistence;
          },
        ),
      );
      addTearDown(coordinator.dispose);
      coordinator.bindPendingEffects();

      final Completer<void> repositorySaved = Completer<void>();
      repository.onSetSong = () {
        if (!repositorySaved.isCompleted) {
          repositorySaved.complete();
        }
      };

      await coordinator.applyReducerResult(
        instanceId: 8,
        result: reducer.handleChangMusic(
          DesktopSessionState.initial(),
          const DesktopChangMusicMessage(
            instanceId: 8,
            title: 'Song',
            artist: 'Artist',
            album: 'Album',
            durationMs: 180000,
            path: r'D:\music\song.flac',
            track: '1',
          ),
        ),
      );
      await repositorySaved.future;

      final DesktopSessionState? session = coordinator.sessionFor(8);
      expect(session?.lyricsRuntime.lyrics?.source, Source.qm);
      expect(session?.lyricsRuntime.lyricsPath, endsWith('.json'));
      expect(jsonDecode(persistence.savedText!)['info']['source'], 'QM');
      expect(floatingHost.showCalls, contains(8));
    });

    test('bindConfigWatch 热更新样式但不反推活动窗口位置', () async {
      final DefaultConfigRepository repository = DefaultConfigRepository();
      await repository.load();
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: panelHost,
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await repository.dispose();
      });

      final DesktopSessionReducer seedReducer = DesktopSessionReducer();
      coordinator.upsertSession(
        seedReducer
            .applySelectedLyrics(
              _session(instanceId: 5),
              DesktopSelectedLyricsPayload(
                lyrics: _lyrics(source: Source.local),
                langs: const <String>['orig', 'ts'],
              ),
            )
            .state,
      );
      coordinator.bindConfigWatch(repository: repository);

      await repository.update(<String, Object?>{
        ConfigKey.desktopPlayedColors: <List<int>>[
          <int>[10, 20, 30],
          <int>[40, 50, 60],
        ],
        ConfigKey.desktopUnplayedColors: <List<int>>[
          <int>[70, 80, 90],
          <int>[100, 110, 120],
        ],
        ConfigKey.desktopDefaultLangs: <String>['orig'],
        ConfigKey.desktopFontFamily: 'Noto Sans CJK SC',
        ConfigKey.desktopShowFurigana: false,
        ConfigKey.desktopRefreshRate: 90,
        ConfigKey.desktopWindowRect: <double>[12, 24, 720, 260],
        ConfigKey.desktopFontSize: 36.0,
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await waitForCondition(
        () =>
            selectorHost.calls.contains('refresh:5:Artist - Song') &&
            floatingHost.snapshots.isNotEmpty,
      );

      final DesktopSessionState? session = coordinator.sessionFor(5);
      expect(session, isNotNull);
      expect(session!.config.defaultLangs, const <String>['orig']);
      expect(session.config.selectedLangs, const <String>['orig']);
      expect(
        session.config.playedColors
            .map((RgbColor color) => <int>[color.r, color.g, color.b])
            .toList(growable: false),
        <List<int>>[
          <int>[10, 20, 30],
          <int>[40, 50, 60],
        ],
      );
      expect(
        session.config.unplayedColors
            .map((RgbColor color) => <int>[color.r, color.g, color.b])
            .toList(growable: false),
        <List<int>>[
          <int>[70, 80, 90],
          <int>[100, 110, 120],
        ],
      );
      expect(session.config.fontFamily, 'Noto Sans CJK SC');
      expect(session.config.fontSize, 36);
      expect(session.config.showFurigana, isFalse);
      expect(session.config.refreshRate, 90);
      expect(session.config.windowRect, isNull);
      expect(
        selectorHost.calls.where(
          (String call) => call == 'refresh:5:Artist - Song',
        ),
        isNotEmpty,
      );
      expect(
        floatingHost.snapshots.last.snapshot.session.enabledLangs,
        const <String>['orig'],
      );
      expect(
        floatingHost.snapshots.last.snapshot.session.playedColors
            .map((RgbColor color) => <int>[color.r, color.g, color.b])
            .toList(growable: false),
        <List<int>>[
          <int>[10, 20, 30],
          <int>[40, 50, 60],
        ],
      );
      expect(
        floatingHost.snapshots.last.snapshot.session.unplayedColors
            .map((RgbColor color) => <int>[color.r, color.g, color.b])
            .toList(growable: false),
        <List<int>>[
          <int>[70, 80, 90],
          <int>[100, 110, 120],
        ],
      );
      expect(
        floatingHost.snapshots.last.snapshot.session.fontFamily,
        'Noto Sans CJK SC',
      );
      expect(floatingHost.snapshots.last.snapshot.session.fontSize, 36);
      expect(
        floatingHost.snapshots.last.snapshot.session.showFurigana,
        isFalse,
      );
      expect(floatingHost.snapshots.last.snapshot.session.refreshRate, 90);
      expect(floatingHost.snapshots.last.snapshot.initialWindowRect, isNull);
    });

    test('搜索与翻译配置变化即使没有桌面样式 diff 也会发布选择器版本', () async {
      final DefaultConfigRepository repository = DefaultConfigRepository();
      await repository.load();
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: _FakePanelHost(),
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await repository.dispose();
      });
      coordinator.bindConfigWatch(repository: repository);
      await waitForCondition(() => selectorHost.calls.contains('config:1'));
      selectorHost.calls.clear();

      await repository.update(<String, Object?>{
        ConfigKey.searchSources: <String>['NE'],
        ConfigKey.translateSource: 'OPENAI',
        ConfigKey.translateOpenAiModel: 'test-model',
      });
      await waitForCondition(() => selectorHost.calls.contains('config:2'));

      expect(selectorHost.calls, <String>['config:2']);
    });

    test('removeSession 会清理目标实例全部窗口资源', () async {
      final _FakeSelectorHost selectorHost = _FakeSelectorHost();
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final _FakePanelLifecycleDisposer panelLifecycleDisposer =
          _FakePanelLifecycleDisposer();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: selectorHost,
        panelHost: panelHost,
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      coordinator.attachPanelLifecycleDisposer(panelLifecycleDisposer);

      final DesktopSessionState state = _session(instanceId: 6).copyWith(
        panels: <int, DesktopPanelState>{
          11: const DesktopPanelState(panelId: 11, visible: true),
          12: const DesktopPanelState(panelId: 12, visible: false),
        },
      );
      coordinator.upsertSession(state);

      await coordinator.removeSession(6);
      await waitForCondition(
        () =>
            selectorHost.destroyCalls.contains(6) &&
            panelLifecycleDisposer.destroyCalls.isNotEmpty &&
            floatingHost.destroyCalls.contains(6),
      );

      expect(coordinator.sessionFor(6), isNull);
      expect(selectorHost.destroyCalls, equals(const <int>[6]));
      expect(panelHost.destroyCalls, isEmpty);
      expect(panelLifecycleDisposer.destroyCalls, hasLength(1));
      expect(panelLifecycleDisposer.destroyCalls.single.instanceId, 6);
      expect(
        panelLifecycleDisposer.destroyCalls.single.panelIds,
        equals(const <int>[11, 12]),
      );
      expect(floatingHost.destroyCalls, equals(const <int>[6]));
      expect(floatingHost.operations, <String>['flush:6', 'destroy:6']);
    });

    test('removeSession 会触发退出守卫复检', () async {
      final _FakeExitGuard exitGuard = _FakeExitGuard();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
        exitGuard: exitGuard,
      );
      addTearDown(coordinator.dispose);

      coordinator.upsertSession(_session(instanceId: 16));

      await coordinator.removeSession(16);

      expect(exitGuard.instanceLifecycleChangedCalls, 1);
    });

    test('发布新 scene 时会释放旧 scene，并在移除实例时清空缓存', () async {
      final DesktopInMemorySceneStore sceneStore = DesktopInMemorySceneStore();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: sceneStore,
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      const DesktopSceneRef sceneRefA = DesktopSceneRef(
        sceneId: '9:1',
        sceneRevision: 1,
        checksum: 'aaaa',
      );
      const DesktopSceneRef sceneRefB = DesktopSceneRef(
        sceneId: '9:2',
        sceneRevision: 2,
        checksum: 'bbbb',
      );
      final DesktopLyricsSceneDocument sceneA = DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.staticText,
        selectedLangs: <String>['orig'],
        langOrder: <String>['orig'],
        durationMs: null,
        staticDisplayLines: <String>['A'],
      );
      final DesktopLyricsSceneDocument sceneB = DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.staticText,
        selectedLangs: <String>['orig'],
        langOrder: <String>['orig'],
        durationMs: null,
        staticDisplayLines: <String>['B'],
      );
      coordinator.upsertSession(
        _session(instanceId: 9).copyWith(
          lyricsRuntime: DesktopLyricsRuntimeState(
            sceneDocument: sceneA,
            sceneRef: sceneRefA,
            sceneRevision: 1,
          ),
        ),
      );
      expect(sceneStore.getScene(sceneRefA.sceneId), isNotNull);

      coordinator.upsertSession(
        _session(instanceId: 9).copyWith(
          lyricsRuntime: DesktopLyricsRuntimeState(
            sceneDocument: sceneB,
            sceneRef: sceneRefB,
            sceneRevision: 2,
          ),
        ),
      );
      expect(sceneStore.getScene(sceneRefA.sceneId), isNull);
      expect(sceneStore.getScene(sceneRefB.sceneId), isNotNull);

      await coordinator.removeSession(9);

      expect(sceneStore.getScene(sceneRefB.sceneId), isNull);
    });

    test('dispose 可重复等待并释放活动 session 的场景引用', () async {
      final DesktopInMemorySceneStore sceneStore = DesktopInMemorySceneStore();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: sceneStore,
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      const DesktopSceneRef sceneRef = DesktopSceneRef(
        sceneId: '10:1',
        sceneRevision: 1,
        checksum: 'cccc',
      );
      coordinator.upsertSession(
        _session(instanceId: 10).copyWith(
          lyricsRuntime: DesktopLyricsRuntimeState(
            sceneDocument: DesktopLyricsSceneDocument(
              mode: DesktopLyricsSceneMode.staticText,
              selectedLangs: <String>['orig'],
              langOrder: <String>['orig'],
              durationMs: null,
              staticDisplayLines: <String>['C'],
            ),
            sceneRef: sceneRef,
            sceneRevision: 1,
          ),
        ),
      );
      expect(sceneStore.getScene(sceneRef.sceneId), isNotNull);

      await Future.wait(<Future<void>>[
        coordinator.dispose(),
        coordinator.dispose(),
      ]);

      expect(sceneStore.getScene(sceneRef.sceneId), isNull);
      expect(coordinator.sessions, isEmpty);
    });

    test('同一 sceneRef 的 start/pause/proceed/sync 不会重复 putScene', () async {
      final _CountingSceneStore sceneStore = _CountingSceneStore();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopSessionReducer reducer = DesktopSessionReducer();
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: reducer,
        sceneStore: sceneStore,
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);

      final DesktopSessionState selectedState = reducer
          .applySelectedLyrics(
            _session(instanceId: 21),
            DesktopSelectedLyricsPayload(
              lyrics: _lyrics(source: Source.local),
              langs: const <String>['orig'],
            ),
          )
          .state;

      coordinator.upsertSession(selectedState);
      expect(sceneStore.putSceneCalls, 1);

      coordinator.upsertSession(
        selectedState.copyWith(
          playbackSync: selectedState.playbackSync.copyWith(
            pluginPlaybackTimeMs: 100,
            hostReceivedAtMs: 100,
            syncRevision: 1,
            isPlaying: true,
          ),
          isPlaying: true,
          lastTask: DesktopIpcTask.start,
        ),
      );
      expect(sceneStore.putSceneCalls, 1);

      coordinator.upsertSession(
        selectedState.copyWith(
          playbackSync: selectedState.playbackSync.copyWith(
            pluginPlaybackTimeMs: 200,
            hostReceivedAtMs: 200,
            syncRevision: 2,
            isPlaying: false,
          ),
          isPlaying: false,
          lastTask: DesktopIpcTask.pause,
        ),
      );
      expect(sceneStore.putSceneCalls, 1);

      coordinator.upsertSession(
        selectedState.copyWith(
          playbackSync: selectedState.playbackSync.copyWith(
            pluginPlaybackTimeMs: 300,
            hostReceivedAtMs: 300,
            syncRevision: 3,
            isPlaying: true,
          ),
          isPlaying: true,
          lastTask: DesktopIpcTask.proceed,
        ),
      );
      expect(sceneStore.putSceneCalls, 1);

      coordinator.upsertSession(
        selectedState.copyWith(
          playbackSync: selectedState.playbackSync.copyWith(
            pluginPlaybackTimeMs: 400,
            hostReceivedAtMs: 400,
            syncRevision: 4,
            isPlaying: true,
          ),
          isPlaying: true,
          lastTask: DesktopIpcTask.sync,
        ),
      );
      expect(sceneStore.putSceneCalls, 1);
    });

    test('removeSession 会经由 panel lifecycle disposer 统一销毁面板', () async {
      final _FakePanelLifecycleDisposer panelLifecycleDisposer =
          _FakePanelLifecycleDisposer();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      coordinator.attachPanelLifecycleDisposer(panelLifecycleDisposer);
      coordinator.upsertSession(
        _session(instanceId: 24).copyWith(
          panels: <int, DesktopPanelState>{
            1: const DesktopPanelState(panelId: 1, width: 400, height: 120),
            2: const DesktopPanelState(panelId: 2, width: 500, height: 180),
          },
        ),
      );

      await coordinator.removeSession(24);

      expect(panelLifecycleDisposer.destroyCalls, hasLength(1));
      expect(panelLifecycleDisposer.destroyCalls.single.instanceId, 24);
      expect(
        panelLifecycleDisposer.destroyCalls.single.panelIds,
        equals(const <int>[1, 2]),
      );
    });

    test('sessionSnapshots 会广播状态，runWindowAction 会复用现有动作链', () async {
      final _FakeMainWindowNavigationPort navigationPort =
          _FakeMainWindowNavigationPort();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: _FakePanelHost(),
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
        mainWindowNavigationPort: navigationPort,
      );
      addTearDown(coordinator.dispose);

      final List<Map<int, DesktopSessionState>> snapshots =
          <Map<int, DesktopSessionState>>[];
      final StreamSubscription<Map<int, DesktopSessionState>> subscription =
          coordinator.sessionSnapshots.listen(snapshots.add);
      addTearDown(subscription.cancel);

      coordinator.upsertSession(_session(instanceId: 30));
      await waitForCondition(() => snapshots.isNotEmpty);
      expect(snapshots.last.keys, contains(30));

      final bool clickThroughChanged = await coordinator.runWindowAction(
        instanceId: 30,
        action: DesktopWindowActionType.toggleClickThrough,
      );
      expect(clickThroughChanged, isTrue);
      expect(coordinator.sessionFor(30)?.uiState.clickThrough, isTrue);

      final bool showMainWindow = await coordinator.runWindowAction(
        instanceId: -1,
        action: DesktopWindowActionType.showMainWindow,
      );
      expect(showMainWindow, isTrue);
      expect(navigationPort.showMainWindowCalls, 1);

      navigationPort.throwOnShow = true;
      final bool failedShowMainWindow = await coordinator.runWindowAction(
        instanceId: -1,
        action: DesktopWindowActionType.showMainWindow,
      );
      expect(failedShowMainWindow, isFalse);
      expect(navigationPort.showMainWindowCalls, 2);

      await coordinator.removeSession(30);
      await waitForCondition(
        () => snapshots.any((snapshot) => snapshot.isEmpty),
      );

      final bool missingAction = await coordinator.runWindowAction(
        instanceId: 999,
        action: DesktopWindowActionType.toggleClickThrough,
      );
      expect(missingAction, isFalse);
    });

    test('窗口 intent 触发主窗口失败时不会冒泡未捕获异常', () async {
      final _FakeFloatingHost floatingHost = _FakeFloatingHost();
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeMainWindowNavigationPort navigationPort =
          _FakeMainWindowNavigationPort()..throwOnShow = true;
      final DefaultConfigRepository repository = DefaultConfigRepository();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: floatingHost,
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
        mainWindowNavigationPort: navigationPort,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await repository.dispose();
      });
      coordinator.bindFloatingIntents(repository: repository);
      coordinator.installPanelIntentHandlers();
      coordinator.upsertSession(_session(instanceId: 35));

      floatingHost.emit(
        const DesktopFloatingActionWindowIntent(
          instanceId: 35,
          action: DesktopWindowActionType.showMainWindow,
        ),
      );
      panelHost.emit(
        const DesktopPanelActionIntent(
          instanceId: 35,
          panelId: 1,
          action: DesktopWindowActionType.showMainWindow,
        ),
      );

      await waitForCondition(() => navigationPort.showMainWindowCalls == 2);
      expect(navigationPort.showMainWindowCalls, 2);
    });

    test('PanelHostBridge bind 后立即创建并合并创建期间的 surface', () async {
      final _FakePanelHost panelHost = _FakePanelHost();
      final Completer<void> createGate = Completer<void>();
      panelHost.createCompleter = createGate;
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );
      addTearDown(bridge.dispose);

      coordinator.upsertSession(_session(instanceId: 31));
      final Future<void> createFuture = bridge.createPanel(
        instanceId: 31,
        panelId: 2,
        hostWindowId: 700,
      );
      await waitForCondition(() => panelHost.createCalls.isNotEmpty);
      expect(panelHost.createCalls.single.initialSurface, isNull);

      final Future<void> firstSurfaceFuture = bridge.updatePanelSurface(
        instanceId: 31,
        panelId: 2,
        update: const PanelSurfaceUpdate(
          width: 640,
          height: 180,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      final Future<void> latestSurfaceFuture = bridge.updatePanelSurface(
        instanceId: 31,
        panelId: 2,
        update: const PanelSurfaceUpdate(
          width: 800,
          height: 200,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      expect(panelHost.surfaceCalls, isEmpty);

      createGate.complete();
      await Future.wait(<Future<void>>[
        createFuture,
        firstSurfaceFuture,
        latestSurfaceFuture,
      ]);

      expect(panelHost.surfaceCalls, hasLength(1));
      expect(panelHost.surfaceCalls.single.width, 800);
      expect(panelHost.surfaceCalls.single.height, 200);
      expect(panelHost.surfaceCalls.single.visible, isTrue);
    });

    test('PanelHostBridge 忽略早于 bind 的兼容 surface 尺寸', () async {
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );

      coordinator.upsertSession(_session(instanceId: 32));
      await bridge.updatePanelSurface(
        instanceId: 32,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 512,
          height: 128,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      expect(panelHost.createCalls, isEmpty);

      await bridge.createPanel(instanceId: 32, panelId: 1, hostWindowId: 701);

      expect(panelHost.createCalls, hasLength(1));
      expect(panelHost.createCalls.single.hostWindowId, 701);
      expect(panelHost.createCalls.single.initialSurface, isNull);
      expect(panelHost.surfaceCalls, isEmpty);
    });

    test('PanelHostBridge surface 未就绪后仅由下一次真实事件重试', () async {
      final _FakePanelHost panelHost = _FakePanelHost()
        ..surfaceUnavailableFailuresRemaining = 1;
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );

      coordinator.upsertSession(_session(instanceId: 33));
      await bridge.createPanel(instanceId: 33, panelId: 1, hostWindowId: 702);
      expect(panelHost.createCalls, hasLength(1));
      expect(panelHost.surfaceCalls, isEmpty);

      await bridge.updatePanelSurface(
        instanceId: 33,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 400,
          height: 160,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );

      expect(panelHost.createCalls, hasLength(2));
      expect(panelHost.surfaceCalls, hasLength(1));
      expect(panelHost.surfaceCalls.single.width, 400);
      expect(panelHost.surfaceCalls.single.height, 160);
    });

    test('PanelHostBridge 支持同一实例下两个 panel 独立创建', () async {
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );

      coordinator.upsertSession(_session(instanceId: 34));
      await bridge.createPanel(instanceId: 34, panelId: 1, hostWindowId: 801);
      await bridge.createPanel(instanceId: 34, panelId: 2, hostWindowId: 802);
      await bridge.updatePanelSurface(
        instanceId: 34,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 500,
          height: 160,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      await bridge.updatePanelSurface(
        instanceId: 34,
        panelId: 2,
        update: const PanelSurfaceUpdate(
          width: 620,
          height: 180,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );

      expect(panelHost.createCalls.map((call) => call.panelId), <int>[1, 2]);
      expect(panelHost.surfaceCalls.map((call) => call.panelId), <int>[1, 2]);
      expect(coordinator.sessionFor(34)?.panels.keys, containsAll(<int>[1, 2]));
    });

    test('PanelHostBridge 会忽略重复 bind 与相同 surface', () async {
      final _FakePanelHost panelHost = _FakePanelHost();
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );

      coordinator.upsertSession(_session(instanceId: 36));
      await bridge.createPanel(instanceId: 36, panelId: 1, hostWindowId: 900);
      await bridge.createPanel(instanceId: 36, panelId: 1, hostWindowId: 900);
      await bridge.updatePanelSurface(
        instanceId: 36,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 600,
          height: 220,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      await bridge.createPanel(instanceId: 36, panelId: 1, hostWindowId: 900);
      await bridge.updatePanelSurface(
        instanceId: 36,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 600,
          height: 220,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );

      expect(panelHost.createCalls, hasLength(1));
      expect(panelHost.surfaceCalls, hasLength(1));
    });

    test('PanelHostBridge 并发 surface 更新只提交最新待处理状态', () async {
      final _FakePanelHost panelHost = _FakePanelHost();
      final Completer<void> surfaceGate = Completer<void>();
      panelHost.surfaceCompleter = surfaceGate;
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );

      coordinator.upsertSession(_session(instanceId: 37));
      await bridge.createPanel(instanceId: 37, panelId: 1, hostWindowId: 901);
      final Future<void> firstFuture = bridge.updatePanelSurface(
        instanceId: 37,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 420,
          height: 180,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      await waitForCondition(() => panelHost.surfaceCalls.length == 1);
      final Future<void> middleFuture = bridge.updatePanelSurface(
        instanceId: 37,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 480,
          height: 220,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      final Future<void> latestFuture = bridge.updatePanelSurface(
        instanceId: 37,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 540,
          height: 260,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );

      expect(panelHost.surfaceCalls, hasLength(1));
      surfaceGate.complete();
      await Future.wait(<Future<void>>[
        firstFuture,
        middleFuture,
        latestFuture,
      ]);

      expect(panelHost.surfaceCalls, hasLength(2));
      expect(panelHost.surfaceCalls.last.width, 540);
      expect(panelHost.surfaceCalls.last.height, 260);

      await bridge.updatePanelSurface(
        instanceId: 37,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 540,
          height: 260,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      expect(panelHost.surfaceCalls, hasLength(2));
    });

    test('PanelHostBridge surface 失败后由下一次真实事件恢复并仍可销毁', () async {
      final _FakePanelHost panelHost = _FakePanelHost()
        ..surfaceFailuresRemaining = 1;
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );
      addTearDown(bridge.dispose);

      coordinator.upsertSession(_session(instanceId: 38));
      await bridge.createPanel(instanceId: 38, panelId: 1, hostWindowId: 902);
      await bridge.updatePanelSurface(
        instanceId: 38,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 400,
          height: 160,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      expect(panelHost.surfaceCalls, hasLength(1));

      await bridge.updatePanelSurface(
        instanceId: 38,
        panelId: 1,
        update: const PanelSurfaceUpdate(
          width: 520,
          height: 200,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: true,
        ),
      );
      await bridge.destroyPanel(instanceId: 38, panelId: 1);

      expect(panelHost.surfaceCalls, hasLength(2));
      expect(panelHost.surfaceCalls.last.width, 520);
      expect(panelHost.destroyCalls, <({int instanceId, int panelId})>[
        (instanceId: 38, panelId: 1),
      ]);
    });

    test('PanelHostBridge 并发 dispose 会等待同一释放 Future', () async {
      final _FakePanelHost panelHost = _FakePanelHost();
      final Completer<void> destroyGate = Completer<void>();
      panelHost.destroyCompleter = destroyGate;
      final _FakeWindowBackend backend = _FakeWindowBackend(
        selectorHost: _FakeSelectorHost(),
        panelHost: panelHost,
        floatingHost: _FakeFloatingHost(),
      );
      final DesktopServiceCoordinator coordinator = DesktopServiceCoordinator(
        reducer: DesktopSessionReducer(),
        sceneStore: DesktopInMemorySceneStore(),
        floatingEffectExecutor: DesktopFloatingEffectExecutor(
          windowBackend: backend,
        ),
        panelEffectExecutor: DesktopPanelEffectExecutor(windowBackend: backend),
        selectorEffectExecutor: DesktopSelectorEffectExecutor(
          windowBackend: backend,
        ),
      );
      addTearDown(coordinator.dispose);
      final DesktopPanelHostBridgeController bridge =
          DesktopPanelHostBridgeController(
            panelHost: panelHost,
            coordinator: coordinator,
          );
      addTearDown(() async {
        if (!destroyGate.isCompleted) {
          destroyGate.complete();
        }
        await bridge.dispose();
      });

      coordinator.upsertSession(_session(instanceId: 39));
      await bridge.createPanel(instanceId: 39, panelId: 1, hostWindowId: 903);
      final Future<void> firstDispose = bridge.dispose();
      await waitForCondition(() => panelHost.destroyCalls.isNotEmpty);
      final Future<void> secondDispose = bridge.dispose();

      expect(identical(firstDispose, secondDispose), isTrue);
      destroyGate.complete();
      await Future.wait(<Future<void>>[firstDispose, secondDispose]);
    });
  });
}

DesktopSessionState _session({required int instanceId}) {
  return DesktopSessionState.initial().copyWith(
    instanceId: instanceId,
    lyricsRuntime: DesktopLyricsRuntimeState(
      song: SongInfo(
        source: Source.local,
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
        album: 'Album',
        durationMs: 180000,
        id: '1',
      ),
    ),
  );
}

Lyrics _lyrics({required Source source}) {
  return Lyrics(
    songInfo: SongInfo(
      source: Source.local,
      title: 'Song',
      artist: SongArtist(<String>['Artist']),
      album: 'Album',
      durationMs: 180000,
      id: '1',
    ),
    source: source,
    id: '1',
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: 'Hello'),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}

class _FakeWindowBackend implements DesktopWindowBackend {
  _FakeWindowBackend({
    required this.selectorHost,
    required this.panelHost,
    DesktopFloatingWindowHostPort? floatingHost,
  }) : floatingHost = floatingHost ?? const DesktopNoopFloatingWindowHost();

  @override
  final DesktopFloatingWindowHostPort floatingHost;

  @override
  final _FakeSelectorHost selectorHost;

  @override
  final _FakePanelHost panelHost;
}

class _FakeMainWindowNavigationPort implements DesktopMainWindowNavigationPort {
  int openAssociationManagerCalls = 0;
  int showMainWindowCalls = 0;
  bool openAssociationManagerResult = true;
  bool showMainWindowResult = true;
  bool throwOnOpenAssociationManager = false;
  bool throwOnShow = false;

  @override
  Future<bool> openAssociationManager() async {
    openAssociationManagerCalls += 1;
    if (throwOnOpenAssociationManager) {
      throw StateError('open association manager failed');
    }
    return openAssociationManagerResult;
  }

  @override
  Future<bool> showMainWindow() async {
    showMainWindowCalls += 1;
    if (throwOnShow) {
      throw StateError('show main window failed');
    }
    return showMainWindowResult;
  }
}

class _FakeSelectorHost implements DesktopSelectorWindowHostPort {
  final List<String> calls = <String>[];
  final List<int> destroyCalls = <int>[];
  DesktopSelectorWindowIntentHandler? _intentHandler;

  @override
  void setIntentHandler(DesktopSelectorWindowIntentHandler? handler) {
    _intentHandler = handler;
  }

  @override
  Future<void> publishConfigRevision({required int revision}) async {
    calls.add('config:$revision');
  }

  @override
  Future<void> destroySelectorWindow({required int instanceId}) async {
    destroyCalls.add(instanceId);
  }

  void emit(DesktopSelectorWindowIntent intent) {
    final DesktopSelectorWindowIntentHandler? handler = _intentHandler;
    if (handler != null) {
      unawaited(handler(intent));
    }
  }

  @override
  Future<void> ensureSelectorWindow({required int instanceId}) async {}

  @override
  Future<void> hideSelectorWindow({required int instanceId}) async {
    calls.add('hide:$instanceId');
  }

  @override
  Future<void> refreshSelectorContext({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {
    calls.add('refresh:$instanceId:${context.keyword}');
  }

  @override
  Future<void> showSelectorWindow({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {
    calls.add('show:$instanceId:${context.keyword}');
  }
}

class _FakeFloatingHost implements DesktopFloatingWindowHostPort {
  final List<int> showCalls = <int>[];
  final List<int> hideCalls = <int>[];
  final List<int> destroyCalls = <int>[];
  final List<int> flushCalls = <int>[];
  final List<String> operations = <String>[];
  DesktopFloatingWindowIntentHandler? _intentHandler;
  final List<({int instanceId, DesktopFloatingWindowSnapshot snapshot})>
  snapshots = <({int instanceId, DesktopFloatingWindowSnapshot snapshot})>[];

  @override
  void setIntentHandler(DesktopFloatingWindowIntentHandler? handler) {
    _intentHandler = handler;
  }

  void emit(DesktopFloatingWindowIntent intent) {
    final DesktopFloatingWindowIntentHandler? handler = _intentHandler;
    if (handler != null) {
      unawaited(handler(intent));
    }
  }

  Future<bool> emitAndWait(DesktopFloatingWindowIntent intent) async {
    final DesktopFloatingWindowIntentHandler? handler = _intentHandler;
    return handler == null ? false : handler(intent);
  }

  @override
  Future<void> destroyFloatingWindow({required int instanceId}) async {
    destroyCalls.add(instanceId);
    operations.add('destroy:$instanceId');
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
  Future<bool> flushFloatingGeometry({required int instanceId}) async {
    flushCalls.add(instanceId);
    operations.add('flush:$instanceId');
    return true;
  }
}

class _FakePanelHost implements DesktopPanelWindowHostPort {
  Completer<void>? createCompleter;
  Completer<void>? surfaceCompleter;
  Completer<void>? destroyCompleter;
  int surfaceUnavailableFailuresRemaining = 0;
  int surfaceFailuresRemaining = 0;
  final List<
    ({
      int instanceId,
      int panelId,
      int hostWindowId,
      PanelSurfaceUpdate? initialSurface,
    })
  >
  createCalls =
      <
        ({
          int instanceId,
          int panelId,
          int hostWindowId,
          PanelSurfaceUpdate? initialSurface,
        })
      >[];
  final List<({int instanceId, int panelId})> destroyCalls =
      <({int instanceId, int panelId})>[];
  final List<
    ({
      int instanceId,
      int panelId,
      int width,
      int height,
      PanelSizeSpace sizeSpace,
      bool visible,
    })
  >
  surfaceCalls =
      <
        ({
          int instanceId,
          int panelId,
          int width,
          int height,
          PanelSizeSpace sizeSpace,
          bool visible,
        })
      >[];
  DesktopPanelWindowIntentHandler? _intentHandler;

  @override
  void setIntentHandler(DesktopPanelWindowIntentHandler? handler) {
    _intentHandler = handler;
  }

  void emit(DesktopPanelWindowIntent intent) {
    final DesktopPanelWindowIntentHandler? handler = _intentHandler;
    if (handler != null) {
      unawaited(handler(intent));
    }
  }

  @override
  Future<void> createPanel({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    DesktopPanelWindowSnapshot? initialSnapshot,
    PanelSurfaceUpdate? initialSurface,
  }) async {
    createCalls.add((
      instanceId: instanceId,
      panelId: panelId,
      hostWindowId: hostWindowId,
      initialSurface: initialSurface,
    ));
    if (surfaceUnavailableFailuresRemaining > 0) {
      surfaceUnavailableFailuresRemaining -= 1;
      throw const DesktopPanelSurfaceUnavailable();
    }
    await createCompleter?.future;
  }

  @override
  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {
    destroyCalls.add((instanceId: instanceId, panelId: panelId));
    await destroyCompleter?.future;
  }

  @override
  Future<void> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {
    surfaceCalls.add((
      instanceId: instanceId,
      panelId: panelId,
      width: update.width,
      height: update.height,
      sizeSpace: update.sizeSpace,
      visible: update.visible,
    ));
    if (surfaceFailuresRemaining > 0) {
      surfaceFailuresRemaining -= 1;
      throw StateError('surface update failed');
    }
    await surfaceCompleter?.future;
  }

  @override
  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  }) async {}
}

class _FakeLyricsSavePersistence extends LyricsSavePersistencePort {
  LyricsSaveRequest? request;
  String? savedText;
  String folder = '';

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    this.request = request;
    savedText = utf8.decode(bytes);
    return '$folder\\${request.resolvedFileNameFormat}';
  }
}

class _FakeLibraryLinkRepository implements LibraryLinkRepository {
  LibraryLinkItem? queryResult;
  SongInfo? savedSong;
  String? savedLyricsPath;
  Map<String, Object?>? savedConfigSnapshot;
  void Function()? onSetSong;

  @override
  Future<void> delAll() async {}

  @override
  Future<void> delItem(int id) async {}

  @override
  Future<void> delItems(Iterable<int> ids) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<int> countItems({String searchText = ''}) async => 0;

  @override
  Future<List<LibraryLinkItem>> getPage({
    required int offset,
    required int limit,
    String searchText = '',
  }) async => const <LibraryLinkItem>[];

  @override
  Future<LibraryLinkItem?> getItem(int id) async => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<LibraryLinkItem?> query(SongInfo song) async => queryResult;

  @override
  Future<LibraryLinkItem> setSong({
    required SongInfo song,
    String? lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) async {
    savedSong = song;
    savedLyricsPath = lyricsPath;
    savedConfigSnapshot = configSnapshot;
    onSetSong?.call();
    return LibraryLinkItem(
      id: 1,
      song: song,
      key: LibraryLinkKey.fromSong(song),
      lyricsPath: lyricsPath,
      configSnapshot: configSnapshot,
    );
  }

  @override
  Future<void> setSongs(Iterable<LibraryLinkUpsertItem> items) async {}

  @override
  Future<void> replaceAll(Iterable<LibraryLinkUpsertItem> items) async {}

  @override
  Future<void> rewriteItems(Iterable<LibraryLinkRewriteItem> items) async {}

  @override
  Stream<void> watchChanges({bool emitCurrent = false}) async* {
    if (emitCurrent) {
      yield null;
    }
  }
}

class _FakeExitGuard implements DesktopExitGuardPort {
  int instanceLifecycleChangedCalls = 0;

  @override
  bool get hasAliveInstances => false;

  @override
  void bindAliveInstanceGetter(bool Function()? getter) {}

  @override
  DesktopExitGuardCloseAction handleWindowCloseRequest({
    required DesktopExitGuardWindowRef window,
  }) {
    return DesktopExitGuardCloseAction.hideWindow;
  }

  @override
  Future<void> handleInstanceLifecycleChanged() async {
    instanceLifecycleChangedCalls += 1;
  }

  @override
  Future<void> handleWindowClosed({
    required DesktopExitGuardWindowRef window,
  }) async {}

  @override
  bool hasAnyVisibleWindow({DesktopExitGuardWindowRef? excludeWindow}) => false;

  @override
  void registerExitHandler(Future<void> Function()? handler) {}

  @override
  void bindMainWindowVisibilityProbe(Future<bool> Function()? probe) {}

  @override
  void setMainWindowOwnership(DesktopMainWindowOwnershipState state) {}
}

class _FakePanelLifecycleDisposer implements DesktopPanelLifecycleDisposer {
  final List<({int instanceId, List<int> panelIds})> destroyCalls =
      <({int instanceId, List<int> panelIds})>[];

  @override
  Future<void> destroyPanelsForInstance({
    required int instanceId,
    required Iterable<int> panelIds,
  }) async {
    destroyCalls.add((
      instanceId: instanceId,
      panelIds: panelIds.toList(growable: false),
    ));
  }
}

class _CountingSceneStore extends DesktopInMemorySceneStore {
  int putSceneCalls = 0;

  @override
  void putScene(
    String sceneId,
    Uint8List bytes, {
    required int revision,
    required String checksum,
  }) {
    putSceneCalls += 1;
    super.putScene(sceneId, bytes, revision: revision, checksum: checksum);
  }
}
