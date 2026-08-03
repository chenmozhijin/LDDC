import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../../../core/logging/logging.dart';
import 'embedded_panel_channel.dart';
import 'windows_desktop_panel_host_adapter.dart';

final AppLogger _panelHostLogger = AppLogger.scope('panel-host');

typedef EmbeddedPanelChannelFactory =
    EmbeddedPanelMethodChannelPort Function(String channelName);

/// Windows embedded Panel 的唯一生产宿主。
///
/// 每个 Panel 只持有一个 child engine、一个 channel handler 和一份最新状态。
/// 所有显示等待都按 revision latest-wins，不排队保存历史内容或 surface。
class WindowsEmbeddedPanelWindowHost implements DesktopPanelWindowHostPort {
  WindowsEmbeddedPanelWindowHost({
    required DesktopSceneStorePort sceneStore,
    DesktopWindowLifecycleRegistry? lifecycleRegistry,
    DesktopWindowsPanelShellPort? panelShellPort,
    Duration channelOperationTimeout = const Duration(seconds: 2),
    EmbeddedPanelChannelFactory? channelFactory,
  }) : _sceneStore = sceneStore,
       _lifecycleRegistry =
           lifecycleRegistry ??
           DesktopWindowLifecycleRegistryController.instance,
       _panelShellPort = panelShellPort ?? WindowsDesktopPanelHostAdapter(),
       _channelOperationTimeout = _requirePositiveDuration(
         channelOperationTimeout,
         'channelOperationTimeout',
       ),
       _channelFactory =
           channelFactory ??
           ((String name) => EmbeddedPanelMethodChannel(name));

  final DesktopSceneStorePort _sceneStore;
  final DesktopWindowLifecycleRegistry _lifecycleRegistry;
  final DesktopWindowsPanelShellPort _panelShellPort;
  final Duration _channelOperationTimeout;
  final EmbeddedPanelChannelFactory _channelFactory;
  final Map<_PanelWindowKey, _EmbeddedPanelEntry> _entries =
      <_PanelWindowKey, _EmbeddedPanelEntry>{};
  final Map<_PanelWindowKey, Future<_EmbeddedPanelEntry>> _creations =
      <_PanelWindowKey, Future<_EmbeddedPanelEntry>>{};
  final Map<_PanelWindowKey, int> _creationTokens = <_PanelWindowKey, int>{};
  DesktopPanelWindowIntentHandler? _intentHandler;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  void setIntentHandler(DesktopPanelWindowIntentHandler? handler) {
    _intentHandler = handler;
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _intentHandler = null;
    final List<_PanelWindowKey> keys = <_PanelWindowKey>{
      ..._entries.keys,
      ..._creations.keys,
    }.toList(growable: false);
    for (final _PanelWindowKey key in keys) {
      await destroyPanel(instanceId: key.instanceId, panelId: key.panelId);
    }
    _panelShellPort.dispose();
  }

  @override
  Future<void> createPanel({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    DesktopPanelWindowSnapshot? initialSnapshot,
    PanelSurfaceUpdate? initialSurface,
  }) async {
    final _EmbeddedPanelEntry entry = await _ensureEntry(
      instanceId: instanceId,
      panelId: panelId,
      hostWindowId: hostWindowId,
      initialSurface: initialSurface,
    );
    if (initialSnapshot != null) {
      await _syncPanelState(entry, initialSnapshot);
    }
    entry.desiredVisible = initialSurface?.visible ?? false;
    await _reconcileVisibility(entry);
  }

