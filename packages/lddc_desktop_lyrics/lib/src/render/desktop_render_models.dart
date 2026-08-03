import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 当前渲染代际的完整身份。
///
/// 说明：
/// - 该身份同时覆盖内容、样式、几何、DPR 与 surface 观测代际。
/// - generation 失效时，任何 backend artifact 都必须整代废弃。
class DesktopRenderGenerationKey {
  const DesktopRenderGenerationKey({
    required this.contentIdentity,
    required this.renderIdentity,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.devicePixelRatio,
    required this.themeSignature,
  });

  final String contentIdentity;
  final String renderIdentity;
  final int viewportWidth;
  final int viewportHeight;
  final double devicePixelRatio;
  final int themeSignature;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DesktopRenderGenerationKey &&
        other.contentIdentity == contentIdentity &&
        other.renderIdentity == renderIdentity &&
        other.viewportWidth == viewportWidth &&
        other.viewportHeight == viewportHeight &&
        other.devicePixelRatio == devicePixelRatio &&
        other.themeSignature == themeSignature;
  }

  @override
  int get hashCode => Object.hash(
    contentIdentity,
    renderIdentity,
    viewportWidth,
    viewportHeight,
    devicePixelRatio,
    themeSignature,
  );
}

/// 渲染层统一使用的行状态。
enum DesktopRenderLineState { played, unplayed, active }

/// 共享渲染层的词级时间片段。
class DesktopRenderWordPlan {
  const DesktopRenderWordPlan({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String text;
  final int? startMs;
  final int? endMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{'text': text, 'startMs': startMs, 'endMs': endMs};
  }
}

/// 共享渲染层的单行描述。
class DesktopRenderLinePlan {
  DesktopRenderLinePlan({
    required this.origIndex,
    required this.lang,
    required this.text,
    required this.state,
    this.activeProgress = const CharProgress(charIndex: 0, charRatio: 0.0),
    double opacity = 1.0,
    this.transitionStartMs,
    this.transitionEndMs,
    this.align = Direction.left,
    List<RubySpan> rubies = const <RubySpan>[],
    List<DesktopRenderWordPlan> words = const <DesktopRenderWordPlan>[],
  }) : opacity = _validateOpacity(opacity),
       rubies = List<RubySpan>.unmodifiable(rubies),
       words = List<DesktopRenderWordPlan>.unmodifiable(words);

  final int origIndex;
  final String lang;
  final String text;
  final DesktopRenderLineState state;
  final CharProgress activeProgress;
  final double opacity;
  final int? transitionStartMs;
  final int? transitionEndMs;
  final Direction align;
  final List<RubySpan> rubies;
  final List<DesktopRenderWordPlan> words;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'origIndex': origIndex,
      'lang': lang,
      'text': text,
      'state': state.name,
      'activeProgress': <String, Object?>{
        'charIndex': activeProgress.charIndex,
        'charRatio': activeProgress.charRatio,
      },
      'opacity': opacity,
      'transitionStartMs': transitionStartMs,
      'transitionEndMs': transitionEndMs,
      'align': align.name,
      'rubies': <Map<String, Object?>>[
        for (final RubySpan ruby in rubies)
          <String, Object?>{
            'start': ruby.start,
            'end': ruby.end,
            'ruby': ruby.ruby,
          },
      ],
      'words': <Map<String, Object?>>[
        for (final DesktopRenderWordPlan word in words) word.toJson(),
      ],
    };
  }
}

/// 浮窗单轨描述。
class DesktopRenderTrackPlan {
  DesktopRenderTrackPlan({
    required this.side,
    required this.track,
    required this.focusedOrigIndex,
    required List<DesktopRenderLinePlan> lines,
  }) : lines = List<DesktopRenderLinePlan>.unmodifiable(lines);

  final Direction side;
  final int track;
  final int focusedOrigIndex;
  final List<DesktopRenderLinePlan> lines;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'side': side.name,
      'track': track,
      'focusedOrigIndex': focusedOrigIndex,
      'lines': <Map<String, Object?>>[
        for (final DesktopRenderLinePlan line in lines) line.toJson(),
      ],
    };
  }
}

/// 面板单块描述。
class DesktopRenderBlockPlan {
  DesktopRenderBlockPlan({
    required this.origIndex,
    required this.state,
    required List<DesktopRenderLinePlan> lines,
  }) : lines = List<DesktopRenderLinePlan>.unmodifiable(lines);

