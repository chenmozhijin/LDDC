import 'dart:ffi';
import 'dart:io';

import 'package:window_manager/window_manager.dart';
import 'package:win32/win32.dart';

import 'desktop_main_window_raise_result.dart';

Future<DesktopMainWindowRaiseResult> raiseDesktopMainWindowToFront() async {
  if (!Platform.isWindows) {
    return const DesktopMainWindowRaiseResult.unsupported();
  }
  final int hwndAddress = await windowManager.getId();
  if (hwndAddress == 0) {
    return const DesktopMainWindowRaiseResult.invalidHandle(hwnd: 0);
  }
  // win32 6.x 将 HWND 从裸 int 升级为强类型，避免把普通数字误传给系统 API。
  // 日志仍记录原始地址，便于排查窗口句柄来源；后续所有调用只使用强类型句柄。
  final HWND hwnd = HWND(Pointer.fromAddress(hwndAddress));
  final bool isWindow = IsWindow(hwnd);
  if (!isWindow) {
    return DesktopMainWindowRaiseResult.invalidHandle(hwnd: hwndAddress);
  }
  // ShowWindow 的返回值表示“调用前窗口是否可见”，不是本次调用是否成功。
  // 隐藏窗口第一次恢复时返回 false 属于正常情况，因此执行后读取真实可见状态。
  ShowWindow(hwnd, SW_RESTORE);
  final bool windowVisible = IsWindowVisible(hwnd);
  final bool setTopmost = SetWindowPos(
    hwnd,
    HWND_TOPMOST,
    0,
    0,
    0,
    0,
    SWP_NOMOVE | SWP_NOSIZE,
  ).value;
  final bool clearTopmost = SetWindowPos(
    hwnd,
    HWND_NOTOPMOST,
    0,
    0,
    0,
    0,
    SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW,
  ).value;
  final bool bringToTop = BringWindowToTop(hwnd).value;
  final bool setForeground = SetForegroundWindow(hwnd);
  return DesktopMainWindowRaiseResult(
    supported: true,
    hwnd: hwndAddress,
    isWindow: isWindow,
    windowVisible: windowVisible,
    setTopmost: setTopmost,
    clearTopmost: clearTopmost,
    bringToTop: bringToTop,
    setForeground: setForeground,
  );
}
