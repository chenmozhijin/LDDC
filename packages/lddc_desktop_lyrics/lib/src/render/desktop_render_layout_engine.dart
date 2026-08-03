import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'desktop_lyrics_content_filter.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'desktop_render_cache.dart';
import 'desktop_render_models.dart';

/// 共享桌面歌词布局引擎，对齐Python版 `LyricsLayoutEngine`。
class DesktopRenderLayoutEngine {
  const DesktopRenderLayoutEngine({
    this.lineSpacingRatio = 1.2,
    this.blockSpacing = 20,
    this.rubyScale = 0.6,
    this.margin = 10,
    this.overhangLimitRatio = 0.5,
  });

  final double lineSpacingRatio;
  final double blockSpacing;
  final double rubyScale;
  final double margin;
  final double overhangLimitRatio;

  DesktopRenderMeasuredLine measureLine({
    required String text,
    required List<RubySpan> rubies,
    required TextStyle baseStyle,
    required bool showFurigana,
    bool reserveRubyHeight = false,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final _PreparedFonts fonts = _prepareFonts(
      baseStyle,
      glyphMeasureCache: glyphMeasureCache,
    );
    final DesktopRenderVisualLine visualLine = _layoutSingleLineWithFonts(
      text: text,
      rubies: showFurigana ? rubies : const <RubySpan>[],
      baseStyle: baseStyle,
      reserveRubyHeight: reserveRubyHeight,
      fonts: fonts,
      glyphMeasureCache: glyphMeasureCache,
    );
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
      fontMetrics: fonts.fontMetrics,
    );
  }

