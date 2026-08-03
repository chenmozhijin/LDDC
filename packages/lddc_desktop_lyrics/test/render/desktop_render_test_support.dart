import 'package:flutter/widgets.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

extension DesktopRenderFrameCompilerTestSupport on DesktopRenderFrameCompiler {
  DesktopFloatingPainterFrame buildFloatingFrame({
    required DesktopFloatingRenderPlan plan,
    required Size viewportSize,
    required String fontFamily,
    required double configuredFontSize,
    required DesktopFloatingFontSizeMode fontSizeMode,
    required bool showFurigana,
    double devicePixelRatio = 1,
    int? estimatedPlaybackTimeMs,
    DesktopGlyphMeasureCache? glyphMeasureCache,
    DesktopLineMeasureCache? lineMeasureCache,
  }) {
    final DesktopFloatingLayoutDocument document = buildFloatingLayoutDocument(
      plan: plan,
      viewportSize: viewportSize,
      fontFamily: fontFamily,
      configuredFontSize: configuredFontSize,
      fontSizeMode: fontSizeMode,
      showFurigana: showFurigana,
      devicePixelRatio: devicePixelRatio,
      glyphMeasureCache: glyphMeasureCache,
      lineMeasureCache: lineMeasureCache,
    );
    return buildFloatingPainterFrame(
      plan: plan,
      document: document,
      estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
    );
  }

  DesktopPanelPainterFrame buildPanelFrame({
    required DesktopPanelRenderPlan plan,
    required Size viewportSize,
    required String fontFamily,
    required double fontSize,
    required bool showFurigana,
    int? estimatedPlaybackTimeMs,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final DesktopPanelLayoutDocument document = buildPanelLayoutDocument(
      plan: plan,
      viewportSize: viewportSize,
      fontFamily: fontFamily,
      fontSize: fontSize,
      showFurigana: showFurigana,
      glyphMeasureCache: glyphMeasureCache,
    );
    return buildPanelPainterFrame(
      plan: plan,
      document: document,
      viewportHeight: viewportSize.height,
      estimatedPlaybackTimeMs: estimatedPlaybackTimeMs,
    );
  }
}
