/// Windows 主窗口前台提升的逐步结果。
///
/// 系统可能因为前台窗口策略拒绝其中某一步，因此保留每个 Win32 调用的结果用于
/// 日志诊断。非 Windows 平台使用 [DesktopMainWindowRaiseResult.unsupported]，不会
/// 伪造成功状态。
final class DesktopMainWindowRaiseResult {
  const DesktopMainWindowRaiseResult({
    required this.supported,
    required this.hwnd,
    required this.isWindow,
    required this.windowVisible,
    required this.setTopmost,
    required this.clearTopmost,
    required this.bringToTop,
    required this.setForeground,
  });

  const DesktopMainWindowRaiseResult.unsupported()
    : supported = false,
      hwnd = null,
      isWindow = null,
      windowVisible = null,
      setTopmost = null,
      clearTopmost = null,
      bringToTop = null,
      setForeground = null;

  const DesktopMainWindowRaiseResult.invalidHandle({required this.hwnd})
    : supported = true,
      isWindow = false,
      windowVisible = null,
      setTopmost = null,
      clearTopmost = null,
      bringToTop = null,
      setForeground = null;

  final bool supported;
  final int? hwnd;
  final bool? isWindow;
  final bool? windowVisible;
  final bool? setTopmost;
  final bool? clearTopmost;
  final bool? bringToTop;
  final bool? setForeground;

  bool get raised =>
      supported &&
      (isWindow ?? false) &&
      (windowVisible ?? false) &&
      (setTopmost ?? false) &&
      (clearTopmost ?? false) &&
      (bringToTop ?? false) &&
      (setForeground ?? false);

  Map<String, Object?> toLogFields() {
    return <String, Object?>{
      'supported': supported,
      'hwnd': hwnd,
      'isWindow': isWindow,
      'windowVisible': windowVisible,
      'setTopmost': setTopmost,
      'clearTopmost': clearTopmost,
      'bringToTop': bringToTop,
      'setForeground': setForeground,
      'raised': raised,
    };
  }
}
