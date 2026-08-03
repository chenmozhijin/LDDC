import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('DesktopRenderLayoutEngine', () {
    const DesktopRenderLayoutEngine engine = DesktopRenderLayoutEngine();
    const TextStyle baseStyle = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w700,
    );

    test('会按 RubySpan 生成共享布局片段并放大 ruby 片段宽度', () {
      final DesktopRenderMeasuredLine line = engine.measureLine(
        text: '東京駅',
        rubies: const <RubySpan>[RubySpan(start: 0, end: 2, ruby: 'とうきょう')],
        baseStyle: baseStyle,
        showFurigana: true,
      );

      expect(line.segments, hasLength(2));
      expect(line.segments.first.text, '東京');
      expect(line.segments.first.ruby, 'とうきょう');
      expect(line.segments.last.text, '駅');
      expect(line.segments.first.rubyWidth, greaterThan(0));
      expect(
        line.segments.first.width,
        equals(
          line.segments.first.baseWidth > line.segments.first.rubyWidth
              ? line.segments.first.baseWidth
              : line.segments.first.rubyWidth,
        ),
      );
      expect(line.contentWidth, greaterThan(line.segments.last.x));
    });

    test('会把 ruby 片段之间的普通字符继续拆成逐字符共享片段', () {
      final DesktopRenderMeasuredLine line = engine.measureLine(
        text: '東京A駅',
        rubies: const <RubySpan>[RubySpan(start: 0, end: 2, ruby: 'とうきょう')],
        baseStyle: baseStyle,
        showFurigana: true,
      );

      expect(
        line.segments.map(
          (DesktopRenderLineLayoutSegment segment) => segment.text,
        ),
        orderedEquals(const <String>['東京', 'A', '駅']),
      );
      expect(line.segments[1].charStart, 2);
      expect(line.segments[1].charEnd, 3);
      expect(line.segments[2].charStart, 3);
      expect(line.segments[2].charEnd, 4);
    });

    test('segment 级 played width 会复用共享 cursor 与 baseInset', () {
      final DesktopRenderMeasuredLine line = engine.measureLine(
        text: '東京',
        rubies: const <RubySpan>[RubySpan(start: 0, end: 1, ruby: 'とう')],
        baseStyle: baseStyle,
        showFurigana: true,
      );

      final DesktopRenderLineLayoutSegment first = line.segments.first;
      final double partial = line.resolveSegmentBasePlayedWidth(
        segment: first,
        state: DesktopRenderLineState.active,
        activeProgress: const CharProgress(charIndex: 0, charRatio: 0.5),
      );
      final double complete = line.resolveSegmentBasePlayedWidth(
        segment: first,
        state: DesktopRenderLineState.active,
        activeProgress: const CharProgress(charIndex: 1, charRatio: 0),
      );

      expect(partial, greaterThan(0));
      expect(partial, lessThan(first.baseWidth));
      expect(complete, greaterThan(partial));
      expect(complete, lessThanOrEqualTo(first.baseWidth));
    });

    test('ruby 片段逐字光标会按 token 宽度均分推进以对齐Python版', () {
      final DesktopRenderToken rubyToken = DesktopRenderToken(
        type: DesktopRenderTokenType.rubyGroup,
        text: '東京',
        rubyText: 'とうきょう',
        baseWidth: 100,
        rubyWidth: 120,
        height: 44,
        ascent: 30,
        x: 10,
        leftOverhang: 10,
        rightOverhang: 10,
        charIndices: <int>[0, 1],
        charOffsets: <double>[0, 20, 100],
      );
      final DesktopRenderMeasuredLine line = DesktopRenderMeasuredLine(
        segments: <DesktopRenderLineLayoutSegment>[
          DesktopRenderLineLayoutSegment(
            charStart: 0,
            charEnd: 2,
            text: '東京',
            ruby: 'とうきょう',
            x: 10,
            width: 120,
            baseWidth: 100,
            rubyWidth: 120,
            charOffsets: <double>[0, 20, 100],
          ),
        ],
        contentWidth: 120,
        visualLine: DesktopRenderVisualLine(
          tokens: <DesktopRenderToken>[rubyToken],
          height: 44,
          width: 120,
          visualLeft: 0,
          visualRight: 120,
          hasRubyLayout: true,
        ),
        fontMetrics: DesktopRenderLineFontMetrics(
          baseHeight: 30,
          baseAscent: 24,
          rubyHeight: 14,
          rubyAscent: 10,
        ),
      );

      const CharProgress halfwayFirstChar = CharProgress(
        charIndex: 0,
        charRatio: 0.5,
      );
      const double expectedCursorX = 35;

      expect(
        line.resolveCursorX(
          state: DesktopRenderLineState.active,
          activeProgress: halfwayFirstChar,
        ),
        closeTo(expectedCursorX, 0.001),
      );
      expect(
        line.resolveSegmentBasePlayedWidth(
          segment: line.segments.first,
          state: DesktopRenderLineState.active,
          activeProgress: halfwayFirstChar,
        ),
        closeTo(expectedCursorX - line.segments.first.x, 0.001),
      );
    });

    test('ACTIVE 长行 offset 会随进度推进增大', () {
      final DesktopRenderMeasuredLine line = engine.measureLine(
        text: '这是一条非常非常长非常非常长的活动歌词',
        rubies: const <RubySpan>[],
        baseStyle: baseStyle,
        showFurigana: false,
      );

      final double early = -line.resolveHorizontalOffset(
        viewportWidth: 180,
        state: DesktopRenderLineState.active,
        activeProgress: const CharProgress(charIndex: 5, charRatio: 0.4),
      );
      final double late = -line.resolveHorizontalOffset(
        viewportWidth: 180,
        state: DesktopRenderLineState.active,
        activeProgress: const CharProgress(charIndex: 11, charRatio: 0.7),
      );

      expect(early, greaterThan(0));
      expect(late, greaterThan(early));
    });

    test('共享字体度量快照会跟随测量结果输出', () {
      final DesktopRenderMeasuredLine line = engine.measureLine(
        text: '東京',
        rubies: const <RubySpan>[RubySpan(start: 0, end: 2, ruby: 'とうきょう')],
        baseStyle: baseStyle,
        showFurigana: true,
      );

      expect(line.fontMetrics.baseHeight, greaterThan(0));
      expect(line.fontMetrics.baseAscent, greaterThan(0));
      expect(line.fontMetrics.rubyHeight, greaterThan(0));
      expect(line.fontMetrics.rubyAscent, greaterThan(0));
      expect(
        line.visualLine.height,
        closeTo(
          line.fontMetrics.baseHeight + line.fontMetrics.rubyHeight,
          0.001,
        ),
      );
    });

    test('panel block 会按容器真实宽度居中而不是偏向左侧 margin', () {
      final List<DesktopRenderVisualBlock> blocks = engine.layoutBlocks(
        plan: DesktopPanelRenderPlan(
          mode: 'lyrics',
          activeIndex: 0,
          enabledLangs: const <String>['orig'],
          blocks: <DesktopRenderBlockPlan>[
            DesktopRenderBlockPlan(
              origIndex: 0,
              state: DesktopRenderLineState.active,
              lines: <DesktopRenderLinePlan>[
                DesktopRenderLinePlan(
                  origIndex: 0,
                  lang: 'orig',
                  text: '居中歌词',
                  state: DesktopRenderLineState.active,
                ),
              ],
            ),
          ],
        ),
        containerWidth: 400,
        fontFamily: '',
        fontSize: 30,
        showFurigana: true,
        hasRubiesGlobally: false,
      );

      final DesktopRenderVisualLine line = blocks.first.lines['orig']!.first;
      final double visualCenterX =
          line.startX + (line.visualLeft + line.visualRight) / 2;
      expect(visualCenterX, closeTo(200, 1));
    });

    test('越界与重叠 RubySpan 不会让文本游标回退或访问越界', () {
      final DesktopRenderMeasuredLine line = engine.measureLine(
        text: 'ABCDE',
        rubies: const <RubySpan>[
          RubySpan(start: -2, end: 2, ruby: 'ab'),
          RubySpan(start: 1, end: 4, ruby: 'overlap'),
          RubySpan(start: 4, end: 4, ruby: 'empty'),
          RubySpan(start: 99, end: 100, ruby: 'outside'),
        ],
        baseStyle: baseStyle,
        showFurigana: true,
      );

      expect(
        line.segments
            .map((DesktopRenderLineLayoutSegment segment) => segment.text)
            .join(),
        'ABCDE',
      );
      expect(line.segments.first.ruby, 'ab');
      expect(
        line.segments.where(
          (DesktopRenderLineLayoutSegment segment) => segment.hasRuby,
        ),
        hasLength(1),
      );
    });

    test('超长拉丁单词会退化为逐字形换行并保持在宽度内', () {
      final List<DesktopRenderVisualLine> lines = engine.layoutParagraph(
        text: 'supercalifragilisticexpialidocious',
        rubies: const <RubySpan>[],
        maxWidth: 60,
        alignment: TextAlign.left,
        baseStyle: const TextStyle(fontSize: 20),
      );

      expect(lines.length, greaterThan(1));
      for (final DesktopRenderVisualLine line in lines) {
        expect(line.width, lessThanOrEqualTo(60.001));
      }
    });

    test('预留 ruby 高度的多行段落使用真实行高推进 Y 坐标', () {
      final List<DesktopRenderVisualLine> lines = engine.layoutParagraph(
        text: 'ABCDEFGHIJKLMN',
        rubies: const <RubySpan>[],
        maxWidth: 70,
        alignment: TextAlign.left,
        baseStyle: const TextStyle(fontSize: 24),
        reserveRubyHeight: true,
      );

      expect(lines.length, greaterThan(1));
      expect(
        lines[1].y - lines[0].y,
        closeTo(lines[0].height * engine.lineSpacingRatio, 0.001),
      );
    });
  });
}
