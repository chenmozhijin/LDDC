import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/src/render/desktop_lyrics_painter.dart';
import 'package:lddc_desktop_lyrics/src/render/desktop_lyrics_perf_stats.dart';
import 'package:lddc_desktop_lyrics/src/render/desktop_render_cache.dart';
import 'package:lddc_desktop_lyrics/src/render/desktop_render_models.dart';

void main() {
  group('DesktopGlyphMeasureCache', () {
    test('遵守 entry 预算并按 LRU 淘汰旧测量结果', () {
      final DesktopLyricsPerfStats stats = DesktopLyricsPerfStats.instance;
      stats.reset();
      final DesktopGlyphMeasureCache cache = DesktopGlyphMeasureCache(
        measureEntryLimit: 1,
        measureByteLimit: 1024 * 1024,
      );
      addTearDown(cache.dispose);
      const TextStyle style = TextStyle(fontSize: 24);

      cache.measureText(text: 'A', style: style);
      cache.measureText(text: 'B', style: style);
      cache.measureText(text: 'B', style: style);
      cache.measureText(text: 'A', style: style);

      expect(stats.peakOf('glyphMeasureEntries'), 1);
      expect(stats.counterOf('cacheMiss'), 3);
      expect(stats.counterOf('cacheHit'), 1);
      expect(stats.counterOf('cacheEvict'), 2);
    });

    test('非法容量在 release 语义下也会明确拒绝', () {
      expect(
        () => DesktopGlyphMeasureCache(measureEntryLimit: 0),
        throwsArgumentError,
      );
      expect(() => DesktopLineMeasureCache(byteLimit: -1), throwsArgumentError);
      expect(() => DesktopLinePictureCache(entryLimit: 0), throwsArgumentError);
    });
  });

  group('DesktopLinePictureCache', () {
    test('优先逐出冷 family 中未使用的 variant', () {
      final DesktopLyricsPerfStats stats = DesktopLyricsPerfStats.instance;
      stats.reset();
      final DesktopLinePictureCache cache = DesktopLinePictureCache(
        entryLimit: 8,
        byteLimit: 8 * 1024 * 1024,
      );
      addTearDown(cache.dispose);
      final DesktopLinePictureCacheFamilyKey familyA = _family(cache, Object());
      final DesktopLinePictureCacheFamilyKey familyB = _family(cache, Object());

      cache.runFrame<void>(_frame(1, soft: 16 * 1024, hard: 16 * 1024), () {
        cache.hintFamily(familyA, DesktopPictureHint.visible, priorityClass: 2);
        cache.hintFamily(
          familyA,
          DesktopPictureHint.protected,
          priorityClass: 3,
        );
        cache.resolveLinePicture(
          familyKey: familyA,
          variant: DesktopPictureCacheVariant.played,
          createPicture: () => _picture(Colors.cyan),
        );
        cache.resolveLinePicture(
          familyKey: familyA,
          variant: DesktopPictureCacheVariant.unplayed,
          createPicture: () => _picture(Colors.blue),
        );
      });

      cache.runFrame<void>(_frame(2, soft: 8192, hard: 8192), () {
        cache.resolveLinePicture(
          familyKey: familyB,
          variant: DesktopPictureCacheVariant.played,
          createPicture: () => _picture(Colors.red),
        );
      });

      expect(stats.counterOf('linePictureVariantEvict'), 1);
      expect(stats.counterOf('linePictureFamilyEvict'), 0);
      expect(stats.counterOf('pictureDispose'), 1);
      expect(stats.latestOf('linePictureEntries'), 2);
    });

    test('当前帧 protected family 不会被预算淘汰', () {
      final DesktopLyricsPerfStats stats = DesktopLyricsPerfStats.instance;
      stats.reset();
      final DesktopLinePictureCache cache = DesktopLinePictureCache();
      addTearDown(cache.dispose);
      final DesktopLinePictureCacheFamilyKey protectedFamily = _family(
        cache,
        Object(),
      );
      final DesktopLinePictureCacheFamilyKey coldFamily = _family(
        cache,
        Object(),
      );

      cache.runFrame<void>(_frame(1, soft: 8192, hard: 8192), () {
        cache.hintFamily(
          protectedFamily,
          DesktopPictureHint.protected,
          priorityClass: 3,
        );
        for (final DesktopPictureCacheVariant variant
            in DesktopPictureCacheVariant.values) {
          cache.resolveLinePicture(
            familyKey: protectedFamily,
            variant: variant,
            createPicture: () => _picture(Colors.cyan),
          );
        }
        cache.resolveLinePicture(
          familyKey: coldFamily,
          variant: DesktopPictureCacheVariant.played,
          createPicture: () => _picture(Colors.red),
        );
      });

      final int missBeforeRecheck = stats.counterOf('cacheMiss');
      cache.runFrame<void>(_frame(2, soft: 8192, hard: 8192), () {
        cache.hintFamily(
          protectedFamily,
          DesktopPictureHint.protected,
          priorityClass: 3,
        );
        for (final DesktopPictureCacheVariant variant
            in DesktopPictureCacheVariant.values) {
          cache.resolveLinePicture(
            familyKey: protectedFamily,
            variant: variant,
            createPicture: () => _picture(Colors.cyan),
          );
        }
      });

      expect(stats.counterOf('cacheMiss'), missBeforeRecheck);
      expect(stats.counterOf('cacheHit'), 2);
      expect(stats.counterOf('cacheEvict'), 1);
    });

    test('warm 预热优先保留滚动方向前方的 family', () {
      final DesktopLyricsPerfStats stats = DesktopLyricsPerfStats.instance;
      stats.reset();
      final DesktopLinePictureCache cache = DesktopLinePictureCache();
      addTearDown(cache.dispose);
      final DesktopLinePictureCacheFamilyKey leadFamily = _family(
        cache,
        Object(),
      );
      final DesktopLinePictureCacheFamilyKey tailFamily = _family(
        cache,
        Object(),
      );

      cache.runFrame<void>(_frame(1, soft: 4096, hard: 8192), () {
        cache.hintFamily(
          leadFamily,
          DesktopPictureHint.warm,
          priorityClass: 1,
          distanceToViewport: 12,
        );
        cache.hintFamily(
          tailFamily,
          DesktopPictureHint.warm,
          distanceToViewport: 12,
        );
        cache.resolveLinePicture(
          familyKey: leadFamily,
          variant: DesktopPictureCacheVariant.played,
          createPicture: () => _picture(Colors.cyan),
        );
        cache.resolveLinePicture(
          familyKey: tailFamily,
          variant: DesktopPictureCacheVariant.played,
          createPicture: () => _picture(Colors.blue),
        );
      });

      final int missBeforeRecheck = stats.counterOf('cacheMiss');
      cache.runFrame<void>(_frame(2, soft: 4096, hard: 8192), () {
        cache.hintFamily(
          leadFamily,
          DesktopPictureHint.warm,
          priorityClass: 1,
          distanceToViewport: 12,
        );
        cache.resolveLinePicture(
          familyKey: leadFamily,
          variant: DesktopPictureCacheVariant.played,
          createPicture: () => _picture(Colors.cyan),
        );
      });

      expect(stats.counterOf('cacheMiss'), missBeforeRecheck);
      expect(stats.counterOf('cacheHit'), 1);
      expect(stats.counterOf('cacheEvict'), 1);
    });

    test('budget 公式按 floating 与 panel 输出精确值', () {
      final DesktopPictureCacheBudget floating =
          resolveDesktopPictureCacheBudget(
            lane: DesktopPictureCacheLane.floating,
            protectedFloorBytes: 20 * 1024 * 1024,
          );
      final DesktopPictureCacheBudget panel = resolveDesktopPictureCacheBudget(
        lane: DesktopPictureCacheLane.panel,
        protectedFloorBytes: 20 * 1024 * 1024,
      );

      expect(floating.softBudgetBytes, 20 * 1024 * 1024);
      expect(floating.hardBudgetBytes, 20 * 1024 * 1024);
      expect(panel.softBudgetBytes, 20 * 1024 * 1024);
      expect(panel.hardBudgetBytes, 32 * 1024 * 1024);
      expect(
        () => resolveDesktopPictureCacheBudget(
          lane: DesktopPictureCacheLane.panel,
          protectedFloorBytes: -1,
        ),
        throwsArgumentError,
      );
    });

    test('family key 对等价视觉行稳定，并拒绝相同 hash 的不同对象', () {
      final DesktopLinePictureCache cache = DesktopLinePictureCache();
      addTearDown(cache.dispose);
      final DesktopLinePictureCacheFamilyKey first = _family(
        cache,
        _visualLine('同一句歌词'),
      );
      final DesktopLinePictureCacheFamilyKey rebuilt = _family(
        cache,
        _visualLine('同一句歌词'),
      );
      final DesktopLinePictureCacheFamilyKey changed = _family(
        cache,
        _visualLine('另一句歌词'),
      );
      final DesktopLinePictureCacheFamilyKey collisionA = _family(
        cache,
        const _CollidingIdentity(1),
      );
      final DesktopLinePictureCacheFamilyKey collisionB = _family(
        cache,
        const _CollidingIdentity(2),
      );

      expect(first, rebuilt);
      expect(first.hashCode, rebuilt.hashCode);
      expect(first, isNot(changed));
      expect(collisionA.lineSignatureHash, collisionB.lineSignatureHash);
      expect(collisionA, isNot(collisionB));
    });

    test('帧回调异常会原样抛出，dispose 后拒绝继续使用', () {
      final DesktopLinePictureCache cache = DesktopLinePictureCache();

      expect(
        () => cache.runFrame<void>(_frame(1), () {
          throw StateError('paint failed');
        }),
        throwsStateError,
      );
      cache.runFrame<void>(_frame(2), () {});
      cache.dispose();

      expect(() => cache.runFrame<void>(_frame(3), () {}), throwsStateError);
      expect(() => cache.bindGeneration(_generation()), throwsStateError);
      cache.dispose();
    });
  });

  testWidgets('文本逻辑宽度不随 DPR 变化，raster 宽度按 DPR 放大', (WidgetTester tester) async {
    const TextSpan text = TextSpan(
      text: 'だから 強く笑い続けた',
      style: TextStyle(fontSize: 48, color: Colors.white),
    );
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    ({double logicalWidth, int rasterWidth}) rasterize(double dpr) {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = Size(1200 * dpr, 800 * dpr);
      final TextPainter painter = TextPainter(
        text: text,
        textDirection: TextDirection.ltr,
      )..layout();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = createDesktopRasterRecordingCanvas(
        recorder,
        devicePixelRatio: dpr,
      );
      painter.paint(canvas, Offset.zero);
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = picture.toImageSync(
        math.max((painter.width * dpr).ceil(), 1),
        math.max((painter.height * dpr).ceil(), 1),
      );
      final double logicalWidth = painter.width;
      final int rasterWidth = image.width;
      image.dispose();
      picture.dispose();
      painter.dispose();
      return (logicalWidth: logicalWidth, rasterWidth: rasterWidth);
    }

    final ({double logicalWidth, int rasterWidth}) at1x = rasterize(1);
    final ({double logicalWidth, int rasterWidth}) at2x = rasterize(2);

    expect(at1x.logicalWidth, closeTo(at2x.logicalWidth, 0.001));
    expect(at1x.rasterWidth, at1x.logicalWidth.ceil());
    expect(at2x.rasterWidth, (at2x.logicalWidth * 2).ceil());

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = createDesktopRasterRecordingCanvas(
      recorder,
      devicePixelRatio: 1.5,
    );
    final Float64List transform = canvas.getTransform();
    recorder.endRecording().dispose();
    expect(transform[0], closeTo(1.5, 0.0001));
    expect(transform[5], closeTo(1.5, 0.0001));
  });
}

