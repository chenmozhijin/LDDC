import 'dart:async';

import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('DesktopFloatingLyricsRenderView', () {
    testWidgets('有 render plan 时走 CustomPaint 主路径', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 180,
              child: DesktopFloatingLyricsRenderView(
                title: 'Song',
                subtitle: 'Artist',
                renderPlan: DesktopFloatingRenderPlan(
                  leftTracks: <DesktopRenderTrackPlan>[
                    DesktopRenderTrackPlan(
                      side: Direction.left,
                      track: 0,
                      focusedOrigIndex: 1,
                      lines: <DesktopRenderLinePlan>[
                        DesktopRenderLinePlan(
                          origIndex: 1,
                          lang: 'orig',
                          text: '你好世界',
                          state: DesktopRenderLineState.active,
                          activeProgress: const CharProgress(
                            charIndex: 1,
                            charRatio: 0.5,
                          ),
                          rubies: const <RubySpan>[
                            RubySpan(start: 0, end: 1, ruby: 'ni'),
                          ],
                        ),
                        DesktopRenderLinePlan(
                          origIndex: 1,
                          lang: 'ts',
                          text: 'hello world',
                          state: DesktopRenderLineState.unplayed,
                        ),
                      ],
                    ),
                  ],
                  rightTracks: const <DesktopRenderTrackPlan>[],
                  hasRubiesGlobally: true,
                ),
                playedColors: const <RgbColor>[
                  RgbColor(0, 255, 255),
                  RgbColor(0, 128, 255),
                ],
                unplayedColors: const <RgbColor>[
                  RgbColor(255, 0, 0),
                  RgbColor(255, 128, 128),
                ],
              ),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CustomPaint &&
              widget.painter is DesktopFloatingLyricsPainter,
        ),
        findsOneWidget,
      );
      expect(find.byType(AnimatedSlide), findsNothing);
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(find.byType(ClipRect), findsNothing);
      expect(find.text('Song'), findsNothing);
    });

    testWidgets('renderPlanResolver 会按 estimatedPlaybackTime 采样当前帧', (
      WidgetTester tester,
    ) async {
      final ValueNotifier<int?> estimatedPlaybackTime = ValueNotifier<int?>(90);

      DesktopFloatingRenderPlan buildPlan(int charIndex) {
        return DesktopFloatingRenderPlan(
          leftTracks: <DesktopRenderTrackPlan>[
            DesktopRenderTrackPlan(
              side: Direction.left,
              track: 0,
              focusedOrigIndex: 0,
              lines: <DesktopRenderLinePlan>[
                DesktopRenderLinePlan(
                  origIndex: 0,
                  lang: 'orig',
                  text: '你好世界',
                  state: DesktopRenderLineState.active,
                  activeProgress: CharProgress(
                    charIndex: charIndex,
                    charRatio: 0.25,
                  ),
                ),
              ],
            ),
          ],
          rightTracks: const <DesktopRenderTrackPlan>[],
          hasRubiesGlobally: false,
        );
      }

      DesktopFloatingRenderPlan? sampleFrame(int? playbackTimeMs) {
        final int charIndex = playbackTimeMs != null && playbackTimeMs >= 200
            ? 2
            : 0;
        return buildPlan(charIndex);
      }

      Finder painterFinder() => find.byWidgetPredicate(
        (Widget widget) =>
            widget is CustomPaint &&
            widget.painter is DesktopFloatingLyricsPainter,
      );

      DesktopFloatingLyricsPainter resolvePainter() {
        final CustomPaint widget = tester.widget<CustomPaint>(painterFinder());
        return widget.painter! as DesktopFloatingLyricsPainter;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 180,
              child: DesktopFloatingLyricsRenderView(
                title: 'Song',
                renderPlan: null,
                renderPlanResolver: sampleFrame,
                estimatedPlaybackTimeListenable: estimatedPlaybackTime,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        resolvePainter().resolveFrame()!.leftLines.first.plan.activeProgress,
        const CharProgress(charIndex: 0, charRatio: 0.25),
      );

      estimatedPlaybackTime.value = 260;
      await tester.pump();

      expect(
        resolvePainter().resolveFrame()!.leftLines.first.plan.activeProgress,
        const CharProgress(charIndex: 2, charRatio: 0.25),
      );
      estimatedPlaybackTime.dispose();
    });

    testWidgets('会回报基于当前内容的首选高度', (WidgetTester tester) async {
      double? reportedHeight;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 180,
              child: DesktopFloatingLyricsRenderView(
                title: 'Song',
                renderPlan: DesktopFloatingRenderPlan(
                  leftTracks: <DesktopRenderTrackPlan>[
                    DesktopRenderTrackPlan(
                      side: Direction.left,
                      track: 0,
                      focusedOrigIndex: 0,
                      lines: <DesktopRenderLinePlan>[
                        DesktopRenderLinePlan(
                          origIndex: 0,
                          lang: 'orig',
                          text: '東京',
                          state: DesktopRenderLineState.active,
                          rubies: const <RubySpan>[
                            RubySpan(start: 0, end: 1, ruby: 'とう'),
                            RubySpan(start: 1, end: 2, ruby: 'きょう'),
                          ],
                        ),
                      ],
                    ),
                  ],
                  rightTracks: const <DesktopRenderTrackPlan>[],
                  hasRubiesGlobally: true,
                ),
                onFrameCommitted: (DesktopFloatingFrameMetrics metrics) async {
                  reportedHeight = metrics.preferredHeight;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(reportedHeight, isNotNull);
      expect(reportedHeight, greaterThan(0));
    });

    testWidgets('ACTIVE 行连续帧会稳定复用 played/unplayed 双变体缓存', (
      WidgetTester tester,
    ) async {
      final DesktopLyricsPerfStats stats = DesktopLyricsPerfStats.instance;
      stats.reset();
      final ValueNotifier<int?> estimatedPlaybackTime = ValueNotifier<int?>(
        100,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 180,
              child: DesktopFloatingLyricsRenderView(
                title: 'Song',
                estimatedPlaybackTimeListenable: estimatedPlaybackTime,
                renderPlan: DesktopFloatingRenderPlan(
                  leftTracks: <DesktopRenderTrackPlan>[
                    DesktopRenderTrackPlan(
                      side: Direction.left,
                      track: 0,
                      focusedOrigIndex: 0,
                      lines: <DesktopRenderLinePlan>[
                        DesktopRenderLinePlan(
                          origIndex: 0,
                          lang: 'orig',
                          text: '你好世界',
                          state: DesktopRenderLineState.active,
                          activeProgress: const CharProgress(
                            charIndex: 1,
                            charRatio: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                  rightTracks: const <DesktopRenderTrackPlan>[],
                  hasRubiesGlobally: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final int hitBeforeSecondFrame = stats.counterOf('cacheHit');
      expect(stats.latestOf('linePictureEntries'), 2);

      estimatedPlaybackTime.value = 140;
      await tester.pump();

      expect(
        stats.counterOf('cacheHit') - hitBeforeSecondFrame,
        greaterThanOrEqualTo(2),
      );
      estimatedPlaybackTime.dispose();
    });

    testWidgets('固定字号模式下，视口高度变化不会改 resolvedFontSize', (
      WidgetTester tester,
    ) async {
      final List<DesktopFloatingFrameMetrics> metrics =
          <DesktopFloatingFrameMetrics>[];

      Future<void> pump(double height) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: height,
                child: DesktopFloatingLyricsRenderView(
                  title: 'Song',
                  fontSize: 30,
                  fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
                  renderPlan: DesktopFloatingRenderPlan(
                    leftTracks: <DesktopRenderTrackPlan>[
                      DesktopRenderTrackPlan(
                        side: Direction.left,
                        track: 0,
                        focusedOrigIndex: 0,
                        lines: <DesktopRenderLinePlan>[
                          DesktopRenderLinePlan(
                            origIndex: 0,
                            lang: 'orig',
                            text: '東京特許許可局',
                            state: DesktopRenderLineState.active,
                          ),
                        ],
                      ),
                    ],
                    rightTracks: const <DesktopRenderTrackPlan>[],
                    hasRubiesGlobally: false,
                  ),
                  onFrameCommitted: (DesktopFloatingFrameMetrics value) async {
                    metrics.add(value);
                  },
                ),
              ),
            ),
          ),
        );
      }

      await pump(180);
      await tester.pump();
      final double firstFontSize = metrics.last.resolvedFontSize;

      await pump(260);
      await tester.pump();

      expect(metrics.last.resolvedFontSize, closeTo(firstFontSize, 0.01));
    });

    testWidgets('交互 resize 模式下，视口高度变大时 resolvedFontSize 也会变大', (
      WidgetTester tester,
    ) async {
      DesktopFloatingFrameMetrics? firstMetrics;
      DesktopFloatingFrameMetrics? secondMetrics;

      Future<void> pump({
        required double height,
        required ValueChanged<DesktopFloatingFrameMetrics> onMetrics,
      }) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: height,
                child: DesktopFloatingLyricsRenderView(
                  title: 'Song',
                  fontSize: 30,
                  fontSizeMode: DesktopFloatingFontSizeMode.interactiveResize,
                  renderPlan: DesktopFloatingRenderPlan(
                    leftTracks: <DesktopRenderTrackPlan>[
                      DesktopRenderTrackPlan(
                        side: Direction.left,
                        track: 0,
                        focusedOrigIndex: 0,
                        lines: <DesktopRenderLinePlan>[
                          DesktopRenderLinePlan(
                            origIndex: 0,
                            lang: 'orig',
                            text: '東京特許許可局',
                            state: DesktopRenderLineState.active,
                          ),
                          DesktopRenderLinePlan(
                            origIndex: 0,
                            lang: 'ts',
                            text: 'Tokyo',
                            state: DesktopRenderLineState.unplayed,
                          ),
                        ],
                      ),
                    ],
                    rightTracks: const <DesktopRenderTrackPlan>[],
                    hasRubiesGlobally: false,
                  ),
                  onFrameCommitted: (DesktopFloatingFrameMetrics value) async {
                    onMetrics(value);
                  },
                ),
              ),
            ),
          ),
        );
      }

      await pump(
        height: 140,
        onMetrics: (DesktopFloatingFrameMetrics metrics) {
          firstMetrics = metrics;
        },
      );
      await tester.pump();
      await pump(
        height: 260,
        onMetrics: (DesktopFloatingFrameMetrics metrics) {
          secondMetrics = metrics;
        },
      );
      await tester.pump();

      expect(firstMetrics, isNotNull);
      expect(secondMetrics, isNotNull);
      expect(
        secondMetrics!.resolvedFontSize,
        greaterThan(firstMetrics!.resolvedFontSize),
      );
    });

    testWidgets('没有 render plan 时保持空白，不再回退 title/subtitle 文案', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DesktopFloatingLyricsRenderView(
              title: 'Song',
              subtitle: 'Artist',
              renderPlan: null,
            ),
          ),
        ),
      );

      expect(find.text('Song'), findsNothing);
      expect(find.text('Artist'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CustomPaint &&
              widget.painter is DesktopFloatingLyricsPainter,
        ),
        findsNothing,
      );
    });

    testWidgets('已有有效帧后，render plan 短暂为空时继续保留 CustomPaint', (
      WidgetTester tester,
    ) async {
      Future<void> pump(DesktopFloatingRenderPlan? plan) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 160,
                child: DesktopFloatingLyricsRenderView(
                  title: 'Song',
                  subtitle: 'Artist',
                  renderPlan: plan,
                ),
              ),
            ),
          ),
        );
      }

      await pump(
        DesktopFloatingRenderPlan(
          leftTracks: <DesktopRenderTrackPlan>[
            DesktopRenderTrackPlan(
              side: Direction.left,
              track: 0,
              focusedOrigIndex: 0,
              lines: <DesktopRenderLinePlan>[
                DesktopRenderLinePlan(
                  origIndex: 0,
                  lang: 'orig',
                  text: '第一句歌词',
                  state: DesktopRenderLineState.active,
                ),
              ],
            ),
          ],
          rightTracks: const <DesktopRenderTrackPlan>[],
          hasRubiesGlobally: false,
        ),
      );
      await tester.pump();

      await pump(null);
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CustomPaint &&
              widget.painter is DesktopFloatingLyricsPainter,
        ),
        findsOneWidget,
      );
      expect(find.text('Song'), findsNothing);
    });

    testWidgets('新内容 candidate 尚未生成时继续显示上一份完整帧', (WidgetTester tester) async {
      Future<void> pump({
        required DesktopFloatingRenderPlan? plan,
        required String renderIdentity,
      }) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 160,
                child: DesktopFloatingLyricsRenderView(
                  title: 'Song',
                  subtitle: 'Artist',
                  renderIdentity: renderIdentity,
                  renderPlan: plan,
                ),
              ),
            ),
          ),
        );
      }

      await pump(
        renderIdentity: 'scene-a',
        plan: DesktopFloatingRenderPlan(
          leftTracks: <DesktopRenderTrackPlan>[
            DesktopRenderTrackPlan(
              side: Direction.left,
              track: 0,
              focusedOrigIndex: 0,
              lines: <DesktopRenderLinePlan>[
                DesktopRenderLinePlan(
                  origIndex: 0,
                  lang: 'orig',
                  text: '第一句歌词',
                  state: DesktopRenderLineState.active,
                ),
              ],
            ),
          ],
          rightTracks: const <DesktopRenderTrackPlan>[],
          hasRubiesGlobally: false,
        ),
      );
      await tester.pump();

      await pump(renderIdentity: 'scene-b', plan: null);
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CustomPaint &&
              widget.painter is DesktopFloatingLyricsPainter,
        ),
        findsOneWidget,
      );
    });

    testWidgets('renderIdentity 变化后即使高度相同也会重新上报 metrics', (
      WidgetTester tester,
    ) async {
      final List<DesktopFloatingFrameMetrics> metrics =
          <DesktopFloatingFrameMetrics>[];

      DesktopFloatingRenderPlan planFor(String text) {
        return DesktopFloatingRenderPlan(
          leftTracks: <DesktopRenderTrackPlan>[
            DesktopRenderTrackPlan(
              side: Direction.left,
              track: 0,
              focusedOrigIndex: 0,
              lines: <DesktopRenderLinePlan>[
                DesktopRenderLinePlan(
                  origIndex: 0,
                  lang: 'orig',
                  text: text,
                  state: DesktopRenderLineState.active,
                ),
              ],
            ),
          ],
          rightTracks: const <DesktopRenderTrackPlan>[],
          hasRubiesGlobally: false,
        );
      }

      Future<void> pump({
        required String renderIdentity,
        required String text,
      }) {
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 160,
                child: DesktopFloatingLyricsRenderView(
                  title: 'Song',
                  renderIdentity: renderIdentity,
                  renderPlan: planFor(text),
                  onFrameCommitted: (DesktopFloatingFrameMetrics value) async {
                    metrics.add(value);
                  },
                ),
              ),
            ),
          ),
        );
      }

      await pump(renderIdentity: 'static-loading', text: '自动加载歌词中');
      await tester.pump();
      final double firstHeight = metrics.single.preferredHeight;

      await pump(renderIdentity: 'lyrics-scene', text: '正式歌词出现');
      await tester.pump();

      expect(metrics, hasLength(2));
      expect(metrics.last.preferredHeight, closeTo(firstHeight, 0.01));
    });

    testWidgets('旧 revision 的延迟 candidate 与 post-frame metrics 不会提交', (
      WidgetTester tester,
    ) async {
      final Completer<bool> oldCandidateGate = Completer<bool>();
      final List<int> candidates = <int>[];
      final List<int> committed = <int>[];

      DesktopFloatingRenderPlan planFor(String text) {
        return DesktopFloatingRenderPlan(
          leftTracks: <DesktopRenderTrackPlan>[
            DesktopRenderTrackPlan(
              side: Direction.left,
              track: 0,
              focusedOrigIndex: 0,
              lines: <DesktopRenderLinePlan>[
                DesktopRenderLinePlan(
                  origIndex: 0,
                  lang: 'orig',
                  text: text,
                  state: DesktopRenderLineState.active,
                ),
              ],
            ),
          ],
          rightTracks: const <DesktopRenderTrackPlan>[],
          hasRubiesGlobally: false,
        );
      }

      Future<void> pump(int revision, String text) {
        return tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 420,
              height: 180,
              child: DesktopFloatingLyricsRenderView(
                title: text,
                contentRevision: revision,
                renderIdentity: 'scene-$revision',
                renderPlan: planFor(text),
                onFrameCandidate: (DesktopFloatingFrameMetrics metrics) {
                  candidates.add(metrics.contentRevision);
                  if (metrics.contentRevision == 1) {
                    return oldCandidateGate.future;
                  }
                  return Future<bool>.value(true);
                },
                onFrameCommitted: (DesktopFloatingFrameMetrics metrics) async {
                  committed.add(metrics.contentRevision);
                },
              ),
            ),
          ),
        );
      }

      await pump(1, '旧歌词');
      await tester.pump();
      expect(candidates, <int>[1]);

      await pump(2, '新歌词');
      oldCandidateGate.complete(true);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(candidates, <int>[1, 2]);
      expect(committed, <int>[2]);
    });

    testWidgets('DPR 变化会生成新的浮窗布局 revision', (WidgetTester tester) async {
      final List<DesktopFloatingFrameMetrics> committed =
          <DesktopFloatingFrameMetrics>[];
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Future<void> pump(double dpr) async {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = Size(800 * dpr, 400 * dpr);
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 420,
              height: 180,
              child: DesktopFloatingLyricsRenderView(
                title: 'Song',
                renderPlan: _singleLinePlan('跨屏歌词'),
                onFrameCommitted: (DesktopFloatingFrameMetrics metrics) async {
                  committed.add(metrics);
                },
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await pump(1);
      await pump(2);

      expect(committed, hasLength(2));
      expect(
        committed.last.layoutRevision,
        greaterThan(committed.first.layoutRevision),
      );
    });

    testWidgets('frame candidate 回调异常会被报告并保留上一提交状态', (
      WidgetTester tester,
    ) async {
      final FlutterExceptionHandler? previousHandler = FlutterError.onError;
      final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previousHandler);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 420,
            height: 180,
            child: DesktopFloatingLyricsRenderView(
              title: 'Song',
              renderPlan: _singleLinePlan('候选歌词'),
              onFrameCandidate: (DesktopFloatingFrameMetrics metrics) async {
                throw StateError('native resize failed');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(errors, hasLength(1));
      expect(errors.single.exception, isA<StateError>());
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is CustomPaint &&
              widget.painter is DesktopFloatingLyricsPainter,
        ),
        findsNothing,
      );
    });

    testWidgets('estimatedPlaybackTime 高频更新时不会重新 layoutSingleLine', (
      WidgetTester tester,
    ) async {
      final _CountingDesktopRenderLayoutEngine layoutEngine =
          _CountingDesktopRenderLayoutEngine();
      final ValueNotifier<int?> estimatedPlayback = ValueNotifier<int?>(0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 180,
              child: DesktopFloatingLyricsRenderView(
                title: 'Song',
                renderPlan: DesktopFloatingRenderPlan(
                  leftTracks: <DesktopRenderTrackPlan>[
                    DesktopRenderTrackPlan(
                      side: Direction.left,
                      track: 0,
                      focusedOrigIndex: 0,
                      lines: <DesktopRenderLinePlan>[
                        DesktopRenderLinePlan(
                          origIndex: 0,
                          lang: 'orig',
                          text: '当前歌词当前歌词当前歌词',
                          state: DesktopRenderLineState.active,
                        ),
                      ],
                    ),
                  ],
                  rightTracks: const <DesktopRenderTrackPlan>[],
                  hasRubiesGlobally: false,
                ),
                estimatedPlaybackTimeListenable: estimatedPlayback,
                layoutEngine: layoutEngine,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final int firstLayoutCount = layoutEngine.layoutSingleLineCallCount;
      estimatedPlayback.value = 500;
      await tester.pump();
      estimatedPlayback.value = 900;
      await tester.pump();

      expect(layoutEngine.layoutSingleLineCallCount, firstLayoutCount);
    });
  });
}

