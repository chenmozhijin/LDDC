import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../logging/desktop_lyrics_logger.dart';
import 'package:window_manager/window_manager.dart';

import '../projection/desktop_lyrics_scene.dart';
import '../render/desktop_lyrics_perf_stats.dart';
import 'desktop_multi_window_port.dart';
import 'desktop_window_backend.dart';
import 'desktop_window_launch.dart';
import 'desktop_window_lifecycle.dart';
import 'desktop_window_method_names.dart';
import 'desktop_window_payload_codec.dart';

typedef DesktopFloatingGeometryFlushHandler = Future<bool> Function();
typedef DesktopFloatingFlagsApplyHandler =
    Future<bool> Function(DesktopFloatingWindowFlags flags);
typedef DesktopSubWindowRootDetachHandler = Future<void> Function();
typedef DesktopSubWindowPrepareCloseHandler = Future<void> Function();
typedef DesktopSubWindowHostResourceDrainHandler = Future<void> Function();
typedef DesktopSelectorRuntimeDiagnosticsProvider =
    DesktopSelectorRuntimeDiagnostics Function();
typedef DesktopSelectorConfigRefreshHandler =
    Future<void> Function(int revision);

/// 子窗口运行时单例。
///
/// 作用：
/// - 在 `runApp` 前绑定当前 engine 的窗口方法处理器，避免首帧消息丢失。
/// - 缓存浮窗快照与选择器上下文，供窗口壳直接消费。
class DesktopSubWindowRuntime {
  DesktopSubWindowRuntime._();

  static final DesktopSubWindowRuntime instance = DesktopSubWindowRuntime._();

  DesktopWindowLaunchArguments _launch =
      const DesktopWindowLaunchArguments.main();
  DesktopMultiWindowPort _multiWindowPort = const DesktopMultiWindowAdapter();
  DesktopWindowLifecycleRegistry _lifecycleRegistry =
      DesktopWindowLifecycleRegistryController.instance;
  DesktopRemoteWindowPort? _currentWindow;
  DesktopWindowRef? _currentWindowRef;
  Duration _notifyHostTimeout = const Duration(milliseconds: 150);
  final Duration _actionNotifyHostTimeout = const Duration(seconds: 2);
  DesktopFloatingGeometryFlushHandler? _floatingGeometryFlushHandler;
  DesktopFloatingFlagsApplyHandler? _floatingFlagsApplyHandler;
  DesktopSelectorRuntimeDiagnosticsProvider?
  _selectorRuntimeDiagnosticsProvider;
  DesktopSelectorConfigRefreshHandler? _selectorConfigRefreshHandler;
  DesktopSubWindowPrepareCloseHandler? _prepareCloseHandler;
  DesktopSubWindowRootDetachHandler _rootDetachHandler =
      _detachDesktopSubWindowRoot;
  DesktopSubWindowHostResourceDrainHandler _hostResourceDrainHandler =
      _noopHostResourceDrain;
  DesktopLyricsLogger _subWindowRuntimeLogger = const DesktopLyricsLogger(
    scope: 'desktop-lyrics/sub-window-runtime',
  );
  Completer<void> _floatingWindowReady = Completer<void>();
  Timer? _closeTimer;
  String? _floatingWindowConfigurationError;
  int _floatingFlagsRevision = 0;
  int _latestSelectorConfigRevision = 0;
  int _appliedSelectorConfigRevision = 0;
  Future<void> _selectorConfigRefreshBarrier = Future<void>.value();

  DesktopWindowLaunchArguments get launch => _launch;
  String? get currentWindowId => _currentWindow?.windowId;

  final ValueNotifier<DesktopFloatingContentState?> floatingContent =
      ValueNotifier<DesktopFloatingContentState?>(null);
  final ValueNotifier<DesktopSelectorWindowContext?> selectorContext =
      ValueNotifier<DesktopSelectorWindowContext?>(null);