  final int origIndex;
  final DesktopRenderLineState state;
  final List<DesktopRenderLinePlan> lines;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'origIndex': origIndex,
      'state': state.name,
      'lines': <Map<String, Object?>>[
        for (final DesktopRenderLinePlan line in lines) line.toJson(),
      ],
    };
  }
}

/// 浮窗结构化渲染计划。
class DesktopFloatingRenderPlan {
  DesktopFloatingRenderPlan({
    required List<DesktopRenderTrackPlan> leftTracks,
    required List<DesktopRenderTrackPlan> rightTracks,
    required this.hasRubiesGlobally,
  }) : leftTracks = List<DesktopRenderTrackPlan>.unmodifiable(leftTracks),
       rightTracks = List<DesktopRenderTrackPlan>.unmodifiable(rightTracks);

  final List<DesktopRenderTrackPlan> leftTracks;
  final List<DesktopRenderTrackPlan> rightTracks;
  final bool hasRubiesGlobally;

  bool get hasAnyTrack => leftTracks.isNotEmpty || rightTracks.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'leftTracks': <Map<String, Object?>>[
        for (final DesktopRenderTrackPlan track in leftTracks) track.toJson(),
      ],
      'rightTracks': <Map<String, Object?>>[
        for (final DesktopRenderTrackPlan track in rightTracks) track.toJson(),
      ],
      'hasRubiesGlobally': hasRubiesGlobally,
    };
  }
}

/// 面板结构化渲染计划。
class DesktopPanelRenderPlan {
  DesktopPanelRenderPlan({
    required this.mode,
    required this.activeIndex,
    required List<String> enabledLangs,
    required List<DesktopRenderBlockPlan> blocks,
  }) : enabledLangs = List<String>.unmodifiable(enabledLangs),
       blocks = List<DesktopRenderBlockPlan>.unmodifiable(blocks);

  final String mode;
  final int activeIndex;
  final List<String> enabledLangs;
  final List<DesktopRenderBlockPlan> blocks;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode,
      'activeIndex': activeIndex,
      'enabledLangs': enabledLangs,
      'blocks': <Map<String, Object?>>[
        for (final DesktopRenderBlockPlan block in blocks) block.toJson(),
      ],
    };
  }
}

/// 桌面歌词布局层使用的 Token 类型。
enum DesktopRenderTokenType { text, rubyGroup }

/// 原子渲染单元，对齐Python版 `RenderToken`。
class DesktopRenderToken {
  DesktopRenderToken({
    required this.type,
    required this.text,
    required this.rubyText,
    required this.baseWidth,
    required this.rubyWidth,
    required this.height,
    required this.ascent,
    required this.x,
    required this.leftOverhang,
    required this.rightOverhang,
    required List<int> charIndices,
    required List<double> charOffsets,
  }) : charIndices = List<int>.unmodifiable(charIndices),
       charOffsets = List<double>.unmodifiable(charOffsets);

  final DesktopRenderTokenType type;
  final String text;
  final String? rubyText;
  final double baseWidth;
  final double rubyWidth;
  final double height;
  final double ascent;
  final double x;
  final double leftOverhang;
  final double rightOverhang;
  final List<int> charIndices;
  final List<double> charOffsets;

  bool get hasRuby =>
      type == DesktopRenderTokenType.rubyGroup &&
      rubyText != null &&
      rubyText!.isNotEmpty;

  double get visualLeft => -leftOverhang;

  double get visualRight => baseWidth + rightOverhang;
}

class DesktopRenderLineLayoutSegment {
  DesktopRenderLineLayoutSegment({
    required this.charStart,
    required this.charEnd,
    required this.text,
    required this.ruby,
    required this.x,
    required this.width,
    required this.baseWidth,
    required this.rubyWidth,
    required List<double> charOffsets,
  }) : charOffsets = List<double>.unmodifiable(charOffsets);

  final int charStart;
  final int charEnd;
  final String text;
  final String? ruby;
  final double x;
  final double width;
  final double baseWidth;
  final double rubyWidth;
  final List<double> charOffsets;

  bool get hasRuby => ruby != null && ruby!.isNotEmpty;

  double get baseInsetX => math.max((width - baseWidth) / 2, 0);

  bool containsChar(int index) => charStart <= index && index < charEnd;
}

