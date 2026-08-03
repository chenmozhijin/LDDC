import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import '../logging/desktop_lyrics_logger.dart';

import '../models/desktop_style_models.dart';
import '../projection/desktop_lyrics_scene.dart';
import 'desktop_host_intent_router.dart';
import 'desktop_host_window_common.dart';
import 'desktop_multi_window_port.dart';
import 'desktop_window_backend.dart';
import 'desktop_window_launch.dart';
import 'desktop_window_lifecycle.dart';
import 'desktop_window_method_names.dart';
import 'desktop_window_payload_codec.dart';

/// 基于 `desktop_multi_window` 的浮窗宿主实现。
class DesktopMultiWindowFloatingWindowHost
    implements DesktopFloatingWindowHostPort {
  DesktopMultiWindowFloatingWindowHost({
    required this.sceneStore,
    DesktopMultiWindowPort? multiWindowPort,
    DesktopWindowLifecycleRegistry? lifecycleRegistry,
    DesktopMultiWindowHostIntentRouter? intentRouter,
    this.channelReadyRetryDelay = const Duration(milliseconds: 25),
    this.channelReadyRetryLimit = 20,
    this.channelOperationTimeout = const Duration(seconds: 2),
    this.windowReadyTimeout = const Duration(seconds: 15),
    DesktopLyricsLogger logger = const DesktopLyricsLogger(),
  }) : _logger = logger.child('floating-host'),
       _multiWindowPort = multiWindowPort ?? const DesktopMultiWindowAdapter(),
       _lifecycleRegistry =
           lifecycleRegistry ??
           DesktopWindowLifecycleRegistryController.instance,
       _intentRouter =
           intentRouter ??
           DesktopMultiWindowHostIntentRouter(
             multiWindowPort:
                 multiWindowPort ?? const DesktopMultiWindowAdapter(),
           ) {
    _floatingActionHandler = (Object? arguments) => _handleHostIntent(
      DesktopWindowMethodNames.floatingActionIntent,
      arguments,
    );
    _floatingMetricsHandler = (Object? arguments) => _handleHostIntent(
      DesktopWindowMethodNames.floatingMetricsCommittedIntent,
      arguments,
    );
    _intentRouter
      ..registerHandler(
        DesktopWindowMethodNames.floatingActionIntent,
        _floatingActionHandler,
      )
      ..registerHandler(
        DesktopWindowMethodNames.floatingMetricsCommittedIntent,
        _floatingMetricsHandler,
      );
  }

  final DesktopSceneStorePort sceneStore;
  final DesktopLyricsLogger _logger;
  final DesktopMultiWindowPort _multiWindowPort;
  final DesktopWindowLifecycleRegistry _lifecycleRegistry;
  final DesktopMultiWindowHostIntentRouter _intentRouter;
  final Duration channelReadyRetryDelay;
  final int channelReadyRetryLimit;
  final Duration channelOperationTimeout;
  final Duration windowReadyTimeout;
  late final DesktopHostIntentHandler _floatingActionHandler;
  late final DesktopHostIntentHandler _floatingMetricsHandler;
  final Map<int, DesktopFloatingWindowEntry> _windows =
      <int, DesktopFloatingWindowEntry>{};
  final Map<int, Future<DesktopFloatingWindowEntry>> _windowCreations =
      <int, Future<DesktopFloatingWindowEntry>>{};
  final Map<int, DesktopFloatingWindowSyncState> _syncStates =
      <int, DesktopFloatingWindowSyncState>{};
  final Map<int, int> _creationGenerations = <int, int>{};
  String? _hostWindowId;
  bool _disposed = false;
  DesktopFloatingWindowIntentHandler? _intentHandler;

  @override
  void setIntentHandler(DesktopFloatingWindowIntentHandler? handler) {
    _intentHandler = handler;
  }

  Future<T> retryWindowChannel<T>(
    Future<T> Function() action, {
    required int instanceId,
    required String operation,
    Duration? operationTimeout,
  }) async {
    return retryDesktopWindowChannel(
      action,
      instanceId: instanceId,
      operation: operation,
      retryDelay: channelReadyRetryDelay,
      retryLimit: channelReadyRetryLimit,
      operationTimeout: operationTimeout ?? channelOperationTimeout,
      logger: _logger,
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _intentRouter
      ..unregisterHandler(
        DesktopWindowMethodNames.floatingActionIntent,
        _floatingActionHandler,
      )
      ..unregisterHandler(
        DesktopWindowMethodNames.floatingMetricsCommittedIntent,
        _floatingMetricsHandler,
      );
    _intentHandler = null;
    final List<int> instanceIds = <int>{
      ..._windows.keys,
      ..._windowCreations.keys,
    }.toList(growable: false);
    for (final int instanceId in instanceIds) {
      _nextCreationGeneration(instanceId);
    }
    for (final DesktopFloatingWindowEntry entry in _windows.values.toList(
      growable: false,
    )) {
      await entry.window.requestClose();
      _lifecycleRegistry.markClosed(entry.ref, reason: 'floating-host-dispose');
    }
    _windows.clear();
    _windowCreations.clear();
    _syncStates.clear();
  }

  @override
  Future<void> destroyFloatingWindow({required int instanceId}) async {
    _nextCreationGeneration(instanceId);
    _windowCreations.remove(instanceId);
    _syncStates.remove(instanceId);
    final DesktopFloatingWindowEntry? entry = _windows.remove(instanceId);
    _logger.info(
      'destroy request instance=$instanceId'
      ' windowId=${entry?.window.windowId ?? '-'}'
      ' cachedWindow=${entry != null}',
    );
    if (entry == null) {
      return;
    }
    _lifecycleRegistry.setDesired(
      entry.ref,
      DesktopWindowDesiredState.absent,
      reason: 'floating-destroy-requested',
    );
    _lifecycleRegistry.markCommandIssued(
      entry.ref,
      observedState: DesktopWindowObservedState.closing,
      desiredState: DesktopWindowDesiredState.absent,
      reason: 'floating-request-close-issued',
    );
    await entry.window.requestClose();
    _lifecycleRegistry.markClosed(
      entry.ref,
      reason: 'floating-window-close-confirmed',
    );
    _logger.info(
      'destroy close requested instance=$instanceId'
      ' windowId=${entry.window.windowId}',
    );
  }

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    await _intentRouter.ensureBound();
    final DesktopFloatingWindowEntry entry = await _ensureWindow(
      instanceId,
      initialWindowRect: snapshot.initialWindowRect,
    );
    final DesktopFloatingWindowSyncState syncState = _syncStates.putIfAbsent(
      instanceId,
      DesktopFloatingWindowSyncState.new,
    );
    await _syncFloatingContent(
      instanceId: instanceId,
      window: entry.window,
      syncState: syncState,
      snapshot: snapshot,
    );
    await _syncFloatingAnchor(
      instanceId: instanceId,
      window: entry.window,
      syncState: syncState,
      snapshot: snapshot,
    );
    await _syncFloatingFlags(
      instanceId: instanceId,
      window: entry.window,
      syncState: syncState,
      flags: snapshot.flags,
      operation: 'applyFloatingFlags',
    );
    if (snapshot.flags.visible) {
      _lifecycleRegistry.setDesired(
        entry.ref,
        DesktopWindowDesiredState.visible,
        reason: 'floating-apply-visible',
      );
      _lifecycleRegistry.upsertObserved(
        entry.ref,
        DesktopWindowObservedState.visible,
        reason: 'floating-apply-shown',
      );
      return;
    }
    _lifecycleRegistry.setDesired(
      entry.ref,
      DesktopWindowDesiredState.hidden,
      reason: 'floating-apply-hidden',
    );
    _lifecycleRegistry.upsertObserved(
      entry.ref,
      DesktopWindowObservedState.ready,
      reason: 'floating-apply-hidden',
    );
  }

  @override
  Future<bool> flushFloatingGeometry({required int instanceId}) async {
    final DesktopFloatingWindowEntry? entry = _windows[instanceId];
    if (entry == null) {
      return true;
    }
    final Object? result = await retryWindowChannel(
      () => entry.window.invokeMethod(
        DesktopWindowMethodNames.floatingFlushGeometry,
      ),
      instanceId: instanceId,
      operation: 'floatingFlushGeometry',
    );
    return result == true;
  }

  Future<Object?> _handleHostIntent(String method, Object? arguments) async {
    final DesktopFloatingWindowIntent? intent =
        DesktopWindowPayloadCodec.decodeFloatingIntent(method, arguments);
    final DesktopFloatingWindowIntentHandler? handler = _intentHandler;
    if (intent == null || handler == null) {
      return false;
    }
    return handler(intent);
  }

  Future<DesktopFloatingWindowEntry> _ensureWindow(
    int instanceId, {
    WindowRect? initialWindowRect,
  }) async {
    if (_disposed) {
      throw StateError('floating window host 已释放，不能创建浮窗');
    }
    final DesktopFloatingWindowEntry? cached = _windows[instanceId];
    if (cached != null) {
      return cached;
    }
    final Future<DesktopFloatingWindowEntry>? creating =
        _windowCreations[instanceId];
    if (creating != null) {
      return creating;
    }
    final int generation = _creationGenerations[instanceId] ?? 0;
    final Future<DesktopFloatingWindowEntry> future = _createWindow(
      instanceId,
      generation: generation,
      initialWindowRect: initialWindowRect,
    );
    _windowCreations[instanceId] = future;
    try {
      final DesktopFloatingWindowEntry entry = await future;
      if (!_isCreationGenerationCurrent(instanceId, generation) || _disposed) {
        await entry.window.requestClose();
        _lifecycleRegistry.markClosed(
          entry.ref,
          reason: 'floating-create-cancelled',
        );
        throw StateError('floating window 创建已取消: instance=$instanceId');
      }
      _windows[instanceId] = entry;
      return entry;
    } finally {
      if (identical(_windowCreations[instanceId], future)) {
        _windowCreations.remove(instanceId);
      }
    }
  }

  Future<DesktopFloatingWindowEntry> _createWindow(
    int instanceId, {
    required int generation,
    required WindowRect? initialWindowRect,
  }) async {
    final String hostWindowId = await _resolveHostWindowId();
    if (!_isCreationGenerationCurrent(instanceId, generation) || _disposed) {
      throw StateError('floating window 创建已取消: instance=$instanceId');
    }
    final DesktopWindowRef ref = _lifecycleRegistry.registerWindow(
      role: DesktopWindowRole.floating,
      instanceId: instanceId,
      observedState: DesktopWindowObservedState.creating,
      desiredState: DesktopWindowDesiredState.hidden,
    );
    final DesktopRemoteWindowPort window = await _multiWindowPort.createWindow(
      arguments: ref.toLaunchArguments(
        hostWindowId: hostWindowId,
        initialWindowRect: initialWindowRect,
      ),
    );
    if (!_isCreationGenerationCurrent(instanceId, generation) || _disposed) {
      await window.requestClose();
      _lifecycleRegistry.markClosed(ref, reason: 'floating-create-cancelled');
      throw StateError('floating window 创建已取消: instance=$instanceId');
    }
    _lifecycleRegistry.attachWindowId(
      ref,
      window.windowId,
      reason: 'floating-window-created',
    );
    _logger.info(
      'window created instance=$instanceId'
      ' windowId=${window.windowId}'
      ' hostWindowId=$hostWindowId',
    );
    await retryWindowChannel(
      () => window.setTitle('LDDC Floating Lyrics [$instanceId]'),
      instanceId: instanceId,
      operation: 'setFloatingWindowTitle',
    );
    await retryWindowChannel(
      () async {
        final Object? ready = await window.invokeMethod(
          DesktopWindowMethodNames.floatingAwaitReady,
        );
        if (ready != true) {
          throw StateError('floating window 尚未完成初始几何配置');
        }
      },
      instanceId: instanceId,
      operation: 'awaitFloatingWindowReady',
      operationTimeout: windowReadyTimeout,
    );
    if (!_isCreationGenerationCurrent(instanceId, generation) || _disposed) {
      await window.requestClose();
      _lifecycleRegistry.markClosed(ref, reason: 'floating-create-cancelled');
      throw StateError('floating window 创建已取消: instance=$instanceId');
    }
    _lifecycleRegistry.upsertObserved(
      ref,
      DesktopWindowObservedState.ready,
      reason: 'floating-window-ready',
    );
    return DesktopFloatingWindowEntry(window: window, ref: ref);
  }

  int _nextCreationGeneration(int instanceId) {
    final int next = (_creationGenerations[instanceId] ?? 0) + 1;
    _creationGenerations[instanceId] = next;
    return next;
  }

  bool _isCreationGenerationCurrent(int instanceId, int generation) {
    return (_creationGenerations[instanceId] ?? 0) == generation;
  }

  Future<String> _resolveHostWindowId() async {
    _hostWindowId = await resolveDesktopHostWindowId(
      cachedHostWindowId: _hostWindowId,
      lifecycleRegistry: _lifecycleRegistry,
      multiWindowPort: _multiWindowPort,
      attachReason: 'floating-host-resolve-main-window',
    );
    return _hostWindowId!;
  }

  Future<void> _syncFloatingContent({
    required int instanceId,
    required DesktopRemoteWindowPort window,
    required DesktopFloatingWindowSyncState syncState,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    final DesktopSceneRef? sceneRef = snapshot.sceneRef;
    final bool sessionChanged = !desktopFloatingSessionEquals(
      syncState.lastSession,
      snapshot.session,
    );
    final bool sceneChanged = !desktopSceneRefEquals(
      syncState.lastSceneRef,
      sceneRef,
    );
    if (!sessionChanged && !sceneChanged) {
      return;
    }
    final DesktopFloatingSessionSnapshot? previousSession =
        syncState.lastSession;
    final DesktopSceneRef? previousSceneRef = syncState.lastSceneRef;
    final int revision = ++syncState.contentRevision;
    final Uint8List? sceneBytes = sceneChanged && sceneRef != null
        ? sceneStore.getScene(sceneRef.sceneId)
        : null;

    // 在 await 前先登记“已排队”的内容身份，允许更高 revision 并发进入
    // 子窗口并显式取代仍在等待布局提交的旧调用。失败时只回滚当前最新项，
    // 不能把已经排队的新内容覆盖回旧状态。
    syncState.lastSession = snapshot.session;
    syncState.lastSceneRef = sceneRef;
    try {
      await retryWindowChannel(
        () => window.invokeMethod(
          DesktopWindowMethodNames.floatingApplyContent,
          DesktopWindowPayloadCodec.encodeFloatingContentPayload(
            DesktopFloatingContentPayload(
              contentRevision: revision,
              session: snapshot.session,
              sceneRef: sceneRef,
              sceneBytes: sceneBytes,
            ),
          ),
        ),
        instanceId: instanceId,
        operation: 'floatingApplyContent',
      );
    } on Object {
      if (syncState.contentRevision == revision) {
        syncState.lastSession = previousSession;
        syncState.lastSceneRef = previousSceneRef;
      }
      rethrow;
    }
  }

  Future<void> _syncFloatingAnchor({
    required int instanceId,
    required DesktopRemoteWindowPort window,
    required DesktopFloatingWindowSyncState syncState,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {
    final DesktopFloatingAnchorSnapshot? anchor = snapshot.anchor;
    if (anchor == null ||
        desktopFloatingAnchorEquals(syncState.lastAnchor, anchor)) {
      return;
    }
    final DesktopFloatingAnchorSnapshot? previousAnchor = syncState.lastAnchor;
    syncState.lastAnchor = anchor;
    try {
      await retryWindowChannel(
        () => window.invokeMethod(
          DesktopWindowMethodNames.floatingSyncAnchor,
          DesktopWindowPayloadCodec.encodeFloatingAnchorSnapshot(anchor),
        ),
        instanceId: instanceId,
        operation: 'floatingSyncAnchor',
      );
    } on Object {
      if (identical(syncState.lastAnchor, anchor)) {
        syncState.lastAnchor = previousAnchor;
      }
      rethrow;
    }
  }

  Future<void> _syncFloatingFlags({
    required int instanceId,
    required DesktopRemoteWindowPort window,
    required DesktopFloatingWindowSyncState syncState,
    required DesktopFloatingWindowFlags flags,
    required String operation,
  }) async {
    if (desktopFloatingFlagsEquals(syncState.lastFlags, flags)) {
      return;
    }
    final DesktopFloatingWindowFlags? previousFlags = syncState.lastFlags;
    final int revision = ++syncState.flagsRevision;
    syncState.lastFlags = flags;
    try {
      await retryWindowChannel(
        () async {
          final Object? applied = await window.invokeMethod(
            DesktopWindowMethodNames.floatingUpdateFlags,
            DesktopWindowPayloadCodec.encodeFloatingFlagsPayload(
              DesktopFloatingFlagsPayload(revision: revision, flags: flags),
            ),
          );
          if (applied != true) {
            throw StateError('floating window flags 未完成原生显示事务');
          }
        },
        instanceId: instanceId,
        operation: operation,
      );
    } on Object {
      if (syncState.flagsRevision == revision) {
        syncState.lastFlags = previousFlags;
      }
      rethrow;
    }
  }
}
