import 'dart:async';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../../../core/logging/logging.dart';
import '../window/desktop_panel_snapshot_host_mapper.dart';
import 'desktop_service_coordinator.dart';
import 'desktop_session_state.dart';

final AppLogger _panelHostBridgeLogger = AppLogger.scope('panel-host-bridge');

/// Panel 宿主桥只维护协议绑定与一个 latest-wins 创建任务。
///
/// `0x0`、创建失败和 resize 都由后续真实 bind/surface IPC 事件继续驱动，
/// 不设置退避 Timer，也不在后台轮询 foobar HWND。
class DesktopPanelHostBridgeController
    implements DesktopPanelLifecycleDisposer {
  DesktopPanelHostBridgeController({
    required DesktopPanelWindowHostPort panelHost,
    required DesktopServiceCoordinator coordinator,
  }) : _panelHost = panelHost,
       _coordinator = coordinator;

  final DesktopPanelWindowHostPort _panelHost;
  final DesktopServiceCoordinator _coordinator;
  final Map<(int, int), _PanelBinding> _bindings =
      <(int, int), _PanelBinding>{};
  bool _disposed = false;
  Future<void>? _disposeFuture;

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    final List<_PanelBinding> bindings = _bindings.values.toList(
      growable: false,
    );
    _bindings.clear();
    await Future.wait(<Future<void>>[
      for (final _PanelBinding binding in bindings)
        _destroyBinding(binding, unregister: false),
    ]);
  }

  Future<void> createPanel({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
  }) async {
    if (_disposed) {
      return;
    }
    final DesktopSessionState? session = _coordinator.sessionFor(instanceId);
    if (session == null) {
      return;
    }
    final (int, int) key = (instanceId, panelId);
    final _PanelBinding? previous = _bindings[key];
    if (previous != null && previous.hostWindowId != hostWindowId) {
      _bindings.remove(key);
      await _destroyBinding(previous, unregister: false);
    }
    final _PanelBinding binding = _bindings.putIfAbsent(
      key,
      () => _PanelBinding(
        instanceId: instanceId,
        panelId: panelId,
        hostWindowId: hostWindowId,
      ),
    );
    _coordinator.registerPanelHost(
      instanceId: instanceId,
      panelId: panelId,
      hostWindowId: hostWindowId,
    );
    await _ensureCreated(binding, initialSession: session);
  }

  Future<void> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {
    if (_disposed) {
      return;
    }
    final (int, int) key = (instanceId, panelId);
    final _PanelBinding? binding = _bindings[key];
    if (binding == null) {
      return;
    }
    binding.latestSurface = update;
    _coordinator.updatePanelHostSurface(
      instanceId: instanceId,
      panelId: panelId,
      hostWindowId: binding.hostWindowId,
      width: update.width,
      height: update.height,
      visible: update.visible,
    );
    await _ensureCreated(binding);
    if (!binding.created || binding.destroyed) {
      return;
    }
    await _flushLatestSurface(binding);
  }

  Future<void> _ensureCreated(
    _PanelBinding binding, {
    DesktopSessionState? initialSession,
  }) async {
    if (_disposed || binding.destroyed || binding.created) {
      return;
    }
    final Future<void>? inFlight = binding.creation;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    late final Future<void> creation;
    creation =
        _createBinding(
          binding,
          initialSession:
              initialSession ?? _coordinator.sessionFor(binding.instanceId),
        ).whenComplete(() {
          if (identical(binding.creation, creation)) {
            binding.creation = null;
          }
        });
    binding.creation = creation;
    await creation;
  }

  Future<void> _createBinding(
    _PanelBinding binding, {
    required DesktopSessionState? initialSession,
  }) async {
    if (initialSession == null || binding.destroyed) {
      return;
    }
    try {
      await _panelHost.createPanel(
        instanceId: binding.instanceId,
        panelId: binding.panelId,
        hostWindowId: binding.hostWindowId,
        initialSurface: binding.latestSurface,
        initialSnapshot: buildDesktopPanelWindowSnapshot(initialSession),
      );
    } on DesktopPanelSurfaceUnavailable catch (error) {
      // foobar 创建 panel HWND 后可能先出现短暂 0x0 客户区。这里只保留
      // binding，等待下一次真实 surface 事件再次触发，不创建计时器。
      binding.lastFailure = error.toString();
      _panelHostBridgeLogger.info(
        'panel surface pending instance=${binding.instanceId}'
        ' panel=${binding.panelId} host=${binding.hostWindowId}',
      );
      return;
    } on Object catch (error, stackTrace) {
      binding.lastFailure = error.toString();
      _panelHostBridgeLogger.error(
        'panel create failed instance=${binding.instanceId}'
        ' panel=${binding.panelId} host=${binding.hostWindowId}'
        ' error=$error stack=$stackTrace',
      );
      return;
    }
    if (_disposed || binding.destroyed) {
      return;
    }
    binding
      ..created = true
      ..lastFailure = null;
  }

  Future<void> _flushLatestSurface(_PanelBinding binding) {
    if (binding.destroyed || !binding.created) {
      return Future<void>.value();
    }
    final PanelSurfaceUpdate? latest = binding.latestSurface;
    if (latest == null ||
        latest == binding.lastAppliedSurface ||
        latest == binding.applyingSurface ||
        latest == binding.pendingSurface) {
      return binding.surfaceTask ?? Future<void>.value();
    }
    // resize 期间只保存尚未开始的最新一份状态。正在执行的系统调用允许结束，
    // 但它完成后只能继续提交当前 pending，不能恢复被覆盖的中间尺寸。
    binding.pendingSurface = latest;
    final Future<void>? running = binding.surfaceTask;
    if (running != null) {
      return running;
    }
    late final Future<void> task;
    task = _runSurfacePump(binding).whenComplete(() {
      if (identical(binding.surfaceTask, task)) {
        binding.surfaceTask = null;
      }
    });
    binding.surfaceTask = task;
    return task;
  }

  Future<void> _runSurfacePump(_PanelBinding binding) async {
    while (!binding.destroyed) {
      final PanelSurfaceUpdate? update = binding.pendingSurface;
      if (update == null) {
        return;
      }
      binding.pendingSurface = null;
      binding.applyingSurface = update;
      try {
        await _panelHost.updatePanelSurface(
          instanceId: binding.instanceId,
          panelId: binding.panelId,
          update: update,
        );
        if (!binding.destroyed) {
          binding
            ..lastAppliedSurface = update
            ..lastFailure = null;
        }
      } on Object catch (error, stackTrace) {
        // 失败的系统调用已经结束，可以安全等待下一次真实 surface 事件重试。
        // 这里不能把同一 update 立即塞回 pending，否则持续故障会形成自旋；
        // 也不能让异常逃出泵，否则销毁流程等待 surfaceTask 时会跳过 destroy。
        binding.lastFailure = error.toString();
        _panelHostBridgeLogger.error(
          'panel surface update failed instance=${binding.instanceId}'
          ' panel=${binding.panelId} error=$error stack=$stackTrace',
        );
      } finally {
        if (binding.applyingSurface == update) {
          binding.applyingSurface = null;
        }
      }
    }
  }

  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {
    if (_disposed) {
      return;
    }
    final _PanelBinding? binding = _bindings.remove((instanceId, panelId));
    _coordinator.unregisterPanelHost(instanceId: instanceId, panelId: panelId);
    if (binding == null) {
      await _panelHost.destroyPanel(instanceId: instanceId, panelId: panelId);
      return;
    }
    await _destroyBinding(binding, unregister: false);
  }

  Future<void> _destroyBinding(
    _PanelBinding binding, {
    required bool unregister,
  }) async {
    if (binding.destroyed) {
      return;
    }
    binding.destroyed = true;
    if (unregister) {
      _coordinator.unregisterPanelHost(
        instanceId: binding.instanceId,
        panelId: binding.panelId,
      );
    }
    final Future<void>? creation = binding.creation;
    try {
      if (creation != null) {
        await creation;
      }
      final Future<void>? surfaceTask = binding.surfaceTask;
      if (surfaceTask != null) {
        await surfaceTask;
      }
    } on Object catch (error, stackTrace) {
      // 创建或 resize 的意外失败不能阻止最终原生销毁；否则 binding 虽已
      // 从 Map 移除，窗口句柄却仍可能留在 Windows 宿主中。
      _panelHostBridgeLogger.error(
        'panel pending task failed during destroy'
        ' instance=${binding.instanceId} panel=${binding.panelId}'
        ' error=$error stack=$stackTrace',
      );
    }
    await _panelHost.destroyPanel(
      instanceId: binding.instanceId,
      panelId: binding.panelId,
    );
  }

  @override
  Future<void> destroyPanelsForInstance({
    required int instanceId,
    required Iterable<int> panelIds,
  }) async {
    if (_disposed) {
      return;
    }
    final Set<int> ids = <int>{...panelIds};
    for (final (int mappedInstanceId, int panelId) in _bindings.keys) {
      if (mappedInstanceId == instanceId) {
        ids.add(panelId);
      }
    }
    for (final int panelId in ids) {
      await destroyPanel(instanceId: instanceId, panelId: panelId);
    }
  }
}

class _PanelBinding {
  _PanelBinding({
    required this.instanceId,
    required this.panelId,
    required this.hostWindowId,
  });

  final int instanceId;
  final int panelId;
  final int hostWindowId;
  PanelSurfaceUpdate? latestSurface;
  PanelSurfaceUpdate? pendingSurface;
  PanelSurfaceUpdate? applyingSurface;
  PanelSurfaceUpdate? lastAppliedSurface;
  Future<void>? creation;
  Future<void>? surfaceTask;
  String? lastFailure;
  bool created = false;
  bool destroyed = false;
}