  @override
  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  }) async {
    for (final int panelId in panelIds) {
      final _EmbeddedPanelEntry? entry =
          _entries[(instanceId: instanceId, panelId: panelId)];
      if (entry == null || entry.destroyed) {
        continue;
      }
      await _syncPanelState(entry, snapshot);
    }
  }

  @override
  Future<void> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {
    final _EmbeddedPanelEntry? entry =
        _entries[(instanceId: instanceId, panelId: panelId)];
    if (entry == null || entry.destroyed) {
      return;
    }
    entry.desiredVisible = update.visible;
    if (!update.visible && entry.nativeVisible) {
      await _setNativeVisibility(entry, false);
    }
    final DesktopPanelSurfaceState surface = await _panelShellPort
        .updatePanelSurface(
          instanceId: instanceId,
          panelId: panelId,
          update: update,
        );
    entry.surface = surface;
    await _sendSurfaceState(entry);
    if (entry.nativeVisible) {
      // 可见 resize 直接让原生 root 跟随 foobar，渲染层继续保留上一完整帧。
      return;
    }
    await _reconcileVisibility(entry);
  }

  @override
  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {
    final _PanelWindowKey key = (instanceId: instanceId, panelId: panelId);
    _creationTokens[key] = (_creationTokens[key] ?? 0) + 1;
    final Future<_EmbeddedPanelEntry>? creating = _creations.remove(key);
    final _EmbeddedPanelEntry? existing = _entries.remove(key);
    if (existing != null) {
      await _destroyEntry(key, existing);
    }
    if (creating != null) {
      try {
        final _EmbeddedPanelEntry created = await creating;
        if (!identical(existing, created)) {
          await _destroyEntry(key, created);
        }
      } on Object {
        // 创建失败路径已经自行清理原生 root 与 channel。
      }
    }
  }

  Future<_EmbeddedPanelEntry> _ensureEntry({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    PanelSurfaceUpdate? initialSurface,
  }) async {
    if (_disposed) {
      throw StateError('embedded panel host 已释放');
    }
    final _PanelWindowKey key = (instanceId: instanceId, panelId: panelId);
    final _EmbeddedPanelEntry? existing = _entries[key];
    if (existing != null) {
      if (existing.hostWindowId == hostWindowId) {
        return existing;
      }
      await destroyPanel(instanceId: instanceId, panelId: panelId);
    }
    final Future<_EmbeddedPanelEntry>? creating = _creations[key];
    if (creating != null) {
      return creating;
    }
    final int token = _creationTokens[key] ?? 0;
    final Future<_EmbeddedPanelEntry> future = _createEntry(
      key: key,
      hostWindowId: hostWindowId,
      initialSurface: initialSurface,
      creationToken: token,
    );
    _creations[key] = future;
    try {
      final _EmbeddedPanelEntry entry = await future;
      if (_disposed || (_creationTokens[key] ?? 0) != token) {
        await _destroyEntry(key, entry);
        throw StateError('embedded panel 创建已取消');
      }
      _entries[key] = entry;
      return entry;
    } finally {
      if (identical(_creations[key], future)) {
        _creations.remove(key);
      }
    }
  }

  Future<_EmbeddedPanelEntry> _createEntry({
    required _PanelWindowKey key,
    required int hostWindowId,
    required PanelSurfaceUpdate? initialSurface,
    required int creationToken,
  }) async {
    final DesktopWindowRef ref = _lifecycleRegistry.registerWindow(
      role: DesktopWindowRole.panel,
      instanceId: key.instanceId,
      panelId: key.panelId,
      observedState: DesktopWindowObservedState.creating,
      desiredState: DesktopWindowDesiredState.hidden,
    );
    final String channelName =
        'lddc.panel.runtime/${key.instanceId}/${key.panelId}/${ref.generation}';
    final EmbeddedPanelMethodChannelPort channel = _channelFactory(channelName);
    final _EmbeddedPanelEntry entry = _EmbeddedPanelEntry(
      ref: ref,
      hostWindowId: hostWindowId,
      channelName: channelName,
      channel: channel,
      desiredVisible: initialSurface?.visible ?? false,
    );
    try {
      await channel.setMethodCallHandler((MethodCall call) {
        return _handleRuntimeCall(entry, call);
      });
      _lifecycleRegistry.attachWindowId(
        ref,
        'embedded-panel/${key.instanceId}/${key.panelId}/${ref.generation}',
        reason: 'embedded-panel-channel-bound',
      );
      final DesktopPanelSurfaceState surface = await _panelShellPort
          .createPanel(
            request: DesktopPanelCreateRequest(
              instanceId: key.instanceId,
              panelId: key.panelId,
              hostWindowId: hostWindowId,
              channelName: channelName,
              generation: ref.generation,
              initialSurface: initialSurface,
            ),
          );
      entry.surface = surface;
      await entry.runtimeReady.future.timeout(_channelOperationTimeout);
      if (_disposed || (_creationTokens[key] ?? 0) != creationToken) {
        throw StateError('embedded panel 创建已取消');
      }
      await _sendSurfaceState(entry);
      _lifecycleRegistry.upsertObserved(
        ref,
        DesktopWindowObservedState.ready,
        reason: 'embedded-panel-runtime-ready',
      );
      return entry;
    } on Object catch (error, stackTrace) {
      try {
        await channel.setMethodCallHandler(null);
      } on Object catch (cleanupError, cleanupStackTrace) {
        _panelHostLogger.warning(
          'panel channel detach failed after create error'
          ' instance=${key.instanceId} panel=${key.panelId}'
          ' error=$cleanupError stack=$cleanupStackTrace',
        );
      }
      try {
        await _panelShellPort.destroyPanel(
          instanceId: key.instanceId,
          panelId: key.panelId,
        );
      } on Object catch (cleanupError, cleanupStackTrace) {
        _panelHostLogger.warning(
          'panel native cleanup failed after create error'
          ' instance=${key.instanceId} panel=${key.panelId}'
          ' error=$cleanupError stack=$cleanupStackTrace',
        );
      }
      _lifecycleRegistry.markUnreachable(
        ref,
        reason: 'embedded-panel-create-failed',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Object?> _handleRuntimeCall(
    _EmbeddedPanelEntry entry,
    MethodCall call,
  ) async {
    if (entry.destroyed) {
      return false;
    }
    switch (call.method) {
      case DesktopWindowMethodNames.panelRuntimeReady:
        if (!entry.runtimeReady.isCompleted) {
          entry.runtimeReady.complete();
        }
        return true;
      case DesktopWindowMethodNames.panelPresentationReady:
        final DesktopPanelPresentationReady ready =
            DesktopWindowPayloadCodec.decodePanelPresentationReady(
              call.arguments,
            );
        entry.lastPresentationReady = ready;
        final _PanelPresentationWaiter? waiter = entry.presentationWaiter;
        if (waiter != null && waiter.matches(ready)) {
          waiter.complete();
        }
        return true;
      case DesktopWindowMethodNames.panelActionIntent:
        final DesktopPanelWindowIntent? intent =
            DesktopWindowPayloadCodec.decodePanelIntent(
              call.method,
              call.arguments,
            );
        final DesktopPanelWindowIntentHandler? handler = _intentHandler;
        if (intent == null || handler == null) {
          return false;
        }
        return handler(intent);
      default:
        throw MissingPluginException(
          '未实现的 embedded panel runtime 方法: ${call.method}',
        );
    }
  }

  Future<void> _syncPanelState(
    _EmbeddedPanelEntry entry,
    DesktopPanelWindowSnapshot snapshot,
  ) async {
    final bool contentChanged =
        !_panelSessionEquals(entry.lastSession, snapshot.session) ||
        !desktopSceneRefEquals(entry.lastSceneRef, snapshot.sceneRef);
    if (contentChanged) {
      final bool sceneChanged = !desktopSceneRefEquals(
        entry.lastSceneRef,
        snapshot.sceneRef,
      );
      final Uint8List? sceneBytes = !sceneChanged || snapshot.sceneRef == null
          ? null
          : _sceneStore.getScene(snapshot.sceneRef!.sceneId);
      final int contentRevision = entry.contentRevision + 1;
      await _invoke<void>(
        entry,
        DesktopWindowMethodNames.panelApplyContent,
        DesktopWindowPayloadCodec.encodePanelContentPayload(
          DesktopPanelContentPayload(
            contentRevision: contentRevision,
            session: snapshot.session,
            sceneRef: snapshot.sceneRef,
            sceneBytes: sceneBytes,
          ),
        ),
      );
      entry
        ..contentRevision = contentRevision
        ..lastSession = snapshot.session
        ..lastSceneRef = snapshot.sceneRef;
      _markPresentationDirty(entry);
    }
    if (!_panelAnchorEquals(entry.lastAnchor, snapshot.anchor)) {
      await _invoke<void>(
        entry,
        DesktopWindowMethodNames.panelSyncAnchor,
        DesktopWindowPayloadCodec.encodePanelAnchorSnapshot(snapshot.anchor),
      );
      entry.lastAnchor = snapshot.anchor;
    }
    await _reconcileVisibility(entry);
  }

  Future<void> _sendSurfaceState(_EmbeddedPanelEntry entry) async {
    final DesktopPanelSurfaceState? surface = entry.surface;
    if (surface == null) {
      return;
    }
    await _invoke<void>(
      entry,
      DesktopWindowMethodNames.panelSurfaceStateSync,
      surface.toPayload(),
    );
    _markPresentationDirty(entry);
  }

  void _markPresentationDirty(_EmbeddedPanelEntry entry) {
    final _PanelPresentationWaiter? waiter = entry.presentationWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeSuperseded();
    }
    entry.presentationWaiter = null;
    entry.visibilityDirty = true;
  }

  Future<void> _reconcileVisibility(_EmbeddedPanelEntry entry) {
    if (entry.destroyed) {
      return Future<void>.value();
    }
    entry.visibilityDirty = true;
    final Future<void>? running = entry.visibilityTask;
    if (running != null) {
      return running;
    }
    late final Future<void> task;
    task = _runVisibilityLoop(entry).whenComplete(() {
      if (identical(entry.visibilityTask, task)) {
        entry.visibilityTask = null;
      }
    });
    entry.visibilityTask = task;
    return task;
  }

  Future<void> _runVisibilityLoop(_EmbeddedPanelEntry entry) async {
    while (!entry.destroyed && entry.visibilityDirty) {
      entry.visibilityDirty = false;
      if (!entry.desiredVisible) {
        if (entry.nativeVisible) {
          await _setNativeVisibility(entry, false);
        }
        continue;
      }
      if (entry.nativeVisible) {
        continue;
      }
      final DesktopPanelSurfaceState? surface = entry.surface;
      if (surface == null || !surface.surfaceReady) {
        continue;
      }
      final _PanelPresentationTarget target = _PanelPresentationTarget(
        contentRevision: entry.contentRevision,
        surfaceRevision: surface.surfaceRevision,
      );
      final bool ready = await _awaitPresentation(entry, target);
      if (!ready || entry.destroyed || !entry.desiredVisible) {
        continue;
      }
      final DesktopPanelSurfaceState? latestSurface = entry.surface;
      if (entry.contentRevision != target.contentRevision ||
          latestSurface?.surfaceRevision != target.surfaceRevision) {
        entry.visibilityDirty = true;
        continue;
      }
      await _setNativeVisibility(entry, true);
    }
  }

  Future<bool> _awaitPresentation(
    _EmbeddedPanelEntry entry,
    _PanelPresentationTarget target,
  ) async {
    if (target.matches(entry.lastPresentationReady)) {
      return true;
    }
    final _PanelPresentationWaiter waiter = _PanelPresentationWaiter(target);
    entry.presentationWaiter = waiter;
    try {
      return await waiter.future.timeout(_channelOperationTimeout);
    } on TimeoutException {
      if (identical(entry.presentationWaiter, waiter)) {
        entry.presentationWaiter = null;
      }
      _panelHostLogger.warning(
        'panel presentation timeout instance=${entry.ref.instanceId}'
        ' panel=${entry.ref.panelId}'
        ' content=${target.contentRevision}'
        ' surface=${target.surfaceRevision}',
      );
      return false;
    }
  }

  Future<void> _setNativeVisibility(
    _EmbeddedPanelEntry entry,
    bool visible,
  ) async {
    await _panelShellPort.setPanelVisibility(
      instanceId: entry.ref.instanceId!,
      panelId: entry.ref.panelId!,
      visible: visible,
    );
    entry.nativeVisible = visible;
    final DesktopPanelSurfaceState? surface = entry.surface;
    if (surface != null && surface.visible != visible) {
      entry.surface = DesktopPanelSurfaceState(
        surfaceRevision: surface.surfaceRevision,
        attached: surface.attached,
        visible: visible,
        clientSizePx: surface.clientSizePx,
        dpi: surface.dpi,
      );
      await _sendSurfaceState(entry);
    }
    _lifecycleRegistry.upsertObserved(
      entry.ref,
      visible
          ? DesktopWindowObservedState.visible
          : DesktopWindowObservedState.ready,
      reason: visible ? 'embedded-panel-visible' : 'embedded-panel-hidden',
    );
  }

  Future<T?> _invoke<T>(
    _EmbeddedPanelEntry entry,
    String method,
    Object? arguments,
  ) {
    return entry.channel
        .invokeMethod<T>(method, arguments)
        .timeout(_channelOperationTimeout);
  }

  Future<void> _destroyEntry(
    _PanelWindowKey key,
    _EmbeddedPanelEntry entry,
  ) async {
    if (entry.destroyed) {
      return;
    }
    entry.destroyed = true;
    entry.presentationWaiter?.completeSuperseded();
    entry.presentationWaiter = null;
    _lifecycleRegistry.markCommandIssued(
      entry.ref,
      observedState: DesktopWindowObservedState.closing,
      desiredState: DesktopWindowDesiredState.absent,
      reason: 'embedded-panel-destroy-issued',
    );
    try {
      await entry.channel.setMethodCallHandler(null);
    } on Object catch (error, stackTrace) {
      _panelHostLogger.warning(
        'panel channel detach failed during destroy'
        ' instance=${key.instanceId} panel=${key.panelId}'
        ' error=$error stack=$stackTrace',
      );
    }
    try {
      await _panelShellPort.destroyPanel(
        instanceId: key.instanceId,
        panelId: key.panelId,
      );
    } on Object catch (error, stackTrace) {
      _lifecycleRegistry.markUnreachable(
        entry.ref,
        reason: 'embedded-panel-destroy-failed',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    _lifecycleRegistry.markClosed(
      entry.ref,
      reason: 'embedded-panel-destroyed',
    );
  }
}

Duration _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, '超时时间必须大于零');
  }
  return value;
}

