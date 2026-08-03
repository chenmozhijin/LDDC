import 'dart:async';

import 'desktop_host_intent_router.dart';
import 'desktop_host_window_common.dart';
import 'desktop_multi_window_port.dart';
import 'desktop_window_backend.dart';
import 'desktop_window_launch.dart';
import 'desktop_window_lifecycle.dart';
import 'desktop_window_method_names.dart';
import 'desktop_window_payload_codec.dart';

/// 基于 `desktop_multi_window` 的选择器宿主实现。
class DesktopMultiWindowSelectorWindowHost
    implements DesktopSelectorWindowHostPort {
  DesktopMultiWindowSelectorWindowHost({
    DesktopMultiWindowPort? multiWindowPort,
    DesktopWindowLifecycleRegistry? lifecycleRegistry,
    DesktopMultiWindowHostIntentRouter? intentRouter,
    this.channelReadyRetryDelay = const Duration(milliseconds: 25),
    this.channelReadyRetryLimit = 20,
    this.channelOperationTimeout = const Duration(seconds: 2),
  }) : _multiWindowPort = multiWindowPort ?? const DesktopMultiWindowAdapter(),
       _lifecycleRegistry =
           lifecycleRegistry ??
           DesktopWindowLifecycleRegistryController.instance,
       _intentRouter =
           intentRouter ??
           DesktopMultiWindowHostIntentRouter(
             multiWindowPort:
                 multiWindowPort ?? const DesktopMultiWindowAdapter(),
           ) {
    _selectorHiddenHandler = (Object? arguments) => _handleHostIntent(
      DesktopWindowMethodNames.selectorHiddenIntent,
      arguments,
    );
    _selectorLyricsSelectedHandler = (Object? arguments) => _handleHostIntent(
      DesktopWindowMethodNames.selectorLyricsSelectedIntent,
      arguments,
    );
    _intentRouter
      ..registerHandler(
        DesktopWindowMethodNames.selectorHiddenIntent,
        _selectorHiddenHandler,
      )
      ..registerHandler(
        DesktopWindowMethodNames.selectorLyricsSelectedIntent,
        _selectorLyricsSelectedHandler,
      );
  }

  final DesktopMultiWindowPort _multiWindowPort;
  final DesktopWindowLifecycleRegistry _lifecycleRegistry;
  final DesktopMultiWindowHostIntentRouter _intentRouter;
  final Duration channelReadyRetryDelay;
  final int channelReadyRetryLimit;
  final Duration channelOperationTimeout;
  late final DesktopHostIntentHandler _selectorHiddenHandler;
  late final DesktopHostIntentHandler _selectorLyricsSelectedHandler;
  final Map<int, DesktopSelectorWindowEntry> _windows =
      <int, DesktopSelectorWindowEntry>{};
  final Map<int, Future<DesktopRemoteWindowPort>> _windowCreations =
      <int, Future<DesktopRemoteWindowPort>>{};
  final Map<int, int> _creationGenerations = <int, int>{};
  String? _hostWindowId;
  bool _disposed = false;
  int _latestConfigRevision = 0;
  DesktopSelectorWindowIntentHandler? _intentHandler;

  @override
  void setIntentHandler(DesktopSelectorWindowIntentHandler? handler) {
    _intentHandler = handler;
  }

  @override
  Future<void> publishConfigRevision({required int revision}) async {
    if (revision <= _latestConfigRevision) {
      return;
    }
    _latestConfigRevision = revision;
    final List<MapEntry<int, DesktopSelectorWindowEntry>> entries = _windows
        .entries
        .toList(growable: false);
    await Future.wait<void>(
      entries.map((MapEntry<int, DesktopSelectorWindowEntry> entry) {
        return _syncConfigRevision(
          instanceId: entry.key,
          window: entry.value.window,
        );
      }),
    );
  }

  Future<T> retryWindowChannel<T>(
    Future<T> Function() action, {
    required int instanceId,
    required String operation,
  }) async {
    return retryDesktopWindowChannel(
      action,
      instanceId: instanceId,
      operation: operation,
      retryDelay: channelReadyRetryDelay,
      retryLimit: channelReadyRetryLimit,
      operationTimeout: channelOperationTimeout,
    );
  }

  @override
  Future<void> destroySelectorWindow({required int instanceId}) async {
    _nextCreationGeneration(instanceId);
    _windowCreations.remove(instanceId);
    final DesktopSelectorWindowEntry? entry = _windows.remove(instanceId);
    if (entry == null) {
      return;
    }
    _lifecycleRegistry.setDesired(
      entry.ref,
      DesktopWindowDesiredState.absent,
      reason: 'selector-destroy-requested',
    );
    _lifecycleRegistry.markCommandIssued(
      entry.ref,
      observedState: DesktopWindowObservedState.closing,
      desiredState: DesktopWindowDesiredState.absent,
      reason: 'selector-close-issued',
    );
    await entry.window.requestClose();
    _lifecycleRegistry.markClosed(
      entry.ref,
      reason: 'selector-window-close-confirmed',
    );
  }

  @override
  Future<void> ensureSelectorWindow({required int instanceId}) async {
    if (_disposed) {
      throw StateError('selector window host 已释放，不能创建选择器');
    }
    await _ensureHandlerBound();
    await _ensureWindow(instanceId);
  }

  @override
  Future<void> hideSelectorWindow({required int instanceId}) async {
    final DesktopSelectorWindowEntry? entry = _windows[instanceId];
    if (entry == null) {
      return;
    }
    await entry.window.hide();
    final DesktopSelectorWindowEntry updated = entry.copyWith(visible: false);
    _windows[instanceId] = updated;
    _lifecycleRegistry.setDesired(
      updated.ref,
      DesktopWindowDesiredState.hidden,
      reason: 'selector-hide',
    );
    _lifecycleRegistry.upsertObserved(
      updated.ref,
      DesktopWindowObservedState.ready,
      reason: 'selector-hidden',
    );
  }

  @override
  Future<void> refreshSelectorContext({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {
    final DesktopSelectorWindowEntry? entry = _windows[instanceId];
    if (entry == null || !entry.visible) {
      return;
    }
    await retryWindowChannel(
      () => entry.window.invokeMethod(
        DesktopWindowMethodNames.selectorRefresh,
        DesktopWindowPayloadCodec.encodeSelectorContext(context),
      ),
      instanceId: instanceId,
      operation: 'refreshSelectorContext',
    );
  }

  /// 读取子 engine 的搜索生命周期快照，用于 resident 资源验收。
  ///
  /// 该调用是只读诊断，不参与窗口显示状态，也不会创建或销毁选择器窗口。
  Future<DesktopSelectorRuntimeDiagnostics> readSelectorRuntimeDiagnostics({
    required int instanceId,
  }) async {
    final DesktopSelectorWindowEntry? entry = _windows[instanceId];
    if (entry == null) {
      throw StateError('selector window 不存在，无法读取 runtime diagnostics');
    }
    final Object? payload = await retryWindowChannel(
      () => entry.window.invokeMethod(
        DesktopWindowMethodNames.selectorRuntimeDiagnostics,
        null,
      ),
      instanceId: instanceId,
      operation: 'readSelectorRuntimeDiagnostics',
    );
    return DesktopWindowPayloadCodec.decodeSelectorRuntimeDiagnostics(payload);
  }

  @override
  Future<void> showSelectorWindow({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {
    await _ensureHandlerBound();
    final DesktopRemoteWindowPort window = await _ensureWindow(instanceId);
    await _syncConfigRevision(instanceId: instanceId, window: window);
    await retryWindowChannel(
      () => window.invokeMethod(
        DesktopWindowMethodNames.selectorShow,
        DesktopWindowPayloadCodec.encodeSelectorContext(context),
      ),
      instanceId: instanceId,
      operation: 'showSelectorWindow',
    );
    // 子窗口必须自己完成 restore/show/focus 和 Windows 前台提升；宿主若先
    // 直接 show，会把“已显示但仍最小化或未获焦点”的中间态暴露给生命周期。
    await retryWindowChannel(
      () => window.invokeMethod(DesktopWindowMethodNames.selectorPresent),
      instanceId: instanceId,
      operation: 'presentSelectorWindow',
    );
    final DesktopSelectorWindowEntry? entry = _windows[instanceId];
    if (entry != null) {
      final DesktopSelectorWindowEntry updated = entry.copyWith(visible: true);
      _windows[instanceId] = updated;
      _lifecycleRegistry.setDesired(
        updated.ref,
        DesktopWindowDesiredState.visible,
        reason: 'selector-show',
      );
      _lifecycleRegistry.upsertObserved(
        updated.ref,
        DesktopWindowObservedState.visible,
        reason: 'selector-shown',
      );
    }
  }

  Future<void> _syncConfigRevision({
    required int instanceId,
    required DesktopRemoteWindowPort window,
  }) async {
    final int revision = _latestConfigRevision;
    if (revision <= 0) {
      return;
    }
    await retryWindowChannel(
      () => window.invokeMethod(
        DesktopWindowMethodNames.selectorConfigChanged,
        DesktopWindowPayloadCodec.encodeSelectorConfigRevision(revision),
      ),
      instanceId: instanceId,
      operation: 'syncSelectorConfigRevision',
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _intentRouter
      ..unregisterHandler(
        DesktopWindowMethodNames.selectorHiddenIntent,
        _selectorHiddenHandler,
      )
      ..unregisterHandler(
        DesktopWindowMethodNames.selectorLyricsSelectedIntent,
        _selectorLyricsSelectedHandler,
      );
    _intentHandler = null;
    final List<int> instanceIds = <int>{
      ..._windows.keys,
      ..._windowCreations.keys,
    }.toList(growable: false);
    for (final int instanceId in instanceIds) {
      _nextCreationGeneration(instanceId);
    }
    for (final DesktopSelectorWindowEntry entry in _windows.values.toList(
      growable: false,
    )) {
      await entry.window.requestClose();
      _lifecycleRegistry.markClosed(entry.ref, reason: 'selector-host-dispose');
    }
    _windows.clear();
    _windowCreations.clear();
  }

  Future<void> _ensureHandlerBound() async {
    await _intentRouter.ensureBound();
  }

  Future<DesktopRemoteWindowPort> _ensureWindow(int instanceId) async {
    if (_disposed) {
      throw StateError('selector window host 已释放，不能创建选择器');
    }
    final DesktopSelectorWindowEntry? cached = _windows[instanceId];
    if (cached != null) {
      return cached.window;
    }
    final Future<DesktopRemoteWindowPort>? creating =
        _windowCreations[instanceId];
    if (creating != null) {
      return creating;
    }
    final int generation = _creationGenerations[instanceId] ?? 0;
    final Future<DesktopRemoteWindowPort> future = _createWindow(
      instanceId,
      generation: generation,
    );
    _windowCreations[instanceId] = future;
    try {
      final DesktopRemoteWindowPort window = await future;
      if (!_isCreationGenerationCurrent(instanceId, generation) || _disposed) {
        await window.requestClose();
        throw StateError('selector window 创建已取消: instance=$instanceId');
      }
      final DesktopWindowRef ref =
          _lifecycleRegistry.currentRef(
            role: DesktopWindowRole.selector,
            instanceId: instanceId,
          ) ??
          _lifecycleRegistry.registerWindow(
            role: DesktopWindowRole.selector,
            instanceId: instanceId,
            observedState: DesktopWindowObservedState.ready,
            desiredState: DesktopWindowDesiredState.hidden,
          );
      _windows[instanceId] = DesktopSelectorWindowEntry(
        window: window,
        ref: ref,
      );
      return window;
    } finally {
      _windowCreations.remove(instanceId);
    }
  }

  Future<DesktopRemoteWindowPort> _createWindow(
    int instanceId, {
    required int generation,
  }) async {
    final String hostWindowId = await _resolveHostWindowId();
    if (!_isCreationGenerationCurrent(instanceId, generation) || _disposed) {
      throw StateError('selector window 创建已取消: instance=$instanceId');
    }
    final DesktopWindowRef ref = _lifecycleRegistry.registerWindow(
      role: DesktopWindowRole.selector,
      instanceId: instanceId,
      observedState: DesktopWindowObservedState.creating,
      desiredState: DesktopWindowDesiredState.hidden,
    );
    final DesktopRemoteWindowPort window = await _multiWindowPort.createWindow(
      arguments: ref.toLaunchArguments(hostWindowId: hostWindowId),
    );
    if (!_isCreationGenerationCurrent(instanceId, generation) || _disposed) {
      await window.requestClose();
      _lifecycleRegistry.markClosed(ref, reason: 'selector-create-cancelled');
      throw StateError('selector window 创建已取消: instance=$instanceId');
    }
    _lifecycleRegistry.attachWindowId(
      ref,
      window.windowId,
      reason: 'selector-window-created',
    );
    await retryWindowChannel(
      () => window.setTitle('LDDC Lyrics Selector [$instanceId]'),
      instanceId: instanceId,
      operation: 'setSelectorWindowTitle',
    );
    if (!_isCreationGenerationCurrent(instanceId, generation) || _disposed) {
      await window.requestClose();
      _lifecycleRegistry.markClosed(ref, reason: 'selector-create-cancelled');
      throw StateError('selector window 创建已取消: instance=$instanceId');
    }
    _lifecycleRegistry.upsertObserved(
      ref,
      DesktopWindowObservedState.ready,
      reason: 'selector-window-ready',
    );
    // 选择器首次创建后默认保持隐藏态，只有 showSelectorWindow 会切到可见。
    return window;
  }

  int _nextCreationGeneration(int instanceId) {
    final int next = (_creationGenerations[instanceId] ?? 0) + 1;
    _creationGenerations[instanceId] = next;
    return next;
  }

  bool _isCreationGenerationCurrent(int instanceId, int generation) {
    return (_creationGenerations[instanceId] ?? 0) == generation;
  }

  void _applyIntentSideEffects(DesktopSelectorWindowIntent intent) {
    final DesktopSelectorWindowEntry? entry = _windows[intent.instanceId];
    if (entry == null) {
      return;
    }
    switch (intent) {
      case DesktopSelectorWindowHiddenIntent():
        final DesktopSelectorWindowEntry hidden = entry.copyWith(
          visible: false,
        );
        _windows[intent.instanceId] = hidden;
        _lifecycleRegistry.setDesired(
          hidden.ref,
          DesktopWindowDesiredState.hidden,
          reason: 'selector-hidden-intent',
        );
        _lifecycleRegistry.upsertObserved(
          hidden.ref,
          DesktopWindowObservedState.ready,
          reason: 'selector-hidden-intent',
        );
      case DesktopSelectorLyricsSelectedIntent():
        break;
    }
  }

  Future<Object?> _handleHostIntent(String method, Object? arguments) async {
    final DesktopSelectorWindowIntent? intent =
        DesktopWindowPayloadCodec.decodeSelectorIntent(method, arguments);
    final DesktopSelectorWindowIntentHandler? handler = _intentHandler;
    if (intent == null || handler == null) {
      return false;
    }
    _applyIntentSideEffects(intent);
    return handler(intent);
  }

  Future<String> _resolveHostWindowId() async {
    _hostWindowId = await resolveDesktopHostWindowId(
      cachedHostWindowId: _hostWindowId,
      lifecycleRegistry: _lifecycleRegistry,
      multiWindowPort: _multiWindowPort,
      attachReason: 'selector-host-resolve-main-window',
    );
    return _hostWindowId!;
  }
}
