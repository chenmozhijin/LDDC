import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/desktop_style_models.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'desktop_render_cache.dart';
import 'desktop_render_layout_engine.dart';
import 'desktop_render_models.dart';

@visibleForTesting
Canvas createDesktopRasterRecordingCanvas(
  ui.PictureRecorder recorder, {
  required double devicePixelRatio,
}) {
  final Canvas canvas = Canvas(recorder);
  // 缓存图 raster 尺寸会按 DPR 放大，因此录制坐标也必须同步放大，
  // 否则文字内容会被压缩进更大的物理图左侧，回贴后表现为高亮偏快。
  final double resolvedDevicePixelRatio = _resolveDevicePixelRatio(
    devicePixelRatio,
  );
  canvas.scale(resolvedDevicePixelRatio, resolvedDevicePixelRatio);
  return canvas;
}

/// 解析缓存位图在逻辑坐标系中的稳定绘制边界。
///
/// 说明：
/// - `DesktopCachedLinePicture.image` 已经是按 DPR 录制好的最终位图，
///   这里必须以实际 raster 尺寸反推逻辑宽高，不能再混用布局估算高度。
/// - 左上角与裁剪右边界统一吸附到物理像素，避免 active 行双层贴图在
///   亚像素滚动时发生轻微错位，露出下层未播放图。
@visibleForTesting
class DesktopResolvedPictureBounds {
  const DesktopResolvedPictureBounds({
    required this.imageBounds,
    required this.clipRect,
  });

  final Rect imageBounds;
  final Rect? clipRect;
}

@visibleForTesting
DesktopResolvedPictureBounds resolveDesktopResolvedPictureBounds({
  required DesktopLyricsPainterLine line,
  required Offset origin,
  required DesktopCachedLinePicture cachedPicture,
  required double devicePixelRatio,
  double? clipRight,
}) {
  final double resolvedDevicePixelRatio = _resolveDevicePixelRatio(
    devicePixelRatio,
  );
  final Offset imageTopLeft = _snapDesktopLogicalOffsetToPhysicalPixels(
    Offset(
      origin.dx + line.visualLine.visualLeft - cachedPicture.padding,
      origin.dy - cachedPicture.padding,
    ),
    resolvedDevicePixelRatio,
  );
  final Rect imageBounds = Rect.fromLTWH(
    imageTopLeft.dx,
    imageTopLeft.dy,
    cachedPicture.image.width / resolvedDevicePixelRatio,
    cachedPicture.image.height / resolvedDevicePixelRatio,
  );
  if (clipRight == null) {
    return DesktopResolvedPictureBounds(
      imageBounds: imageBounds,
      clipRect: null,
    );
  }
  final double snappedClipRight = _snapDesktopLogicalValueToPhysicalPixels(
    clipRight,
    resolvedDevicePixelRatio,
  ).clamp(imageBounds.left, imageBounds.right);
  return DesktopResolvedPictureBounds(
    imageBounds: imageBounds,
    clipRect: Rect.fromLTRB(
      imageBounds.left,
      imageBounds.top,
      snappedClipRight,
      imageBounds.bottom,
    ),
  );
}

double _snapDesktopLogicalValueToPhysicalPixels(
  double value,
  double devicePixelRatio,
) {
  final double resolvedDevicePixelRatio = _resolveDevicePixelRatio(
    devicePixelRatio,
  );
  return (value * resolvedDevicePixelRatio).roundToDouble() /
      resolvedDevicePixelRatio;
}

Offset _snapDesktopLogicalOffsetToPhysicalPixels(
  Offset value,
  double devicePixelRatio,
) {
  return Offset(
    _snapDesktopLogicalValueToPhysicalPixels(value.dx, devicePixelRatio),
    _snapDesktopLogicalValueToPhysicalPixels(value.dy, devicePixelRatio),
  );
}

double _resolveDevicePixelRatio(double value) {
  return value.isFinite && value > 0 ? value : 1;
}

/// 单行缓存位图的唯一 raster 几何来源。
///
/// 描边宽度、抗锯齿覆盖、DPR 向上取整和最终图片逻辑尺寸都在这里计算；
/// 布局文档、图片缓存与 painter 必须复用这组函数，禁止各自增加经验补偿。
@visibleForTesting
double resolveDesktopLineStrokeWidth(DesktopLyricsPainterLine line) {
  return math.max(
        line.fontMetrics.baseHeight,
        line.visualLine.hasRubyLayout ? line.fontMetrics.rubyHeight : 0,
      ) *
      0.06;
}

@visibleForTesting
double resolveDesktopLineRasterPadding(
  DesktopLyricsPainterLine line, {
  required double devicePixelRatio,
}) {
  final double dpr = _resolveDevicePixelRatio(devicePixelRatio);
  final double strokeOutset = resolveDesktopLineStrokeWidth(line) / 2;
  final double antiAliasOutset = 1 / dpr;
  return ((strokeOutset + antiAliasOutset) * dpr).ceilToDouble() / dpr;
}

@visibleForTesting
Size resolveDesktopLineRasterSize(
  DesktopLyricsPainterLine line, {
  required double devicePixelRatio,
}) {
  final double dpr = _resolveDevicePixelRatio(devicePixelRatio);
  final double padding = resolveDesktopLineRasterPadding(
    line,
    devicePixelRatio: dpr,
  );
  final double width =
      line.visualLine.visualRight - line.visualLine.visualLeft + padding * 2;
  final double height = line.visualLine.height + padding * 2;
  return Size(
    math.max((width * dpr).ceil(), 1).toDouble(),
    math.max((math.max(height, 1) * dpr).ceil(), 1).toDouble(),
  );
}

class DesktopFloatingRasterGeometry {
  const DesktopFloatingRasterGeometry({
    required this.renderInsets,
    required this.preferredHeight,
  });

  final EdgeInsets renderInsets;
  final double preferredHeight;
}

@visibleForTesting
DesktopFloatingRasterGeometry resolveDesktopFloatingRasterGeometry({
  required List<DesktopLyricsPainterLine> lines,
  required double lineSpacingRatio,
  required double devicePixelRatio,
}) {
  final double dpr = _resolveDevicePixelRatio(devicePixelRatio);
  double cursorY = 0;
  double minimumTop = 0;
  double maximumBottom = 0;
  double horizontalInset = 0;
  for (final DesktopLyricsPainterLine line in lines) {
    final double padding = resolveDesktopLineRasterPadding(
      line,
      devicePixelRatio: dpr,
    );
    final Size rasterSize = resolveDesktopLineRasterSize(
      line,
      devicePixelRatio: dpr,
    );
    final double imageTop = _snapDesktopLogicalValueToPhysicalPixels(
      cursorY - padding,
      dpr,
    );
    minimumTop = math.min(minimumTop, imageTop);
    maximumBottom = math.max(maximumBottom, imageTop + rasterSize.height / dpr);
    horizontalInset = math.max(horizontalInset, padding + 1 / dpr);
    cursorY += line.visualLine.height * lineSpacingRatio;
  }
  final double topInset = ((-minimumTop) * dpr).ceilToDouble() / dpr;
  final double shiftedRasterBottom = maximumBottom + topInset;
  final double shiftedLayoutBottom = cursorY + topInset;
  final double preferredHeight =
      (math.max(shiftedRasterBottom, shiftedLayoutBottom) * dpr)
          .ceilToDouble() /
      dpr;
  return DesktopFloatingRasterGeometry(
    renderInsets: EdgeInsets.fromLTRB(
      horizontalInset,
      topInset,
      horizontalInset,
      math.max(preferredHeight - shiftedLayoutBottom, 0),
    ),
    preferredHeight: math.max(preferredHeight, 1 / dpr),
  );
}

