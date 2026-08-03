import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import 'desktop_render_test_support.dart';

void main() {
  group('DesktopRenderFrameCompiler', () {
    const DesktopRenderFrameCompiler compiler = DesktopRenderFrameCompiler();

    test('浮窗会为全局注音的原文行统一预留 ruby 高度', () {
      final DesktopFloatingPainterFrame frame = compiler.buildFloatingFrame(
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
                  text: '東京',
                  state: DesktopRenderLineState.active,
                  rubies: const <RubySpan>[
                    RubySpan(start: 0, end: 1, ruby: 'とう'),
                  ],
                ),
                DesktopRenderLinePlan(
                  origIndex: 1,
                  lang: 'orig',
                  text: '大阪',
                  state: DesktopRenderLineState.unplayed,
                ),
              ],
            ),
          ],
          rightTracks: const <DesktopRenderTrackPlan>[],
          hasRubiesGlobally: true,
        ),
        viewportSize: const Size(360, 180),
        fontFamily: '',
        configuredFontSize: 30,
        fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
        showFurigana: true,
      );

      expect(frame.document.leftLines, hasLength(2));
      expect(frame.document.leftLines[0].visualLine.hasRubyLayout, isTrue);
      expect(frame.document.leftLines[1].visualLine.hasRubyLayout, isTrue);
      expect(
        frame.document.leftLines[0].fontMetrics.rubyHeight,
        greaterThan(0),
      );
      expect(
        frame.document.leftLines[0].fontMetrics.baseHeight,
        closeTo(frame.document.leftLines[1].fontMetrics.baseHeight, 0.001),
      );
      expect(
        frame.document.leftLines[0].fontMetrics.rubyAscent,
        closeTo(frame.document.leftLines[1].fontMetrics.rubyAscent, 0.001),
      );
      expect(
        frame.document.leftLines[1].visualLine.height,
        greaterThan(frame.document.leftLines[1].baseStyle.fontSize ?? 0),
      );
    });

    test('浮窗 raster 上下边界在不同 DPR 下都位于 preferredHeight 内', () {
      final DesktopFloatingRenderPlan plan = DesktopFloatingRenderPlan(
        leftTracks: <DesktopRenderTrackPlan>[
          DesktopRenderTrackPlan(
            side: Direction.left,
            track: 0,
            focusedOrigIndex: 0,
            lines: <DesktopRenderLinePlan>[
              DesktopRenderLinePlan(
                origIndex: 0,
                lang: 'orig',
                text: '東京の夜空',
                state: DesktopRenderLineState.active,
                rubies: const <RubySpan>[
                  RubySpan(start: 0, end: 2, ruby: 'とうきょう'),
                ],
              ),
              DesktopRenderLinePlan(
                origIndex: 0,
                lang: 'ts',
                text: '东京的夜空',
                state: DesktopRenderLineState.unplayed,
              ),
            ],
          ),
        ],
        rightTracks: const <DesktopRenderTrackPlan>[],
        hasRubiesGlobally: true,
      );

      for (final double dpr in <double>[1, 1.25, 1.5, 2]) {
        final DesktopFloatingPainterFrame frame = compiler.buildFloatingFrame(
          plan: plan,
          viewportSize: const Size(480, 240),
          fontFamily: '',
          configuredFontSize: 42,
          fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
          showFurigana: true,
          devicePixelRatio: dpr,
        );
        double cursorY = frame.document.renderInsets.top;
        for (final DesktopLyricsPainterLine line in <DesktopLyricsPainterLine>[
          ...frame.leftLines,
          ...frame.rightLines,
        ]) {
          final double padding = resolveDesktopLineRasterPadding(
            line,
            devicePixelRatio: dpr,
          );
          final Size rasterSize = resolveDesktopLineRasterSize(
            line,
            devicePixelRatio: dpr,
          );
          final double top = ((cursorY - padding) * dpr).roundToDouble() / dpr;
          final double bottom = top + rasterSize.height / dpr;
          expect(top, greaterThanOrEqualTo(-0.0001), reason: 'dpr=$dpr');
          expect(
            bottom,
            lessThanOrEqualTo(frame.document.preferredHeight + 0.0001),
            reason: 'dpr=$dpr',
          );
          cursorY +=
              line.visualLine.height * compiler.layoutEngine.lineSpacingRatio;
        }
        expect(
          frame.document.preferredHeight * dpr,
          closeTo((frame.document.preferredHeight * dpr).roundToDouble(), 1e-6),
        );
      }
    });

    test('面板会根据 activeIndex 计算居中滚动目标', () {
      final DesktopPanelPainterFrame frame = compiler.buildPanelFrame(
        plan: DesktopPanelRenderPlan(
          mode: 'lyrics',
          activeIndex: 2,
          enabledLangs: const <String>['orig'],
          blocks: <DesktopRenderBlockPlan>[
            for (int index = 0; index < 4; index += 1)
              DesktopRenderBlockPlan(
                origIndex: index,
                state: index < 2
                    ? DesktopRenderLineState.played
                    : index == 2
                    ? DesktopRenderLineState.active
                    : DesktopRenderLineState.unplayed,
                lines: <DesktopRenderLinePlan>[
                  DesktopRenderLinePlan(
                    origIndex: index,
                    lang: 'orig',
                    text: '第$index句歌词第$index句歌词第$index句歌词',
                    state: index < 2
                        ? DesktopRenderLineState.played
                        : index == 2
                        ? DesktopRenderLineState.active
                        : DesktopRenderLineState.unplayed,
                  ),
                ],
              ),
          ],
        ),
        viewportSize: const Size(400, 180),
        fontFamily: '',
        fontSize: 30,
        showFurigana: true,
      );

      expect(frame.document.blocks, hasLength(4));
      expect(frame.targetScrollY, greaterThan(0));
    });

    test('floating 与 panel 会复用同一份 ruby 字体度量快照', () {
      final DesktopFloatingPainterFrame floatingFrame = compiler
          .buildFloatingFrame(
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
                      text: '東京',
                      state: DesktopRenderLineState.active,
                      rubies: const <RubySpan>[
                        RubySpan(start: 0, end: 2, ruby: 'とうきょう'),
                      ],
                    ),
                  ],
                ),
              ],
              rightTracks: const <DesktopRenderTrackPlan>[],
              hasRubiesGlobally: true,
            ),
            viewportSize: const Size(360, 180),
            fontFamily: '',
            configuredFontSize: 30,
            fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
            showFurigana: true,
          );
      final DesktopPanelPainterFrame panelFrame = compiler.buildPanelFrame(
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
                  text: '東京',
                  state: DesktopRenderLineState.active,
                  rubies: const <RubySpan>[
                    RubySpan(start: 0, end: 2, ruby: 'とうきょう'),
                  ],
                ),
              ],
            ),
          ],
        ),
        viewportSize: const Size(360, 220),
        fontFamily: '',
        fontSize: 30,
        showFurigana: true,
      );

      final DesktopStaticLyricsLine floatingLine =
          floatingFrame.document.leftLines.first;
      final DesktopStaticLyricsLine panelLine =
          panelFrame.document.blocks.first.lines['orig']!.first;

      expect(
        floatingLine.measuredLine.fontMetrics.baseHeight,
        closeTo(panelLine.measuredLine.fontMetrics.baseHeight, 0.001),
      );
      expect(
        floatingLine.measuredLine.fontMetrics.rubyHeight,
        closeTo(panelLine.measuredLine.fontMetrics.rubyHeight, 0.001),
      );
      final double floatingBaseTop = floatingLine.fontMetrics.rubyHeight;
      final double floatingRubyTop =
          floatingBaseTop - floatingLine.fontMetrics.rubyHeight;
      final double panelBaseTop = panelLine.fontMetrics.rubyHeight;
      final double panelRubyTop =
          panelBaseTop - panelLine.fontMetrics.rubyHeight;
      expect(
        floatingRubyTop + floatingLine.fontMetrics.rubyHeight,
        closeTo(floatingBaseTop, 0.001),
      );
      expect(
        panelRubyTop + panelLine.fontMetrics.rubyHeight,
        closeTo(panelBaseTop, 0.001),
      );
    });

    test('浮窗帧构建不会覆盖 projector 已计算的逐字进度', () {
      final DesktopFloatingPainterFrame frame = compiler.buildFloatingFrame(
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
                  text: '你好世界',
                  state: DesktopRenderLineState.active,
                  activeProgress: const CharProgress(
                    charIndex: 1,
                    charRatio: 0.25,
                  ),
                  words: const <DesktopRenderWordPlan>[
                    DesktopRenderWordPlan(
                      text: '你好世界',
                      startMs: 1000,
                      endMs: 2000,
                    ),
                  ],
                ),
              ],
            ),
          ],
          rightTracks: const <DesktopRenderTrackPlan>[],
          hasRubiesGlobally: false,
        ),
        viewportSize: const Size(360, 180),
        fontFamily: '',
        configuredFontSize: 30,
        fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
        showFurigana: true,
        estimatedPlaybackTimeMs: 1750,
      );

      expect(
        frame.leftLines.single.plan.activeProgress,
        const CharProgress(charIndex: 1, charRatio: 0.25),
      );
    });

    test('active 行缓存位图会按实际 raster 尺寸解析并吸附到物理像素', () {
      final DesktopFloatingPainterFrame frame = compiler.buildFloatingFrame(
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
        viewportSize: const Size(360, 180),
        fontFamily: '',
        configuredFontSize: 30,
        fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
        showFurigana: true,
      );
      final ui.Image image = _createTestImage(width: 153, height: 61);
      addTearDown(image.dispose);

      final DesktopResolvedPictureBounds resolvedBounds =
          resolveDesktopResolvedPictureBounds(
            line: frame.leftLines.single,
            origin: const Offset(10.3, 20.6),
            cachedPicture: DesktopCachedLinePicture(
              image: image,
              padding: 2,
              estimatedBytes: image.width * image.height * 4,
            ),
            devicePixelRatio: 1.5,
            clipRight: 71.37,
          );

      expect(
        resolvedBounds.imageBounds.height,
        closeTo(image.height / 1.5, 0.0001),
      );
      expect(
        resolvedBounds.imageBounds.width,
        closeTo(image.width / 1.5, 0.0001),
      );
      expect(resolvedBounds.clipRect, isNotNull);
      expect(
        resolvedBounds.clipRect!.top,
        closeTo(resolvedBounds.imageBounds.top, 0.0001),
      );
      expect(
        resolvedBounds.clipRect!.bottom,
        closeTo(resolvedBounds.imageBounds.bottom, 0.0001),
      );
      expect(
        resolvedBounds.clipRect!.left,
        closeTo(resolvedBounds.imageBounds.left, 0.0001),
      );
      expect(_isOnPhysicalPixel(resolvedBounds.imageBounds.left, 1.5), isTrue);
      expect(_isOnPhysicalPixel(resolvedBounds.imageBounds.top, 1.5), isTrue);
      expect(_isOnPhysicalPixel(resolvedBounds.clipRect!.right, 1.5), isTrue);
    });

    test('非 active 行按 transition window 解析淡入淡出透明度', () {
      final DesktopFloatingPainterFrame earlyFrame = compiler
          .buildFloatingFrame(
            plan: _transitionPlan(),
            viewportSize: const Size(360, 180),
            fontFamily: '',
            configuredFontSize: 30,
            fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
            showFurigana: true,
            estimatedPlaybackTimeMs: 1250,
          );
      final DesktopFloatingPainterFrame lateFrame = compiler.buildFloatingFrame(
        plan: _transitionPlan(),
        viewportSize: const Size(360, 180),
        fontFamily: '',
        configuredFontSize: 30,
        fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
        showFurigana: true,
        estimatedPlaybackTimeMs: 1750,
      );

      expect(earlyFrame.leftLines.first.opacity, closeTo(0.75, 0.0001));
      expect(lateFrame.leftLines.first.opacity, closeTo(0.25, 0.0001));
      expect(earlyFrame.leftLines.last.opacity, closeTo(0.25, 0.0001));
      expect(lateFrame.leftLines.last.opacity, closeTo(0.75, 0.0001));
    });

    test('浮窗 painter 会输出真实非透明像素并在结束后释放缓存', () async {
      final DesktopFloatingPainterFrame frame = compiler.buildFloatingFrame(
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
                  text: '真实像素',
                  state: DesktopRenderLineState.active,
                  activeProgress: const CharProgress(
                    charIndex: 2,
                    charRatio: 0.5,
                  ),
                ),
              ],
            ),
          ],
          rightTracks: const <DesktopRenderTrackPlan>[],
          hasRubiesGlobally: false,
        ),
        viewportSize: const Size(360, 180),
        fontFamily: '',
        configuredFontSize: 36,
        fontSizeMode: DesktopFloatingFontSizeMode.fixedFont,
        showFurigana: true,
      );
      final DesktopLinePictureCache cache = DesktopLinePictureCache();
      addTearDown(cache.dispose);
      final DesktopFloatingLyricsPainter painter = DesktopFloatingLyricsPainter(
        resolveFrame: () => frame,
        playedColors: const <RgbColor>[
          RgbColor(0, 255, 255),
          RgbColor(0, 128, 255),
        ],
        unplayedColors: const <RgbColor>[
          RgbColor(255, 0, 0),
          RgbColor(255, 128, 128),
        ],
        layoutEngine: compiler.layoutEngine,
        pictureCache: cache,
        devicePixelRatio: 1,
      );
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(360, 180));
      final ui.Picture picture = recorder.endRecording();
      addTearDown(picture.dispose);
      final ui.Image image = picture.toImageSync(360, 180);
      addTearDown(image.dispose);

      final ByteData? pixels = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final Uint8List bytes = pixels!.buffer.asUint8List();
      bool hasVisiblePixel = false;
      for (int index = 3; index < bytes.length; index += 4) {
        if (bytes[index] != 0) {
          hasVisiblePixel = true;
          break;
        }
      }

      expect(hasVisiblePixel, isTrue);
    });
  });
}

DesktopFloatingRenderPlan _transitionPlan() {
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
            text: '上一句',
            state: DesktopRenderLineState.played,
            opacity: 0.75,
            transitionStartMs: 1000,
            transitionEndMs: 2000,
          ),
          DesktopRenderLinePlan(
            origIndex: 1,
            lang: 'orig',
            text: '下一句',
            state: DesktopRenderLineState.unplayed,
            opacity: 0.25,
            transitionStartMs: 1000,
            transitionEndMs: 2000,
          ),
        ],
      ),
    ],
    rightTracks: const <DesktopRenderTrackPlan>[],
    hasRubiesGlobally: false,
  );
}

ui.Image _createTestImage({required int width, required int height}) {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

bool _isOnPhysicalPixel(double value, double devicePixelRatio) {
  final double physical = value * devicePixelRatio;
  return (physical - physical.roundToDouble()).abs() < 0.0001;
}
