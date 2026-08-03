import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_main_window_navigation.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_main_window_raise_result.dart';

void main() {
  test('关联库路由失败会返回 false 而不是泄漏异步异常', () async {
    final DesktopMainWindowNavigationController controller =
        DesktopMainWindowNavigationController(
          openAssociationManager: () async {
            throw StateError('route failed');
          },
        );

    expect(await controller.openAssociationManager(), isFalse);
  });

  test('窗口提升结果以执行后的可见状态判断成功', () {
    const DesktopMainWindowRaiseResult result = DesktopMainWindowRaiseResult(
      supported: true,
      hwnd: 1,
      isWindow: true,
      windowVisible: true,
      setTopmost: true,
      clearTopmost: true,
      bringToTop: true,
      setForeground: true,
    );

    expect(result.raised, isTrue);
    expect(result.toLogFields()['windowVisible'], isTrue);
    expect(const DesktopMainWindowRaiseResult.unsupported().raised, isFalse);
  });
}
