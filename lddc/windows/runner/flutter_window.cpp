#include "flutter_window.h"

#include <optional>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "runner_plugin_registrant.h"

namespace {

void ReloadSystemFontsIfEngineAlive(
    const std::unique_ptr<flutter::FlutterViewController>& controller) {
  // 销毁期仍可能收到 WM_FONTCHANGE；此时 controller 或 engine 已释放，
  // 只能把消息交回默认窗口过程，不能再解引用 Flutter engine。
  if (controller && controller->engine()) {
    controller->engine()->ReloadSystemFonts();
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool show_on_first_frame)
    : project_(project), show_on_first_frame_(show_on_first_frame) {}

FlutterWindow::~FlutterWindow() {
  // FlutterDesktopViewControllerDestroy 会同步销毁内部原生 view，并可能在删除
  // 过程中重新进入顶层窗口过程。unique_ptr 的默认析构在 delete 完成前仍保存旧
  // 指针，MessageHandler 因而会把嵌套消息转发给正在析构的 controller。
  // reset() 会先把成员置空再调用 deleter，使重入消息只走 Win32 默认处理路径。
  flutter_controller_.reset();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterMainWindowPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterDesktopMultiWindowChildPlugins(flutter_view_controller->engine());
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (show_on_first_frame_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      ReloadSystemFontsIfEngineAlive(flutter_controller_);
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
