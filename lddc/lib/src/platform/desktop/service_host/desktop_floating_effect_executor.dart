import 'dart:async';

import '../../../core/logging/logging.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import '../window/desktop_projection_host_mapper.dart';
import 'desktop_session_state.dart';
import 'desktop_window_action_builder.dart';

final AppLogger _floatingExecutorLogger = AppLogger.scope('floating-executor');

/// 将实例状态同步到桌面歌词浮窗窗口壳。
///
/// 说明：
/// - executor 只负责“主机状态 -> 浮窗快照”；
/// - 渲染布局由子窗口侧 `DesktopRenderFrameCompiler` 统一编译；
/// - 配置热更新后也统一复用这条快照同步链。
class DesktopFloatingEffectExecutor {
  DesktopFloatingEffectExecutor({required DesktopWindowBackend windowBackend})
    : _windowBackend = windowBackend;

  final DesktopWindowBackend _windowBackend;
  final Map<int, _FloatingDispatchState> _dispatchStates =
      <int, _FloatingDispatchState>{};

  void setIntentHandler(DesktopFloatingWindowIntentHandler? handler) {
    _windowBackend.floatingHost.setIntentHandler(handler);
  }

  Future<void> syncState(DesktopSessionState state) async {
    final int? instanceId = state.instanceId;
    if (instanceId == null) {
      return;
    }
    final DesktopFloatingWindowSnapshot snapshot = _buildSnapshot(state);
    final _FloatingDispatchState dispatchState = _dispatchStates.putIfAbsent(
      instanceId,
      _FloatingDispatchState.new,
    );
    dispatchState
      ..latestSnapshot = snapshot
      ..removeWhenIdle = false;
    _floatingExecutorLogger.info(
      'floating dispatch queued instance=$instanceId'
      ' visible=${snapshot.flags.visible}'
      ' scene=${snapshot.sceneRef?.sceneId ?? '-'}'
      ' sync=${snapshot.anchor?.syncRevision ?? 0}',
    );
    DesktopLyricsPerfStats.instance.recordPeak(
      'floatingQueueDepth',
      _dispatchStates.length,
    );
    _ensurePump(instanceId, dispatchState);
  }

  Future<void> destroyInstance(int instanceId) async {
    final _FloatingDispatchState dispatchState = _dispatchStates.putIfAbsent(
      instanceId,
      _FloatingDispatchState.new,
    );
    final Completer<void> completer = Completer<void>();
    dispatchState
      ..destroyRequested = true
      ..latestSnapshot = null
      ..removeWhenIdle = true
      ..destroyWaiters.add(completer);
    _floatingExecutorLogger.info(
      'floating destroy queued instance=$instanceId'
      ' running=${dispatchState.running}'
      ' waiters=${dispatchState.destroyWaiters.length}',
    );
    _ensurePump(instanceId, dispatchState);
    await completer.future;
    _floatingExecutorLogger.info(
      'floating destroy completed instance=$instanceId',
    );
  }

  DesktopFloatingWindowSnapshot _buildSnapshot(DesktopSessionState state) {
    final bool visible = _shouldShowWindow(state);
    final song = state.lyricsRuntime.song;
    return DesktopFloatingWindowSnapshot(
      session: DesktopFloatingSessionSnapshot(
        songId: song?.id ?? song?.mid ?? song?.path,
        songTitle: song?.title,
        artistText: song?.artistText,
        enabledLangs: state.config.selectedLangs,
        playedColors: state.config.playedColors,
        unplayedColors: state.config.unplayedColors,
        fontFamily: state.config.fontFamily,
        fontSize: state.config.fontSize,
        showFurigana: state.config.showFurigana,
        isPlaying: state.isPlaying,
        isInstrumental: state.config.isInstrumental,
        hasStaticDisplay: state.lyricsRuntime.hasStaticDisplay,
        refreshRate: state.config.refreshRate,
        actions: buildDesktopWindowActionSnapshot(state),
        infoBadge: buildDesktopLyricsInfoBadgeSnapshot(state),
      ),
      initialWindowRect: state.config.windowRect,
      sceneRef: state.lyricsRuntime.sceneRef,
      anchor: DesktopFloatingAnchorSnapshot(
        pluginPlaybackTimeMs: state.playbackSync.pluginPlaybackTimeMs,
        pluginSendTimeMs: state.playbackSync.pluginSendTimeMs,
        hostReceivedAtMs: state.playbackSync.hostReceivedAtMs,
        isPlaying: state.playbackSync.isPlaying,
        syncRevision: state.playbackSync.syncRevision,
        eventKind: state.playbackSync.task.toPlaybackEventKind(),
        sceneId: state.playbackSync.sceneId,
        songToken: state.playbackSync.songToken,
      ),
      flags: DesktopFloatingWindowFlags(
        visible: visible,
        clickThrough: state.uiState.clickThrough,
      ),
    );
  }

  bool _shouldShowWindow(DesktopSessionState state) {
    return switch (state.uiState.floatingVisibilityMode) {
      DesktopFloatingVisibilityMode.forcedHidden => false,
      DesktopFloatingVisibilityMode.forcedVisible => true,
      DesktopFloatingVisibilityMode.auto =>
        state.lyricsRuntime.song != null ||
            state.lyricsRuntime.hasStaticDisplay ||
            state.lyricsRuntime.sceneRef != null ||
            state.lyricsRuntime.hasLyrics,
    };
  }

  void _ensurePump(int instanceId, _FloatingDispatchState dispatchState) {
    if (dispatchState.running) {
      return;
    }
    dispatchState.running = true;
    unawaited(_pump(instanceId, dispatchState));
  }

