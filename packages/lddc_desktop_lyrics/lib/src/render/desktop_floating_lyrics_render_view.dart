import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/desktop_style_models.dart';
import 'desktop_lyrics_painter.dart';
import 'desktop_render_cache.dart';
import 'desktop_render_layout_engine.dart';
import 'desktop_render_models.dart';

typedef DesktopFloatingFrameCandidateHandler =
    Future<bool> Function(DesktopFloatingFrameMetrics metrics);
typedef DesktopFloatingFrameCommittedHandler =
    Future<void> Function(DesktopFloatingFrameMetrics metrics);

/// 浮窗歌词真实绘制入口。
///
/// 布局变化先生成 candidate frame，几何层确认原生窗口可容纳后才替换
/// committed frame。播放进度只更新已提交帧的轻量状态，不进入 resize 链。
class DesktopFloatingLyricsRenderView extends StatefulWidget {
  const DesktopFloatingLyricsRenderView({
    required this.title,
    this.subtitle = '',
    this.contentRevision = 0,
    this.renderIdentity,
    required this.renderPlan,
    this.renderPlanResolver,
    this.estimatedPlaybackTimeListenable,
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
    this.fontSizeMode = DesktopFloatingFontSizeMode.fixedFont,
    this.showFurigana = true,
    this.layoutEngine = const DesktopRenderLayoutEngine(),
    this.onFrameCandidate,
    this.onFrameCommitted,
    super.key,
  });

  final String title;
  final String subtitle;
  final int contentRevision;
  final String? renderIdentity;
  final DesktopFloatingRenderPlan? renderPlan;
  final DesktopFloatingRenderPlan? Function(int? estimatedPlaybackTimeMs)?
  renderPlanResolver;
  final ValueListenable<int?>? estimatedPlaybackTimeListenable;
  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final String fontFamily;
  final double fontSize;
  final DesktopFloatingFontSizeMode fontSizeMode;
  final bool showFurigana;
  final DesktopRenderLayoutEngine layoutEngine;
  final DesktopFloatingFrameCandidateHandler? onFrameCandidate;
  final DesktopFloatingFrameCommittedHandler? onFrameCommitted;

  @override
  State<DesktopFloatingLyricsRenderView> createState() =>
      _DesktopFloatingLyricsRenderViewState();
}