/// 共享帧编译器：负责把结构化 plan 投影为当前视口可直接绘制的帧。
///
/// 这里刻意把“布局测量”和“逐帧绘制”拆开：字体、假名、换行等测量结果
/// 可以被缓存复用，而播放进度只需要生成轻量 painter frame。维护时不要把
/// TextPainter 测量放回 paint() 热路径，否则桌面歌词窗口会在高频刷新时抖动。
class DesktopRenderFrameCompiler {
  const DesktopRenderFrameCompiler({
    this.layoutEngine = const DesktopRenderLayoutEngine(),
  });

  final DesktopRenderLayoutEngine layoutEngine;

  DesktopFloatingLayoutDocument buildFloatingLayoutDocument({
    required DesktopFloatingRenderPlan plan,
    required Size viewportSize,
    required String fontFamily,
    required double configuredFontSize,
    required DesktopFloatingFontSizeMode fontSizeMode,
    required bool showFurigana,
    double devicePixelRatio = 1,
    DesktopGlyphMeasureCache? glyphMeasureCache,
    DesktopLineMeasureCache? lineMeasureCache,
  }) {
    final List<DesktopRenderLinePlan> leftPlans = _flattenFloatingTracks(
      plan.leftTracks,
    );
    final List<DesktopRenderLinePlan> rightPlans = _flattenFloatingTracks(
      plan.rightTracks,
    );
    final List<DesktopRenderLinePlan> allPlans = <DesktopRenderLinePlan>[
      ...leftPlans,
      ...rightPlans,
    ];
    final bool hasRubiesGlobally = plan.hasRubiesGlobally && showFurigana;
    final double resolvedFontSize = switch (fontSizeMode) {
      DesktopFloatingFontSizeMode.fixedFont => math.max(configuredFontSize, 8),
      DesktopFloatingFontSizeMode.interactiveResize => _resolveFloatingFontSize(
        viewportHeight: viewportSize.height,
        configuredFontSize: configuredFontSize,
        fontFamily: fontFamily,
        lines: allPlans,
        hasRubiesGlobally: hasRubiesGlobally,
        glyphMeasureCache: glyphMeasureCache,
      ),
    };

    final List<DesktopStaticLyricsLine> leftLines = leftPlans
        .map(
          (DesktopRenderLinePlan line) => _buildStaticLine(
            line: line,
            fontFamily: fontFamily,
            resolvedFontSize: resolvedFontSize,
            reserveRubyHeight: hasRubiesGlobally && line.lang == 'orig',
            showFurigana: showFurigana,
            glyphMeasureCache: glyphMeasureCache,
            lineMeasureCache: lineMeasureCache,
          ),
        )
        .toList(growable: false);
    final List<DesktopStaticLyricsLine> rightLines = rightPlans
        .map(
          (DesktopRenderLinePlan line) => _buildStaticLine(
            line: line,
            fontFamily: fontFamily,
            resolvedFontSize: resolvedFontSize,
            reserveRubyHeight: hasRubiesGlobally && line.lang == 'orig',
            showFurigana: showFurigana,
            glyphMeasureCache: glyphMeasureCache,
            lineMeasureCache: lineMeasureCache,
          ),
        )
        .toList(growable: false);
    final List<DesktopLyricsPainterLine> rasterLines =
        <DesktopLyricsPainterLine>[
          ..._buildPainterLines(
            plans: leftPlans,
            staticLines: leftLines,
            estimatedPlaybackTimeMs: null,
          ),
          ..._buildPainterLines(
            plans: rightPlans,
            staticLines: rightLines,
            estimatedPlaybackTimeMs: null,
          ),
        ];
    final DesktopFloatingRasterGeometry rasterGeometry =
        resolveDesktopFloatingRasterGeometry(
          lines: rasterLines,
          lineSpacingRatio: layoutEngine.lineSpacingRatio,
          devicePixelRatio: devicePixelRatio,
        );
    return DesktopFloatingLayoutDocument(
      leftLines: leftLines,
      rightLines: rightLines,
      fontSize: resolvedFontSize,
      renderInsets: rasterGeometry.renderInsets,
      preferredHeight: rasterGeometry.preferredHeight,
      hasRubiesGlobally: hasRubiesGlobally,
    );
  }

  DesktopFloatingPainterFrame buildFloatingPainterFrame({
    required DesktopFloatingRenderPlan plan,
    required DesktopFloatingLayoutDocument document,
    int? estimatedPlaybackTimeMs,
  }) {
    final List<DesktopRenderLinePlan> leftPlans = _flattenFloatingTracks(
      plan.leftTracks,
    );
    final List<DesktopRenderLinePlan> rightPlans = _flattenFloatingTracks(
      plan.rightTracks,
    );
    return DesktopFloatingPainterFrame(
      document: document,
      leftLines: _buildPainterLines(
        plans: leftPlans,
        staticLines: document.leftLines,
        estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
      ),
      rightLines: _buildPainterLines(
        plans: rightPlans,
        staticLines: document.rightLines,
        estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
      ),
      estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
    );
  }

  DesktopPanelLayoutDocument buildPanelLayoutDocument({
    required DesktopPanelRenderPlan plan,
    required Size viewportSize,
    required String fontFamily,
    required double fontSize,
    required bool showFurigana,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final List<DesktopRenderVisualBlock> visualBlocks = layoutEngine
        .layoutBlocks(
          plan: plan,
          containerWidth: viewportSize.width,
          fontFamily: fontFamily,
          fontSize: fontSize,
          showFurigana: showFurigana,
          hasRubiesGlobally:
              showFurigana &&
              plan.blocks.any(
                (DesktopRenderBlockPlan block) => block.lines.any(
                  (DesktopRenderLinePlan line) =>
                      line.lang == 'orig' && line.rubies.isNotEmpty,
                ),
              ),
          glyphMeasureCache: glyphMeasureCache,
        );
    final List<DesktopStaticPanelBlock> blocks = <DesktopStaticPanelBlock>[];
    final double leadingGutter = viewportSize.height / 2;
    final double trailingGutter = viewportSize.height / 2;
    double contentBottom = 0;
    for (int index = 0; index < plan.blocks.length; index += 1) {
      final DesktopRenderBlockPlan blockPlan = plan.blocks[index];
      final DesktopRenderVisualBlock visualBlock = visualBlocks[index];
      final Map<String, List<DesktopStaticLyricsLine>> lineMap =
          <String, List<DesktopStaticLyricsLine>>{};
      for (final DesktopRenderLinePlan linePlan in blockPlan.lines) {
        final List<DesktopRenderVisualLine> paragraphLines =
            visualBlock.lines[linePlan.lang] ??
            const <DesktopRenderVisualLine>[];
        if (paragraphLines.isEmpty) {
          continue;
        }
        final bool isOrig = linePlan.lang == 'orig';
        final TextStyle baseStyle = layoutEngine.buildBaseTextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          isOrig: isOrig,
        );
        final TextStyle rubyStyle = layoutEngine.buildRubyTextStyle(baseStyle);
        final DesktopRenderLineFontMetrics fontMetrics = layoutEngine
            .buildLineFontMetrics(
              baseStyle,
              glyphMeasureCache: glyphMeasureCache,
            );
        lineMap[linePlan.lang] = paragraphLines
            .map(
              (DesktopRenderVisualLine visualLine) => DesktopStaticLyricsLine(
                origIndex: linePlan.origIndex,
                lang: linePlan.lang,
                visualLine: visualLine,
                measuredLine: _measureFromVisualLine(
                  visualLine,
                  fontMetrics: fontMetrics,
                ),
                baseStyle: baseStyle,
                rubyStyle: rubyStyle,
                fontMetrics: fontMetrics,
              ),
            )
            .toList(growable: false);
      }
      final Rect shiftedRect = visualBlock.virtualRect.shift(
        Offset(0, leadingGutter),
      );
      contentBottom = math.max(contentBottom, shiftedRect.bottom);
      blocks.add(
        DesktopStaticPanelBlock(
          origIndex: blockPlan.origIndex,
          virtualRect: shiftedRect,
          lines: lineMap,
        ),
      );
    }
    return DesktopPanelLayoutDocument(
      blocks: blocks,
      contentHeight: contentBottom + layoutEngine.margin + trailingGutter,
    );
  }