DesktopFloatingRenderPlan _singleLinePlan(String text) {
  return DesktopFloatingRenderPlan(
    leftTracks: <DesktopRenderTrackPlan>[
      DesktopRenderTrackPlan(
        side: Direction.left,
        track: 0,
        focusedOrigIndex: 0,
        lines: <DesktopRenderLinePlan>[
          DesktopRenderLinePlan(
            origIndex: 0,
            lang: 'orig',
            text: text,
            state: DesktopRenderLineState.active,
          ),
        ],
      ),
    ],
    rightTracks: const <DesktopRenderTrackPlan>[],
    hasRubiesGlobally: false,
  );
}

class _CountingDesktopRenderLayoutEngine extends DesktopRenderLayoutEngine {
  int layoutSingleLineCallCount = 0;

  @override
  DesktopRenderVisualLine layoutSingleLine({
    required String text,
    required List<RubySpan> rubies,
    required TextStyle baseStyle,
    required bool reserveRubyHeight,
    DesktopGlyphMeasureCache? glyphMeasureCache,
  }) {
    layoutSingleLineCallCount += 1;
    return super.layoutSingleLine(
      text: text,
      rubies: rubies,
      baseStyle: baseStyle,
      reserveRubyHeight: reserveRubyHeight,
      glyphMeasureCache: glyphMeasureCache,
    );
  }
}