  DesktopRenderVisualLine layoutSingleLine({
    required String text,
    required List<RubySpan> rubies,
    required TextStyle baseStyle,
    required bool reserveRubyHeight,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final _PreparedFonts fonts = _prepareFonts(
      baseStyle,
      glyphMeasureCache: glyphMeasureCache,
    );
    return _layoutSingleLineWithFonts(
      text: text,
      rubies: rubies,
      baseStyle: baseStyle,
      reserveRubyHeight: reserveRubyHeight,
      fonts: fonts,
      glyphMeasureCache: glyphMeasureCache,
    );
  }

  DesktopRenderVisualLine _layoutSingleLineWithFonts({
    required String text,
    required List<RubySpan> rubies,
    required TextStyle baseStyle,
    required bool reserveRubyHeight,
    required _PreparedFonts fonts,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final List<DesktopRenderToken> tokens = _createTokens(
      text: text,
      rubies: rubies,
      baseStyle: fonts.baseStyle,
      rubyStyle: fonts.rubyStyle,
      fontMetrics: fonts.fontMetrics,
      localOverhangLimit: fonts.localOverhangLimit,
      glyphMeasureCache: glyphMeasureCache,
    );

    if (tokens.isEmpty) {
      double height = fonts.baseMeasure.height;
      if (reserveRubyHeight) {
        height = math.max(
          height,
          fonts.baseMeasure.height + fonts.rubyMeasure.height,
        );
      }
      return DesktopRenderVisualLine(
        tokens: const <DesktopRenderToken>[],
        height: height,
      );
    }

    double lineMinX = double.infinity;
    double lineMaxX = double.negativeInfinity;
    double maxHeight = 0;
    for (final DesktopRenderToken token in tokens) {
      final double tokenVisualLeft = token.x + token.visualLeft;
      final double tokenVisualRight = token.x + token.visualRight;
      lineMinX = math.min(lineMinX, tokenVisualLeft);
      lineMaxX = math.max(lineMaxX, tokenVisualRight);
      maxHeight = math.max(maxHeight, token.height);
    }

    final bool hasRubyLayout =
        tokens.any((DesktopRenderToken token) => token.hasRuby) ||
        reserveRubyHeight;
    if (reserveRubyHeight) {
      final double requiredHeight =
          fonts.baseMeasure.height + fonts.rubyMeasure.height;
      maxHeight = math.max(maxHeight, requiredHeight);
    }

    return DesktopRenderVisualLine(
      tokens: tokens,
      height: maxHeight,
      width: lineMaxX - lineMinX,
      startX: 0,
      visualLeft: lineMinX,
      visualRight: lineMaxX,
      hasRubyLayout: hasRubyLayout,
    );
  }

  List<DesktopRenderVisualLine> layoutParagraph({
    required String text,
    required List<RubySpan> rubies,
    required double maxWidth,
    required TextAlign alignment,
    required TextStyle baseStyle,
    double offsetY = 0,
    bool reserveRubyHeight = false,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final double resolvedMaxWidth = maxWidth.isFinite
        ? math.max(maxWidth, 1)
        : 1;
    final _PreparedFonts fonts = _prepareFonts(
      baseStyle,
      glyphMeasureCache: glyphMeasureCache,
    );
    final List<DesktopRenderToken> rawTokens = _createTokens(
      text: text,
      rubies: rubies,
      baseStyle: fonts.baseStyle,
      rubyStyle: fonts.rubyStyle,
      fontMetrics: fonts.fontMetrics,
      localOverhangLimit: fonts.localOverhangLimit,
      glyphMeasureCache: glyphMeasureCache,
    );
    if (rawTokens.isEmpty) {
      return const <DesktopRenderVisualLine>[];
    }

    final List<List<DesktopRenderToken>> chunks = <List<DesktopRenderToken>>[];
    List<DesktopRenderToken> currentChunk = <DesktopRenderToken>[];
    for (final DesktopRenderToken token in rawTokens) {
      final bool isCjk = _isCjk(token.text);
      final bool isSpace = token.text.trim().isEmpty;
      bool shouldBreak = false;
      if (currentChunk.isNotEmpty) {
        final DesktopRenderToken lastToken = currentChunk.last;
        final bool lastIsCjk = _isCjk(lastToken.text);
        final bool lastIsSpace = lastToken.text.trim().isEmpty;
        if (isCjk || isSpace || lastIsCjk || lastIsSpace) {
          shouldBreak = true;
        }
      }
      if (shouldBreak && currentChunk.isNotEmpty) {
        chunks.add(List<DesktopRenderToken>.unmodifiable(currentChunk));
        currentChunk = <DesktopRenderToken>[];
      }
      currentChunk.add(token);
    }
    if (currentChunk.isNotEmpty) {
      chunks.add(List<DesktopRenderToken>.unmodifiable(currentChunk));
    }

    final List<DesktopRenderVisualLine> finalLines =
        <DesktopRenderVisualLine>[];
    List<DesktopRenderToken> currentLineTokens = <DesktopRenderToken>[];
    double currentY = offsetY;

    double commitLine(List<DesktopRenderToken> tokens) {
      if (tokens.isEmpty) {
        return 0;
      }
      final double offsetX = tokens.first.x;
      double lineMinX = double.infinity;
      double lineMaxX = double.negativeInfinity;
      double lineHeight = 0;
      final bool hasRuby = tokens.any(
        (DesktopRenderToken token) => token.hasRuby,
      );
      final List<DesktopRenderToken> normalizedTokens = tokens
          .map((DesktopRenderToken token) {
            final double newX = token.x - offsetX;
            final DesktopRenderToken normalized = DesktopRenderToken(
              type: token.type,
              text: token.text,
              rubyText: token.rubyText,
              baseWidth: token.baseWidth,
              rubyWidth: token.rubyWidth,
              height: token.height,
              ascent: token.ascent,
              x: newX,
              leftOverhang: token.leftOverhang,
              rightOverhang: token.rightOverhang,
              charIndices: token.charIndices,
              charOffsets: token.charOffsets,
            );
            lineMinX = math.min(lineMinX, normalized.x + normalized.visualLeft);
            lineMaxX = math.max(
              lineMaxX,
              normalized.x + normalized.visualRight,
            );
            lineHeight = math.max(lineHeight, normalized.height);
            return normalized;
          })
          .toList(growable: false);

      final bool hasRubyLayout = hasRuby || reserveRubyHeight;
      if (reserveRubyHeight) {
        lineHeight = math.max(
          lineHeight,
          fonts.baseMeasure.height + fonts.rubyMeasure.height,
        );
      }

      final double contentWidth = lineMaxX - lineMinX;
      final double startX = switch (alignment) {
        TextAlign.right => resolvedMaxWidth - lineMaxX,
        TextAlign.center => (resolvedMaxWidth - contentWidth) / 2 - lineMinX,
        _ => -lineMinX,
      };
      finalLines.add(
        DesktopRenderVisualLine(
          tokens: normalizedTokens,
          y: currentY,
          height: lineHeight,
          width: contentWidth,
          startX: startX,
          visualLeft: lineMinX,
          visualRight: lineMaxX,
          hasRubyLayout: hasRubyLayout,
        ),
      );
      return lineHeight;
    }

    double visualWidthBetween(
      DesktopRenderToken first,
      DesktopRenderToken last,
    ) {
      return last.x + last.visualRight - (first.x + first.visualLeft);
    }

    double visualWidth(List<DesktopRenderToken> tokens) {
      if (tokens.isEmpty) {
        return 0;
      }
      return visualWidthBetween(tokens.first, tokens.last);
    }

    void commitCurrentLine() {
      if (currentLineTokens.isEmpty) {
        return;
      }
      final double lineHeight = commitLine(currentLineTokens);
      currentY += lineHeight * lineSpacingRatio;
      currentLineTokens = <DesktopRenderToken>[];
    }

    void appendChunk(List<DesktopRenderToken> chunk) {
      if (chunk.isEmpty) {
        return;
      }
      if (currentLineTokens.isNotEmpty) {
        if (visualWidthBetween(currentLineTokens.first, chunk.last) <=
            resolvedMaxWidth) {
          currentLineTokens.addAll(chunk);
          return;
        }
        commitCurrentLine();
      }
      if (visualWidth(chunk) <= resolvedMaxWidth || chunk.length == 1) {
        currentLineTokens.addAll(chunk);
        return;
      }
      // 英文等连续非 CJK 文本通常作为一个单词块换行。若单词本身比视口还宽，
      // 必须退化为逐字形切分，否则面板会永久横向溢出。单个 ruby group 不拆分，
      // 因为拆开后将无法维持正文与注音的对应关系。
      for (final DesktopRenderToken token in chunk) {
        if (currentLineTokens.isNotEmpty &&
            visualWidthBetween(currentLineTokens.first, token) >
                resolvedMaxWidth) {
          commitCurrentLine();
        }
        currentLineTokens.add(token);
      }
    }

    for (final List<DesktopRenderToken> chunk in chunks) {
      appendChunk(chunk);
    }

    if (currentLineTokens.isNotEmpty) {
      commitLine(currentLineTokens);
    }

    return List<DesktopRenderVisualLine>.unmodifiable(finalLines);
  }

  List<DesktopRenderVisualBlock> layoutBlocks({
    required DesktopPanelRenderPlan plan,
    required double containerWidth,
    required String fontFamily,
    required double fontSize,
    required bool showFurigana,
    required bool hasRubiesGlobally,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final double resolvedContainerWidth = containerWidth.isFinite
        ? math.max(containerWidth, 1)
        : 1;
    final double validWidth = math.max(
      100.0,
      resolvedContainerWidth - margin * 2,
    );
    double currentY = margin;
    final List<DesktopRenderVisualBlock> blocks = <DesktopRenderVisualBlock>[];

    for (final DesktopRenderBlockPlan blockPlan in plan.blocks) {
      final Map<String, List<DesktopRenderVisualLine>> blockLines =
          <String, List<DesktopRenderVisualLine>>{};
      double blockHeight = 0;
      bool hasVisualContent = false;

      for (final DesktopRenderLinePlan linePlan in blockPlan.lines) {
        final String text = linePlan.text;
        if (!desktopLyricsHasRenderableContent(text)) {
          continue;
        }
        final bool isOrig = linePlan.lang == 'orig';
        final TextStyle baseStyle = buildBaseTextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          isOrig: isOrig,
        );
        final List<DesktopRenderVisualLine> lines = layoutParagraph(
          text: text,
          rubies: showFurigana && isOrig ? linePlan.rubies : const <RubySpan>[],
          maxWidth: validWidth,
          alignment: TextAlign.center,
          baseStyle: baseStyle,
          offsetY: blockHeight,
          reserveRubyHeight: hasRubiesGlobally && isOrig,
          glyphMeasureCache: glyphMeasureCache,
        );
        if (lines.isEmpty) {
          continue;
        }
        final List<DesktopRenderVisualLine> shiftedLines = lines
            .map(
              (DesktopRenderVisualLine line) => DesktopRenderVisualLine(
                tokens: line.tokens,
                y: line.y,
                height: line.height,
                width: line.width,
                startX: line.startX + margin,
                visualLeft: line.visualLeft,
                visualRight: line.visualRight,
                hasRubyLayout: line.hasRubyLayout,
              ),
            )
            .toList(growable: false);
        blockLines[linePlan.lang] = shiftedLines;
        final DesktopRenderVisualLine lastLine = shiftedLines.last;
        blockHeight = lastLine.y + lastLine.height * lineSpacingRatio;
        hasVisualContent = true;
      }

      blocks.add(
        DesktopRenderVisualBlock(
          origIndex: blockPlan.origIndex,
          virtualRect: Rect.fromLTWH(
            0,
            currentY,
            resolvedContainerWidth,
            blockHeight,
          ),
          lines: blockLines,
        ),
      );
      if (hasVisualContent) {
        currentY += blockHeight + blockSpacing;
      }
    }

    return List<DesktopRenderVisualBlock>.unmodifiable(blocks);
  }

  TextStyle buildBaseTextStyle({
    required String fontFamily,
    required double fontSize,
    required bool isOrig,
  }) {
    final double resolvedFontSize = fontSize.isFinite && fontSize > 0
        ? fontSize
        : 8;
    return TextStyle(
      fontFamily: fontFamily.trim().isEmpty ? null : fontFamily,
      fontSize: isOrig ? resolvedFontSize : resolvedFontSize * 0.8,
      fontWeight: FontWeight.w700,
      height: 1.0,
    );
  }

  TextStyle buildRubyTextStyle(TextStyle baseStyle) {
    return baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? 20) * rubyScale,
      height: 1.0,
      fontWeight: FontWeight.w500,
    );
  }

  DesktopRenderLineFontMetrics buildLineFontMetrics(
    TextStyle baseStyle, {
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final _PreparedFonts fonts = _prepareFonts(
      baseStyle,
      glyphMeasureCache: glyphMeasureCache,
    );
    return fonts.fontMetrics;
  }

  _PreparedFonts _prepareFonts(
    TextStyle baseStyle, {
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final TextStyle resolvedBaseStyle = baseStyle.copyWith(height: 1.0);
    final TextStyle rubyStyle = buildRubyTextStyle(resolvedBaseStyle);
    final _TextMeasure baseMeasure = _measureTextCached(
      value: '〇',
      textStyle: resolvedBaseStyle,
      glyphMeasureCache: glyphMeasureCache,
    );
    final _TextMeasure fullBaseMeasure = _measureTextCached(
      value: 'M',
      textStyle: resolvedBaseStyle,
      glyphMeasureCache: glyphMeasureCache,
    );
    final _TextMeasure rubyMeasure = _measureTextCached(
      value: 'M',
      textStyle: rubyStyle,
      glyphMeasureCache: glyphMeasureCache,
    );
    return _PreparedFonts(
      baseStyle: resolvedBaseStyle,
      rubyStyle: rubyStyle,
      baseMeasure: fullBaseMeasure,
      rubyMeasure: rubyMeasure,
      fontMetrics: DesktopRenderLineFontMetrics(
        baseHeight: fullBaseMeasure.height,
        baseAscent: fullBaseMeasure.ascent,
        rubyHeight: rubyMeasure.height,
        rubyAscent: rubyMeasure.ascent,
      ),
      localOverhangLimit: baseMeasure.width * overhangLimitRatio,
    );
  }

  List<DesktopRenderToken> _createTokens({
    required String text,
    required List<RubySpan> rubies,
    required TextStyle baseStyle,
    required TextStyle rubyStyle,
    required DesktopRenderLineFontMetrics fontMetrics,
    required double localOverhangLimit,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final List<DesktopRenderToken> tokens = <DesktopRenderToken>[];
    double currentPenX = 0;
    double lastRubyEndX = -10000;

    for (final _LogicalToken logical in _iterLogicalTokens(text, rubies)) {
      final _TokenMetrics metrics = _calcMetrics(
        text: logical.text,
        rubyText: logical.rubyText,
        baseStyle: baseStyle,
        rubyStyle: rubyStyle,
        fontMetrics: fontMetrics,
        glyphMeasureCache: glyphMeasureCache,
      );
      final List<double> charOffsets = _buildCharOffsets(
        logical.text,
        baseStyle,
        glyphMeasureCache: glyphMeasureCache,
      );

      double gap = 0;
      final bool hasRuby =
          logical.type == DesktopRenderTokenType.rubyGroup &&
          logical.rubyText != null &&
          logical.rubyText!.isNotEmpty;
      final double rubyLeftOffset = hasRuby ? metrics.leftOverhang : 0;

      if (hasRuby) {
        final double needed = lastRubyEndX - currentPenX + rubyLeftOffset;
        gap = math.max(gap, needed);
        gap = math.max(gap, rubyLeftOffset - localOverhangLimit);
      }

      gap = math.max(gap, lastRubyEndX - currentPenX - localOverhangLimit);
      final double tokenX = currentPenX + gap;
      final DesktopRenderToken token = DesktopRenderToken(
        type: logical.type,
        text: logical.text,
        rubyText: logical.rubyText,
        baseWidth: metrics.baseWidth,
        rubyWidth: metrics.rubyWidth,
        height: metrics.height,
        ascent: metrics.ascent,
        x: tokenX,
        leftOverhang: metrics.leftOverhang,
        rightOverhang: metrics.rightOverhang,
        charIndices: logical.charIndices,
        charOffsets: charOffsets,
      );
      tokens.add(token);
      currentPenX = token.x + token.baseWidth;
      if (hasRuby) {
        lastRubyEndX = token.x + token.baseWidth + token.rightOverhang;
      }
    }

    return List<DesktopRenderToken>.unmodifiable(tokens);
  }

  Iterable<_LogicalToken> _iterLogicalTokens(
    String text,
    List<RubySpan> rubyMapping,
  ) sync* {
    final List<String> chars = text.characters.toList(growable: false);
    if (chars.isEmpty) {
      return;
    }
    if (rubyMapping.isEmpty) {
      for (int index = 0; index < chars.length; index += 1) {
        yield _LogicalToken(
          type: DesktopRenderTokenType.text,
          text: chars[index],
          rubyText: null,
          charIndices: <int>[index],
        );
      }
      return;
    }

    final List<_NormalizedRubySpan> normalizedRubies = _normalizeRubySpans(
      rubyMapping,
      chars.length,
    );
    int textCursor = 0;
    for (final _NormalizedRubySpan ruby in normalizedRubies) {
      for (int index = textCursor; index < ruby.start; index += 1) {
        yield _LogicalToken(
          type: DesktopRenderTokenType.text,
          text: chars[index],
          rubyText: null,
          charIndices: <int>[index],
        );
      }
      yield _LogicalToken(
        type: DesktopRenderTokenType.rubyGroup,
        text: chars.sublist(ruby.start, ruby.end).join(),
        rubyText: ruby.ruby,
        charIndices: List<int>.generate(
          ruby.end - ruby.start,
          (int index) => ruby.start + index,
          growable: false,
        ),
      );
      textCursor = ruby.end;
    }
    for (int index = textCursor; index < chars.length; index += 1) {
      yield _LogicalToken(
        type: DesktopRenderTokenType.text,
        text: chars[index],
        rubyText: null,
        charIndices: <int>[index],
      );
    }
  }

  _TokenMetrics _calcMetrics({
    required String text,
    required String? rubyText,
    required TextStyle baseStyle,
    required TextStyle rubyStyle,
    required DesktopRenderLineFontMetrics fontMetrics,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    final _TextMeasure baseMeasure = _measureTextCached(
      value: text,
      textStyle: baseStyle,
      glyphMeasureCache: glyphMeasureCache,
    );
    double rubyWidth = 0;
    double leftOverhang = 0;
    double rightOverhang = 0;
    double height = fontMetrics.baseHeight;
    if (rubyText != null && rubyText.isNotEmpty) {
      final _TextMeasure rubyMeasure = _measureTextCached(
        value: rubyText,
        textStyle: rubyStyle,
        glyphMeasureCache: glyphMeasureCache,
      );
      rubyWidth = rubyMeasure.width;
      height += fontMetrics.rubyHeight;
      if (rubyWidth > baseMeasure.width) {
        final double diff = (rubyWidth - baseMeasure.width) / 2;
        leftOverhang = diff;
        rightOverhang = diff;
      }
    }
    return _TokenMetrics(
      baseWidth: baseMeasure.width,
      rubyWidth: rubyWidth,
      height: height,
      ascent: fontMetrics.baseAscent,
      leftOverhang: leftOverhang,
      rightOverhang: rightOverhang,
    );
  }

  bool _isCjk(String text) {
    if (text.isEmpty) {
      return false;
    }
    final int code = text.runes.first;
    return (0x4E00 <= code && code <= 0x9FFF) ||
        (0x3000 <= code && code <= 0x303F) ||
        (0xFF00 <= code && code <= 0xFFEF) ||
        (0x3040 <= code && code <= 0x309F) ||
        (0x30A0 <= code && code <= 0x30FF) ||
        (0xAC00 <= code && code <= 0xD7AF) ||
        (0x2000 <= code && code <= 0x206F);
  }

  List<double> _buildCharOffsets(
    String text,
    TextStyle style, {
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    if (text.isEmpty) {
      return const <double>[0];
    }
    final DesktopGlyphMeasureCache? cache = glyphMeasureCache;
    if (cache != null) {
      return cache.measureCharOffsets(text: text, style: style);
    }
    final List<double> offsets = <double>[0];
    double currentWidth = 0;
    for (final String char in text.characters) {
      currentWidth += _measureText(value: char, textStyle: style).width;
      offsets.add(currentWidth);
    }
    return List<double>.unmodifiable(offsets);
  }
}

class _PreparedFonts {
  const _PreparedFonts({
    required this.baseStyle,
    required this.rubyStyle,
    required this.baseMeasure,
    required this.rubyMeasure,
    required this.fontMetrics,
    required this.localOverhangLimit,
  });

  final TextStyle baseStyle;
  final TextStyle rubyStyle;
  final _TextMeasure baseMeasure;
  final _TextMeasure rubyMeasure;
  final DesktopRenderLineFontMetrics fontMetrics;
  final double localOverhangLimit;
}

class _LogicalToken {
  const _LogicalToken({
    required this.type,
    required this.text,
    required this.rubyText,
    required this.charIndices,
  });

  final DesktopRenderTokenType type;
  final String text;
  final String? rubyText;
  final List<int> charIndices;
}

class _NormalizedRubySpan {
  const _NormalizedRubySpan({
    required this.start,
    required this.end,
    required this.ruby,
  });

  final int start;
  final int end;
  final String ruby;
}

class _TokenMetrics {
  const _TokenMetrics({
    required this.baseWidth,
    required this.rubyWidth,
    required this.height,
    required this.ascent,
    required this.leftOverhang,
    required this.rightOverhang,
  });

  final double baseWidth;
  final double rubyWidth;
  final double height;
  final double ascent;
  final double leftOverhang;
  final double rightOverhang;
}

class _TextMeasure {
  const _TextMeasure({
    required this.width,
    required this.height,
    required this.ascent,
  });

  final double width;
  final double height;
  final double ascent;
}

_TextMeasure _measureTextCached({
  required String value,
  required TextStyle textStyle,
  DesktopGlyphMeasureCache? glyphMeasureCache,
}) {
  final DesktopGlyphMeasureCache? cache = glyphMeasureCache;
  if (cache == null) {
    return _measureText(value: value, textStyle: textStyle);
  }
  final DesktopMeasuredText measure = cache.measureText(
    text: value,
    style: textStyle,
  );
  return _TextMeasure(
    width: measure.width,
    height: measure.height,
    ascent: measure.ascent,
  );
}

_TextMeasure _measureText({
  required String value,
  required TextStyle textStyle,
}) {
  // 不传 LRU cache 的调用只做一次性低频测量，不能写入库级全局 Map。
  // 高频浮窗/面板路径必须显式传入 DesktopGlyphMeasureCache 管理容量和生命周期。
  final TextPainter painter = TextPainter(
    text: TextSpan(text: value, style: textStyle),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final List<LineMetrics> metrics = painter.computeLineMetrics();
  final LineMetrics? lineMetrics = metrics.isEmpty ? null : metrics.first;
  final _TextMeasure measure = _TextMeasure(
    width: painter.width,
    height: painter.height,
    ascent: lineMetrics?.ascent ?? painter.height,
  );
  return measure;
}

List<_NormalizedRubySpan> _normalizeRubySpans(
  List<RubySpan> rubies,
  int textLength,
) {
  if (rubies.isEmpty || textLength <= 0) {
    return const <_NormalizedRubySpan>[];
  }
  final List<RubySpan> sorted = List<RubySpan>.of(rubies)
    ..sort((RubySpan left, RubySpan right) {
      final int startCompare = left.start.compareTo(right.start);
      if (startCompare != 0) {
        return startCompare;
      }
      final int endCompare = right.end.compareTo(left.end);
      if (endCompare != 0) {
        return endCompare;
      }
      return left.ruby.compareTo(right.ruby);
    });
  final List<_NormalizedRubySpan> result = <_NormalizedRubySpan>[];
  int coveredEnd = 0;
  for (final RubySpan ruby in sorted) {
    final int start = ruby.start.clamp(0, textLength);
    final int end = ruby.end.clamp(start, textLength);
    if (end <= start || start < coveredEnd) {
      continue;
    }
    result.add(_NormalizedRubySpan(start: start, end: end, ruby: ruby.ruby));
    coveredEnd = end;
  }
  return result;
}