  DesktopPanelPainterFrame buildPanelPainterFrame({
    required DesktopPanelRenderPlan plan,
    required DesktopPanelLayoutDocument document,
    required double viewportHeight,
    int? estimatedPlaybackTimeMs,
  }) {
    final List<DesktopPanelPainterBlock> blocks = <DesktopPanelPainterBlock>[];
    for (int index = 0; index < plan.blocks.length; index += 1) {
      final DesktopRenderBlockPlan blockPlan = plan.blocks[index];
      final DesktopStaticPanelBlock staticBlock = document.blocks[index];
      final Map<String, List<DesktopLyricsPainterLine>> lineMap =
          <String, List<DesktopLyricsPainterLine>>{};
      for (final DesktopRenderLinePlan linePlan in blockPlan.lines) {
        final List<DesktopStaticLyricsLine> staticLines =
            staticBlock.lines[linePlan.lang] ??
            const <DesktopStaticLyricsLine>[];
        if (staticLines.isEmpty) {
          continue;
        }
        lineMap[linePlan.lang] = staticLines
            .map((DesktopStaticLyricsLine staticLine) {
              return DesktopLyricsPainterLine(
                plan: linePlan,
                visualLine: staticLine.visualLine,
                measuredLine: staticLine.measuredLine,
                baseStyle: staticLine.baseStyle,
                rubyStyle: staticLine.rubyStyle,
                fontMetrics: staticLine.fontMetrics,
                opacity: _resolveDisplayOpacity(
                  line: linePlan,
                  estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
                ),
              );
            })
            .toList(growable: false);
      }
      blocks.add(
        DesktopPanelPainterBlock(
          origIndex: blockPlan.origIndex,
          state: blockPlan.state,
          virtualRect: staticBlock.virtualRect,
          lines: lineMap,
        ),
      );
    }
    final double maxScroll = math.max(
      0,
      document.contentHeight - viewportHeight,
    );
    return DesktopPanelPainterFrame(
      document: document,
      blocks: blocks,
      targetScrollY: _resolvePanelTargetScroll(
        blocks: document.blocks,
        activeIndex: plan.activeIndex,
        viewportHeight: viewportHeight,
      ).clamp(0, maxScroll),
    );
  }

  DesktopStaticLyricsLine _buildStaticLine({
    required DesktopRenderLinePlan line,
    required String fontFamily,
    required double resolvedFontSize,
    required bool reserveRubyHeight,
    required bool showFurigana,
    DesktopGlyphMeasureCache? glyphMeasureCache,
    DesktopLineMeasureCache? lineMeasureCache,
  }) {
    final bool isOrig = line.lang == 'orig';
    final TextStyle baseStyle = layoutEngine.buildBaseTextStyle(
      fontFamily: fontFamily,
      fontSize: resolvedFontSize,
      isOrig: isOrig,
    );
    final TextStyle rubyStyle = layoutEngine.buildRubyTextStyle(baseStyle);
    final List<RubySpan> visibleRubies = showFurigana && isOrig
        ? line.rubies
        : const <RubySpan>[];
    DesktopRenderMeasuredLine? measuredLine = lineMeasureCache?.read(
      text: line.text,
      rubies: visibleRubies,
      baseStyle: baseStyle,
      reserveRubyHeight: reserveRubyHeight,
    );
    measuredLine ??= layoutEngine.measureLine(
      text: line.text,
      rubies: visibleRubies,
      baseStyle: baseStyle,
      showFurigana: true,
      reserveRubyHeight: reserveRubyHeight,
      glyphMeasureCache: glyphMeasureCache,
    );
    lineMeasureCache?.write(
      text: line.text,
      rubies: visibleRubies,
      baseStyle: baseStyle,
      reserveRubyHeight: reserveRubyHeight,
      measuredLine: measuredLine,
    );
    return DesktopStaticLyricsLine(
      origIndex: line.origIndex,
      lang: line.lang,
      visualLine: measuredLine.visualLine,
      measuredLine: measuredLine,
      baseStyle: baseStyle,
      rubyStyle: rubyStyle,
      fontMetrics: measuredLine.fontMetrics,
    );
  }

  List<DesktopLyricsPainterLine> _buildPainterLines({
    required List<DesktopRenderLinePlan> plans,
    required List<DesktopStaticLyricsLine> staticLines,
    required int? estimatedPlaybackTimeMs,
  }) {
    final int count = math.min(plans.length, staticLines.length);
    return List<DesktopLyricsPainterLine>.generate(count, (int index) {
      final DesktopRenderLinePlan plan = plans[index];
      final DesktopStaticLyricsLine staticLine = staticLines[index];
      return DesktopLyricsPainterLine(
        plan: plan,
        visualLine: staticLine.visualLine,
        measuredLine: staticLine.measuredLine,
        baseStyle: staticLine.baseStyle,
        rubyStyle: staticLine.rubyStyle,
        fontMetrics: staticLine.fontMetrics,
        opacity: _resolveDisplayOpacity(
          line: plan,
          estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
        ),
      );
    }, growable: false);
  }

  List<DesktopRenderLinePlan> _flattenFloatingTracks(
    List<DesktopRenderTrackPlan> tracks,
  ) {
    final List<DesktopRenderTrackPlan> sortedTracks =
        List<DesktopRenderTrackPlan>.of(tracks)
          ..sort((DesktopRenderTrackPlan left, DesktopRenderTrackPlan right) {
            final int trackCompare = left.track.compareTo(right.track);
            if (trackCompare != 0) {
              return trackCompare;
            }
            return left.focusedOrigIndex.compareTo(right.focusedOrigIndex);
          });
    return sortedTracks
        .expand((DesktopRenderTrackPlan track) => track.lines)
        .toList(growable: false);
  }