  Future<DesktopWindowLaunchArguments> ensureInitialized({
    DesktopMultiWindowPort? multiWindowPort,
    DesktopWindowLifecycleRegistry? lifecycleRegistry,
    Duration notifyHostTimeout = const Duration(milliseconds: 150),
    Duration currentWindowRetryDelay = const Duration(milliseconds: 25),
    int currentWindowRetryLimit = 40,
    DesktopSubWindowRootDetachHandler? rootDetachHandler,
    DesktopSubWindowHostResourceDrainHandler? drainHostResources,
    DesktopLyricsLogger? logger,
  }) async {
    _subWindowRuntimeLogger =
        logger ??
        const DesktopLyricsLogger(scope: 'desktop-lyrics/sub-window-runtime');
    _hostResourceDrainHandler = drainHostResources ?? _noopHostResourceDrain;
    if (!_supportsDesktopSubWindow()) {
      _launch = const DesktopWindowLaunchArguments.main();
      _currentWindowRef = null;
      _subWindowRuntimeLogger.info(
        'ensureInitialized fallback role=main reason=unsupported-platform',
      );
      return _launch;
    }
    _multiWindowPort = multiWindowPort ?? const DesktopMultiWindowAdapter();
    _lifecycleRegistry =
        lifecycleRegistry ?? DesktopWindowLifecycleRegistryController.instance;
    _notifyHostTimeout = notifyHostTimeout;
    _rootDetachHandler = rootDetachHandler ?? _detachDesktopSubWindowRoot;
    _currentWindow = await _resolveCurrentWindow(
      retryDelay: currentWindowRetryDelay,
      retryLimit: currentWindowRetryLimit,
    );
    _launch = DesktopWindowLaunchArguments.decode(_currentWindow!.arguments);
    _bindCurrentWindowLifecycle();
    _subWindowRuntimeLogger.info(
      'ensureInitialized role=${_launch.role.name}'
      ' instance=${_launch.instanceId ?? '-'}'
      ' panel=${_launch.panelId ?? '-'}'
      ' windowId=${_currentWindow?.windowId ?? '-'}'
      ' hostWindowId=${_launch.hostWindowId ?? '-'}'
      ' generation=${_launch.generation ?? '-'}',
    );
    if (_launch.role != DesktopWindowRole.main) {
      await windowManager.ensureInitialized();
      await _currentWindow!.setMethodHandler(_handleMethodCall);
      if (_currentWindowRef case final DesktopWindowRef ref) {
        _lifecycleRegistry.upsertObserved(
          ref,
          DesktopWindowObservedState.ready,
          windowId: _currentWindow?.windowId,
          reason: 'subwindow-runtime-bound',
        );
      }
      _subWindowRuntimeLogger.info(
        'method handler bound role=${_launch.role.name}'
        ' instance=${_launch.instanceId ?? '-'}'
        ' panel=${_launch.panelId ?? '-'}',
      );
    }
    return _launch;
  }