DesktopPictureCacheFrameContext _frame(
  int frameId, {
  int soft = 1024 * 1024,
  int hard = 2 * 1024 * 1024,
}) {
  return DesktopPictureCacheFrameContext(
    frameId: frameId,
    softBudgetBytes: soft,
    hardBudgetBytes: hard,
  );
}

DesktopLinePictureCacheFamilyKey _family(
  DesktopLinePictureCache cache,
  Object identity,
) {
  return cache.buildFamilyKey(
    lineIdentity: identity,
    baseStyle: const TextStyle(fontSize: 28),
    rubyStyle: const TextStyle(fontSize: 14),
    themeSignature: 1,
    devicePixelRatio: 1,
  );
}

DesktopCachedLinePicture _picture(Color color) {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 32, 32), Paint()..color = color);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = picture.toImageSync(32, 32);
  picture.dispose();
  return DesktopCachedLinePicture(
    image: image,
    padding: 1,
    estimatedBytes: 32 * 32 * 4,
  );
}

DesktopRenderVisualLine _visualLine(String text) {
  return DesktopRenderVisualLine(
    tokens: <DesktopRenderToken>[
      DesktopRenderToken(
        type: DesktopRenderTokenType.text,
        text: text,
        rubyText: null,
        baseWidth: text.length * 12,
        rubyWidth: 0,
        height: 28,
        ascent: 22,
        x: 0,
        leftOverhang: 0,
        rightOverhang: 0,
        charIndices: List<int>.generate(text.length, (int index) => index),
        charOffsets: <double>[
          for (int index = 0; index <= text.length; index += 1) index * 12.0,
        ],
      ),
    ],
    height: 28,
    width: text.length * 12,
    visualRight: text.length * 12,
  );
}

DesktopRenderGenerationKey _generation() {
  return const DesktopRenderGenerationKey(
    contentIdentity: 'content',
    renderIdentity: 'render',
    viewportWidth: 320,
    viewportHeight: 180,
    devicePixelRatio: 1,
    themeSignature: 1,
  );
}

class _CollidingIdentity {
  const _CollidingIdentity(this.value);

  final int value;

  @override
  bool operator ==(Object other) {
    return other is _CollidingIdentity && other.value == value;
  }

  @override
  int get hashCode => 1;
}
