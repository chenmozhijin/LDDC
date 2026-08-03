import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../logging/desktop_lyrics_logger.dart';
import 'package:window_manager/window_manager.dart';

import '../models/desktop_style_models.dart';
import '../projection/desktop_lyrics_projection_runtime.dart';
import '../projection/desktop_lyrics_scene.dart';
import '../projection/desktop_projection_snapshot_mapper.dart';
import '../render/desktop_render.dart';
import 'desktop_floating_window_geometry_coordinator.dart';
import 'desktop_playback_ticker_coordinator.dart';
import 'desktop_sub_window_runtime.dart';
import 'desktop_window_backend.dart';
import 'desktop_window_interaction.dart';
import 'desktop_window_launch.dart';
import 'desktop_window_shell_shared.dart';
import 'desktop_window_style_channel.dart';
import 'desktop_window_strings.dart';
import 'desktop_window_view_binding_coordinator.dart';

class DesktopFloatingWindowShellPage extends StatefulWidget {
  const DesktopFloatingWindowShellPage({
    super.key,
    required this.launch,
    this.nowMsFactory,
    this.strings = const DesktopLyricsWindowStrings.zhHans(),
    this.logger = const DesktopLyricsLogger(),
  });

  final DesktopWindowLaunchArguments launch;
  final int Function()? nowMsFactory;
  final DesktopLyricsWindowStrings strings;
  final DesktopLyricsLogger logger;

  @override
  State<DesktopFloatingWindowShellPage> createState() =>
      DesktopFloatingWindowShellPageState();
}