  Future<DesktopRemoteWindowPort> _resolveCurrentWindow({
    required Duration retryDelay,
    required int retryLimit,
  }) async {
    if (retryLimit <= 0) {
      throw ArgumentError.value(retryLimit, 'retryLimit', '必须大于 0');
    }
    for (int attempt = 1; attempt <= retryLimit; attempt += 1) {
      try {
        return await _multiWindowPort.currentWindow();
      } on Object catch (error) {
        final bool canRetry =
            isDesktopWindowChannelUnregistered(error) && attempt < retryLimit;
        _subWindowRuntimeLogger.info(
          'current window resolve failed'
          ' attempt=$attempt/$retryLimit error=$error retry=$canRetry',
        );
        if (!canRetry) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay);
      }
    }
    throw StateError('当前桌面子窗口解析未返回结果');
  }

  /// 解除当前 engine 的方法通道和延迟关闭任务。
  ///
  /// lifecycle registry 与宿主资源由调用方拥有，这里只释放 runtime 自己建立的
  /// 监听和缓存；保留 notifier 对象以允许同一测试 isolate 再次初始化单例。
  Future<void> dispose() async {
    _closeTimer?.cancel();
    _closeTimer = null;
    final DesktopRemoteWindowPort? oldWindow = _currentWindow;
    _currentWindow = null;
    if (oldWindow != null) {
      await oldWindow.setMethodHandler(null);
    }
    if (!_floatingWindowReady.isCompleted) {
      _floatingWindowConfigurationError = '子窗口运行时已释放';
      _floatingWindowReady.complete();
      await Future<void>.delayed(Duration.zero);
    }
    _launch = const DesktopWindowLaunchArguments.main();
    _currentWindowRef = null;
    floatingContent.value = null;
    selectorContext.value = null;
    _floatingGeometryFlushHandler = null;
    _floatingFlagsApplyHandler = null;
    _selectorRuntimeDiagnosticsProvider = null;
    _selectorConfigRefreshHandler = null;
    await _selectorConfigRefreshBarrier;
    _selectorConfigRefreshBarrier = Future<void>.value();
    _prepareCloseHandler = null;
    _floatingWindowReady = Completer<void>();
    _floatingWindowConfigurationError = null;
    _floatingFlagsRevision = 0;
    _latestSelectorConfigRevision = 0;
    _appliedSelectorConfigRevision = 0;
    _rootDetachHandler = _detachDesktopSubWindowRoot;
    _hostResourceDrainHandler = _noopHostResourceDrain;
  }

  @visibleForTesting
  void debugResetForTests() {
    final DesktopRemoteWindowPort? oldWindow = _currentWindow;
    if (oldWindow != null) {
      unawaited(oldWindow.setMethodHandler(null));
    }
    _launch = const DesktopWindowLaunchArguments.main();
    _currentWindow = null;
    _currentWindowRef = null;
    floatingContent.value = null;
    selectorContext.value = null;
    _floatingGeometryFlushHandler = null;
    _floatingFlagsApplyHandler = null;
    _selectorRuntimeDiagnosticsProvider = null;
    _selectorConfigRefreshHandler = null;
    _selectorConfigRefreshBarrier = Future<void>.value();
    _prepareCloseHandler = null;
    _floatingWindowReady = Completer<void>();
    _floatingWindowConfigurationError = null;
    _floatingFlagsRevision = 0;
    _latestSelectorConfigRevision = 0;
    _appliedSelectorConfigRevision = 0;
    _closeTimer?.cancel();
    _closeTimer = null;
    _rootDetachHandler = _detachDesktopSubWindowRoot;
    _hostResourceDrainHandler = _noopHostResourceDrain;
    _subWindowRuntimeLogger = const DesktopLyricsLogger(
      scope: 'desktop-lyrics/sub-window-runtime',
    );
  }

  void setFloatingGeometryFlushHandler(
    DesktopFloatingGeometryFlushHandler? handler,
  ) {
    _floatingGeometryFlushHandler = handler;
  }

  void setFloatingFlagsApplyHandler(DesktopFloatingFlagsApplyHandler? handler) {
    _floatingFlagsApplyHandler = handler;
  }

  void setPrepareCloseHandler(DesktopSubWindowPrepareCloseHandler? handler) {
    _prepareCloseHandler = handler;
  }

  /// 注册当前选择器页面的只读诊断提供者，并返回精确解绑回调。
  ///
  /// 使用 identity 校验避免旧页面 dispose 时误删已由新页面注册的 provider。
  VoidCallback registerSelectorRuntimeDiagnosticsProvider(
    DesktopSelectorRuntimeDiagnosticsProvider provider,
  ) {
    _selectorRuntimeDiagnosticsProvider = provider;
    return () {
      if (identical(_selectorRuntimeDiagnosticsProvider, provider)) {
        _selectorRuntimeDiagnosticsProvider = null;
      }
    };
  }

  /// 在选择器根组件启动前绑定配置刷新处理器，并收口此前到达的版本通知。
  Future<void> bindSelectorConfigRefreshHandler(
    DesktopSelectorConfigRefreshHandler handler,
  ) async {
    _selectorConfigRefreshHandler = handler;
    await _enqueueSelectorConfigRefresh();
  }

  void markFloatingWindowReady() {
    if (_floatingWindowReady.isCompleted) {
      return;
    }
    _floatingWindowConfigurationError = null;
    _floatingWindowReady.complete();
  }

  void markFloatingWindowConfigurationFailed(Object error) {
    if (_floatingWindowReady.isCompleted) {
      return;
    }
    // 不使用 completeError：host 可能尚未开始等待，如果此时直接完成错误
    // Future，Dart 会先报告一次未处理异步异常。这里保存失败原因并正常解除
    // 屏障，真正的调用方随后会收到带上下文的明确错误。
    _floatingWindowConfigurationError = error.toString();
    _floatingWindowReady.complete();
  }

  Future<void> notifySelectorHidden() {
    return _notifyHostBestEffort(
      DesktopWindowMethodNames.selectorHiddenIntent,
      DesktopWindowPayloadCodec.encodeSelectorHiddenIntent(_launch.instanceId!),
    );
  }

  Future<bool> notifySelectorLyricsSelected(
    DesktopSelectorLyricsSelectedIntent intent,
  ) {
    return _dispatchHostNotification(
      DesktopWindowMethodNames.selectorLyricsSelectedIntent,
      DesktopWindowPayloadCodec.encodeSelectorLyricsSelectedIntent(intent),
      timeout: _actionNotifyHostTimeout,
    );
  }

  Future<bool> notifyFloatingMetricsCommitted(
    DesktopFloatingMetricsCommittedIntent intent,
  ) {
    return _dispatchHostNotification(
      DesktopWindowMethodNames.floatingMetricsCommittedIntent,
      DesktopWindowPayloadCodec.encodeFloatingMetricsCommittedIntent(intent),
      timeout: _actionNotifyHostTimeout,
    );
  }

  Future<bool> notifyFloatingAction(DesktopFloatingActionWindowIntent intent) {
    return _dispatchHostNotification(
      DesktopWindowMethodNames.floatingActionIntent,
      DesktopWindowPayloadCodec.encodeFloatingActionIntent(intent),
      timeout: _actionNotifyHostTimeout,
    );
  }

  Future<Object?> _handleMethodCall(String method, Object? arguments) async {
    switch (method) {
      case 'window_close':
        _subWindowRuntimeLogger.info(
          'window_close received role=${_launch.role.name}'
          ' instance=${_launch.instanceId ?? '-'}'
          ' panel=${_launch.panelId ?? '-'}'
          ' windowId=${_currentWindow?.windowId ?? '-'}',
        );
        final DesktopWindowRef? ref = _currentWindowRef;
        if (ref != null) {
          _lifecycleRegistry.upsertObserved(
            ref,
            DesktopWindowObservedState.closing,
            reason: 'request-close-received',
          );
        }
        if (defaultTargetPlatform == TargetPlatform.windows) {
          // 先用空根组件替换当前应用并等待一帧，让 ProviderScope、监听器和
          // 页面资源在 engine 仍存活时完成 dispose。某些页面还可能有
          // window_manager 方法通道调用在途，必须先等它们收口，否则
          // DestroyWindow 释放 engine 后，native 回调会访问已销毁的 messenger。
          await _prepareCloseHandler?.call();
          await _rootDetachHandler();
          // Provider、数据库、日志等资源由宿主拥有。共享包只维持关闭顺序，
          // 通过单一回调等待宿主资源真正释放，避免把 Riverpod 或日志实现耦合进来。
          await _hostResourceDrainHandler();
          // 根组件已卸载，清空屏障避免重复关闭时再进入已释放的页面。
          _prepareCloseHandler = null;
          // 使用新的事件任务投递 SC_CLOSE，确保当前跨 engine 方法调用
          // 已完成响应后再进入窗口销毁。这避免主 engine 直接 DestroyWindow
          // 时在 FlutterViewController 的消息栈内重入析构。
          _closeTimer?.cancel();
          _closeTimer = Timer(const Duration(milliseconds: 100), () {
            _closeTimer = null;
            unawaited(_closeCurrentWindow());
          });
          return null;
        }
        unawaited(_closeCurrentWindow());
        return null;
      case 'window_set_title':
        await windowManager.setTitle(arguments?.toString() ?? '');
        return null;
      case DesktopWindowMethodNames.floatingApplyContent:
        final DesktopFloatingContentPayload payload =
            DesktopWindowPayloadCodec.decodeFloatingContentPayload(arguments);
        final DesktopFloatingContentState current =
            floatingContent.value ?? _emptyFloatingContentState();
        final int currentRevision = current.snapshot.contentRevision;
        if (payload.contentRevision < currentRevision) {
          _subWindowRuntimeLogger.info(
            'floating content dropped instance=${_launch.instanceId ?? '-'}'
            ' nextRevision=${payload.contentRevision}'
            ' currentRevision=$currentRevision',
          );
          return true;
        }
        if (payload.contentRevision == currentRevision) {
          return true;
        }
        final bool keepsCurrentScene = desktopSceneRefEquals(
          current.snapshot.sceneRef,
          payload.sceneRef,
        );
        final DesktopLyricsSceneDocument? sceneDocument =
            payload.sceneBytes == null || payload.sceneBytes!.isEmpty
            ? (keepsCurrentScene ? current.sceneDocument : null)
            : _decodeSceneDocument(payload.sceneBytes);
        _subWindowRuntimeLogger.info(
          'floating content applied instance=${_launch.instanceId ?? '-'}'
          ' revision=${payload.contentRevision}'
          ' scene=${payload.sceneRef?.sceneId ?? '-'}'
          ' sceneRevision=${payload.sceneRef?.sceneRevision ?? '-'}'
          ' bytes=${payload.sceneBytes?.length ?? 0}'
          ' song=${payload.session.songId ?? payload.session.songTitle ?? '-'}',
        );
        floatingContent.value = DesktopFloatingContentState(
          snapshot: DesktopFloatingWindowSnapshot(
            session: payload.session,
            contentRevision: payload.contentRevision,
            sceneRef: payload.sceneRef,
            anchor: current.snapshot.anchor,
            flags: current.snapshot.flags,
          ),
          sceneDocument: sceneDocument,
        );
        return true;
      case DesktopWindowMethodNames.floatingAwaitReady:
        // Host 只有在保存位置和原生窗口样式完成后才能继续同步并显示浮窗。
        // 这里等待单一就绪屏障，避免默认矩形短暂暴露后再移动到记忆位置。
        await _floatingWindowReady.future;
        final String? configurationError = _floatingWindowConfigurationError;
        if (configurationError != null) {
          throw StateError('浮窗原生配置失败: $configurationError');
        }
        return true;
      case DesktopWindowMethodNames.floatingFlushGeometry:
        return await _floatingGeometryFlushHandler?.call() ?? false;
      case DesktopWindowMethodNames.floatingSyncAnchor:
        final DesktopFloatingContentState current =
            floatingContent.value ?? _emptyFloatingContentState();
        final DesktopFloatingAnchorSnapshot nextAnchor =
            DesktopWindowPayloadCodec.decodeFloatingAnchorSnapshot(arguments);
        final bool accepted = _shouldAcceptFloatingAnchor(
          current: current.snapshot,
          next: nextAnchor,
        );
        if (!accepted) {
          _subWindowRuntimeLogger.info(
            'floating anchor dropped instance=${_launch.instanceId ?? '-'}'
            ' revision=${nextAnchor.syncRevision}'
            ' scene=${nextAnchor.sceneId ?? '-'}'
            ' song=${nextAnchor.songToken ?? '-'}',
          );
          return null;
        }
        if (current.snapshot.anchor?.eventKind != nextAnchor.eventKind ||
            current.snapshot.anchor?.songToken != nextAnchor.songToken ||
            current.snapshot.anchor?.sceneId != nextAnchor.sceneId ||
            nextAnchor.syncRevision <= 3) {
          _subWindowRuntimeLogger.info(
            'floating anchor synced instance=${_launch.instanceId ?? '-'}'
            ' revision=${nextAnchor.syncRevision}'
            ' event=${nextAnchor.eventKind.name}'
            ' scene=${nextAnchor.sceneId ?? '-'}'
            ' song=${nextAnchor.songToken ?? '-'}'
            ' playing=${nextAnchor.isPlaying}',
          );
        }
        floatingContent.value = DesktopFloatingContentState(
          snapshot: DesktopFloatingWindowSnapshot(
            session: current.snapshot.session.copyWith(
              isPlaying: nextAnchor.isPlaying,
            ),
            contentRevision: current.snapshot.contentRevision,
            sceneRef: current.snapshot.sceneRef,
            anchor: nextAnchor,
            flags: current.snapshot.flags,
          ),
          sceneDocument: current.sceneDocument,
        );
        return null;
      case DesktopWindowMethodNames.floatingUpdateFlags:
        final DesktopFloatingContentState current =
            floatingContent.value ?? _emptyFloatingContentState();
        final DesktopFloatingFlagsPayload payload =
            DesktopWindowPayloadCodec.decodeFloatingFlagsPayload(arguments);
        if (payload.revision < _floatingFlagsRevision) {
          return true;
        }
        _floatingFlagsRevision = payload.revision;
        final DesktopFloatingWindowFlags flags = payload.flags;
        _subWindowRuntimeLogger.info(
          'floating flags updated instance=${_launch.instanceId ?? '-'}'
          ' visible=${flags.visible}'
          ' clickThrough=${flags.clickThrough}'
          ' alwaysOnTop=${flags.alwaysOnTop}'
          ' frameless=${flags.frameless}'
          ' opacity=${flags.opacity}',
        );
        floatingContent.value = DesktopFloatingContentState(
          snapshot: DesktopFloatingWindowSnapshot(
            session: current.snapshot.session,
            contentRevision: current.snapshot.contentRevision,
            sceneRef: current.snapshot.sceneRef,
            anchor: current.snapshot.anchor,
            flags: flags,
          ),
          sceneDocument: current.sceneDocument,
        );
        final DesktopFloatingFlagsApplyHandler? applyHandler =
            _floatingFlagsApplyHandler;
        if (applyHandler == null) {
          return false;
        }
        return applyHandler(flags);
      case DesktopWindowMethodNames.selectorShow:
      case DesktopWindowMethodNames.selectorRefresh:
        selectorContext.value = DesktopWindowPayloadCodec.decodeSelectorContext(
          arguments,
        );
        return null;
      case DesktopWindowMethodNames.selectorPresent:
        return _presentSelectorWindow();
      case DesktopWindowMethodNames.selectorConfigChanged:
        final int revision =
            DesktopWindowPayloadCodec.decodeSelectorConfigRevision(arguments);
        if (revision > _latestSelectorConfigRevision) {
          _latestSelectorConfigRevision = revision;
        }
        await _enqueueSelectorConfigRefresh();
        return null;
      case DesktopWindowMethodNames.selectorRuntimeDiagnostics:
        final DesktopSelectorRuntimeDiagnosticsProvider? provider =
            _selectorRuntimeDiagnosticsProvider;
        final DesktopSelectorRuntimeDiagnostics diagnostics = provider == null
            ? const DesktopSelectorRuntimeDiagnostics.unavailable()
            : provider();
        return DesktopWindowPayloadCodec.encodeSelectorRuntimeDiagnostics(
          diagnostics,
        );
      default:
        throw MissingPluginException('未实现的桌面子窗口方法: $method');
    }
  }

  Future<void> _enqueueSelectorConfigRefresh() {
    final Future<void> result = _selectorConfigRefreshBarrier.then((_) async {
      final DesktopSelectorConfigRefreshHandler? handler =
          _selectorConfigRefreshHandler;
      if (handler == null ||
          _latestSelectorConfigRevision <= _appliedSelectorConfigRevision) {
        return;
      }
      final int targetRevision = _latestSelectorConfigRevision;
      await handler(targetRevision);
      if (identical(_selectorConfigRefreshHandler, handler)) {
        _appliedSelectorConfigRevision = targetRevision;
      }
    });
    // 失败只返回给当前 host 调用；恢复后的 barrier 允许后续版本或 show 重试。
    _selectorConfigRefreshBarrier = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<bool> _presentSelectorWindow() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }

    await windowManager.show();
    final bool wasAlwaysOnTop = await windowManager.isAlwaysOnTop();
    final bool pulseTopmost =
        defaultTargetPlatform == TargetPlatform.windows && !wasAlwaysOnTop;
    if (pulseTopmost) {
      await windowManager.setAlwaysOnTop(true);
    }
    try {
      await windowManager.focus();
    } finally {
      if (pulseTopmost) {
        // 只借助 TOPMOST 触发一次可靠的前台排序，恢复用户原来的窗口属性。
        await windowManager.setAlwaysOnTop(false);
      }
    }
    await markCurrentWindowVisible(reason: 'selector-presented');
    return true;
  }

  Future<void> markCurrentWindowClosed({String? reason}) async {
    final DesktopWindowRef? ref = _currentWindowRef;
    if (ref == null) {
      return;
    }
    _lifecycleRegistry.markClosed(ref, reason: reason ?? 'window-disposed');
  }

  Future<void> markCurrentWindowVisible({String? reason}) async {
    final DesktopWindowRef? ref = _currentWindowRef;
    if (ref == null) {
      return;
    }
    _lifecycleRegistry.upsertObserved(
      ref,
      DesktopWindowObservedState.visible,
      reason: reason ?? 'window-visible',
    );
  }

  Future<void> markCurrentWindowHidden({String? reason}) async {
    final DesktopWindowRef? ref = _currentWindowRef;
    if (ref == null) {
      return;
    }
    _lifecycleRegistry.upsertObserved(
      ref,
      DesktopWindowObservedState.ready,
      reason: reason ?? 'window-hidden',
    );
  }

  void _bindCurrentWindowLifecycle() {
    final DesktopRemoteWindowPort? currentWindow = _currentWindow;
    if (currentWindow == null) {
      _currentWindowRef = null;
      return;
    }
    final int? generation = _launch.generation;
    if (_launch.role == DesktopWindowRole.main) {
      final DesktopWindowRef ref = _lifecycleRegistry.ensureMainWindow();
      _lifecycleRegistry.attachWindowId(
        ref,
        currentWindow.windowId,
        reason: 'main-window-attached',
      );
      _currentWindowRef = ref;
      return;
    }
    if (generation == null) {
      _currentWindowRef = null;
      return;
    }
    final DesktopWindowRef ref = DesktopWindowRef(
      role: _launch.role,
      instanceId: _launch.instanceId,
      panelId: _launch.panelId,
      generation: generation,
    );
    _currentWindowRef = ref;
    _lifecycleRegistry.attachWindowId(
      ref,
      currentWindow.windowId,
      reason: 'subwindow-attached',
    );
    _lifecycleRegistry.upsertObserved(
      ref,
      DesktopWindowObservedState.creating,
      windowId: currentWindow.windowId,
      reason: 'subwindow-initializing',
    );
  }

  Future<void> _closeCurrentWindow() async {
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
      _subWindowRuntimeLogger.info(
        'window_close completed role=${_launch.role.name}'
        ' instance=${_launch.instanceId ?? '-'}'
        ' panel=${_launch.panelId ?? '-'}',
      );
    } on Object catch (error, stackTrace) {
      final DesktopWindowRef? ref = _currentWindowRef;
      if (ref != null) {
        _lifecycleRegistry.markUnreachable(ref, reason: 'window-close-failed');
      }
      _subWindowRuntimeLogger.info(
        'window_close failed role=${_launch.role.name}'
        ' instance=${_launch.instanceId ?? '-'}'
        ' panel=${_launch.panelId ?? '-'}'
        ' error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> _notifyHostBestEffort(String method, Object? arguments) async {
    unawaited(_dispatchHostNotification(method, arguments));
  }

  Future<bool> _dispatchHostNotification(
    String method,
    Object? arguments, {
    Duration? timeout,
  }) async {
    final String? hostWindowId = _launch.hostWindowId;
    if (hostWindowId == null) {
      return false;
    }
    try {
      final DesktopRemoteWindowPort hostWindow = await _multiWindowPort
          .fromWindowId(hostWindowId);
      final Object? result = await hostWindow
          .invokeMethod(method, arguments)
          .timeout(timeout ?? _notifyHostTimeout);
      return result == true;
    } on Object catch (error, stackTrace) {
      _subWindowRuntimeLogger.info(
        'notify host ignored method=$method'
        ' role=${_launch.role.name}'
        ' instance=${_launch.instanceId ?? '-'}'
        ' panel=${_launch.panelId ?? '-'}'
        ' hostWindowId=$hostWindowId'
        ' error=$error stack=$stackTrace',
      );
      return false;
    }
  }

  bool _supportsDesktopSubWindow() {
    if (kIsWeb) {
      return false;
    }
    return <TargetPlatform>{
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);
  }

  DesktopFloatingContentState _emptyFloatingContentState() {
    return DesktopFloatingContentState(
      snapshot: DesktopFloatingWindowSnapshot(
        session: DesktopFloatingSessionSnapshot(),
        anchor: DesktopFloatingAnchorSnapshot(),
      ),
      sceneDocument: null,
    );
  }

  bool _shouldAcceptFloatingAnchor({
    required DesktopFloatingWindowSnapshot current,
    required DesktopFloatingAnchorSnapshot next,
  }) {
    final DesktopFloatingAnchorSnapshot? currentAnchor = current.anchor;
    if (currentAnchor != null &&
        next.syncRevision < currentAnchor.syncRevision) {
      return false;
    }
    final String? boundSceneId = current.sceneRef?.sceneId;
    if (boundSceneId != null &&
        next.sceneId != null &&
        next.sceneId != boundSceneId) {
      return false;
    }
    final String? currentSongId = current.session.songId;
    if (boundSceneId == null &&
        currentSongId != null &&
        next.songToken != null &&
        next.songToken != currentSongId) {
      return false;
    }
    return true;
  }

  DesktopLyricsSceneDocument? _decodeSceneDocument(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    DesktopLyricsPerfStats.instance.bump('sceneDecode');
    return const DesktopLyricsSceneCodec().decode(bytes);
  }
}

Future<void> _detachDesktopSubWindowRoot() async {
  runApp(const SizedBox.shrink());
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _noopHostResourceDrain() async {}
