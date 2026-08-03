import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/capability/capability.dart';

void main() {
  test('Web 能力观察不冒充五平台正式能力', () {
    expect(kIsWeb, isTrue, reason: '该观察用例必须在浏览器设备上运行');

    final AppCapability capability = AppCapabilityResolver.resolveCurrent();
    expect(capability.multiWindow, isFalse);
    expect(capability.systemTray, isFalse);
    expect(capability.androidSafTreeAccess, isFalse);
    expect(capability.webFileSystemAccess, isFalse);
    expect(capability.webTaglibWasmReady, isFalse);
  });
}