  DesktopRenderMeasuredLine _measureFromVisualLine(
    DesktopRenderVisualLine visualLine, {
    required DesktopRenderLineFontMetrics fontMetrics,
  }) {
    final List<DesktopRenderLineLayoutSegment> segments = visualLine.tokens
        .map((DesktopRenderToken token) {
          final int charStart = token.charIndices.isEmpty
              ? 0
              : token.charIndices.first;
          final int charEnd = token.charIndices.isEmpty
              ? 0
              : token.charIndices.last + 1;
          return DesktopRenderLineLayoutSegment(
            charStart: charStart,
            charEnd: charEnd,
            text: token.text,
            ruby: token.rubyText,
            x: token.x,
            width: math.max(token.baseWidth, token.rubyWidth),
            baseWidth: token.baseWidth,
            rubyWidth: token.rubyWidth,
            charOffsets: token.charOffsets,
          );
        })
        .toList(growable: false);
    return DesktopRenderMeasuredLine(
      segments: segments,
      contentWidth: visualLine.width,
      visualLine: visualLine,
      fontMetrics: fontMetrics,
    );
  }

  double _resolveFloatingFontSize({
    required double viewportHeight,
    required double configuredFontSize,
    required String fontFamily,
    required List<DesktopRenderLinePlan> lines,
    required bool hasRubiesGlobally,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    if (viewportHeight <= 0 || lines.isEmpty) {
      return math.max(configuredFontSize, 8);
    }
    const double referenceSize = 100;
    final TextStyle referenceStyle = layoutEngine.buildBaseTextStyle(
      fontFamily: fontFamily,
      fontSize: referenceSize,
      isOrig: true,
    );
    final DesktopRenderMeasuredLine referenceLine = layoutEngine.measureLine(
      text: '示',
      rubies: const <RubySpan>[],
      baseStyle: referenceStyle,
      showFurigana: false,
      glyphMeasureCache: glyphMeasureCache,
    );
    final double k = referenceSize == 0
        ? 1
        : referenceLine.visualLine.height / referenceSize;
    if (k <= 0) {
      return math.max(configuredFontSize, 8);
    }

    double totalWeightedUnits = 0;
    for (final DesktopRenderLinePlan line in lines) {
      final double baseScale = line.lang == 'orig' ? 1.0 : 0.8;
      double lineUnit = baseScale;
      if ((line.rubies.isNotEmpty || hasRubiesGlobally) &&
          line.lang == 'orig') {
        lineUnit += baseScale * layoutEngine.rubyScale;
      }
      lineUnit *= layoutEngine.lineSpacingRatio;
      totalWeightedUnits += lineUnit;
    }
    if (totalWeightedUnits <= 0) {
      return math.max(configuredFontSize, 8);
    }
    final double availableHeight = viewportHeight * 0.95;
    return math.max(availableHeight / (k * totalWeightedUnits), 8);
  }

  double _resolveDisplayOpacity({
    required DesktopRenderLinePlan line,
    required int? estimatedPlaybackTimeMs,
  }) {
    if (line.state == DesktopRenderLineState.active ||
        estimatedPlaybackTimeMs == null) {
      return line.opacity;
    }
    final int? startMs = line.transitionStartMs;
    final int? endMs = line.transitionEndMs;
    if (startMs == null || endMs == null || endMs <= startMs) {
      return line.opacity;
    }
    final double progress =
        ((estimatedPlaybackTimeMs - startMs) / (endMs - startMs)).clamp(
          0.0,
          1.0,
        );
    return switch (line.state) {
      DesktopRenderLineState.active => 1.0,
      DesktopRenderLineState.played => 1.0 - progress,
      DesktopRenderLineState.unplayed => progress,
    };
  }

  double _resolvePanelTargetScroll({
    required List<DesktopStaticPanelBlock> blocks,
    required int activeIndex,
    required double viewportHeight,
  }) {
    if (activeIndex < 0) {
      return 0;
    }
    DesktopStaticPanelBlock? targetBlock;
    for (final DesktopStaticPanelBlock block in blocks) {
      if (block.origIndex == activeIndex) {
        targetBlock = block;
        break;
      }
    }
    if (targetBlock == null) {
      return 0;
    }
    return targetBlock.virtualRect.center.dy - viewportHeight / 2;
  }
}

class _DesktopPreparedPaintLine {
  const _DesktopPreparedPaintLine({
    required this.line,
    required this.origin,
    required this.familyKey,
    required this.estimatedVariantBytes,
  });

  final DesktopLyricsPainterLine line;
  final Offset origin;
  final DesktopLinePictureCacheFamilyKey familyKey;
  final int estimatedVariantBytes;
}

class _DesktopPictureFamilyFramePlan {
  _DesktopPictureFamilyFramePlan({required this.estimatedVariantBytes});

  final int estimatedVariantBytes;
  bool requiresPlayed = false;
  bool requiresUnplayed = false;
  int priorityClass = 0;
  double distanceToViewport = double.infinity;
  bool visible = false;
  bool protected = false;
  bool warm = false;

  int get requiredVariantCount =>
      (requiresPlayed ? 1 : 0) + (requiresUnplayed ? 1 : 0);

  void includeState(DesktopRenderLineState state) {
    switch (state) {
      case DesktopRenderLineState.played:
        requiresPlayed = true;
      case DesktopRenderLineState.unplayed:
        requiresUnplayed = true;
      case DesktopRenderLineState.active:
        requiresPlayed = true;
        requiresUnplayed = true;
    }
  }

  void mergeFrom(_DesktopPictureFamilyFramePlan other) {
    requiresPlayed = requiresPlayed || other.requiresPlayed;
    requiresUnplayed = requiresUnplayed || other.requiresUnplayed;
    priorityClass = math.max(priorityClass, other.priorityClass);
    distanceToViewport = math.min(distanceToViewport, other.distanceToViewport);
    visible = visible || other.visible;
    protected = protected || other.protected;
    warm = warm || other.warm;
  }
}

enum _DesktopPictureCacheScrollDirection { idle, forward, backward }

/// 浮窗共享 painter。
class DesktopFloatingLyricsPainter extends CustomPainter {
  DesktopFloatingLyricsPainter({
    required this.resolveFrame,
    required this.playedColors,
    required this.unplayedColors,
    required this.layoutEngine,
    required this.pictureCache,
    required this.devicePixelRatio,
    super.repaint,
  }) : _linePainter = _DesktopLyricsLinePainter(
         playedColors: playedColors,
         unplayedColors: unplayedColors,
         pictureCache: pictureCache,
         devicePixelRatio: devicePixelRatio,
       );