class _EmbeddedPanelEntry {
  _EmbeddedPanelEntry({
    required this.ref,
    required this.hostWindowId,
    required this.channelName,
    required this.channel,
    required this.desiredVisible,
  });

  final DesktopWindowRef ref;
  final int hostWindowId;
  final String channelName;
  final EmbeddedPanelMethodChannelPort channel;
  final Completer<void> runtimeReady = Completer<void>();
  DesktopPanelSurfaceState? surface;
  DesktopPanelSessionSnapshot? lastSession;
  DesktopSceneRef? lastSceneRef;
  DesktopPanelAnchorSnapshot? lastAnchor;
  DesktopPanelPresentationReady? lastPresentationReady;
  _PanelPresentationWaiter? presentationWaiter;
  Future<void>? visibilityTask;
  int contentRevision = 0;
  bool desiredVisible;
  bool nativeVisible = false;
  bool visibilityDirty = false;
  bool destroyed = false;
}

class _PanelPresentationTarget {
  const _PanelPresentationTarget({
    required this.contentRevision,
    required this.surfaceRevision,
  });

  final int contentRevision;
  final int surfaceRevision;

  bool matches(DesktopPanelPresentationReady? ready) {
    return ready?.contentRevision == contentRevision &&
        ready?.surfaceRevision == surfaceRevision;
  }
}

