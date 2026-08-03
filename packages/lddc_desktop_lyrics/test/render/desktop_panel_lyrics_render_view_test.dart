import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('DesktopPanelLyricsRenderView', () {
    testWidgets('有 render plan 时走 CustomPaint 主路径', (
      WidgetTester tester,
    ) async {
      await _pumpPanel(tester, plan: _buildPlan(activeIndex: 1));

      final DesktopPanelLyricsPainter painter = _resolvePainter(tester);
      expect(painter.resolveFrame(), isNotNull);
      expect(painter.resolveFrame()!.blocks, hasLength(6));
    });

    testWidgets('renderPlanResolver 会按播放时间采样当前面板帧', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int?> playbackTime = ValueNotifier<int?>(90);
      addTearDown(playbackTime.dispose);

      await _pumpPanel(
        tester,
        plan: null,
        playbackTime: playbackTime,
        resolver: (int? timeMs) => _buildPlan(
          activeIndex: 1,
          activeProgress: CharProgress(
            charIndex: timeMs != null && timeMs >= 200 ? 2 : 0,
            charRatio: 0.25,
          ),
        ),
      );

      CharProgress progress() {
        return _resolvePainter(
          tester,
        ).resolveFrame()!.blocks[1].lines['orig']!.first.plan.activeProgress;
      }

      expect(progress(), const CharProgress(charIndex: 0, charRatio: 0.25));

      playbackTime.value = 260;
      await tester.pump();

      expect(progress(), const CharProgress(charIndex: 2, charRatio: 0.25));
    });

    testWidgets('仅 activeIndex 变化时复用布局并平滑滚动', (WidgetTester tester) async {
      final _CountingDesktopRenderLayoutEngine engine =
          _CountingDesktopRenderLayoutEngine();

      await _pumpPanel(
        tester,
        plan: _buildPlan(activeIndex: 0),
        layoutEngine: engine,
      );
      final int firstLayoutCount = engine.layoutBlocksCallCount;

      await _pumpPanel(
        tester,
        plan: _buildPlan(activeIndex: 4),
        layoutEngine: engine,
      );
      final DesktopPanelLyricsPainter painter = _resolvePainter(tester);
      final double target = painter.resolveFrame()!.targetScrollY;

      await tester.pump(const Duration(milliseconds: 200));
      final double middle = _resolvePainter(tester).resolveScrollY();

      expect(engine.layoutBlocksCallCount, firstLayoutCount);
      expect(target, greaterThan(0));
      expect(middle, greaterThan(0));
      expect(middle, lessThan(target));
    });

    testWidgets('viewport 改变时立即重置旧滚动动画', (WidgetTester tester) async {
      await _pumpPanel(tester, plan: _buildPlan(activeIndex: 0), height: 180);
      await _pumpPanel(tester, plan: _buildPlan(activeIndex: 4), height: 180);
      await tester.pump(const Duration(milliseconds: 100));

      final double animatedValue = _resolvePainter(tester).resolveScrollY();
      await _pumpPanel(tester, plan: _buildPlan(activeIndex: 4), height: 260);
      final DesktopPanelLyricsPainter resizedPainter = _resolvePainter(tester);

      expect(animatedValue, greaterThan(0));
      expect(
        resizedPainter.resolveScrollY(),
        closeTo(resizedPainter.resolveFrame()!.targetScrollY, 0.001),
      );
    });

    testWidgets('内容代际变化时丢弃旧滚动状态并重新 seed', (WidgetTester tester) async {
      await _pumpPanel(
        tester,
        plan: _buildPlan(activeIndex: 0),
        generation: _generation('content-0'),
      );
      await _pumpPanel(
        tester,
        plan: _buildPlan(activeIndex: 4),
        generation: _generation('content-0'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final double animatedValue = _resolvePainter(tester).resolveScrollY();

      await _pumpPanel(
        tester,
        plan: _buildPlan(activeIndex: 4),
        generation: _generation('content-1'),
      );
      final DesktopPanelLyricsPainter resetPainter = _resolvePainter(tester);

      expect(animatedValue, greaterThan(0));
      expect(
        resetPainter.resolveScrollY(),
        closeTo(resetPainter.resolveFrame()!.targetScrollY, 0.001),
      );
    });

    testWidgets('已有有效帧后 render plan 短暂为空时继续显示上一帧', (WidgetTester tester) async {
      await _pumpPanel(tester, plan: _buildPlan(activeIndex: 2));
      final DesktopPanelPainterFrame originalFrame = _resolvePainter(
        tester,
      ).resolveFrame()!;

      await _pumpPanel(tester, plan: null);

      expect(find.byType(CustomPaint), findsWidgets);
      expect(_resolvePainter(tester).resolveFrame(), same(originalFrame));
    });

    testWidgets('播放时间刷新不会覆盖 render plan 自带逐字进度', (WidgetTester tester) async {
      final ValueNotifier<int?> playbackTime = ValueNotifier<int?>(0);
      addTearDown(playbackTime.dispose);
      const CharProgress expected = CharProgress(charIndex: 1, charRatio: 0.4);

      await _pumpPanel(
        tester,
        plan: _buildPlan(activeIndex: 1, activeProgress: expected),
        playbackTime: playbackTime,
      );

      playbackTime.value = 750;
      await tester.pump();

      expect(
        _resolvePainter(
          tester,
        ).resolveFrame()!.blocks[1].lines['orig']!.first.plan.activeProgress,
        expected,
      );
    });

    testWidgets('卸载后会解除播放时间监听', (WidgetTester tester) async {
      final ValueNotifier<int?> playbackTime = ValueNotifier<int?>(0);
      addTearDown(playbackTime.dispose);

      await _pumpPanel(
        tester,
        plan: _buildPlan(activeIndex: 1),
        playbackTime: playbackTime,
      );
      await tester.pumpWidget(const SizedBox.shrink());

      playbackTime.value = 1000;
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required DesktopPanelRenderPlan? plan,
  double width = 420,
  double height = 220,
  DesktopRenderGenerationKey? generation,
  DesktopRenderLayoutEngine layoutEngine = const DesktopRenderLayoutEngine(),
  ValueListenable<int?>? playbackTime,
  DesktopPanelRenderPlan? Function(int? playbackTimeMs)? resolver,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: DesktopPanelLyricsRenderView(
            renderPlan: plan,
            renderPlanResolver: resolver,
            renderGenerationKey:
                generation ??
                _generation('content-0', width: width, height: height),
            layoutEngine: layoutEngine,
            estimatedPlaybackTimeListenable: playbackTime,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

DesktopPanelLyricsPainter _resolvePainter(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (Widget widget) =>
          widget is CustomPaint && widget.painter is DesktopPanelLyricsPainter,
    ),
  );
  return paint.painter! as DesktopPanelLyricsPainter;
}

DesktopRenderGenerationKey _generation(
  String contentIdentity, {
  double width = 420,
  double height = 220,
  double devicePixelRatio = 1,
}) {
  return DesktopRenderGenerationKey(
    contentIdentity: contentIdentity,
    renderIdentity: 'panel-scene',
    viewportWidth: width.round(),
    viewportHeight: height.round(),
    devicePixelRatio: devicePixelRatio,
    themeSignature: 1,
  );
}

DesktopPanelRenderPlan _buildPlan({
  required int activeIndex,
  CharProgress activeProgress = const CharProgress(charIndex: 0, charRatio: 0),
}) {
  return DesktopPanelRenderPlan(
    mode: 'lyrics',
    activeIndex: activeIndex,
    enabledLangs: const <String>['orig'],
    blocks: <DesktopRenderBlockPlan>[
      for (int index = 0; index < 6; index += 1)
        DesktopRenderBlockPlan(
          origIndex: index,
          state: index < activeIndex
              ? DesktopRenderLineState.played
              : index == activeIndex
              ? DesktopRenderLineState.active
              : DesktopRenderLineState.unplayed,
          lines: <DesktopRenderLinePlan>[
            DesktopRenderLinePlan(
              origIndex: index,
              lang: 'orig',
              text: '第$index句歌词第$index句歌词第$index句歌词',
              state: index < activeIndex
                  ? DesktopRenderLineState.played
                  : index == activeIndex
                  ? DesktopRenderLineState.active
                  : DesktopRenderLineState.unplayed,
              activeProgress: index == activeIndex
                  ? activeProgress
                  : const CharProgress(charIndex: 0, charRatio: 0),
            ),
          ],
        ),
    ],
  );
}

class _CountingDesktopRenderLayoutEngine extends DesktopRenderLayoutEngine {
  int layoutBlocksCallCount = 0;

  @override
  List<DesktopRenderVisualBlock> layoutBlocks({
    required DesktopPanelRenderPlan plan,
    required double containerWidth,
    required String fontFamily,
    required double fontSize,
    required bool showFurigana,
    required bool hasRubiesGlobally,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    layoutBlocksCallCount += 1;
    return super.layoutBlocks(
      plan: plan,
      containerWidth: containerWidth,
      fontFamily: fontFamily,
      fontSize: fontSize,
      showFurigana: showFurigana,
      hasRubiesGlobally: hasRubiesGlobally,
      glyphMeasureCache: glyphMeasureCache,
    );
  }
}
