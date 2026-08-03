import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

const ui.Size kPreferredDesktopContentSize = ui.Size(1280, 720);

class IntegrationViewportSnapshot {
  const IntegrationViewportSnapshot({
    required this.logicalSize,
    required this.physicalSize,
    required this.devicePixelRatio,
    required this.padding,
    required this.viewPadding,
    required this.viewInsets,
    this.windowBounds,
    this.displayBounds,
    this.displayVisibleBounds,
    this.displayScaleFactor,
  });

  final ui.Size logicalSize;
  final ui.Size physicalSize;
  final double devicePixelRatio;
  final Map<String, double> padding;
  final Map<String, double> viewPadding;
  final Map<String, double> viewInsets;
  final ui.Rect? windowBounds;
  final ui.Rect? displayBounds;
  final ui.Rect? displayVisibleBounds;
  final double? displayScaleFactor;

  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  ui.Size get expectedDesktopContentSize {
    final ui.Rect? nativeWindow = windowBounds;
    final ui.Rect? visible = displayVisibleBounds;
    if (nativeWindow == null || visible == null) {
      return kPreferredDesktopContentSize;
    }
    // window_manager 在不同桌面系统可能返回外框或客户区。用它与
    // Flutter 内容区的差值反推非客户区，使预期尺寸与原生窗口的
    // 实际语义一致，不用平台硬编码的标题栏高度。
    final double frameWidth = (nativeWindow.width - logicalSize.width)
        .clamp(0, double.infinity)
        .toDouble();
    final double frameHeight = (nativeWindow.height - logicalSize.height)
        .clamp(0, double.infinity)
        .toDouble();
    final double availableWidth = (visible.width - frameWidth)
        .clamp(1, double.infinity)
        .toDouble();
    final double availableHeight = (visible.height - frameHeight)
        .clamp(1, double.infinity)
        .toDouble();
    final double scale = <double>[
      1,
      availableWidth / kPreferredDesktopContentSize.width,
      availableHeight / kPreferredDesktopContentSize.height,
    ].reduce((double left, double right) => left < right ? left : right);
    return ui.Size(
      (kPreferredDesktopContentSize.width * scale).floorToDouble(),
      (kPreferredDesktopContentSize.height * scale).floorToDouble(),
    );
  }

  String get summary =>
      'logical=${logicalSize.width.toStringAsFixed(1)}x'
      '${logicalSize.height.toStringAsFixed(1)} '
      'physical=${physicalSize.width.toStringAsFixed(1)}x'
      '${physicalSize.height.toStringAsFixed(1)} '
      'dpr=${devicePixelRatio.toStringAsFixed(2)}';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'logicalSize': _sizeToJson(logicalSize),
      'physicalSize': _sizeToJson(physicalSize),
      'devicePixelRatio': devicePixelRatio,
      'padding': padding,
      'viewPadding': viewPadding,
      'viewInsets': viewInsets,
      'windowBounds': _rectToJson(windowBounds),
      'displayBounds': _rectToJson(displayBounds),
      'displayVisibleBounds': _rectToJson(displayVisibleBounds),
      'displayScaleFactor': displayScaleFactor,
      if (isDesktop)
        'desktopContract': <String, Object?>{
          'preferredContentSize': _sizeToJson(kPreferredDesktopContentSize),
          'expectedContentSize': _sizeToJson(expectedDesktopContentSize),
          'clamped': expectedDesktopContentSize != kPreferredDesktopContentSize,
        },
    };
  }
}

Future<IntegrationViewportSnapshot> captureIntegrationViewport(
  WidgetTester tester,
) async {
  final ui.FlutterView view = tester.view;
  final double dpr = view.devicePixelRatio;
  final ui.Size physicalSize = view.physicalSize;
  final ui.Size logicalSize = physicalSize / dpr;
  ui.Rect? windowBounds;
  ui.Rect? displayBounds;
  ui.Rect? displayVisibleBounds;
  double? displayScaleFactor;

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    windowBounds = await windowManager.getBounds();
    final List<Display> displays = await screenRetriever.getAllDisplays();
    Display? currentDisplay;
    for (final Display display in displays) {
      final ui.Offset visiblePosition =
          display.visiblePosition ?? ui.Offset.zero;
      final ui.Size visibleSize = display.visibleSize ?? display.size;
      if ((visiblePosition & visibleSize).contains(windowBounds.center)) {
        currentDisplay = display;
        break;
      }
    }
    currentDisplay ??= await screenRetriever.getPrimaryDisplay();
    final ui.Offset displayPosition =
        currentDisplay.visiblePosition ?? ui.Offset.zero;
    displayBounds = displayPosition & currentDisplay.size;
    displayVisibleBounds =
        displayPosition & (currentDisplay.visibleSize ?? currentDisplay.size);
    displayScaleFactor = currentDisplay.scaleFactor?.toDouble();
  }

  return IntegrationViewportSnapshot(
    logicalSize: logicalSize,
    physicalSize: physicalSize,
    devicePixelRatio: dpr,
    padding: _paddingToJson(view.padding, dpr),
    viewPadding: _paddingToJson(view.viewPadding, dpr),
    viewInsets: _paddingToJson(view.viewInsets, dpr),
    windowBounds: windowBounds,
    displayBounds: displayBounds,
    displayVisibleBounds: displayVisibleBounds,
    displayScaleFactor: displayScaleFactor,
  );
}

Map<String, double> _paddingToJson(ui.ViewPadding value, double dpr) {
  return <String, double>{
    'left': value.left / dpr,
    'top': value.top / dpr,
    'right': value.right / dpr,
    'bottom': value.bottom / dpr,
  };
}

Map<String, double> _sizeToJson(ui.Size value) {
  return <String, double>{'width': value.width, 'height': value.height};
}

Map<String, double>? _rectToJson(ui.Rect? value) {
  if (value == null) {
    return null;
  }
  return <String, double>{
    'left': value.left,
    'top': value.top,
    'width': value.width,
    'height': value.height,
  };
}
