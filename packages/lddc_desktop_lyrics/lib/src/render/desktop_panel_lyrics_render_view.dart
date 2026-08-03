import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/desktop_style_models.dart';
import 'desktop_lyrics_painter.dart';
import 'desktop_render_cache.dart';
import 'desktop_render_layout_engine.dart';
import 'desktop_render_models.dart';

const int _kDefaultPanelRefreshRate = 60;

/// 面板歌词渲染入口。
///
/// 当前 active path 只复用 `DesktopRenderFrameCompiler` 的纯布局语义，
/// 面板视图层只维护滚动、缓存和 Flutter 生命周期。
class DesktopPanelLyricsRenderView extends StatefulWidget {
  const DesktopPanelLyricsRenderView({
    required this.renderPlan,
    this.renderGenerationKey = const DesktopRenderGenerationKey(
      contentIdentity: 'panel',
      renderIdentity: 'panel',
      viewportWidth: 1,
      viewportHeight: 1,
      devicePixelRatio: 1,
      themeSignature: 0,
    ),
    this.renderPlanResolver,
    this.playedColors = const <RgbColor>[
      RgbColor(0, 255, 255),
      RgbColor(0, 128, 255),
    ],
    this.unplayedColors = const <RgbColor>[
      RgbColor(255, 0, 0),
      RgbColor(255, 128, 128),
    ],
    this.fontFamily = '',
    this.fontSize = 30,
    this.showFurigana = true,
    this.refreshRate = _kDefaultPanelRefreshRate,
    this.layoutEngine = const DesktopRenderLayoutEngine(),
    this.estimatedPlaybackTimeListenable,
    super.key,
  });

  final DesktopPanelRenderPlan? renderPlan;
  final DesktopRenderGenerationKey renderGenerationKey;
  final DesktopPanelRenderPlan? Function(int? estimatedPlaybackTimeMs)?
  renderPlanResolver;
  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final String fontFamily;
  final double fontSize;
  final bool showFurigana;
  final int refreshRate;
  final DesktopRenderLayoutEngine layoutEngine;
  final ValueListenable<int?>? estimatedPlaybackTimeListenable;

  @override
  State<DesktopPanelLyricsRenderView> createState() =>
      _DesktopPanelLyricsRenderViewState();
}