  final DesktopFloatingPainterFrame? Function() resolveFrame;
  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final DesktopRenderLayoutEngine layoutEngine;
  final DesktopLinePictureCache pictureCache;
  final double devicePixelRatio;
  final _DesktopLyricsLinePainter _linePainter;
  int _frameId = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final DesktopFloatingPainterFrame? frame = resolveFrame();
    if (frame == null) {
      return;
    }
    _frameId += 1;
    final List<_DesktopPreparedPaintLine> preparedLines =
        <_DesktopPreparedPaintLine>[];
    double currentY = frame.document.renderInsets.top;
    for (final List<DesktopLyricsPainterLine> group
        in <List<DesktopLyricsPainterLine>>[
          frame.leftLines,
          frame.rightLines,
        ]) {
      for (final DesktopLyricsPainterLine line in group) {
        final double drawX = _linePainter.resolveFloatingDrawX(
          line: line,
          viewportWidth: size.width,
        );
        preparedLines.add(
          _DesktopPreparedPaintLine(
            line: line,
            origin: Offset(drawX, currentY),
            familyKey: _linePainter.buildPictureFamilyKey(line: line),
            estimatedVariantBytes: _linePainter.estimatePictureBytesForLine(
              line,
            ),
          ),
        );
        currentY += line.visualLine.height * layoutEngine.lineSpacingRatio;
      }
    }
    final Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>
    protectedFamilies =
        <DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>{};
    // 浮窗通常只显示少量行，但 active 行需要 played/unplayed 两张位图叠加裁剪。
    // 先统计本帧必须保护的 cache family，再 beginFrame，可以让缓存按预算淘汰
    // 远离当前歌词的旧图，避免播放一段时间后 ui.Image 长期占用显存/内存。
    for (final _DesktopPreparedPaintLine preparedLine in preparedLines) {
      _mergeProtectedLinePlan(
        preparedLine: preparedLine,
        families: protectedFamilies,
      );
    }
    final DesktopPictureCacheBudget budget = resolveDesktopPictureCacheBudget(
      lane: DesktopPictureCacheLane.floating,
      protectedFloorBytes: _estimateProtectedBytes(protectedFamilies),
    );
    pictureCache.runFrame<void>(
      DesktopPictureCacheFrameContext(
        frameId: _frameId,
        softBudgetBytes: budget.softBudgetBytes,
        hardBudgetBytes: budget.hardBudgetBytes,
      ),
      () {
        _hintFamilies(protectedFamilies);
        for (final _DesktopPreparedPaintLine preparedLine in preparedLines) {
          final Rect bounds = _linePainter.paintLine(
            canvas,
            line: preparedLine.line,
            origin: preparedLine.origin,
            familyKey: preparedLine.familyKey,
          );
          assert(() {
            final double tolerance =
                1 / _resolveDevicePixelRatio(devicePixelRatio);
            // 超长歌词会按播放进度水平滚动，缓存位图宽于 viewport 是合法的；
            // 高度方向没有滚动语义，任何上下越界都表示真实裁切风险。
            if (bounds.top < -tolerance ||
                bounds.bottom > size.height + tolerance) {
              throw FlutterError(
                '浮窗歌词 raster 越界: bounds=$bounds canvas=$size '
                'origIndex=${preparedLine.line.plan.origIndex} '
                'lang=${preparedLine.line.plan.lang}',
              );
            }
            return true;
          }());
        }
      },
    );
  }

  @override
  bool shouldRepaint(covariant DesktopFloatingLyricsPainter oldDelegate) {
    return oldDelegate.pictureCache != pictureCache ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.playedColors != playedColors ||
        oldDelegate.unplayedColors != unplayedColors ||
        oldDelegate.resolveFrame != resolveFrame;
  }

  void _mergeProtectedLinePlan({
    required _DesktopPreparedPaintLine preparedLine,
    required Map<
      DesktopLinePictureCacheFamilyKey,
      _DesktopPictureFamilyFramePlan
    >
    families,
  }) {
    final _DesktopPictureFamilyFramePlan familyPlan = families.putIfAbsent(
      preparedLine.familyKey,
      () => _DesktopPictureFamilyFramePlan(
        estimatedVariantBytes: preparedLine.estimatedVariantBytes,
      ),
    );
    familyPlan
      ..visible = true
      ..protected = true
      ..distanceToViewport = 0
      ..priorityClass = math.max(
        familyPlan.priorityClass,
        preparedLine.line.plan.state == DesktopRenderLineState.active ? 3 : 2,
      );
    familyPlan.includeState(preparedLine.line.plan.state);
  }

  int _estimateProtectedBytes(
    Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>
    families,
  ) {
    int total = 0;
    for (final _DesktopPictureFamilyFramePlan family in families.values) {
      total += family.estimatedVariantBytes * family.requiredVariantCount;
    }
    return total;
  }

  void _hintFamilies(
    Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>
    families,
  ) {
    for (final MapEntry<
          DesktopLinePictureCacheFamilyKey,
          _DesktopPictureFamilyFramePlan
        >
        entry
        in families.entries) {
      if (entry.value.visible) {
        pictureCache.hintFamily(
          entry.key,
          DesktopPictureHint.visible,
          priorityClass: entry.value.priorityClass,
          distanceToViewport: entry.value.distanceToViewport,
        );
      }
      if (entry.value.protected) {
        pictureCache.hintFamily(
          entry.key,
          DesktopPictureHint.protected,
          priorityClass: entry.value.priorityClass,
          distanceToViewport: entry.value.distanceToViewport,
        );
      }
      if (entry.value.warm) {
        pictureCache.hintFamily(
          entry.key,
          DesktopPictureHint.warm,
          priorityClass: entry.value.priorityClass,
          distanceToViewport: entry.value.distanceToViewport,
        );
      }
    }
  }
}

/// 面板共享 painter。
class DesktopPanelLyricsPainter extends CustomPainter {
  DesktopPanelLyricsPainter({
    required this.resolveFrame,
    required this.resolveScrollY,
    required this.playedColors,
    required this.unplayedColors,
    required this.pictureCache,
    required this.devicePixelRatio,
    super.repaint,
  }) : _linePainter = _DesktopLyricsLinePainter(
         playedColors: playedColors,
         unplayedColors: unplayedColors,
         pictureCache: pictureCache,
         devicePixelRatio: devicePixelRatio,
       );

  final DesktopPanelPainterFrame? Function() resolveFrame;
  final double Function() resolveScrollY;
  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final DesktopLinePictureCache pictureCache;
  final double devicePixelRatio;
  final _DesktopLyricsLinePainter _linePainter;
  int _frameId = 0;
  double? _lastScrollY;