class DesktopRenderMeasuredLine {
  DesktopRenderMeasuredLine({
    required List<DesktopRenderLineLayoutSegment> segments,
    required this.contentWidth,
    required this.visualLine,
    required this.fontMetrics,
  }) : segments = List<DesktopRenderLineLayoutSegment>.unmodifiable(segments);

  final List<DesktopRenderLineLayoutSegment> segments;
  final double contentWidth;
  final DesktopRenderVisualLine visualLine;
  final DesktopRenderLineFontMetrics fontMetrics;

  double resolveHorizontalOffset({
    required double viewportWidth,
    required DesktopRenderLineState state,
    required CharProgress activeProgress,
    double leadingInset = 0,
    double trailingInset = 0,
  }) {
    if (contentWidth <= viewportWidth) {
      return 0;
    }
    final double cursorX = resolveCursorX(
      state: state,
      activeProgress: activeProgress,
    );
    final double idealOffsetX = viewportWidth * 0.35 - cursorX;
    final double minOffsetX =
        viewportWidth - trailingInset - visualLine.visualRight;
    final double maxOffsetX = leadingInset - visualLine.visualLeft;
    return idealOffsetX.clamp(minOffsetX, maxOffsetX);
  }

  double resolveCursorX({
    required DesktopRenderLineState state,
    required CharProgress activeProgress,
  }) {
    if (segments.isEmpty || visualLine.tokens.isEmpty) {
      return 0;
    }
    switch (state) {
      case DesktopRenderLineState.played:
        return visualLine.visualRight;
      case DesktopRenderLineState.unplayed:
        return 0;
      case DesktopRenderLineState.active:
        final int currentIndex = activeProgress.charIndex;
        final double currentRatio = activeProgress.charRatio.clamp(0.0, 1.0);
        final DesktopRenderToken lastToken = visualLine.tokens.last;
        if (lastToken.charIndices.isEmpty) {
          return visualLine.visualRight;
        }
        final int lastCharIndex = lastToken.charIndices.last;
        if (currentIndex > lastCharIndex) {
          return visualLine.visualRight;
        }

        double cursorX = 0;
        for (final DesktopRenderToken token in visualLine.tokens) {
          if (token.charIndices.isEmpty) {
            continue;
          }
          final int startIndex = token.charIndices.first;
          final int endIndex = token.charIndices.last;
          if (startIndex <= currentIndex && currentIndex <= endIndex) {
            final int totalChars = token.charIndices.length;
            if (totalChars <= 0) {
              return token.x;
            }
            final int localIndex = currentIndex - startIndex;
            final double progress = ((localIndex + currentRatio) / totalChars)
                .clamp(0.0, 1.0);
            return (token.x + token.baseWidth * progress).clamp(
              0,
              visualLine.visualRight,
            );
          }
          if (endIndex < currentIndex) {
            cursorX = token.x + token.baseWidth + token.rightOverhang;
            continue;
          }
          if (startIndex > currentIndex) {
            break;
          }
        }
        return cursorX.clamp(0, visualLine.visualRight);
    }
  }

  double resolveSegmentBasePlayedWidth({
    required DesktopRenderLineLayoutSegment segment,
    required DesktopRenderLineState state,
    required CharProgress activeProgress,
  }) {
    if (segment.baseWidth <= 0) {
      return 0;
    }
    switch (state) {
      case DesktopRenderLineState.played:
        return segment.baseWidth;
      case DesktopRenderLineState.unplayed:
        return 0;
      case DesktopRenderLineState.active:
        final double globalCursorX = resolveCursorX(
          state: state,
          activeProgress: activeProgress,
        );
        return (globalCursorX - segment.x).clamp(0, segment.baseWidth);
    }
  }
}

/// 单行视觉布局结果，对齐Python版 `VisualLine`。
class DesktopRenderVisualLine {
  DesktopRenderVisualLine({
    required List<DesktopRenderToken> tokens,
    this.y = 0,
    this.height = 0,
    this.width = 0,
    this.startX = 0,
    this.visualLeft = 0,
    this.visualRight = 0,
    this.hasRubyLayout = false,
  }) : tokens = List<DesktopRenderToken>.unmodifiable(tokens);

  final List<DesktopRenderToken> tokens;
  final double y;
  final double height;
  final double width;
  final double startX;
  final double visualLeft;
  final double visualRight;
  final bool hasRubyLayout;
}

