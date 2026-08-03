import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/capability/capability.dart';

void main() {
  testWidgets('Web 能力观察不冒充五平台正式能力', (WidgetTester _) async {
    expect(kIsWeb, isTrue, reason: '该观察用例必须由真实 Chrome runtime 执行');

    final AppCapability capability = AppCapabilityResolver.resolveCurrent();
    expect(capability.multiWindow, isFalse);
    expect(capability.systemTray, isFalse);
    expect(capability.androidSafTreeAccess, isFalse);
    expect(capability.webFileSystemAccess, isFalse);
    expect(capability.webTaglibWasmReady, isFalse);
  }, tags: 'web-observation');
}
