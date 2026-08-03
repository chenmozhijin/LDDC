import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import 'desktop_render_test_support.dart';

void main() {
  group('DesktopRenderFrameCompiler 规格', () {
    const DesktopRenderFrameCompiler compiler = DesktopRenderFrameCompiler();

    test('浮窗和面板首帧都由同一 compiler 生成可绘制布局', () {
      final DesktopFloatingPainterFrame floatingFrame = compiler
          .buildFloatingFrame(
            plan: _floatingPlan(),
            viewportSize: const Size(420, 180),
            fontFamily: '',
            configuredFontSize: 30,
            fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
            showFurigana: true,
          );
      final DesktopPanelPainterFrame panelFrame = compiler.buildPanelFrame(
        plan: _panelPlan(),
        viewportSize: const Size(420, 240),
        fontFamily: '',
        fontSize: 30,
        showFurigana: true,
      );

      expect(floatingFrame.document.hasAnyLine, isTrue);
      expect(
        floatingFrame.leftLines.single.plan.state,
        DesktopRenderLineState.active,
      );
      expect(floatingFrame.leftLines.single.visualLine.hasRubyLayout, isTrue);
      expect(panelFrame.blocks, hasLength(3));
      expect(panelFrame.blocks[1].state, DesktopRenderLineState.active);
      expect(panelFrame.targetScrollY, greaterThanOrEqualTo(0));
    });

    test('动静内容切换会通过 geometry hash 触发不同布局 key', () {
      final DesktopFloatingRenderPlan firstPlan = _floatingPlan(text: '春の歌');
      final DesktopFloatingRenderPlan secondPlan = _floatingPlan(text: '夏の歌');

      expect(
        desktopHashFloatingPlanGeometry(firstPlan),
        isNot(desktopHashFloatingPlanGeometry(secondPlan)),
      );
      expect(
        compiler
            .buildFloatingFrame(
              plan: firstPlan,
              viewportSize: const Size(360, 160),
              fontFamily: '',
              configuredFontSize: 30,
              fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
              showFurigana: true,
            )
            .leftLines
            .single
            .plan
            .text,
        '春の歌',
      );
    });

    test('grapheme/ruby cursor 不落到注音 token 之外', () {
      final DesktopFloatingPainterFrame frame = compiler.buildFloatingFrame(
        plan: _floatingPlan(
          text: '👩‍🎤東京',
          activeProgress: const CharProgress(charIndex: 1, charRatio: 0.5),
        ),
        viewportSize: const Size(420, 180),
        fontFamily: '',
        configuredFontSize: 30,
        fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
        showFurigana: true,
      );
      final DesktopLyricsPainterLine line = frame.leftLines.single;
      final double cursorX = line.measuredLine.resolveCursorX(
        state: DesktopRenderLineState.active,
        activeProgress: line.plan.activeProgress,
      );

      expect(cursorX, greaterThanOrEqualTo(0));
      expect(cursorX, lessThanOrEqualTo(line.visualLine.visualRight));
    });

    test('render model 构造后会冻结输入集合', () {
      final List<int> charIndices = <int>[0, 1];
      final List<double> charOffsets = <double>[0, 12, 24];
      final DesktopRenderToken token = DesktopRenderToken(
        type: DesktopRenderTokenType.text,
        text: 'ab',
        rubyText: null,
        baseWidth: 24,
        rubyWidth: 0,
        height: 20,
        ascent: 16,
        x: 0,
        leftOverhang: 0,
        rightOverhang: 0,
        charIndices: charIndices,
        charOffsets: charOffsets,
      );
      final DesktopRenderLineLayoutSegment segment =
          DesktopRenderLineLayoutSegment(
            charStart: 0,
            charEnd: 2,
            text: 'ab',
            ruby: null,
            x: 0,
            width: 24,
            baseWidth: 24,
            rubyWidth: 0,
            charOffsets: charOffsets,
          );
      final List<DesktopRenderLineLayoutSegment> segments =
          <DesktopRenderLineLayoutSegment>[segment];
      final DesktopRenderMeasuredLine measuredLine = DesktopRenderMeasuredLine(
        segments: segments,
        contentWidth: 24,
        visualLine: DesktopRenderVisualLine(
          tokens: <DesktopRenderToken>[token],
        ),
        fontMetrics: const DesktopRenderLineFontMetrics(
          baseHeight: 20,
          baseAscent: 16,
          rubyHeight: 8,
          rubyAscent: 6,
        ),
      );

      charIndices.add(9);
      charOffsets.add(99);
      segments.clear();

      expect(token.charIndices, <int>[0, 1]);
      expect(token.charOffsets, <double>[0, 12, 24]);
      expect(segment.charOffsets, <double>[0, 12, 24]);
      expect(measuredLine.segments, hasLength(1));
      expect(() => token.charIndices.add(3), throwsUnsupportedError);

      final List<DesktopRenderVisualLine> visualLines =
          <DesktopRenderVisualLine>[measuredLine.visualLine];
      final Map<String, List<DesktopRenderVisualLine>> visualLineMap =
          <String, List<DesktopRenderVisualLine>>{'orig': visualLines};
      final DesktopRenderVisualBlock block = DesktopRenderVisualBlock(
        origIndex: 0,
        virtualRect: const Rect.fromLTWH(0, 0, 100, 40),
        lines: visualLineMap,
      );
      visualLines.clear();
      visualLineMap.clear();

      expect(block.lines['orig'], hasLength(1));
      expect(
        () => block.lines['ts'] = const <DesktopRenderVisualLine>[],
        throwsUnsupportedError,
      );
    });

    test('渲染行透明度拒绝非有限值和越界值', () {
      expect(
        () => DesktopRenderLinePlan(
          origIndex: 0,
          lang: 'orig',
          text: 'line',
          state: DesktopRenderLineState.active,
          opacity: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => DesktopRenderLinePlan(
          origIndex: 0,
          lang: 'orig',
          text: 'line',
          state: DesktopRenderLineState.active,
          opacity: 1.1,
        ),
        throwsArgumentError,
      );
    });
  });
}

DesktopFloatingRenderPlan _floatingPlan({
  String text = '東京',
  CharProgress activeProgress = const CharProgress(charIndex: 0, charRatio: 0),
}) {
  return DesktopFloatingRenderPlan(
    leftTracks: <DesktopRenderTrackPlan>[
      DesktopRenderTrackPlan(
        side: Direction.left,
        track: 0,
        focusedOrigIndex: 1,
        lines: <DesktopRenderLinePlan>[
          DesktopRenderLinePlan(
            origIndex: 1,
            lang: 'orig',
            text: text,
            state: DesktopRenderLineState.active,
            activeProgress: activeProgress,
            rubies: const <RubySpan>[RubySpan(start: 0, end: 2, ruby: 'とう')],
          ),
        ],
      ),
    ],
    rightTracks: const <DesktopRenderTrackPlan>[],
    hasRubiesGlobally: true,
  );
}

DesktopPanelRenderPlan _panelPlan() {
  return DesktopPanelRenderPlan(
    mode: 'lyrics',
    activeIndex: 1,
    enabledLangs: const <String>['orig', 'ts'],
    blocks: <DesktopRenderBlockPlan>[
      _panelBlock(0, DesktopRenderLineState.played, '上一句'),
      _panelBlock(1, DesktopRenderLineState.active, '当前句'),
      _panelBlock(2, DesktopRenderLineState.unplayed, '下一句'),
    ],
  );
}

DesktopRenderBlockPlan _panelBlock(
  int index,
  DesktopRenderLineState state,
  String text,
) {
  return DesktopRenderBlockPlan(
    origIndex: index,
    state: state,
    lines: <DesktopRenderLinePlan>[
      DesktopRenderLinePlan(
        origIndex: index,
        lang: 'orig',
        text: text,
        state: state,
      ),
      DesktopRenderLinePlan(
        origIndex: index,
        lang: 'ts',
        text: '$text translation',
        state: state,
      ),
    ],
  );
}
