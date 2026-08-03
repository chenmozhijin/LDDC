import 'dart:async';

import '../../../core/logging/logging.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import 'desktop_session_reducer.dart';

final AppLogger _selectorExecutorLogger = AppLogger.scope('selector-executor');

/// 执行桌面歌词选择器相关 effect。
///
/// 说明：
/// - `onlyIfVisible=true` 时只尝试刷新已显示的选择器窗口；
/// - `onlyIfVisible=false` 时按Python版 `to_select(false)` 语义显示窗口并注入上下文；
/// - 选择器回传意图通过唯一异步 handler 串到 reducer，并把真实结果返回子窗口。
class DesktopSelectorEffectExecutor {
  DesktopSelectorEffectExecutor({required DesktopWindowBackend windowBackend})
    : _windowBackend = windowBackend;

  final DesktopWindowBackend _windowBackend;
  final Map<int, _SelectorDispatchState> _dispatchStates =
      <int, _SelectorDispatchState>{};

  void setIntentHandler(DesktopSelectorWindowIntentHandler? handler) {
    _windowBackend.selectorHost.setIntentHandler(handler);
  }

  Future<void> publishConfigRevision(int revision) async {
    try {
      await _windowBackend.selectorHost.publishConfigRevision(
        revision: revision,
      );
    } on Object catch (error, stackTrace) {
      // 单个失联子窗口不能阻塞主 engine 应用配置；host 会保留最新版本，
      // 下次窗口显示时再次重放并修复短暂通道故障。
      _selectorExecutorLogger.info(
        'selector config sync failed revision=$revision'
        ' error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> executeAll(Iterable<DesktopSessionEffect> effects) async {
    final List<Future<void>> dispatches = <Future<void>>[];
    for (final DesktopSessionEffect effect in effects) {
      dispatches.add(execute(effect));
    }
    if (dispatches.isNotEmpty) {
      await Future.wait(dispatches);
    }
  }

  Future<void> execute(DesktopSessionEffect effect) {
    if (effect is! DesktopRefreshSelectorEffect) {
      return Future<void>.value();
    }
    final int instanceId = effect.instanceId;
    final _SelectorDispatchState dispatchState = _dispatchStates.putIfAbsent(
      instanceId,
      _SelectorDispatchState.new,
    );
    if (dispatchState.destroyRequested) {
      return dispatchState.destroyCompleter?.future ?? Future<void>.value();
    }
    final DesktopRefreshSelectorEffect? pending = dispatchState.pendingEffect;
    dispatchState.pendingEffect = pending == null
        ? effect
        : DesktopRefreshSelectorEffect(
            instanceId: instanceId,
            context: effect.context,
            // 尚未执行的任一请求要求显示窗口时，合并后仍必须显示；
            // 只替换为最新上下文，不能被后到的“仅可见时刷新”降级。
            onlyIfVisible: pending.onlyIfVisible && effect.onlyIfVisible,
          );
    final Completer<void> idleCompleter = dispatchState.idleCompleter ??=
        Completer<void>();
    _selectorExecutorLogger.info(
      'selector dispatch queued instance=$instanceId'
      ' onlyIfVisible=${dispatchState.pendingEffect!.onlyIfVisible}'
      ' keyword=${effect.context.keyword ?? '-'}',
    );
    _ensurePump(instanceId, dispatchState);
    return idleCompleter.future;
  }

  void _ensurePump(int instanceId, _SelectorDispatchState dispatchState) {
    if (dispatchState.running) {
      return;
    }
    dispatchState.running = true;
    unawaited(_pump(instanceId, dispatchState));
  }

  Future<void> _pump(
    int instanceId,
    _SelectorDispatchState dispatchState,
  ) async {
    try {
      while (identical(_dispatchStates[instanceId], dispatchState)) {
        if (dispatchState.destroyRequested) {
          await _destroyHost(instanceId);
          dispatchState.destroyRequested = false;
          _dispatchStates.remove(instanceId);
          _complete(dispatchState.destroyCompleter);
          _complete(dispatchState.idleCompleter);
          return;
        }
        final DesktopRefreshSelectorEffect? pending =
            dispatchState.pendingEffect;
        if (pending == null) {
          break;
        }
        dispatchState.pendingEffect = null;
        await _dispatch(pending);
      }
    } on Object catch (error, stackTrace) {
      // 意外异常不能让 per-instance 泵永久保持 running，也不能让等待销毁
      // 的会话悬挂。丢弃当前状态后，下一次有效 effect 可重新创建干净泵。
      _selectorExecutorLogger.warning(
        'selector dispatch pump failed instance=$instanceId'
        ' error=$error stack=$stackTrace',
      );
      _complete(dispatchState.destroyCompleter);
      _complete(dispatchState.idleCompleter);
      if (identical(_dispatchStates[instanceId], dispatchState)) {
        _dispatchStates.remove(instanceId);
      }
      return;
    }

    dispatchState.running = false;
    if (!identical(_dispatchStates[instanceId], dispatchState)) {
      return;
    }
    if (dispatchState.destroyRequested || dispatchState.pendingEffect != null) {
      _ensurePump(instanceId, dispatchState);
      return;
    }
    _dispatchStates.remove(instanceId);
    _complete(dispatchState.idleCompleter);
  }

  Future<void> _dispatch(DesktopRefreshSelectorEffect effect) async {
    try {
      if (effect.onlyIfVisible) {
        await _windowBackend.selectorHost.refreshSelectorContext(
          instanceId: effect.instanceId,
          context: effect.context,
        );
      } else {
        await _windowBackend.selectorHost.showSelectorWindow(
          instanceId: effect.instanceId,
          context: effect.context,
        );
      }
    } on Object catch (error, stackTrace) {
      _selectorExecutorLogger.info(
        'selector dispatch failed instance=${effect.instanceId}'
        ' error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> _destroyHost(int instanceId) async {
    try {
      await _windowBackend.selectorHost.destroySelectorWindow(
        instanceId: instanceId,
      );
    } on Object catch (error, stackTrace) {
      _selectorExecutorLogger.info(
        'selector destroy failed instance=$instanceId'
        ' error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> destroyInstance(int instanceId) {
    final _SelectorDispatchState dispatchState = _dispatchStates.putIfAbsent(
      instanceId,
      _SelectorDispatchState.new,
    );
    final Completer<void> destroyCompleter = dispatchState.destroyCompleter ??=
        Completer<void>();
    dispatchState
      ..destroyRequested = true
      ..pendingEffect = null
      ..idleCompleter ??= Completer<void>();
    _ensurePump(instanceId, dispatchState);
    return destroyCompleter.future;
  }

  void _complete(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class _SelectorDispatchState {
  DesktopRefreshSelectorEffect? pendingEffect;
  Completer<void>? idleCompleter;
  Completer<void>? destroyCompleter;
  bool destroyRequested = false;
  bool running = false;
}