class _DesktopPanelLyricsRenderViewState
    extends State<DesktopPanelLyricsRenderView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scrollController;
  // Flutter 承载优化：面板 block 几何缓存保留在视图层，activeIndex/scrollY
  // 变化时只更新当前帧与滚动采样，不改变Python版 `_trigger_relayout()` 语义。
  final DesktopLinePictureCache _pictureCache = DesktopLinePictureCache();
  final DesktopGlyphMeasureCache _glyphMeasureCache =
      DesktopGlyphMeasureCache();
  final ValueNotifier<double> _sampledScrollYNotifier = ValueNotifier<double>(
    0,
  );
  final ValueNotifier<int> _repaintRevision = ValueNotifier<int>(0);
  late final Listenable _painterRepaint;

  DesktopPanelLayoutCacheKey? _layoutKey;
  DesktopPanelLayoutDocument? _layoutDocument;
  DesktopPanelPainterFrame? _currentFrame;
  DesktopPanelPainterFrame? _lastRenderableFrame;
  ValueListenable<int?>? _boundEstimatedPlaybackListenable;
  bool _scrollSeeded = false;
  double _lastTargetScrollY = 0;
  Size _lastViewportSize = Size.zero;
  Size _currentViewportSize = Size.zero;
  int _lastActiveIndex = -1;
  int _lastScrollSampleUs = 0;

  @override
  void initState() {
    super.initState();
    _painterRepaint = Listenable.merge(<Listenable>[
      _repaintRevision,
      _sampledScrollYNotifier,
    ]);
    _scrollController = AnimationController.unbounded(vsync: this);
    _scrollController.addListener(_handleScrollControllerTick);
    _bindEstimatedPlaybackListenable(widget.estimatedPlaybackTimeListenable);
    _pictureCache.bindGeneration(widget.renderGenerationKey);
  }

  @override
  void didUpdateWidget(covariant DesktopPanelLyricsRenderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderGenerationKey.contentIdentity !=
        widget.renderGenerationKey.contentIdentity) {
      _resetForGeometryEpochChange();
    }
    if (oldWidget.renderGenerationKey != widget.renderGenerationKey) {
      _pictureCache.bindGeneration(widget.renderGenerationKey);
    }
    if (oldWidget.layoutEngine != widget.layoutEngine ||
        oldWidget.renderGenerationKey.devicePixelRatio !=
            widget.renderGenerationKey.devicePixelRatio) {
      _layoutKey = null;
      _layoutDocument = null;
      _currentFrame = null;
    }
    if (oldWidget.estimatedPlaybackTimeListenable !=
        widget.estimatedPlaybackTimeListenable) {
      _bindEstimatedPlaybackListenable(widget.estimatedPlaybackTimeListenable);
    }
    if (oldWidget.refreshRate != widget.refreshRate) {
      _lastScrollSampleUs = 0;
      _pushScrollSample(force: true);
    }
  }

  @override
  void dispose() {
    _unbindEstimatedPlaybackListenable();
    _pictureCache.dispose();
    _glyphMeasureCache.dispose();
    _sampledScrollYNotifier.dispose();
    _repaintRevision.dispose();
    _scrollController.removeListener(_handleScrollControllerTick);
    _scrollController.dispose();
    super.dispose();
  }

  void _resetForGeometryEpochChange() {
    _scrollController.stop();
    _scrollController.value = 0;
    _layoutKey = null;
    _layoutDocument = null;
    _currentFrame = null;
    _lastRenderableFrame = null;
    _scrollSeeded = false;
    _lastTargetScrollY = 0;
    _lastViewportSize = Size.zero;
    _currentViewportSize = Size.zero;
    _lastActiveIndex = -1;
    _lastScrollSampleUs = 0;
    _sampledScrollYNotifier.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final DesktopPanelRenderPlan? initialPlan = _resolveRenderPlan(
      _currentEstimatedPlaybackTime(),
    );
    if (initialPlan == null) {
      return _buildFromCachedFrameOrEmpty(context);
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewportSize = Size(
          constraints.hasBoundedWidth ? math.max(constraints.maxWidth, 1) : 1,
          constraints.hasBoundedHeight
              ? math.max(constraints.maxHeight, 1)
              : math.max(widget.fontSize * 3, 1),
        );
        _currentViewportSize = viewportSize;
        final DesktopPanelRenderPlan? renderPlan = _resolveRenderPlan(
          _currentEstimatedPlaybackTime(),
        );
        if (renderPlan == null || !_syncCurrentFrame(renderPlan: renderPlan)) {
          return _buildFromCachedFrameOrEmpty(context);
        }
        final DesktopPanelPainterFrame frame = _currentFrame!;
        _lastRenderableFrame = frame;
        _syncScrollTarget(
          targetScrollY: frame.targetScrollY,
          viewportSize: viewportSize,
          activeIndex: renderPlan.activeIndex,
        );
        return _buildPainter(context);
      },
    );
  }

  int? _currentEstimatedPlaybackTime() {
    return widget.estimatedPlaybackTimeListenable?.value;
  }

  DesktopPanelRenderPlan? _resolveRenderPlan(int? estimatedPlaybackTimeMs) {
    final DesktopPanelRenderPlan? Function(int? estimatedPlaybackTimeMs)?
    resolver = widget.renderPlanResolver;
    if (resolver != null) {
      return resolver(estimatedPlaybackTimeMs);
    }
    final DesktopPanelRenderPlan? directPlan = widget.renderPlan;
    if (directPlan != null) {
      return directPlan;
    }
    return null;
  }

  bool _syncCurrentFrame({required DesktopPanelRenderPlan renderPlan}) {
    if (_currentViewportSize == Size.zero || renderPlan.blocks.isEmpty) {
      _currentFrame = null;
      return false;
    }
    final DesktopPanelLayoutDocument? document = _resolvePanelLayoutDocument(
      renderPlan,
    );
    if (document == null || document.blocks.isEmpty) {
      _currentFrame = null;
      return false;
    }
    _currentFrame = _buildPanelPainterFrame(
      plan: renderPlan,
      document: document,
      estimatedPlaybackTimeMs: _currentEstimatedPlaybackTime(),
    );
    return _currentFrame != null;
  }

  DesktopPanelLayoutDocument? _resolvePanelLayoutDocument(
    DesktopPanelRenderPlan plan,
  ) {
    final double configuredScale = widget.renderGenerationKey.devicePixelRatio;
    final double effectiveLayoutScale =
        configuredScale.isFinite && configuredScale > 0 ? configuredScale : 1.0;
    final DesktopPanelLayoutCacheKey nextKey = DesktopPanelLayoutCacheKey(
      planGeometryHash: desktopHashPanelPlanGeometry(plan),
      viewportWidth: math.max(_currentViewportSize.width.round(), 1),
      viewportHeight: math.max(_currentViewportSize.height.round(), 1),
      fontFamily: widget.fontFamily,
      configuredFontSize: widget.fontSize,
      layoutScale: effectiveLayoutScale,
      showFurigana: widget.showFurigana,
    );
    if (_layoutKey == nextKey && _layoutDocument != null) {
      return _layoutDocument;
    }
    _layoutKey = nextKey;
    _layoutDocument =
        DesktopRenderFrameCompiler(
          layoutEngine: widget.layoutEngine,
        ).buildPanelLayoutDocument(
          plan: plan,
          viewportSize: _currentViewportSize,
          fontFamily: widget.fontFamily,
          fontSize: widget.fontSize * effectiveLayoutScale,
          showFurigana: widget.showFurigana,
          glyphMeasureCache: _glyphMeasureCache,
        );
    return _layoutDocument;
  }

  DesktopPanelPainterFrame _buildPanelPainterFrame({
    required DesktopPanelRenderPlan plan,
    required DesktopPanelLayoutDocument document,
    required int? estimatedPlaybackTimeMs,
  }) {
    return DesktopRenderFrameCompiler(
      layoutEngine: widget.layoutEngine,
    ).buildPanelPainterFrame(
      plan: plan,
      document: document,
      viewportHeight: _currentViewportSize.height,
      estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
    );
  }

  bool _refreshCurrentFrame() {
    final DesktopPanelRenderPlan? renderPlan = _resolveRenderPlan(
      _currentEstimatedPlaybackTime(),
    );
    if (renderPlan == null) {
      return false;
    }
    final bool updated = _syncCurrentFrame(renderPlan: renderPlan);
    if (updated && _currentFrame != null) {
      _syncScrollTarget(
        targetScrollY: _currentFrame!.targetScrollY,
        viewportSize: _currentViewportSize,
        activeIndex: renderPlan.activeIndex,
      );
    }
    return updated;
  }

  void _bindEstimatedPlaybackListenable(ValueListenable<int?>? listenable) {
    if (identical(_boundEstimatedPlaybackListenable, listenable)) {
      return;
    }
    _unbindEstimatedPlaybackListenable();
    _boundEstimatedPlaybackListenable = listenable;
    listenable?.addListener(_handleEstimatedPlaybackChanged);
  }

  void _unbindEstimatedPlaybackListenable() {
    _boundEstimatedPlaybackListenable?.removeListener(
      _handleEstimatedPlaybackChanged,
    );
    _boundEstimatedPlaybackListenable = null;
  }

  void _handleEstimatedPlaybackChanged() {
    if (!_refreshCurrentFrame()) {
      return;
    }
    _lastRenderableFrame = _currentFrame;
    if (mounted) {
      _repaintRevision.value += 1;
    }
  }

  Widget _buildFromCachedFrameOrEmpty(BuildContext context) {
    final DesktopPanelPainterFrame? cachedFrame = _lastRenderableFrame;
    if (cachedFrame == null) {
      return const SizedBox.expand();
    }
    return _buildPainter(context);
  }

  Widget _buildPainter(BuildContext context) {
    final double devicePixelRatio = View.of(context).devicePixelRatio;
    return RepaintBoundary(
      child: CustomPaint(
        painter: DesktopPanelLyricsPainter(
          resolveFrame: () => _currentFrame ?? _lastRenderableFrame,
          resolveScrollY: () => _sampledScrollYNotifier.value,
          repaint: _painterRepaint,
          playedColors: widget.playedColors,
          unplayedColors: widget.unplayedColors,
          pictureCache: _pictureCache,
          devicePixelRatio: devicePixelRatio,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _syncScrollTarget({
    required double targetScrollY,
    required Size viewportSize,
    required int activeIndex,
  }) {
    final bool viewportChanged =
        (_lastViewportSize.width - viewportSize.width).abs() > 1 ||
        (_lastViewportSize.height - viewportSize.height).abs() > 1;
    final bool activeChanged = _lastActiveIndex != activeIndex;
    _lastViewportSize = viewportSize;
    _lastActiveIndex = activeIndex;

    if (!_scrollSeeded) {
      _scrollSeeded = true;
      _lastTargetScrollY = targetScrollY;
      _scrollController.value = targetScrollY;
      _pushScrollSample(force: true);
      return;
    }

    if (viewportChanged) {
      _lastTargetScrollY = targetScrollY;
      _scrollController.stop();
      _scrollController.value = targetScrollY;
      _pushScrollSample(force: true);
      return;
    }

    if ((targetScrollY - _lastTargetScrollY).abs() < 1) {
      return;
    }
    _lastTargetScrollY = targetScrollY;

    if (activeChanged) {
      _scrollController.animateTo(
        targetScrollY,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _scrollController.value = targetScrollY;
    _pushScrollSample(force: true);
  }

  void _handleScrollControllerTick() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      // MethodChannel 和 ValueNotifier 会在当前调用栈里同步通知 listener。
      // 这类跳转发生在 Flutter 帧外，currentFrameTimeStamp 此时为空；对应
      // 调用点随后会走 force 路径提交最终值，因此这里无需重复采样。
      return;
    }
    _pushScrollSample();
  }

  void _pushScrollSample({bool force = false}) {
    final double nextValue = _scrollController.value;
    if (force) {
      // 同步 seed/reset/jump 不属于动画帧，不读取帧时间。清零后允许下一次
      // 真正的动画帧立即采样，避免把两个不同时间域混在同一个节流状态中。
      _lastScrollSampleUs = 0;
      _sampledScrollYNotifier.value = nextValue;
      return;
    }
    final int nowUs =
        SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds;
    if (!_shouldSampleScroll(nowUs)) {
      return;
    }
    _lastScrollSampleUs = nowUs;
    if ((_sampledScrollYNotifier.value - nextValue).abs() < 0.001) {
      return;
    }
    _sampledScrollYNotifier.value = nextValue;
  }

  bool _shouldSampleScroll(int nowUs) {
    final int rate = widget.refreshRate > 0
        ? widget.refreshRate
        : _kDefaultPanelRefreshRate;
    final int intervalUs = (1000000 / rate).round();
    return _lastScrollSampleUs == 0 ||
        nowUs - _lastScrollSampleUs >= intervalUs;
  }
}