/// 单行共享字体度量快照。
///
/// 说明：
/// - 布局阶段与绘制阶段必须复用同一份字体度量，避免注音预留高度与
///   实际绘制基线不一致。
/// - 这里固定记录“当前样式下”的正文/注音高度与 ascent，不跟随具体文本变化。
class DesktopRenderLineFontMetrics {
  const DesktopRenderLineFontMetrics({
    required this.baseHeight,
    required this.baseAscent,
    required this.rubyHeight,
    required this.rubyAscent,
  });

  final double baseHeight;
  final double baseAscent;
  final double rubyHeight;
  final double rubyAscent;
}

/// 面板单块视觉布局结果，对齐Python版 `VisualBlock`。
class DesktopRenderVisualBlock {
  DesktopRenderVisualBlock({
    required this.origIndex,
    required this.virtualRect,
    required Map<String, List<DesktopRenderVisualLine>> lines,
  }) : lines = Map<String, List<DesktopRenderVisualLine>>.unmodifiable(
         <String, List<DesktopRenderVisualLine>>{
           for (final MapEntry<String, List<DesktopRenderVisualLine>> entry
               in lines.entries)
             entry.key: List<DesktopRenderVisualLine>.unmodifiable(entry.value),
         },
       );

  final int origIndex;
  final Rect virtualRect;
  final Map<String, List<DesktopRenderVisualLine>> lines;

  double get centerY => virtualRect.top + virtualRect.height / 2;
}

/// 浮窗/面板绘制时的单行载荷。
class DesktopLyricsPainterLine {
  const DesktopLyricsPainterLine({
    required this.plan,
    required this.visualLine,
    required this.measuredLine,
    required this.baseStyle,
    required this.rubyStyle,
    required this.fontMetrics,
    required this.opacity,
  });

  final DesktopRenderLinePlan plan;
  final DesktopRenderVisualLine visualLine;
  final DesktopRenderMeasuredLine measuredLine;
  final TextStyle baseStyle;
  final TextStyle rubyStyle;
  final DesktopRenderLineFontMetrics fontMetrics;
  final double opacity;
}

class DesktopStaticLyricsLine {
  const DesktopStaticLyricsLine({
    required this.origIndex,
    required this.lang,
    required this.visualLine,
    required this.measuredLine,
    required this.baseStyle,
    required this.rubyStyle,
    required this.fontMetrics,
  });

  final int origIndex;
  final String lang;
  final DesktopRenderVisualLine visualLine;
  final DesktopRenderMeasuredLine measuredLine;
  final TextStyle baseStyle;
  final TextStyle rubyStyle;
  final DesktopRenderLineFontMetrics fontMetrics;
}

enum DesktopFloatingFontSizeMode { fixedFont, interactiveResize }

class DesktopFloatingFrameMetrics {
  const DesktopFloatingFrameMetrics({
    this.contentRevision = 0,
    this.layoutRevision = 0,
    required this.resolvedFontSize,
    this.renderInsets = EdgeInsets.zero,
    required this.preferredHeight,
  });

  final int contentRevision;
  final int layoutRevision;
  final double resolvedFontSize;
  final EdgeInsets renderInsets;
  final double preferredHeight;
}

/// 浮窗当前视口下的静态布局文档。
class DesktopFloatingLayoutDocument {
  DesktopFloatingLayoutDocument({
    required List<DesktopStaticLyricsLine> leftLines,
    required List<DesktopStaticLyricsLine> rightLines,
    required this.fontSize,
    required this.renderInsets,
    required this.preferredHeight,
    required this.hasRubiesGlobally,
  }) : leftLines = List<DesktopStaticLyricsLine>.unmodifiable(leftLines),
       rightLines = List<DesktopStaticLyricsLine>.unmodifiable(rightLines);

  final List<DesktopStaticLyricsLine> leftLines;
  final List<DesktopStaticLyricsLine> rightLines;
  final double fontSize;
  final EdgeInsets renderInsets;
  final double preferredHeight;
  final bool hasRubiesGlobally;

  bool get hasAnyLine => leftLines.isNotEmpty || rightLines.isNotEmpty;
}

/// 浮窗绘制帧。
class DesktopFloatingPainterFrame {
  DesktopFloatingPainterFrame({
    required this.document,
    required List<DesktopLyricsPainterLine> leftLines,
    required List<DesktopLyricsPainterLine> rightLines,
    required this.estimatedPlaybackTimeMs,
  }) : leftLines = List<DesktopLyricsPainterLine>.unmodifiable(leftLines),
       rightLines = List<DesktopLyricsPainterLine>.unmodifiable(rightLines);

