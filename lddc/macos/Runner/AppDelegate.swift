import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 隐藏服务模式会把主窗口 orderOut，但仍需继续提供 loopback IPC。若把最后窗口
    // 状态交给 AppKit 自动结束，后台服务可能绕过 Dart 退出守卫直接退出，并留下
    // control.json。真正退出统一由退出守卫撤销 endpoint 后调用 windowManager.destroy。
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