  @override
  void paint(Canvas canvas, Size size) {
    final DesktopPanelPainterFrame? frame = resolveFrame();
    if (frame == null) {
      return;
    }
    final double scrollY = resolveScrollY();
    _frameId += 1;
    final _DesktopPictureCacheScrollDirection scrollDirection =
        _resolveScrollDirection(scrollY);
    _lastScrollY = scrollY;
    final double viewTop = scrollY;
    final double viewBottom = scrollY + size.height;
    final Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>
    protectedFamilies =
        <DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>{};
    final Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>
    warmFamilies =
        <DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>{};
    final List<_DesktopPreparedPaintLine> visibleLines =
        <_DesktopPreparedPaintLine>[];
    DesktopPanelPainterBlock? nearestBefore;
    DesktopPanelPainterBlock? nearestAfter;
    double nearestBeforeDistance = double.infinity;
    double nearestAfterDistance = double.infinity;
    // 面板模式可能包含整首歌词，不能每帧把所有行都录制成图片。
    // 本循环只收集可见行、当前 active 行，以及视口前后一小段预热行；
    // 这样滚动时能提前准备临近内容，同时把常规帧的绘制和缓存创建量限制在视口附近。
    for (final DesktopPanelPainterBlock block in frame.blocks) {
      final bool isVisible =
          block.virtualRect.bottom >= viewTop &&
          block.virtualRect.top <= viewBottom;
      final bool isActive = block.state == DesktopRenderLineState.active;
      if (!isVisible) {
        if (block.virtualRect.bottom < viewTop) {
          final double distance = viewTop - block.virtualRect.bottom;
          if (distance < nearestBeforeDistance) {
            nearestBeforeDistance = distance;
            nearestBefore = block;
          }
        } else if (block.virtualRect.top > viewBottom) {
          final double distance = block.virtualRect.top - viewBottom;
          if (distance < nearestAfterDistance) {
            nearestAfterDistance = distance;
            nearestAfter = block;
          }
        }
      }
      if (!isVisible && !isActive) {
        continue;
      }
      final double blockY = block.virtualRect.top;
      for (final List<DesktopLyricsPainterLine> lines in block.lines.values) {
        for (final DesktopLyricsPainterLine line in lines) {
          final _DesktopPreparedPaintLine preparedLine =
              _DesktopPreparedPaintLine(
                line: line,
                origin: Offset(
                  line.visualLine.startX,
                  blockY + line.visualLine.y,
                ),
                familyKey: _linePainter.buildPictureFamilyKey(line: line),
                estimatedVariantBytes: _linePainter.estimatePictureBytesForLine(
                  line,
                ),
              );
          _mergePanelFamilyPlan(
            preparedLine: preparedLine,
            families: protectedFamilies,
            distanceToViewport: _distanceToViewport(
              block.virtualRect,
              viewTop: viewTop,
              viewBottom: viewBottom,
            ),
            priorityClass: isActive ? 3 : 2,
            visible: isVisible,
            protected: true,
          );
          if (isVisible) {
            visibleLines.add(preparedLine);
          }
        }
      }
    }
    final int protectedBytes = _estimateProtectedBytes(protectedFamilies);
    final DesktopPictureCacheBudget budget = resolveDesktopPictureCacheBudget(
      lane: DesktopPictureCacheLane.panel,
      protectedFloorBytes: protectedBytes,
    );
    int remainingWarmBytes = budget.softBudgetBytes - protectedBytes;
    void addWarmBlock(
      DesktopPanelPainterBlock? block,
      double distance, {
      required int priorityClass,
    }) {
      if (block == null || remainingWarmBytes <= 0) {
        return;
      }
      final Map<
        DesktopLinePictureCacheFamilyKey,
        _DesktopPictureFamilyFramePlan
      >
      candidateFamilies =
          <DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>{};
      for (final List<DesktopLyricsPainterLine> lines in block.lines.values) {
        for (final DesktopLyricsPainterLine line in lines) {
          _mergePanelFamilyPlan(
            preparedLine: _DesktopPreparedPaintLine(
              line: line,
              origin: Offset(
                line.visualLine.startX,
                block.virtualRect.top + line.visualLine.y,
              ),
              familyKey: _linePainter.buildPictureFamilyKey(line: line),
              estimatedVariantBytes: _linePainter.estimatePictureBytesForLine(
                line,
              ),
            ),
            families: candidateFamilies,
            distanceToViewport: distance,
            priorityClass: priorityClass,
            visible: false,
            protected: false,
            warm: true,
          );
        }
      }
      final int candidateBytes = _estimateProtectedBytes(candidateFamilies);
      if (candidateBytes > remainingWarmBytes) {
        return;
      }
      remainingWarmBytes -= candidateBytes;
      for (final MapEntry<
            DesktopLinePictureCacheFamilyKey,
            _DesktopPictureFamilyFramePlan
          >
          entry
          in candidateFamilies.entries) {
        warmFamilies
            .putIfAbsent(
              entry.key,
              () => _DesktopPictureFamilyFramePlan(
                estimatedVariantBytes: entry.value.estimatedVariantBytes,
              ),
            )
            .mergeFrom(entry.value);
      }
    }

    switch (scrollDirection) {
      case _DesktopPictureCacheScrollDirection.forward:
        addWarmBlock(nearestAfter, nearestAfterDistance, priorityClass: 1);
        addWarmBlock(nearestBefore, nearestBeforeDistance, priorityClass: 0);
        break;
      case _DesktopPictureCacheScrollDirection.backward:
        addWarmBlock(nearestBefore, nearestBeforeDistance, priorityClass: 1);
        addWarmBlock(nearestAfter, nearestAfterDistance, priorityClass: 0);
        break;
      case _DesktopPictureCacheScrollDirection.idle:
        addWarmBlock(nearestAfter, nearestAfterDistance, priorityClass: 1);
        addWarmBlock(nearestBefore, nearestBeforeDistance, priorityClass: 1);
        break;
    }
    final Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>
    hintedFamilies =
        <DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>{};
    for (final MapEntry<
          DesktopLinePictureCacheFamilyKey,
          _DesktopPictureFamilyFramePlan
        >
        entry
        in protectedFamilies.entries) {
      hintedFamilies[entry.key] = entry.value;
    }
    for (final MapEntry<
          DesktopLinePictureCacheFamilyKey,
          _DesktopPictureFamilyFramePlan
        >
        entry
        in warmFamilies.entries) {
      hintedFamilies
          .putIfAbsent(
            entry.key,
            () => _DesktopPictureFamilyFramePlan(
              estimatedVariantBytes: entry.value.estimatedVariantBytes,
            ),
          )
          .mergeFrom(entry.value);
    }
    canvas.save();
    try {
      canvas.translate(0, -scrollY);
      pictureCache.runFrame<void>(
        DesktopPictureCacheFrameContext(
          frameId: _frameId,
          softBudgetBytes: budget.softBudgetBytes,
          hardBudgetBytes: budget.hardBudgetBytes,
        ),
        () {
          _hintFamilies(hintedFamilies);
          for (final _DesktopPreparedPaintLine preparedLine in visibleLines) {
            _linePainter.paintLine(
              canvas,
              line: preparedLine.line,
              origin: preparedLine.origin,
              familyKey: preparedLine.familyKey,
            );
          }
        },
      );
    } finally {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant DesktopPanelLyricsPainter oldDelegate) {
    return oldDelegate.pictureCache != pictureCache ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.playedColors != playedColors ||
        oldDelegate.unplayedColors != unplayedColors ||
        oldDelegate.resolveFrame != resolveFrame ||
        oldDelegate.resolveScrollY != resolveScrollY;
  }

  _DesktopPictureCacheScrollDirection _resolveScrollDirection(double scrollY) {
    final double? previous = _lastScrollY;
    if (previous == null || (scrollY - previous).abs() < 0.5) {
      return _DesktopPictureCacheScrollDirection.idle;
    }
    if (scrollY > previous) {
      return _DesktopPictureCacheScrollDirection.forward;
    }
    return _DesktopPictureCacheScrollDirection.backward;
  }

  void _mergePanelFamilyPlan({
    required _DesktopPreparedPaintLine preparedLine,
    required Map<
      DesktopLinePictureCacheFamilyKey,
      _DesktopPictureFamilyFramePlan
    >
    families,
    required double distanceToViewport,
    required int priorityClass,
    required bool visible,
    required bool protected,
    bool warm = false,
  }) {
    final _DesktopPictureFamilyFramePlan familyPlan = families.putIfAbsent(
      preparedLine.familyKey,
      () => _DesktopPictureFamilyFramePlan(
        estimatedVariantBytes: preparedLine.estimatedVariantBytes,
      ),
    );
    familyPlan
      ..priorityClass = math.max(familyPlan.priorityClass, priorityClass)
      ..distanceToViewport = math.min(
        familyPlan.distanceToViewport,
        distanceToViewport,
      )
      ..visible = familyPlan.visible || visible
      ..protected = familyPlan.protected || protected
      ..warm = familyPlan.warm || warm;
    familyPlan.includeState(preparedLine.line.plan.state);
  }

  int _estimateProtectedBytes(
    Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>
    families,
  ) {
    int total = 0;
    for (final _DesktopPictureFamilyFramePlan family in families.values) {
      total += family.estimatedVariantBytes * family.requiredVariantCount;
    }
    return total;
  }

  double _distanceToViewport(
    Rect rect, {
    required double viewTop,
    required double viewBottom,
  }) {
    if (rect.bottom < viewTop) {
      return viewTop - rect.bottom;
    }
    if (rect.top > viewBottom) {
      return rect.top - viewBottom;
    }
    return 0;
  }

  void _hintFamilies(
    Map<DesktopLinePictureCacheFamilyKey, _DesktopPictureFamilyFramePlan>
    families,
  ) {
    for (final MapEntry<
          DesktopLinePictureCacheFamilyKey,
          _DesktopPictureFamilyFramePlan
        >
        entry
        in families.entries) {
      if (entry.value.visible) {
        pictureCache.hintFamily(
          entry.key,
          DesktopPictureHint.visible,
          priorityClass: entry.value.priorityClass,
          distanceToViewport: entry.value.distanceToViewport,
        );
      }
      if (entry.value.protected) {
        pictureCache.hintFamily(
          entry.key,
          DesktopPictureHint.protected,
          priorityClass: entry.value.priorityClass,
          distanceToViewport: entry.value.distanceToViewport,
        );
      }
      if (entry.value.warm) {
        pictureCache.hintFamily(
          entry.key,
          DesktopPictureHint.warm,
          priorityClass: entry.value.priorityClass,
          distanceToViewport: entry.value.distanceToViewport,
        );
      }
    }
  }
}

// 单行绘制器只负责“把一行歌词变成可复用位图，再按状态贴回 Canvas”。
// played/unplayed/active 三种状态共享同一套 family key：active 行先贴未播放图，
// 再按进度裁剪播放图。这个设计用少量 ui.Image 换取稳定帧时间，代价是必须严格
// 控制缓存预算，并在 DPR、字体或颜色变化时让 family key 失效。
class _DesktopLyricsLinePainter {
  _DesktopLyricsLinePainter({
    required List<RgbColor> playedColors,
    required List<RgbColor> unplayedColors,
    required this.pictureCache,
    required this.devicePixelRatio,
  }) : playedGradient = _toColors(
         playedColors,
         fallback: const <Color>[
           Color.fromARGB(255, 0, 255, 255),
           Color.fromARGB(255, 0, 128, 255),
         ],
       ),
       unplayedGradient = _toColors(
         unplayedColors,
         fallback: const <Color>[
           Color.fromARGB(255, 255, 0, 0),
           Color.fromARGB(255, 255, 128, 128),
         ],
       ),
       themeSignature = Object.hash(
         _rgbColorsHash(
           playedColors,
           fallback: const <RgbColor>[
             RgbColor(0, 255, 255),
             RgbColor(0, 128, 255),
           ],
         ),
         _rgbColorsHash(
           unplayedColors,
           fallback: const <RgbColor>[
             RgbColor(255, 0, 0),
             RgbColor(255, 128, 128),
           ],
         ),
       );

