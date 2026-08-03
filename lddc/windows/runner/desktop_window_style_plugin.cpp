#include "desktop_window_style_plugin.h"

#include <windows.h>

namespace {

HWND ResolveRootWindow(flutter::PluginRegistrarWindows* registrar) {
  if (registrar == nullptr || registrar->GetView() == nullptr) {
    return nullptr;
  }
  HWND view = registrar->GetView()->GetNativeWindow();
  if (view == nullptr) {
    return nullptr;
  }
  return GetAncestor(view, GA_ROOT);
}

bool ApplyToolWindowStyle(HWND hwnd) {
  if (hwnd == nullptr) {
    return false;
  }
  const bool was_visible = IsWindowVisible(hwnd) != FALSE;
  if (was_visible) {
    // 任务栏枚举依赖窗口显示时的扩展样式。子窗口由 desktop_multi_window
    // 先显示、后注册插件，因此这里需要先隐藏再改类型，最后无激活显示回来，
    // 否则 Windows 可能继续保留旧的任务栏按钮。
    ShowWindow(hwnd, SW_HIDE);
  }
  SetLastError(ERROR_SUCCESS);
  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  if (ex_style == 0 && GetLastError() != ERROR_SUCCESS) {
    if (was_visible) {
      ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    }
    return false;
  }

  // 桌面歌词浮窗不是普通应用窗口，必须用 tool window 类型让系统
  // 从 Alt-Tab/任务栏枚举中排除；仅调用 ITaskbarList::DeleteTab 不够稳定。
  ex_style |= WS_EX_TOOLWINDOW;
  ex_style &= ~WS_EX_APPWINDOW;
  SetLastError(ERROR_SUCCESS);
  if (SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style) == 0 &&
      GetLastError() != ERROR_SUCCESS) {
    if (was_visible) {
      ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    }
    return false;
  }
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  if (was_visible) {
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);
  }
  return true;
}

bool CenterWindowInCurrentMonitor(HWND hwnd) {
  if (hwnd == nullptr || !IsWindow(hwnd)) {
    return false;
  }
  RECT window_rect{};
  if (!GetWindowRect(hwnd, &window_rect)) {
    return false;
  }
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  const HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr || !GetMonitorInfo(monitor, &monitor_info)) {
    return false;
  }
  const int width = window_rect.right - window_rect.left;
  const int height = window_rect.bottom - window_rect.top;
  const RECT& work = monitor_info.rcWork;
  const int x = work.left + ((work.right - work.left) - width) / 2;
  const int y = work.top + ((work.bottom - work.top) - height) / 2;
  return SetWindowPos(hwnd, nullptr, x, y, 0, 0,
                      SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE) != FALSE;
}

}  // namespace

void DesktopWindowStylePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<DesktopWindowStylePlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

DesktopWindowStylePlugin::DesktopWindowStylePlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar_->messenger(), "lddc/desktop_window_style",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

DesktopWindowStylePlugin::~DesktopWindowStylePlugin() {
  channel_ = nullptr;
}

void DesktopWindowStylePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "setToolWindow") {
    if (!ApplyToolWindowStyle(ResolveRootWindow(registrar_))) {
      result->Error("style_failed", "failed to apply tool window style");
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }
  if (call.method_name() == "centerWindow") {
    if (!CenterWindowInCurrentMonitor(ResolveRootWindow(registrar_))) {
      result->Error("center_failed", "failed to center child window");
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }
  result->NotImplemented();
}
