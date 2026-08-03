import 'dart:async';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import '../../../core/logging/logging.dart';
import 'desktop_session_reducer.dart';

final AppLogger _panelExecutorLogger = AppLogger.scope('panel-executor');

/// 执行面板内容快照同步。
///
/// 说明：
/// - 面板宿主生命周期已由宿主桥接管；
/// - 这里仅保留 `DesktopSyncPanelsEffect` 的内容广播；
/// - 通过按 panel 维度合并最新快照，避免无界积压。
class DesktopPanelEffectExecutor {
  DesktopPanelEffectExecutor({required DesktopWindowBackend windowBackend})
    : _windowBackend = windowBackend;

  final DesktopWindowBackend _windowBackend;
  final Map<_PanelDispatchKey, _PanelDispatchState> _dispatchStates =
      <_PanelDispatchKey, _PanelDispatchState>{};

  void setIntentHandler(DesktopPanelWindowIntentHandler? handler) {
    _windowBackend.panelHost.setIntentHandler(handler);
  }

  Future<void> executeAll(Iterable<DesktopSessionEffect> effects) async {
    for (final DesktopSessionEffect effect in effects) {
      await execute(effect);
    }
  }

  Future<void> execute(DesktopSessionEffect effect) async {
    if (effect is! DesktopSyncPanelsEffect) {
      return;
    }
    for (final int panelId in effect.panelIds) {
      final _PanelDispatchKey key = (
        instanceId: effect.instanceId,
        panelId: panelId,
      );
      final _PanelDispatchState dispatchState = _dispatchStates.putIfAbsent(
        key,
        _PanelDispatchState.new,
      );
      dispatchState.latestSnapshot = effect.snapshot;
      DesktopLyricsPerfStats.instance.recordPeak(
        'panelQueueDepth',
        _dispatchStates.length,
      );
      _ensurePump(key, dispatchState);
    }
  }

  void _ensurePump(_PanelDispatchKey key, _PanelDispatchState dispatchState) {
    if (dispatchState.running) {
      return;
    }
    dispatchState.running = true;
    unawaited(_pump(key, dispatchState));
  }

  Future<void> _pump(
    _PanelDispatchKey key,
    _PanelDispatchState dispatchState,
  ) async {
    try {
      while (identical(_dispatchStates[key], dispatchState)) {
        final DesktopPanelWindowSnapshot? snapshot =
            dispatchState.latestSnapshot;
        if (snapshot == null) {
          break;
        }
        dispatchState.latestSnapshot = null;
        try {
          // 通道握手、调用超时和销毁竞态由 panel host 统一管理。
          // executor 若在外层提前超时，底层 Future 仍会继续运行；此时立即
          // 重放同一快照会让两个原生调用并发修改同一个 panel。
          await _windowBackend.panelHost.syncPanelSnapshot(
            instanceId: key.instanceId,
            panelIds: <int>[key.panelId],
            snapshot: snapshot,
          );
        } on Object catch (error, stackTrace) {
          _panelExecutorLogger.warning(
            'panel sync failed instance=${key.instanceId}'
            ' panel=${key.panelId} error=$error stack=$stackTrace',
          );
        }
      }
    } on Object catch (error, stackTrace) {
      // 这里兜住泵自身的意外异常，避免 running 永久保持 true 并泄漏状态。
      _panelExecutorLogger.warning(
        'panel dispatch pump failed instance=${key.instanceId}'
        ' panel=${key.panelId} error=$error stack=$stackTrace',
      );
      if (identical(_dispatchStates[key], dispatchState)) {
        _dispatchStates.remove(key);
      }
    } finally {
      dispatchState.running = false;
      if (identical(_dispatchStates[key], dispatchState)) {
        if (dispatchState.latestSnapshot != null) {
          _ensurePump(key, dispatchState);
        } else {
          _dispatchStates.remove(key);
        }
      }
    }
  }
}

typedef _PanelDispatchKey = ({int instanceId, int panelId});

class _PanelDispatchState {
  DesktopPanelWindowSnapshot? latestSnapshot;
  bool running = false;
}