  final DesktopFloatingLayoutDocument document;
  final List<DesktopLyricsPainterLine> leftLines;
  final List<DesktopLyricsPainterLine> rightLines;
  final int? estimatedPlaybackTimeMs;
}

class DesktopStaticPanelBlock {
  DesktopStaticPanelBlock({
    required this.origIndex,
    required this.virtualRect,
    required Map<String, List<DesktopStaticLyricsLine>> lines,
  }) : lines = Map<String, List<DesktopStaticLyricsLine>>.unmodifiable(
         <String, List<DesktopStaticLyricsLine>>{
           for (final MapEntry<String, List<DesktopStaticLyricsLine>> entry
               in lines.entries)
             entry.key: List<DesktopStaticLyricsLine>.unmodifiable(entry.value),
         },
       );

  final int origIndex;
  final Rect virtualRect;
  final Map<String, List<DesktopStaticLyricsLine>> lines;
}

/// 面板当前视口下的静态布局文档。
class DesktopPanelLayoutDocument {
  DesktopPanelLayoutDocument({
    required List<DesktopStaticPanelBlock> blocks,
    required this.contentHeight,
  }) : blocks = List<DesktopStaticPanelBlock>.unmodifiable(blocks);

  final List<DesktopStaticPanelBlock> blocks;
  final double contentHeight;
}

/// 面板单块绘制载荷。
class DesktopPanelPainterBlock {
  DesktopPanelPainterBlock({
    required this.origIndex,
    required this.state,
    required this.virtualRect,
    required Map<String, List<DesktopLyricsPainterLine>> lines,
  }) : lines = Map<String, List<DesktopLyricsPainterLine>>.unmodifiable(<
         String,
         List<DesktopLyricsPainterLine>
       >{
         for (final MapEntry<String, List<DesktopLyricsPainterLine>> entry
             in lines.entries)
           entry.key: List<DesktopLyricsPainterLine>.unmodifiable(entry.value),
       });

  final int origIndex;
  final DesktopRenderLineState state;
  final Rect virtualRect;
  final Map<String, List<DesktopLyricsPainterLine>> lines;
}

/// 面板绘制帧。
class DesktopPanelPainterFrame {
  DesktopPanelPainterFrame({
    required this.document,
    required List<DesktopPanelPainterBlock> blocks,
    required this.targetScrollY,
  }) : blocks = List<DesktopPanelPainterBlock>.unmodifiable(blocks);

  final DesktopPanelLayoutDocument document;
  final List<DesktopPanelPainterBlock> blocks;
  final double targetScrollY;
}

int desktopHashFloatingPlanGeometry(DesktopFloatingRenderPlan plan) {
  int result = Object.hash(plan.hasRubiesGlobally, plan.leftTracks.length);
  for (final DesktopRenderTrackPlan track in <DesktopRenderTrackPlan>[
    ...plan.leftTracks,
    ...plan.rightTracks,
  ]) {
    result = Object.hash(
      result,
      track.side,
      track.track,
      track.focusedOrigIndex,
      track.lines.length,
    );
    for (final DesktopRenderLinePlan line in track.lines) {
      result = Object.hash(
        result,
        line.origIndex,
        line.lang,
        line.text,
        line.align,
        _hashRubies(line.rubies),
      );
    }
  }
  return result;
}

int desktopHashPanelPlanGeometry(DesktopPanelRenderPlan plan) {
  int result = Object.hash(
    plan.mode,
    plan.blocks.length,
    plan.enabledLangs.length,
  );
  for (final String lang in plan.enabledLangs) {
    result = Object.hash(result, lang);
  }
  for (final DesktopRenderBlockPlan block in plan.blocks) {
    result = Object.hash(result, block.origIndex, block.lines.length);
    for (final DesktopRenderLinePlan line in block.lines) {
      result = Object.hash(
        result,
        line.origIndex,
        line.lang,
        line.text,
        line.align,
        _hashRubies(line.rubies),
      );
    }
  }
  return result;
}

int _hashRubies(List<Object> rubies) {
  int result = rubies.length;
  for (final Object ruby in rubies) {
    result = Object.hash(result, ruby);
  }
  return result;
}

double _validateOpacity(double value) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, 'opacity', '必须是 0 到 1 之间的有限数值');
  }
  return value;
}