class DesktopFloatingWindowShellPageState
    extends State<DesktopFloatingWindowShellPage>
    with
        WindowListener,
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  final DesktopSubWindowRuntime _runtime = DesktopSubWindowRuntime.instance;
  late final DesktopLyricsProjectionRuntime _lyricsRuntime;
  late final DesktopWindowViewBindingCoordinator _viewBinding;
  late final DesktopPlaybackTickerCoordinator _playbackTicker;
  late final DesktopFloatingWindowGeometryCoordinator _geometryCoordinator;
  late final DesktopLyricsLogger _logger;
  DesktopFloatingWindowSnapshot? _snapshot;
  DesktopLyricsSceneDocument? _sceneDocument;
  DesktopFloatingWindowFlags? _lastAppliedFlags;
  Timer? _hoverShowTimer;
  Timer? _hoverHideTimer;
  Timer? _autoExposeTimer;
  bool _hoverVisible = false;
  bool _autoExposeVisible = false;
  String? _transientControlNotice;

  @override
  void initState() {
    super.initState();
    _logger = widget.logger.child('floating-shell');
    _lyricsRuntime = DesktopLyricsProjectionRuntime(
      nowMsFactory: _currentPlaybackTimeMs,
    );
    final DesktopFloatingContentState? content = _runtime.floatingContent.value;
    _snapshot = content?.snapshot;
    _sceneDocument = content?.sceneDocument;
    _syncLyricsRuntime();
    _viewBinding =
        DesktopWindowViewBindingCoordinator(target: 'floating', logger: _logger)
          ..addListener(_handleViewBindingChanged)
          ..updateConfiguredRefreshRate(
            _snapshot?.session.refreshRate ?? -1,
            immediate: false,
          );
    _playbackTicker = DesktopPlaybackTickerCoordinator(
      vsync: this,
      shouldTick: _shouldTickPlayback,
      tickPlaybackTime: _lyricsRuntime.tick,
      resolveRefreshRate: () => _viewBinding.state.effectiveRefreshRate,
      initialPlaybackTimeMs: _lyricsRuntime.currentTimeMs,
    );
    _geometryCoordinator = DesktopFloatingWindowGeometryCoordinator(
      isMounted: () => mounted,
      setBounds: windowManager.setBounds,
      awaitViewportStableBounds: _awaitFloatingViewportStableBounds,
      awaitNextFrame: _awaitNextFrame,
      reapplyFlags: _reapplyFloatingFlags,
      scheduleRefreshRateResolve: _viewBinding.scheduleResolve,
      commitMetrics: _commitFloatingMetrics,
      resolveSessionFontSize: _currentSessionFontSize,
      logger: _logger,
    )..addListener(_handleGeometryChanged);
    if ((_snapshot?.contentRevision ?? 0) > 0) {
      _geometryCoordinator.beginContentRevision(_snapshot!.contentRevision);
    }
    _runtime.setFloatingGeometryFlushHandler(
      _geometryCoordinator.flushGeometry,
    );
    _runtime.setFloatingFlagsApplyHandler(_applyFlagsAndVisibility);
    _runtime.floatingContent.addListener(_handleContentChanged);
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _logger.info(
      'init instance=${widget.launch.instanceId ?? '-'}'
      ' hostWindowId=${widget.launch.hostWindowId ?? '-'}'
      ' visible=${_snapshot?.flags.visible ?? false}'
      ' scene=${_snapshot?.sceneRef?.sceneId ?? '-'}'
      ' song=${_snapshot?.session.songId ?? _snapshot?.session.songTitle ?? '-'}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_configureWindowSafely());
    });
  }

  @override
  void dispose() {
    _logger.info(
      'dispose instance=${widget.launch.instanceId ?? '-'}'
      ' visible=${_snapshot?.flags.visible ?? false}'
      ' scene=${_snapshot?.sceneRef?.sceneId ?? '-'}'
      ' song=${_snapshot?.session.songId ?? _snapshot?.session.songTitle ?? '-'}',
    );
    _hoverShowTimer?.cancel();
    _hoverHideTimer?.cancel();
    _autoExposeTimer?.cancel();
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _runtime.floatingContent.removeListener(_handleContentChanged);
    _runtime.setFloatingGeometryFlushHandler(null);
    _runtime.setFloatingFlagsApplyHandler(null);
    _geometryCoordinator
      ..removeListener(_handleGeometryChanged)
      ..dispose();
    _playbackTicker.dispose();
    _viewBinding
      ..removeListener(_handleViewBindingChanged)
      ..dispose();
    unawaited(
      _runtime.markCurrentWindowClosed(reason: 'floating-shell-dispose'),
    );
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewBinding.bindView(View.maybeOf(context));
  }

  @override
  Widget build(BuildContext context) {
    final DesktopFloatingWindowSnapshot? snapshot = _snapshot;
    final DesktopFloatingSessionSnapshot session =
        snapshot?.session ??
        DesktopFloatingSessionSnapshot(songTitle: widget.strings.appTitle);
    final DesktopWindowActionSnapshot actions = session.actions;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        opaque: false,
        onEnter: (_) => _handleFloatingHoverEnter(),
        onExit: (_) => _handleFloatingHoverExit(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: (TapDownDetails details) {
            unawaited(
              _showFloatingContextMenu(details.globalPosition, actions),
            );
          },
          child: DragToResizeArea(
            resizeEdgeSize: 10,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      opacity: _shouldShowFloatingBackdrop ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DesktopWindowDragSurface(
                    onSetBounds: _geometryCoordinator.applyUserBounds,
                    logger: _logger,
                    child: Column(
                      children: <Widget>[
                        _FloatingChromeSizeReporter(
                          onChanged: (Size size) {
                            _geometryCoordinator.updateControlChromeHeight(
                              size.height,
                            );
                          },
                          child: _buildFloatingControlChrome(
                            context,
                            session: session,
                            actions: actions,
                          ),
                        ),
                        Expanded(
                          child: DesktopFloatingLyricsRenderView(
                            title: session.songTitle ?? widget.strings.appTitle,
                            subtitle: session.artistText ?? '',
                            contentRevision: snapshot?.contentRevision ?? 0,
                            renderIdentity: snapshot == null
                                ? null
                                : _resolveFloatingRenderIdentity(snapshot),
                            renderPlan: _resolveFloatingRenderPlan(
                              _playbackTicker
                                  .estimatedPlaybackTimeMsNotifier
                                  .value,
                            ),
                            renderPlanResolver: _resolveFloatingRenderPlan,
                            estimatedPlaybackTimeListenable:
                                _playbackTicker.estimatedPlaybackTimeMsNotifier,
                            playedColors: session.playedColors,
                            unplayedColors: session.unplayedColors,
                            fontFamily: session.fontFamily,
                            fontSize: _geometryCoordinator.effectiveFontSize(
                              session.fontSize,
                            ),
                            fontSizeMode:
                                _geometryCoordinator.state.isUserResizing
                                ? DesktopFloatingFontSizeMode.interactiveResize
                                : DesktopFloatingFontSizeMode.fixedFont,
                            showFurigana: session.showFurigana,
                            onFrameCandidate:
                                _geometryCoordinator.handleFrameCandidate,
                            onFrameCommitted:
                                _geometryCoordinator.handleFrameCommitted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _configureWindowSafely() async {
    try {
      await _configureWindow();
    } on Object catch (error, stackTrace) {
      _logger.error(
        'configure failed',
        fields: <String, Object?>{
          'instanceId': widget.launch.instanceId,
          'windowId': _runtime.currentWindowId,
          'hostWindowId': widget.launch.hostWindowId,
          'phase': 'native-window-configuration',
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      _runtime.markFloatingWindowConfigurationFailed(error);
      return;
    }
    _runtime.markFloatingWindowReady();
  }

  Future<void> _configureWindow() async {
    const DesktopFloatingWindowFlags flags = DesktopFloatingWindowFlags();
    final WindowRect? windowRect = widget.launch.initialWindowRect;
    _logger.info(
      'configure begin instance=${widget.launch.instanceId ?? '-'}'
      ' rect=${windowRect == null ? '-' : '${windowRect.left},${windowRect.top},${windowRect.width}x${windowRect.height}'}'
      ' visible=${flags.visible}'
      ' clickThrough=${flags.clickThrough}'
      ' alwaysOnTop=${flags.alwaysOnTop}'
      ' frameless=${flags.frameless}',
    );
    await windowManager.setSize(
      Size(windowRect?.width ?? 1200, windowRect?.height ?? 150),
    );
    if (windowRect == null && defaultTargetPlatform == TargetPlatform.windows) {
      await desktopWindowStyleChannel.invokeMethod<bool>('centerWindow');
    } else if (windowRect == null) {
      await windowManager.center();
    }
    await _geometryCoordinator.applyInitialWindowRect(windowRect);
    await _applyWindowStyle(flags, force: true);
    _lastAppliedFlags = flags;
    await _applyFloatingToolWindowStyle();
    await _runtime.markCurrentWindowHidden(
      reason: 'floating-window-configured',
    );
    _viewBinding.scheduleResolve(immediate: true);
    _playbackTicker.syncTicker();
    _logger.info(
      'configure end instance=${widget.launch.instanceId ?? '-'}'
      ' visible=${flags.visible}',
    );
  }

  void _handleViewBindingChanged() {
    _playbackTicker.resetCadence();
  }

  void _handleGeometryChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _handleContentChanged() {
    if (!mounted) {
      return;
    }
    final DesktopFloatingWindowSnapshot? previous = _snapshot;
    final DesktopFloatingContentState? content = _runtime.floatingContent.value;
    final DesktopFloatingWindowSnapshot? next = content?.snapshot;
    if (content == null) {
      setState(() {
        _snapshot = null;
        _sceneDocument = null;
      });
      _syncLyricsRuntime();
      _playbackTicker.syncTicker();
      return;
    }
    if (next != null &&
        next.contentRevision > (previous?.contentRevision ?? 0)) {
      _geometryCoordinator.beginContentRevision(next.contentRevision);
    }
    setState(() {
      _snapshot = next;
      _sceneDocument = content.sceneDocument;
    });
    if (next != null) {
      _geometryCoordinator.reconcileSessionFontSize(next.session.fontSize);
    }
    _maybeAutoExposeFloatingChrome(previous: previous, next: next);
    _syncLyricsRuntime();
    _playbackTicker.syncCurrentTime(_lyricsRuntime.currentTimeMs);
    _viewBinding.updateConfiguredRefreshRate(
      next?.session.refreshRate ?? -1,
      immediate: true,
    );
    _playbackTicker.syncTicker();
  }

  Future<bool> _applyFlagsAndVisibility(
    DesktopFloatingWindowFlags flags,
  ) async {
    final bool? previousVisibility = _lastAppliedFlags?.visible;
    await _applyWindowStyle(flags);
    if (previousVisibility != flags.visible) {
      if (flags.visible) {
        await windowManager.show();
        await _runtime.markCurrentWindowVisible(
          reason: 'floating-flags-visible',
        );
      } else {
        await windowManager.hide();
        await _runtime.markCurrentWindowHidden(reason: 'floating-flags-hidden');
      }
    }
    _lastAppliedFlags = flags;
    _playbackTicker.syncTicker();
    return true;
  }

  Future<void> _applyWindowStyle(
    DesktopFloatingWindowFlags flags, {
    bool force = false,
  }) async {
    if (!force && desktopShellFloatingStyleEquals(_lastAppliedFlags, flags)) {
      return;
    }
    if (flags.frameless) {
      await windowManager.setAsFrameless();
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        // window_manager 0.5.2 只在 Windows 和 macOS 实现窗口阴影接口。
        // Linux 调用该方法会抛出 MissingPluginException，导致浮窗配置失败，
        // 最终使隐藏服务无法在最后一个实例删除后正常退出。
        await windowManager.setHasShadow(false);
      }
    } else {
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        // 有边框样式同样只能在插件明确支持阴影的桌面平台恢复阴影；
        // Linux 保留窗口管理器自身的装饰策略，不调用不存在的原生通道。
        await windowManager.setHasShadow(true);
      }
    }
    await windowManager.setAlwaysOnTop(flags.alwaysOnTop);
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      // window_manager 0.5.2 的鼠标穿透通道仅在 Windows 和 macOS 注册。
      // Linux 无条件调用会抛出 MissingPluginException，使浮窗创建反复失败，
      // 并阻断最后实例删除后的服务退出；Linux 继续使用原生窗口默认命中行为。
      await windowManager.setIgnoreMouseEvents(flags.clickThrough);
    }
    await windowManager.setOpacity(flags.opacity);
    // Windows 上 frameless、阴影和分层透明度都会改写底层窗口样式；
    // 如果只依赖 waitUntilReadyToShow() 里的初始 backgroundColor，
    // 样式重排后 Flutter 子窗口可能退回黑色合成底。这里在所有 flags
    // 生效后重新声明透明背景，确保桌面歌词浮窗保持真正透明。
    await windowManager.setBackgroundColor(Colors.transparent);
  }

  Future<void> _applyFloatingToolWindowStyle() async {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    try {
      await desktopWindowStyleChannel.invokeMethod<Object?>('setToolWindow');
    } on Object catch (error, stackTrace) {
      // 窗口类型校正失败不应阻断歌词渲染，因此只记录诊断。
      // 此时窗口仍能显示，但可能暂时出现在任务栏或 Alt-Tab 中。
      _logger.warning(
        'apply floating tool window style failed'
        ' instance=${widget.launch.instanceId ?? '-'}'
        ' error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> _reapplyFloatingFlags({bool force = false}) async {
    final DesktopFloatingWindowFlags flags =
        _snapshot?.flags ?? const DesktopFloatingWindowFlags();
    await _applyWindowStyle(flags, force: force);
    _lastAppliedFlags = flags;
  }

  bool _shouldTickPlayback() {
    final DesktopFloatingWindowSnapshot? snapshot = _snapshot;
    return snapshot != null &&
        snapshot.flags.visible &&
        snapshot.anchor != null &&
        snapshot.session.isPlaying;
  }

  int _currentPlaybackTimeMs() {
    return widget.nowMsFactory?.call() ?? DateTime.now().millisecondsSinceEpoch;
  }

  double _currentSessionFontSize() {
    return _snapshot?.session.fontSize ??
        DesktopFloatingSessionSnapshot().fontSize;
  }

  Future<bool> _commitFloatingMetrics(double fontSize) async {
    final int? instanceId = widget.launch.instanceId;
    if (instanceId == null) {
      return false;
    }
    final Rect? bounds = await _awaitFloatingViewportStableBounds();
    if (bounds == null) {
      return false;
    }
    return _runtime.notifyFloatingMetricsCommitted(
      DesktopFloatingMetricsCommittedIntent(
        instanceId: instanceId,
        windowRect: WindowRect(
          left: bounds.left,
          top: bounds.top,
          width: bounds.width,
          height: bounds.height,
        ),
        fontSize: fontSize,
      ),
    );
  }

  Future<void> _awaitNextFrame() {
    final Completer<void> completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  bool _floatingViewportMatchesBounds(Rect bounds) {
    final ui.FlutterView? view = _viewBinding.boundView;
    final Size? physicalSize = view?.physicalSize;
    final double? dpr = view?.devicePixelRatio;
    if (physicalSize == null || dpr == null || dpr == 0) {
      return true;
    }
    final Size logicalViewportSize = Size(
      physicalSize.width / dpr,
      physicalSize.height / dpr,
    );
    return (bounds.width - logicalViewportSize.width).abs() <= 1 &&
        (bounds.height - logicalViewportSize.height).abs() <= 1;
  }

  Future<Rect?> _awaitFloatingViewportStableBounds({
    int maxAttempts = 6,
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt += 1) {
      Rect bounds;
      try {
        bounds = await windowManager.getBounds();
      } on Object {
        return null;
      }
      if (_floatingViewportMatchesBounds(bounds)) {
        return bounds;
      }
      await _awaitNextFrame();
      if (!mounted) {
        return null;
      }
    }
    return null;
  }

  @override
  void onWindowResize() {
    _geometryCoordinator.onWindowResize();
  }

  @override
  void onWindowResized() {
    _geometryCoordinator.onWindowResized();
  }

  @override
  void onWindowMove() {
    _geometryCoordinator.onWindowMove();
  }

  @override
  void onWindowMoved() {
    _geometryCoordinator.onWindowMoved();
  }

  @override
  void didChangeMetrics() {
    _geometryCoordinator.didChangeMetrics();
  }

  void _handleFloatingHoverEnter() {
    _hoverHideTimer?.cancel();
    _hoverShowTimer?.cancel();
    _hoverShowTimer = Timer(const Duration(milliseconds: 500), () {
      _setFloatingHoverVisible(true);
    });
  }

  void _handleFloatingHoverExit() {
    _hoverShowTimer?.cancel();
    _hoverHideTimer?.cancel();
    _hoverHideTimer = Timer(const Duration(milliseconds: 500), () {
      _setFloatingHoverVisible(false);
    });
  }

  void _setFloatingHoverVisible(bool visible) {
    if (!mounted || _hoverVisible == visible) {
      return;
    }
    setState(() {
      _hoverVisible = visible;
    });
  }

  bool get _shouldShowFloatingBackdrop =>
      _hoverVisible || _geometryCoordinator.state.isUserResizing;

  bool get _shouldShowFloatingChrome =>
      _hoverVisible ||
      _geometryCoordinator.state.isUserResizing ||
      _autoExposeVisible;

  DesktopFloatingRenderPlan? _resolveFloatingRenderPlan(
    int? estimatedPlaybackTimeMs,
  ) {
    return _lyricsRuntime.buildFloatingRenderPlan(
      currentTimeMs: estimatedPlaybackTimeMs,
    );
  }

  String _resolveFloatingRenderIdentity(
    DesktopFloatingWindowSnapshot snapshot,
  ) {
    final String? sceneId = snapshot.sceneRef?.sceneId;
    if (sceneId != null && sceneId.isNotEmpty) {
      return sceneId;
    }
    return '${snapshot.session.songId ?? '-'}'
        '|static=${snapshot.session.hasStaticDisplay}'
        '|inst=${snapshot.session.isInstrumental}';
  }

  void _syncLyricsRuntime() {
    _lyricsRuntime
      ..updateFloatingStyle(_snapshot?.session.toProjectionStyle())
      ..bindScene(_sceneDocument)
      ..syncEvent(
        _snapshot?.anchor == null
            ? null
            : _snapshot!.anchor!.toProjectionSyncEvent(),
        nowMs: _currentPlaybackTimeMs(),
      );
  }

  Widget _buildFloatingControlChrome(
    BuildContext context, {
    required DesktopFloatingSessionSnapshot session,
    required DesktopWindowActionSnapshot actions,
  }) {
    final DesktopLyricsWindowStrings strings = widget.strings;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: IgnorePointer(
          ignoring: !_shouldShowFloatingChrome,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            opacity: _shouldShowFloatingChrome ? 1 : 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: DesktopFloatingControlBar(
                strings: strings,
                infoText:
                    _transientControlNotice ??
                    buildInfoBadgeText(strings, session.infoBadge),
                actions: actions,
                isPlaying: session.isPlaying,
                onSelectLyrics: actions.canOpenSelector
                    ? () => _dispatchFloatingAction(
                        DesktopWindowActionType.openSelector,
                      )
                    : null,
                onHide: () => _dispatchFloatingAction(
                  DesktopWindowActionType.toggleFloatingVisibility,
                ),
                onPrevious:
                    actions.supportsControlTask(
                      DesktopPlaybackControlTask.previous,
                    )
                    ? () => _dispatchFloatingAction(
                        DesktopWindowActionType.controlCommand,
                        controlTask: DesktopPlaybackControlTask.previous,
                      )
                    : null,
                onNext:
                    actions.supportsControlTask(DesktopPlaybackControlTask.next)
                    ? () => _dispatchFloatingAction(
                        DesktopWindowActionType.controlCommand,
                        controlTask: DesktopPlaybackControlTask.next,
                      )
                    : null,
                onPlayPause:
                    actions.supportsControlTask(
                          DesktopPlaybackControlTask.play,
                        ) &&
                        actions.supportsControlTask(
                          DesktopPlaybackControlTask.pause,
                        )
                    ? () => _dispatchFloatingAction(
                        DesktopWindowActionType.controlCommand,
                        controlTask: session.isPlaying
                            ? DesktopPlaybackControlTask.pause
                            : DesktopPlaybackControlTask.play,
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFloatingContextMenu(
    Offset globalPosition,
    DesktopWindowActionSnapshot actions,
  ) async {
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }
    final RenderBox overlayBox =
        overlay.context.findRenderObject()! as RenderBox;
    final DesktopWindowActionType? action =
        await showMenu<DesktopWindowActionType>(
          context: context,
          position: RelativeRect.fromRect(
            Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
            Offset.zero & overlayBox.size,
          ),
          items: buildFloatingMenuEntries(widget.strings, actions),
        );
    if (action == null) {
      return;
    }
    await _dispatchFloatingAction(action);
  }

  Future<void> _dispatchFloatingAction(
    DesktopWindowActionType action, {
    DesktopPlaybackControlTask? controlTask,
  }) async {
    final int? instanceId = widget.launch.instanceId;
    if (instanceId == null) {
      return;
    }
    final bool succeeded = await _runtime.notifyFloatingAction(
      DesktopFloatingActionWindowIntent(
        instanceId: instanceId,
        action: action,
        controlTask: controlTask,
      ),
    );
    if (!mounted || action != DesktopWindowActionType.controlCommand) {
      return;
    }
    if (succeeded) {
      if (_transientControlNotice != null) {
        setState(() {
          _transientControlNotice = null;
        });
      }
      return;
    }
    _showAutoExposedChrome(notice: widget.strings.controlConnectionLost);
  }

  void _maybeAutoExposeFloatingChrome({
    required DesktopFloatingWindowSnapshot? previous,
    required DesktopFloatingWindowSnapshot? next,
  }) {
    if (!_shouldAutoExposeFloatingChrome(previous: previous, next: next)) {
      return;
    }
    _showAutoExposedChrome();
  }

  void _showAutoExposedChrome({String? notice}) {
    _autoExposeTimer?.cancel();
    if (!_autoExposeVisible || _transientControlNotice != notice) {
      setState(() {
        _autoExposeVisible = true;
        _transientControlNotice = notice;
      });
    }
    _autoExposeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted ||
          (!_autoExposeVisible && _transientControlNotice == null)) {
        return;
      }
      setState(() {
        _autoExposeVisible = false;
        _transientControlNotice = null;
      });
    });
  }

  bool _shouldAutoExposeFloatingChrome({
    required DesktopFloatingWindowSnapshot? previous,
    required DesktopFloatingWindowSnapshot? next,
  }) {
    if (next == null) {
      return false;
    }
    final DesktopFloatingSessionSnapshot nextSession = next.session;
    final DesktopFloatingSessionSnapshot? previousSession = previous?.session;
    final String? previousSceneId = previous?.sceneRef?.sceneId;
    final String? nextSceneId = next.sceneRef?.sceneId;
    return previousSession == null ||
        previousSession.songId != nextSession.songId ||
        previousSession.songTitle != nextSession.songTitle ||
        previousSession.artistText != nextSession.artistText ||
        !desktopShellFloatingInfoBadgeEquals(
          previousSession.infoBadge,
          nextSession.infoBadge,
        ) ||
        previousSession.isInstrumental != nextSession.isInstrumental ||
        previousSession.hasStaticDisplay != nextSession.hasStaticDisplay ||
        previousSceneId != nextSceneId;
  }
}

/// 只负责把控制栏的真实布局高度交给几何协调器。
///
/// 控制栏始终保留同一占位，悬停只改变透明度，因此歌词 viewport 不会因
/// 控制栏显示或隐藏而跳变。回调按尺寸去重，不参与播放刷新热路径。
class _FloatingChromeSizeReporter extends StatefulWidget {
  const _FloatingChromeSizeReporter({
    required this.onChanged,
    required this.child,
  });

  final ValueChanged<Size> onChanged;
  final Widget child;

  @override
  State<_FloatingChromeSizeReporter> createState() =>
      _FloatingChromeSizeReporterState();
}

class _FloatingChromeSizeReporterState
    extends State<_FloatingChromeSizeReporter> {
  Size? _lastSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final Size? size = context.size;
      if (size == null || size == _lastSize) {
        return;
      }
      _lastSize = size;
      widget.onChanged(size);
    });
    return widget.child;
  }
}
