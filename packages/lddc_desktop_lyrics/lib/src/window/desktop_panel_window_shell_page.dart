import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../logging/desktop_lyrics_logger.dart';

import '../projection/desktop_lyrics_projection_runtime.dart';
import '../projection/desktop_lyrics_scene.dart';
import '../projection/desktop_projection_snapshot_mapper.dart';
import '../render/desktop_render.dart';
import 'desktop_embedded_panel_runtime.dart';
import 'desktop_panel_host.dart';
import 'desktop_playback_ticker_coordinator.dart';
import 'desktop_window_interaction.dart';
import 'desktop_window_launch.dart';
import 'desktop_window_shell_shared.dart';
import 'desktop_window_strings.dart';
import 'desktop_window_view_binding_coordinator.dart';

class DesktopPanelWindowShellPage extends StatefulWidget {
  const DesktopPanelWindowShellPage({
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
  State<DesktopPanelWindowShellPage> createState() =>
      DesktopPanelWindowShellPageState();
}

class DesktopPanelWindowShellPageState
    extends State<DesktopPanelWindowShellPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final DesktopEmbeddedPanelRuntime _runtime =
      DesktopEmbeddedPanelRuntime.instance;
  late final DesktopLyricsProjectionRuntime _lyricsRuntime;
  late final DesktopWindowViewBindingCoordinator _viewBinding;
  late final DesktopPlaybackTickerCoordinator _playbackTicker;
  late final DesktopLyricsLogger _logger;
  DesktopPanelContentState? _content;
  DesktopPanelSurfaceState? _surface;
  ({int contentRevision, int surfaceRevision})? _scheduledPresentation;
  ({int contentRevision, int surfaceRevision})? _reportedPresentation;

  @override
  void initState() {
    super.initState();
    _logger = widget.logger.child('panel-shell');
    _lyricsRuntime = DesktopLyricsProjectionRuntime(
      nowMsFactory: _currentPlaybackTimeMs,
    );
    _content = _runtime.panelContent.value;
    _surface = _runtime.panelSurfaceState.value;
    _syncLyricsRuntime();
    _viewBinding =
        DesktopWindowViewBindingCoordinator(target: 'panel', logger: _logger)
          ..addListener(_handleViewBindingChanged)
          ..updateConfiguredRefreshRate(
            _content?.snapshot.session.refreshRate ?? -1,
            immediate: false,
          );
    _playbackTicker = DesktopPlaybackTickerCoordinator(
      vsync: this,
      shouldTick: _shouldTickPlayback,
      tickPlaybackTime: _lyricsRuntime.tick,
      resolveRefreshRate: () => _viewBinding.state.effectiveRefreshRate,
      initialPlaybackTimeMs: _lyricsRuntime.currentTimeMs,
    );
    _runtime.panelContent.addListener(_handleContentChanged);
    _runtime.panelSurfaceState.addListener(_handleSurfaceChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtime.panelContent.removeListener(_handleContentChanged);
    _runtime.panelSurfaceState.removeListener(_handleSurfaceChanged);
    _playbackTicker.dispose();
    _viewBinding
      ..removeListener(_handleViewBindingChanged)
      ..dispose();
    unawaited(_runtime.dispose());
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewBinding.bindView(View.maybeOf(context));
  }

  @override
  void didChangeMetrics() {
    _viewBinding.scheduleResolve(immediate: true);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final DesktopPanelContentState content = _content ?? _emptyPanelContent();
    final DesktopPanelWindowSnapshot snapshot = content.snapshot;
    final DesktopPanelSessionSnapshot session = snapshot.session;
    final DesktopPanelRenderPlan? renderPlan = _resolvePanelRenderPlan(
      _playbackTicker.estimatedPlaybackTimeMsNotifier.value,
    );

    return Scaffold(
      // embedded Panel 当前按不透明 surface 交付。固定纯黑可避免主题 surface
      // 在 foobar 深色界面中呈现偏绿或偏灰，同时保持歌词颜色对比稳定。
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (TapDownDetails details) {
          unawaited(
            _showPanelContextMenu(details.globalPosition, session.actions),
          );
        },
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final ui.FlutterView view = View.of(context);
            final double dpr = math.max(view.devicePixelRatio, 0.01);
            final int width = math.max(
              1,
              (constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : view.physicalSize.width / dpr)
                  .round(),
            );
            final int height = math.max(
              1,
              (constraints.hasBoundedHeight
                      ? constraints.maxHeight
                      : view.physicalSize.height / dpr)
                  .round(),
            );
            _schedulePresentationReady(view);
            return IgnorePointer(
              child: DesktopPanelLyricsRenderView(
                renderGenerationKey: DesktopRenderGenerationKey(
                  contentIdentity: 'panel-content:${snapshot.contentRevision}',
                  renderIdentity:
                      '${snapshot.sceneRef?.sceneId ?? '-'}:'
                      '${snapshot.sceneRef?.sceneRevision ?? 0}:'
                      '${_surface?.surfaceRevision ?? 0}',
                  viewportWidth: width,
                  viewportHeight: height,
                  devicePixelRatio: dpr,
                  themeSignature: Object.hash(
                    session.fontFamily,
                    session.fontSize,
                    session.showFurigana,
                    Object.hashAll(session.playedColors),
                    Object.hashAll(session.unplayedColors),
                  ),
                ),
                renderPlan: renderPlan,
                renderPlanResolver: _resolvePanelRenderPlan,
                playedColors: session.playedColors,
                unplayedColors: session.unplayedColors,
                fontFamily: session.fontFamily,
                fontSize: session.fontSize,
                showFurigana: session.showFurigana,
                refreshRate: _viewBinding.state.effectiveRefreshRate,
                estimatedPlaybackTimeListenable:
                    _playbackTicker.estimatedPlaybackTimeMsNotifier,
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleContentChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _content = _runtime.panelContent.value;
      _scheduledPresentation = null;
    });
    _syncLyricsRuntime();
    _playbackTicker.syncCurrentTime(_lyricsRuntime.currentTimeMs);
    _viewBinding.updateConfiguredRefreshRate(
      _content?.snapshot.session.refreshRate ?? -1,
      immediate: true,
    );
    _playbackTicker.syncTicker();
  }

  void _handleSurfaceChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _surface = _runtime.panelSurfaceState.value;
      _scheduledPresentation = null;
    });
    _viewBinding.scheduleResolve(immediate: true);
    _playbackTicker.syncTicker();
  }