class _PanelPresentationWaiter {
  _PanelPresentationWaiter(this.target);

  final _PanelPresentationTarget target;
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> get future => _completer.future;
  bool get isCompleted => _completer.isCompleted;

  bool matches(DesktopPanelPresentationReady ready) => target.matches(ready);

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete(true);
    }
  }

  void completeSuperseded() {
    if (!_completer.isCompleted) {
      _completer.complete(false);
    }
  }
}

typedef _PanelWindowKey = ({int instanceId, int panelId});

bool _panelSessionEquals(
  DesktopPanelSessionSnapshot? left,
  DesktopPanelSessionSnapshot right,
) {
  if (left == null) {
    return false;
  }
  return left.songId == right.songId &&
      desktopStringListEquals(left.enabledLangs, right.enabledLangs) &&
      desktopRgbColorListEquals(left.playedColors, right.playedColors) &&
      desktopRgbColorListEquals(left.unplayedColors, right.unplayedColors) &&
      left.fontFamily == right.fontFamily &&
      left.fontSize == right.fontSize &&
      left.showFurigana == right.showFurigana &&
      left.refreshRate == right.refreshRate &&
      left.visible == right.visible &&
      desktopWindowActionEquals(left.actions, right.actions);
}

bool _panelAnchorEquals(
  DesktopPanelAnchorSnapshot? left,
  DesktopPanelAnchorSnapshot right,
) {
  if (left == null) {
    return false;
  }
  return left.pluginPlaybackTimeMs == right.pluginPlaybackTimeMs &&
      left.pluginSendTimeMs == right.pluginSendTimeMs &&
      left.hostReceivedAtMs == right.hostReceivedAtMs &&
      left.isPlaying == right.isPlaying &&
      left.syncRevision == right.syncRevision &&
      left.eventKind == right.eventKind &&
      left.sceneId == right.sceneId &&
      left.songToken == right.songToken;
}