  final List<Color> playedGradient;
  final List<Color> unplayedGradient;
  final int themeSignature;
  final DesktopLinePictureCache pictureCache;
  final double devicePixelRatio;
  final Color strokeColor = const Color.fromARGB(179, 0, 0, 0);

  Rect paintLine(
    Canvas canvas, {
    required DesktopLyricsPainterLine line,
    required Offset origin,
    DesktopLinePictureCacheFamilyKey? familyKey,
  }) {
    final DesktopLinePictureCacheFamilyKey resolvedFamilyKey =
        familyKey ?? buildPictureFamilyKey(line: line);
    switch (line.plan.state) {
      case DesktopRenderLineState.played:
        return _drawCachedLine(
          canvas,
          line: line,
          origin: origin,
          familyKey: resolvedFamilyKey,
          colors: playedGradient,
          variant: DesktopPictureCacheVariant.played,
        );
      case DesktopRenderLineState.unplayed:
        return _drawCachedLine(
          canvas,
          line: line,
          origin: origin,
          familyKey: resolvedFamilyKey,
          colors: unplayedGradient,
          variant: DesktopPictureCacheVariant.unplayed,
        );
      case DesktopRenderLineState.active:
        final DesktopCachedLinePicture unplayedPicture = _resolveLinePicture(
          line: line,
          familyKey: resolvedFamilyKey,
          colors: unplayedGradient,
          variant: DesktopPictureCacheVariant.unplayed,
        );
        final DesktopCachedLinePicture playedPicture = _resolveLinePicture(
          line: line,
          familyKey: resolvedFamilyKey,
          colors: playedGradient,
          variant: DesktopPictureCacheVariant.played,
        );
        final DesktopResolvedPictureBounds baseBounds =
            resolveDesktopResolvedPictureBounds(
              line: line,
              origin: origin,
              cachedPicture: unplayedPicture,
              devicePixelRatio: devicePixelRatio,
            );
        _drawResolvedPictureAtBounds(
          canvas,
          line: line,
          imageBounds: baseBounds.imageBounds,
          cachedPicture: unplayedPicture,
        );
        final double progressX = line.measuredLine.resolveCursorX(
          state: DesktopRenderLineState.active,
          activeProgress: line.plan.activeProgress,
        );
        final DesktopResolvedPictureBounds resolvedBounds =
            resolveDesktopResolvedPictureBounds(
              line: line,
              origin: origin,
              cachedPicture: unplayedPicture,
              devicePixelRatio: devicePixelRatio,
              clipRight: origin.dx + progressX,
            );
        final Rect? clipRect = resolvedBounds.clipRect;
        if (clipRect == null || clipRect.width <= 0) {
          return baseBounds.imageBounds;
        }
        canvas.save();
        try {
          canvas.clipRect(clipRect);
          _drawResolvedPictureAtBounds(
            canvas,
            line: line,
            imageBounds: resolvedBounds.imageBounds,
            cachedPicture: playedPicture,
          );
        } finally {
          canvas.restore();
        }
        return baseBounds.imageBounds;
    }
  }

  DesktopLinePictureCacheFamilyKey buildPictureFamilyKey({
    required DesktopLyricsPainterLine line,
  }) {
    return pictureCache.buildFamilyKey(
      lineIdentity: line.visualLine,
      baseStyle: line.baseStyle,
      rubyStyle: line.rubyStyle,
      themeSignature: themeSignature,
      devicePixelRatio: devicePixelRatio,
    );
  }

  int estimatePictureBytesForLine(DesktopLyricsPainterLine line) {
    final double picturePadding = _resolvePicturePadding(line);
    return _estimatePictureBytes(line, picturePadding);
  }

  double resolveFloatingDrawX({
    required DesktopLyricsPainterLine line,
    required double viewportWidth,
  }) {
    final DesktopRenderMeasuredLine measuredLine = line.measuredLine;
    final DesktopRenderVisualLine visualLine = line.visualLine;
    final DesktopRenderLinePlan plan = line.plan;
    final double contentWidth = measuredLine.contentWidth;
    final double edgeSafetyInset =
        _resolvePicturePadding(line) +
        1 / _resolveDevicePixelRatio(devicePixelRatio);
    if (contentWidth <= viewportWidth) {
      if (plan.align == Direction.left) {
        return edgeSafetyInset - visualLine.visualLeft;
      }
      return viewportWidth - edgeSafetyInset - visualLine.visualRight;
    }
    return measuredLine.resolveHorizontalOffset(
      viewportWidth: viewportWidth,
      state: plan.state,
      activeProgress: plan.activeProgress,
      leadingInset: edgeSafetyInset,
      trailingInset: edgeSafetyInset,
    );
  }