class _DesktopFloatingLyricsRenderViewState
    extends State<DesktopFloatingLyricsRenderView> {
  final DesktopLinePictureCache _pictureCache = DesktopLinePictureCache();
  final DesktopGlyphMeasureCache _glyphMeasureCache =
      DesktopGlyphMeasureCache();
  final DesktopLineMeasureCache _lineMeasureCache = DesktopLineMeasureCache();
  final ValueNotifier<int> _repaintRevision = ValueNotifier<int>(0);

  DesktopFloatingLayoutCacheKey? _layoutKey;
  DesktopFloatingLayoutDocument? _layoutDocument;
  int _layoutRevision = 0;
  DesktopFloatingPainterFrame? _committedFrame;
  int _committedContentRevision = -1;
  int _committedLayoutRevision = -1;
  _DesktopFloatingFrameCandidate? _candidate;
  bool _candidateEvaluationScheduled = false;
  bool _candidateEvaluationInFlight = false;
  Size _viewportSize = Size.zero;
  double _devicePixelRatio = 1;
  ValueListenable<int?>? _boundEstimatedPlaybackListenable;

  @override
  void initState() {
    super.initState();
    _bindEstimatedPlaybackListenable(widget.estimatedPlaybackTimeListenable);
  }

  @override
  void didUpdateWidget(covariant DesktopFloatingLyricsRenderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.estimatedPlaybackTimeListenable !=
        widget.estimatedPlaybackTimeListenable) {
      _bindEstimatedPlaybackListenable(widget.estimatedPlaybackTimeListenable);
    }
    if (oldWidget.layoutEngine != widget.layoutEngine) {
      _layoutKey = null;
      _layoutDocument = null;
    }
  }

  @override
  void dispose() {
    _unbindEstimatedPlaybackListenable();
    _pictureCache.dispose();
    _glyphMeasureCache.dispose();
    _lineMeasureCache.dispose();
    _repaintRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _devicePixelRatio = View.of(context).devicePixelRatio;
    final String renderSignature = _renderIdentityOf(widget);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _viewportSize = Size(
          constraints.hasBoundedWidth ? math.max(constraints.maxWidth, 1) : 1,
          constraints.hasBoundedHeight
              ? math.max(constraints.maxHeight, 1)
              : math.max(widget.fontSize * 2, 1),
        );
        final DesktopFloatingRenderPlan? plan = _resolveRenderPlan(
          _currentEstimatedPlaybackTime(),
        );
        if (plan != null) {
          _prepareFrame(plan: plan, renderSignature: renderSignature);
        }
        final DesktopFloatingPainterFrame? committed = _committedFrame;
        if (committed == null) {
          return const SizedBox.expand();
        }
        return _buildFloatingPainter(
          context,
          repaint: _repaintRevision,
          resolveFrame: () => _committedFrame,
        );
      },
    );
  }

  void _prepareFrame({
    required DesktopFloatingRenderPlan plan,
    required String renderSignature,
  }) {
    if (_viewportSize == Size.zero || !plan.hasAnyTrack) {
      return;
    }
    final DesktopFloatingLayoutDocument? document =
        _resolveFloatingLayoutDocument(plan);
    if (document == null || !document.hasAnyLine) {
      return;
    }
    final DesktopFloatingPainterFrame frame = _buildFloatingPainterFrame(
      plan: plan,
      document: document,
      estimatedPlaybackTimeMs: _currentEstimatedPlaybackTime(),
    );
    final bool matchesCommitted =
        _committedContentRevision == widget.contentRevision &&
        _committedLayoutRevision == _layoutRevision;
    if (matchesCommitted && _candidate == null) {
      _committedFrame = frame;
      return;
    }
    final DesktopFloatingFrameMetrics metrics = DesktopFloatingFrameMetrics(
      contentRevision: widget.contentRevision,
      layoutRevision: _layoutRevision,
      resolvedFontSize: document.fontSize,
      renderInsets: document.renderInsets,
      preferredHeight: document.preferredHeight,
    );
    final _DesktopFloatingFrameCandidate next = _DesktopFloatingFrameCandidate(
      renderSignature: renderSignature,
      frame: frame,
      metrics: metrics,
    );
    if (widget.onFrameCandidate == null) {
      _committedFrame = frame;
      _committedContentRevision = metrics.contentRevision;
      _committedLayoutRevision = metrics.layoutRevision;
      _candidate = null;
      _reportCommittedMetrics(metrics);
      return;
    }
    final _DesktopFloatingFrameCandidate? current = _candidate;
    if (current == null || !current.hasSameIdentity(next)) {
      _candidate = next;
    } else {
      _candidate = current.copyWith(frame: frame);
    }
    _scheduleCandidateEvaluation();
  }

  DesktopFloatingLayoutDocument? _resolveFloatingLayoutDocument(
    DesktopFloatingRenderPlan plan,
  ) {
    final DesktopFloatingLayoutCacheKey nextKey = DesktopFloatingLayoutCacheKey(
      planGeometryHash: desktopHashFloatingPlanGeometry(plan),
      viewportWidth: math.max(_viewportSize.width.round(), 1),
      // 固定字号布局不依赖窗口高度。把高度从缓存身份中移除，可避免自动
      // 增高后再次生成同几何 candidate，形成无意义的第二轮事务。
      viewportHeight:
          widget.fontSizeMode == DesktopFloatingFontSizeMode.fixedFont
          ? 0
          : math.max(_viewportSize.height.round(), 1),
      fontFamily: widget.fontFamily,
      configuredFontSize: widget.fontSize,
      devicePixelRatio: _devicePixelRatio,
      fontSizeMode: widget.fontSizeMode,
      showFurigana: widget.showFurigana,
    );
    if (_layoutKey == nextKey && _layoutDocument != null) {
      return _layoutDocument;
    }
    _layoutKey = nextKey;
    _layoutRevision += 1;
    _layoutDocument =
        DesktopRenderFrameCompiler(
          layoutEngine: widget.layoutEngine,
        ).buildFloatingLayoutDocument(
          plan: plan,
          viewportSize: _viewportSize,
          fontFamily: widget.fontFamily,
          configuredFontSize: widget.fontSize,
          fontSizeMode: widget.fontSizeMode,
          showFurigana: widget.showFurigana,
          devicePixelRatio: _devicePixelRatio,
          glyphMeasureCache: _glyphMeasureCache,
          lineMeasureCache: _lineMeasureCache,
        );
    return _layoutDocument;
  }

  DesktopFloatingPainterFrame _buildFloatingPainterFrame({
    required DesktopFloatingRenderPlan plan,
    required DesktopFloatingLayoutDocument document,
    required int? estimatedPlaybackTimeMs,
  }) {
    return DesktopRenderFrameCompiler(
      layoutEngine: widget.layoutEngine,
    ).buildFloatingPainterFrame(
      plan: plan,
      document: document,
      estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
    );
  }

  void _scheduleCandidateEvaluation() {
    if (_candidateEvaluationScheduled || _candidateEvaluationInFlight) {
      return;
    }
    _candidateEvaluationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _candidateEvaluationScheduled = false;
      if (!mounted) {
        return;
      }
      unawaited(_evaluateCandidate());
    });
  }

  Future<void> _evaluateCandidate() async {
    final _DesktopFloatingFrameCandidate? candidate = _candidate;
    if (candidate == null || _candidateEvaluationInFlight) {
      return;
    }
    _candidateEvaluationInFlight = true;
    bool accepted = false;
    try {
      accepted = await widget.onFrameCandidate?.call(candidate.metrics) ?? true;
    } on Object catch (error, stackTrace) {
      _reportCallbackError(
        callbackName: 'onFrameCandidate',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _candidateEvaluationInFlight = false;
    }
    if (!mounted) {
      return;
    }
    if (!identical(_candidate, candidate)) {
      // 旧 candidate 等待原生几何确认时，更新可能已经把它替换为最新
      // revision。此处已经释放 in-flight 所有权，必须立即继续处理最新值；
      // 若再次等待 post-frame，而页面此后没有新帧，最新歌词会永久停在
      // candidate，表现为切歌或行数变化后仍显示上一份 committed frame。
      unawaited(_evaluateCandidate());
      return;
    }
    if (!accepted) {
      return;
    }
    setState(() {
      _committedFrame = candidate.frame;
      _committedContentRevision = candidate.metrics.contentRevision;
      _committedLayoutRevision = candidate.metrics.layoutRevision;
      _candidate = null;
      _repaintRevision.value += 1;
    });
    _reportCommittedMetrics(candidate.metrics);
  }

  void _reportCommittedMetrics(DesktopFloatingFrameMetrics metrics) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _committedContentRevision != metrics.contentRevision ||
          _committedLayoutRevision != metrics.layoutRevision) {
        return;
      }
      final DesktopFloatingFrameCommittedHandler? callback =
          widget.onFrameCommitted;
      if (callback == null) {
        return;
      }
      try {
        unawaited(
          callback(metrics).catchError((Object error, StackTrace stackTrace) {
            _reportCallbackError(
              callbackName: 'onFrameCommitted',
              error: error,
              stackTrace: stackTrace,
            );
          }),
        );
      } on Object catch (error, stackTrace) {
        _reportCallbackError(
          callbackName: 'onFrameCommitted',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  void _refreshPlaybackFrame() {
    final DesktopFloatingRenderPlan? plan = _resolveRenderPlan(
      _currentEstimatedPlaybackTime(),
    );
    if (plan == null || _viewportSize == Size.zero) {
      return;
    }
    _prepareFrame(plan: plan, renderSignature: _renderIdentityOf(widget));
    if (mounted) {
      _repaintRevision.value += 1;
    }
  }

  int? _currentEstimatedPlaybackTime() {
    return widget.estimatedPlaybackTimeListenable?.value;
  }

  DesktopFloatingRenderPlan? _resolveRenderPlan(int? estimatedPlaybackTimeMs) {
    final DesktopFloatingRenderPlan? Function(int? estimatedPlaybackTimeMs)?
    resolver = widget.renderPlanResolver;
    if (resolver != null) {
      return resolver(estimatedPlaybackTimeMs);
    }
    if (widget.renderPlan != null) {
      return widget.renderPlan;
    }
    return null;
  }

  void _bindEstimatedPlaybackListenable(ValueListenable<int?>? listenable) {
    if (identical(_boundEstimatedPlaybackListenable, listenable)) {
      return;
    }
    _unbindEstimatedPlaybackListenable();
    _boundEstimatedPlaybackListenable = listenable;
    listenable?.addListener(_refreshPlaybackFrame);
  }

  void _unbindEstimatedPlaybackListenable() {
    _boundEstimatedPlaybackListenable?.removeListener(_refreshPlaybackFrame);
    _boundEstimatedPlaybackListenable = null;
  }

  String _renderIdentityOf(DesktopFloatingLyricsRenderView widget) {
    final String identity = widget.renderIdentity?.trim() ?? '';
    if (identity.isNotEmpty) {
      return identity;
    }
    return '${widget.title.trim()}\n${widget.subtitle.trim()}';
  }

  Widget _buildFloatingPainter(
    BuildContext context, {
    required DesktopFloatingPainterFrame? Function() resolveFrame,
    Listenable? repaint,
  }) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: DesktopFloatingLyricsPainter(
          resolveFrame: resolveFrame,
          repaint: repaint,
          playedColors: widget.playedColors,
          unplayedColors: widget.unplayedColors,
          layoutEngine: widget.layoutEngine,
          pictureCache: _pictureCache,
          devicePixelRatio: _devicePixelRatio,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  void _reportCallbackError({
    required String callbackName,
    required Object error,
    required StackTrace stackTrace,
  }) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'lddc desktop lyrics render',
        context: ErrorDescription('执行 $callbackName 时'),
      ),
    );
  }
}

class _DesktopFloatingFrameCandidate {
  const _DesktopFloatingFrameCandidate({
    required this.renderSignature,
    required this.frame,
    required this.metrics,
  });

  final String renderSignature;
  final DesktopFloatingPainterFrame frame;
  final DesktopFloatingFrameMetrics metrics;

  bool hasSameIdentity(_DesktopFloatingFrameCandidate other) {
    return renderSignature == other.renderSignature &&
        metrics.contentRevision == other.metrics.contentRevision &&
        metrics.layoutRevision == other.metrics.layoutRevision;
  }

  _DesktopFloatingFrameCandidate copyWith({
    DesktopFloatingPainterFrame? frame,
  }) {
    return _DesktopFloatingFrameCandidate(
      renderSignature: renderSignature,
      frame: frame ?? this.frame,
      metrics: metrics,
    );
  }
}