  void _handleViewBindingChanged() {
    _playbackTicker.resetCadence();
    if (mounted) {
      setState(() {});
    }
  }

  void _schedulePresentationReady(ui.FlutterView view) {
    final DesktopPanelContentState? content = _content;
    final DesktopPanelSurfaceState? surface = _surface;
    if (content == null || surface == null || !surface.surfaceReady) {
      return;
    }
    if (!_viewMatchesSurface(view, surface)) {
      return;
    }
    final ({int contentRevision, int surfaceRevision}) target = (
      contentRevision: content.snapshot.contentRevision,
      surfaceRevision: surface.surfaceRevision,
    );
    if (_scheduledPresentation == target || _reportedPresentation == target) {
      return;
    }
    _scheduledPresentation = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_currentPresentationMatches(target)) {
        if (_scheduledPresentation == target) {
          _scheduledPresentation = null;
        }
        return;
      }
      unawaited(_reportPresentationReady(target));
    });
  }

  Future<void> _reportPresentationReady(
    ({int contentRevision, int surfaceRevision}) target,
  ) async {
    final bool reported = await _runtime.notifyPresentationReady(
      DesktopPanelPresentationReady(
        contentRevision: target.contentRevision,
        surfaceRevision: target.surfaceRevision,
      ),
    );
    if (!mounted || !_currentPresentationMatches(target)) {
      return;
    }
    setState(() {
      if (reported) {
        _reportedPresentation = target;
      }
      if (_scheduledPresentation == target) {
        _scheduledPresentation = null;
      }
    });
  }

  bool _currentPresentationMatches(
    ({int contentRevision, int surfaceRevision}) target,
  ) {
    return _content?.snapshot.contentRevision == target.contentRevision &&
        _surface?.surfaceRevision == target.surfaceRevision;
  }

  bool _viewMatchesSurface(
    ui.FlutterView view,
    DesktopPanelSurfaceState surface,
  ) {
    final Size actual = view.physicalSize;
    final Size expected = surface.clientSizePx;
    return (actual.width - expected.width).abs() <= 1 &&
        (actual.height - expected.height).abs() <= 1;
  }

  void _syncLyricsRuntime() {
    final DesktopPanelContentState? content = _content;
    _lyricsRuntime
      ..updatePanelStyle(content?.snapshot.session.toProjectionStyle())
      ..bindScene(content?.sceneDocument)
      ..syncEvent(
        content?.snapshot.anchor.toProjectionSyncEvent(),
        nowMs: _currentPlaybackTimeMs(),
      );
  }

  DesktopPanelRenderPlan? _resolvePanelRenderPlan(
    int? estimatedPlaybackTimeMs,
  ) {
    final DesktopPanelContentState? content = _content;
    if (content == null || content.sceneDocument == null) {
      return null;
    }
    final DesktopSceneRef? sceneRef = content.snapshot.sceneRef;
    final String? anchorSceneId = content.snapshot.anchor.sceneId;
    if (sceneRef != null &&
        anchorSceneId != null &&
        sceneRef.sceneId != anchorSceneId) {
      return null;
    }
    return _lyricsRuntime.buildPanelRenderPlan(
      currentTimeMs: estimatedPlaybackTimeMs,
    );
  }

  bool _shouldTickPlayback() {
    final DesktopPanelContentState? content = _content;
    return content != null &&
        (_surface?.visible ?? false) &&
        content.snapshot.anchor.isPlaying &&
        _resolvePanelRenderPlan(
              _playbackTicker.estimatedPlaybackTimeMsNotifier.value,
            ) !=
            null;
  }

  int _currentPlaybackTimeMs() {
    return widget.nowMsFactory?.call() ?? DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> _showPanelContextMenu(
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
          items: buildPanelMenuEntries(widget.strings, actions),
        );
    if (action != null) {
      await _dispatchPanelAction(action);
    }
  }

  Future<bool> _dispatchPanelAction(
    DesktopWindowActionType action, {
    DesktopPlaybackControlTask? controlTask,
  }) async {
    final int? instanceId = widget.launch.instanceId;
    final int? panelId = widget.launch.panelId;
    if (instanceId == null || panelId == null) {
      return false;
    }
    return _runtime.notifyPanelAction(
      DesktopPanelActionIntent(
        instanceId: instanceId,
        panelId: panelId,
        action: action,
        controlTask: controlTask,
      ),
    );
  }

  DesktopPanelContentState _emptyPanelContent() {
    return const DesktopPanelContentState(
      snapshot: DesktopPanelWindowSnapshot(
        session: DesktopPanelSessionSnapshot.empty(),
        anchor: DesktopPanelAnchorSnapshot(),
      ),
      sceneDocument: null,
    );
  }
}