  Future<void> _pump(
    int instanceId,
    _FloatingDispatchState dispatchState,
  ) async {
    try {
      while (identical(_dispatchStates[instanceId], dispatchState)) {
        if (dispatchState.destroyRequested) {
          _floatingExecutorLogger.info(
            'floating destroy start instance=$instanceId'
            ' removeWhenIdle=${dispatchState.removeWhenIdle}'
            ' snapshotPending=${dispatchState.latestSnapshot != null}',
          );
          final bool destroyed = await _tryDestroy(
            instanceId,
            operation: 'destroyWindow',
          );
          if (!destroyed) {
            _floatingExecutorLogger.warning(
              'floating destroy failed without retry instance=$instanceId',
            );
          }
          _floatingExecutorLogger.info(
            'floating destroy host completed instance=$instanceId',
          );
          dispatchState.destroyRequested = false;
          _completeDestroyWaiters(dispatchState);
          if (dispatchState.removeWhenIdle &&
              dispatchState.latestSnapshot == null) {
            _floatingExecutorLogger.info(
              'floating dispatch state removed instance=$instanceId reason=destroyed',
            );
            _dispatchStates.remove(instanceId);
            return;
          }
        }

        final DesktopFloatingWindowSnapshot? snapshot =
            dispatchState.latestSnapshot;
        if (snapshot == null) {
          break;
        }
        dispatchState.latestSnapshot = null;

        bool applied = await _tryApply(instanceId, snapshot);
        if (!applied) {
          _floatingExecutorLogger.info(
            'floating apply failed; recreate once instance=$instanceId',
          );
          final bool destroyed = await _tryDestroy(
            instanceId,
            operation: 'destroyWindowForSingleRecreate',
          );
          if (destroyed) {
            applied = await _tryApply(instanceId, snapshot);
          }
        }
        if (!applied) {
          _floatingExecutorLogger.info(
            'floating apply abandoned until next snapshot instance=$instanceId',
          );
        }
      }
    } on Object catch (error, stackTrace) {
      // 泵内部若出现预期边界之外的异常，必须释放状态和销毁等待者；
      // 否则 running 会永久保持 true，后续快照也无法再启动新的泵。
      _floatingExecutorLogger.warning(
        'floating dispatch pump failed instance=$instanceId'
        ' error=$error stack=$stackTrace',
      );
      dispatchState.running = false;
      _completeDestroyWaiters(dispatchState);
      if (identical(_dispatchStates[instanceId], dispatchState)) {
        _dispatchStates.remove(instanceId);
      }
      return;
    }

    dispatchState.running = false;
    if (!identical(_dispatchStates[instanceId], dispatchState)) {
      return;
    }
    if (dispatchState.destroyRequested ||
        dispatchState.latestSnapshot != null) {
      _ensurePump(instanceId, dispatchState);
      return;
    }
    if (dispatchState.removeWhenIdle) {
      _completeDestroyWaiters(dispatchState);
      _floatingExecutorLogger.info(
        'floating dispatch state removed instance=$instanceId reason=idle',
      );
      _dispatchStates.remove(instanceId);
    }
  }

  Future<bool> flushGeometry(int instanceId) async {
    try {
      // 通道重试和超时由 floating host 统一负责，避免外层提前返回后
      // 底层 Future 仍继续写配置，导致会话清理与几何持久化并发执行。
      return await _windowBackend.floatingHost.flushFloatingGeometry(
        instanceId: instanceId,
      );
    } on Object catch (error, stackTrace) {
      _floatingExecutorLogger.warning(
        'floating geometry flush failed instance=$instanceId'
        ' error=$error stack=$stackTrace',
      );
      return false;
    }
  }

  Future<bool> _tryApply(
    int instanceId,
    DesktopFloatingWindowSnapshot snapshot,
  ) async {
    try {
      // 创建、通道握手和 ready 屏障的超时由具体 window host 统一拥有。
      // executor 再套一层更短 timeout 会让仍在合法初始化期的窗口被误销毁，
      // 同时迟到的底层 Future 仍会继续运行，形成重复创建和资源抖动。
      await _windowBackend.floatingHost.applyFloatingSnapshot(
        instanceId: instanceId,
        snapshot: snapshot,
      );
      return true;
    } on Object catch (error, stackTrace) {
      _floatingExecutorLogger.warning(
        'floating apply failed instance=$instanceId'
        ' visible=${snapshot.flags.visible}'
        ' error=$error stack=$stackTrace',
      );
      return false;
    }
  }

  Future<bool> _tryDestroy(int instanceId, {required String operation}) async {
    try {
      // floating host 会等待自身的关闭观察屏障；executor 必须等待同一个
      // Future 真正结束，才能允许同实例的新快照继续创建窗口。
      await _windowBackend.floatingHost.destroyFloatingWindow(
        instanceId: instanceId,
      );
      return true;
    } on Object catch (error, stackTrace) {
      _floatingExecutorLogger.warning(
        'floating destroy failed instance=$instanceId'
        ' operation=$operation error=$error stack=$stackTrace',
      );
      return false;
    }
  }

  void _completeDestroyWaiters(_FloatingDispatchState dispatchState) {
    if (dispatchState.destroyWaiters.isEmpty) {
      return;
    }
    final List<Completer<void>> waiters = List<Completer<void>>.from(
      dispatchState.destroyWaiters,
    );
    dispatchState.destroyWaiters.clear();
    _floatingExecutorLogger.info(
      'floating destroy waiters completed count=${waiters.length}',
    );
    for (final Completer<void> waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}

class _FloatingDispatchState {
  DesktopFloatingWindowSnapshot? latestSnapshot;
  bool destroyRequested = false;
  bool removeWhenIdle = false;
  bool running = false;
  final List<Completer<void>> destroyWaiters = <Completer<void>>[];
}
