import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/integration_viewport.dart';

void main() {
  test('工作区足够时保留 1280x720 内容区', () {
    const IntegrationViewportSnapshot snapshot = IntegrationViewportSnapshot(
      logicalSize: Size(1280, 720),
      physicalSize: Size(1920, 1080),
      devicePixelRatio: 1.5,
      padding: <String, double>{},
      viewPadding: <String, double>{},
      viewInsets: <String, double>{},
      windowBounds: Rect.fromLTWH(100, 100, 1296, 760),
      displayVisibleBounds: Rect.fromLTWH(0, 0, 1920, 1040),
    );

    expect(snapshot.expectedDesktopContentSize, const Size(1280, 720));
    expect(
      (snapshot.toJson()['desktopContract']!
          as Map<String, Object?>)['clamped'],
      isFalse,
    );
  });

  test('小工作区会连同非客户区等比缩小', () {
    const IntegrationViewportSnapshot snapshot = IntegrationViewportSnapshot(
      logicalSize: Size(960, 540),
      physicalSize: Size(960, 540),
      devicePixelRatio: 1,
      padding: <String, double>{},
      viewPadding: <String, double>{},
      viewInsets: <String, double>{},
      windowBounds: Rect.fromLTWH(0, 0, 976, 580),
      displayVisibleBounds: Rect.fromLTWH(0, 0, 976, 580),
    );

    expect(snapshot.expectedDesktopContentSize, const Size(960, 540));
    expect(
      snapshot.expectedDesktopContentSize.aspectRatio,
      closeTo(16 / 9, 0.001),
    );
  });
}