  Rect _drawCachedLine(
    Canvas canvas, {
    required DesktopLyricsPainterLine line,
    required Offset origin,
    required DesktopLinePictureCacheFamilyKey familyKey,
    required List<Color> colors,
    required DesktopPictureCacheVariant variant,
  }) {
    final DesktopCachedLinePicture cachedPicture = _resolveLinePicture(
      line: line,
      familyKey: familyKey,
      colors: colors,
      variant: variant,
    );
    final DesktopResolvedPictureBounds resolvedBounds =
        resolveDesktopResolvedPictureBounds(
          line: line,
          origin: origin,
          cachedPicture: cachedPicture,
          devicePixelRatio: devicePixelRatio,
        );
    _drawResolvedPictureAtBounds(
      canvas,
      line: line,
      imageBounds: resolvedBounds.imageBounds,
      cachedPicture: cachedPicture,
    );
    return resolvedBounds.imageBounds;
  }

  DesktopCachedLinePicture _resolveLinePicture({
    required DesktopLyricsPainterLine line,
    required DesktopLinePictureCacheFamilyKey familyKey,
    required List<Color> colors,
    required DesktopPictureCacheVariant variant,
  }) {
    return pictureCache.resolveLinePicture(
      familyKey: familyKey,
      variant: variant,
      createPicture: () => _recordLinePicture(line, colors: colors),
    );
  }

  void _drawResolvedPictureAtBounds(
    Canvas canvas, {
    required DesktopLyricsPainterLine line,
    required Rect imageBounds,
    required DesktopCachedLinePicture cachedPicture,
  }) {
    _drawImageWithOpacity(
      canvas,
      image: cachedPicture.image,
      bounds: imageBounds,
      opacity: line.opacity,
    );
  }

  DesktopCachedLinePicture _recordLinePicture(
    DesktopLyricsPainterLine line, {
    required List<Color> colors,
  }) {
    // 录制缓存图时使用物理像素尺寸，贴回时再换算成逻辑坐标。
    // 这样高 DPR 屏幕不会出现模糊文字；picturePadding 负责给描边留空间，
    // 防止黑色描边被图片边界裁掉。
    final double picturePadding = _resolvePicturePadding(line);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas pictureCanvas = createDesktopRasterRecordingCanvas(
      recorder,
      devicePixelRatio: devicePixelRatio,
    );
    _drawFullLine(
      pictureCanvas,
      line: line,
      origin: Offset(
        -line.visualLine.visualLeft + picturePadding,
        picturePadding,
      ),
      colors: colors,
    );
    final ui.Picture picture = recorder.endRecording();
    late final ui.Image image;
    try {
      final Size rasterSize = _resolveRasterSize(line, picturePadding);
      image = picture.toImageSync(
        rasterSize.width.toInt(),
        rasterSize.height.toInt(),
      );
    } finally {
      picture.dispose();
    }
    return DesktopCachedLinePicture(
      image: image,
      padding: picturePadding,
      estimatedBytes: image.width * image.height * 4,
    );
  }

  void _drawImageWithOpacity(
    Canvas canvas, {
    required ui.Image image,
    required Rect bounds,
    required double opacity,
  }) {
    if (opacity <= 0) {
      return;
    }
    final Paint paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (opacity < 0.999) {
      paint.colorFilter = ColorFilter.mode(
        const Color(0xFFFFFFFF).withValues(alpha: opacity),
        BlendMode.modulate,
      );
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      bounds,
      paint,
    );
  }

  void _drawFullLine(
    Canvas canvas, {
    required DesktopLyricsPainterLine line,
    required Offset origin,
    required List<Color> colors,
  }) {
    final DesktopRenderLineFontMetrics fontMetrics = line.fontMetrics;
    final double strokeWidth = resolveDesktopLineStrokeWidth(line);
    final double baseTop =
        origin.dy +
        (line.visualLine.hasRubyLayout ? fontMetrics.rubyHeight : 0);
    final double rubyTop = baseTop - fontMetrics.rubyHeight;

    for (final DesktopRenderToken token in line.visualLine.tokens) {
      final double tokenX = origin.dx + token.x;
      if (token.hasRuby) {
        _drawTokenPart(
          canvas,
          text: token.rubyText!,
          textWidth: token.rubyWidth,
          style: line.rubyStyle,
          colors: colors,
          topLeft: Offset(
            tokenX + (token.baseWidth - token.rubyWidth) / 2,
            rubyTop,
          ),
          gradientHeight: fontMetrics.rubyHeight,
          strokeWidth: strokeWidth,
        );
      }
      _drawTokenPart(
        canvas,
        text: token.text,
        textWidth: token.baseWidth,
        style: line.baseStyle,
        colors: colors,
        topLeft: Offset(tokenX, baseTop),
        gradientHeight: fontMetrics.baseHeight,
        strokeWidth: strokeWidth,
      );
    }
  }

  double _resolvePicturePadding(DesktopLyricsPainterLine line) {
    return resolveDesktopLineRasterPadding(
      line,
      devicePixelRatio: devicePixelRatio,
    );
  }

  void _drawTokenPart(
    Canvas canvas, {
    required String text,
    required double textWidth,
    required TextStyle style,
    required List<Color> colors,
    required Offset topLeft,
    required double gradientHeight,
    required double strokeWidth,
  }) {
    if (text.isEmpty) {
      return;
    }
    final Paint fillPaint = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(
            Rect.fromLTWH(
              topLeft.dx,
              topLeft.dy,
              math.max(textWidth, 1),
              math.max(gradientHeight, 1),
            ),
          );
    final TextPainter strokePainter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = strokeColor,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final TextPainter fillPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(foreground: fillPaint),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    try {
      strokePainter.paint(canvas, topLeft);
      fillPainter.paint(canvas, topLeft);
    } finally {
      strokePainter.dispose();
      fillPainter.dispose();
    }
  }

  static List<Color> _toColors(
    List<RgbColor> colors, {
    required List<Color> fallback,
  }) {
    if (colors.isEmpty) {
      return fallback;
    }
    return colors
        .map((RgbColor value) => Color.fromARGB(255, value.r, value.g, value.b))
        .toList(growable: false);
  }

  static int _rgbColorsHash(
    List<RgbColor> colors, {
    required List<RgbColor> fallback,
  }) {
    final List<RgbColor> resolvedColors = colors.isEmpty ? fallback : colors;
    int result = resolvedColors.length;
    for (final RgbColor color in resolvedColors) {
      result = Object.hash(result, color.r, color.g, color.b);
    }
    return result;
  }

  int _estimatePictureBytes(
    DesktopLyricsPainterLine line,
    double picturePadding,
  ) {
    final Size rasterSize = _resolveRasterSize(line, picturePadding);
    return rasterSize.width.toInt() * rasterSize.height.toInt() * 4;
  }

  Size _resolveRasterSize(
    DesktopLyricsPainterLine line,
    double picturePadding,
  ) {
    assert(
      (picturePadding -
                  resolveDesktopLineRasterPadding(
                    line,
                    devicePixelRatio: devicePixelRatio,
                  ))
              .abs() <
          0.0001,
    );
    return resolveDesktopLineRasterSize(
      line,
      devicePixelRatio: devicePixelRatio,
    );
  }
}
