import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';
import 'support/integration_viewport.dart';

void main() {
  ensureIntegrationBinding();

  testWidgets('集成测试失败截图能力会生成有效 PNG', (WidgetTester tester) async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'screenshot_capability',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'screenshot_capability',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });

    final GlobalKey screenshotKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: const ColoredBox(color: Colors.green),
      ),
    );
    await tester.pump();
    final IntegrationViewportSnapshot viewport =
        await captureIntegrationViewport(tester);
    debugPrint(
      'integration[screenshot_capability] viewport ${viewport.summary}',
    );
    reporter.recordContext('viewport', viewport.toJson());

    final String path = await reporter.runStep(
      'capture_png_on_real_device',
      () => captureIntegrationFailureScreenshot(
        tester: tester,
        screenshotBoundaryKey: screenshotKey,
        runtimeConfig: runtime,
      ),
    );
    final File screenshot = File(path);
    final Uint8List bytes = await screenshot.readAsBytes();

    expect(screenshot.existsSync(), isTrue);
    expect(screenshot.parent.path, contains('screenshots'));
    expect(bytes.length, greaterThan(8));
    expect(bytes.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    try {
      final ui.Size expectedSize = Platform.isAndroid || Platform.isIOS
          ? viewport.physicalSize
          : viewport.logicalSize;
      expect(image.width, expectedSize.width.round());
      expect(image.height, expectedSize.height.round());
      final ByteData? rgba = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(rgba, isNotNull);
      final Uint8List pixels = rgba!.buffer.asUint8List(
        rgba.offsetInBytes,
        rgba.lengthInBytes,
      );
      bool hasVisiblePixel = false;
      for (int index = 3; index < pixels.length; index += 4) {
        if (pixels[index] != 0) {
          hasVisiblePixel = true;
          break;
        }
      }
      expect(hasVisiblePixel, isTrue, reason: '截图不能是全透明画面');
    } finally {
      image.dispose();
      codec.dispose();
    }
    await reporter.writeSummary(
      extra: <String, Object?>{
        'verifiedScreenshot': screenshot.path,
        'syntheticContent': true,
      },
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
