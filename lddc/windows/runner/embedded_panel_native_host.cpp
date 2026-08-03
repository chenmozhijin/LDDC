#include "embedded_panel_native_host.h"

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include "runner_plugin_registrant.h"
#include "utils.h"
#include "win32_window.h"

namespace {

std::string EscapeJsonString(const std::string& value) {
  std::ostringstream buffer;
  for (char ch : value) {
    switch (ch) {
      case '\\':
        buffer << "\\\\";
        break;
      case '"':
        buffer << "\\\"";
        break;
      case '\n':
        buffer << "\\n";
        break;
      case '\r':
        buffer << "\\r";
        break;
      case '\t':
        buffer << "\\t";
        break;
      default:
        buffer << ch;
        break;
    }
  }
  return buffer.str();
}

std::string BuildEmbeddedPanelLaunchPayloadJson(
    int instance_id,
    int panel_id,
    HWND host_window_handle,
    const std::string& channel_name,
    int generation) {
  std::ostringstream buffer;
  buffer << "{"
         << "\"instanceId\":" << instance_id << ","
         << "\"panelId\":" << panel_id << ","
         << "\"hostWindowId\":"
         << static_cast<int64_t>(reinterpret_cast<intptr_t>(host_window_handle))
         << ","
         << "\"channelName\":\"" << EscapeJsonString(channel_name) << "\","
         << "\"generation\":" << generation << "}";
  return buffer.str();
}

std::optional<RECT> GetClientRectSafe(HWND window_handle) {
  if (!::IsWindow(window_handle)) {
    return std::nullopt;
  }
  RECT rect = {0};
  if (!::GetClientRect(window_handle, &rect)) {
    return std::nullopt;
  }
  return rect;
}

std::wstring ResolveFlutterDataPath() {
  const std::wstring executable_directory = GetExecutableDirectory();
  return executable_directory.empty() ? L"data"
                                      : executable_directory + L"\\data";
}

bool SetWindowLongPtrChecked(HWND window_handle,
                             int index,
                             LONG_PTR value) {
  ::SetLastError(ERROR_SUCCESS);
  const LONG_PTR previous = ::SetWindowLongPtrW(window_handle, index, value);
  return previous != 0 || ::GetLastError() == ERROR_SUCCESS;
}

void SetFailureMessage(std::string* error_message,
                       const std::string& operation) {
  if (error_message == nullptr) {
    return;
  }
  std::ostringstream buffer;
  buffer << operation << " failed win32=" << ::GetLastError();
  *error_message = buffer.str();
}

void ReloadSystemFontsIfEngineAlive(
    const std::unique_ptr<flutter::FlutterViewController>& controller) {
  if (controller && controller->engine()) {
    controller->engine()->ReloadSystemFonts();
  }
}

}  // namespace

class EmbeddedPanelNativeHost::EmbeddedPanelWindow : public Win32Window {
 public:
  EmbeddedPanelWindow(const EmbeddedPanelNativeCreateRequest& request,
                      int width,
                      int height)
      : key_(request.key),
        host_window_handle_(request.host_window_handle),
        channel_name_(request.channel_name),
        generation_(request.generation),
        initial_width_(width),
        initial_height_(height) {}

  ~EmbeddedPanelWindow() override = default;

  HWND view_window_handle() const {
    if (flutter_controller_ == nullptr ||
        flutter_controller_->view() == nullptr) {
      return nullptr;
    }
    return flutter_controller_->view()->GetNativeWindow();
  }

  HWND surface_window_handle() { return GetHandle(); }

  bool AttachToHost(int width, int height, std::string* error_message) {
    const HWND root = GetHandle();
    const HWND view = view_window_handle();
    if (!::IsWindow(root) || !::IsWindow(view) ||
        !::IsWindow(host_window_handle_)) {
      if (error_message != nullptr) {
        *error_message = "embedded root, Flutter view, or host HWND is invalid";
      }
      return false;
    }

    // Flutter view 始终由本进程 root 持有，跨进程嵌入只移动 root。这样销毁
    // 顺序、输入消息和 Flutter embedder 管理的 view 样式都只有一个所有者。
    ::SetLastError(ERROR_SUCCESS);
    const HWND previous_parent = ::SetParent(root, host_window_handle_);
    if (previous_parent == nullptr && ::GetLastError() != ERROR_SUCCESS) {
      SetFailureMessage(error_message, "SetParent(root host)");
      return false;
    }

    if (!SetWindowLongPtrChecked(
            root, GWL_STYLE,
            WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS)) {
      SetFailureMessage(error_message, "SetWindowLongPtrW(root child style)");
      return false;
    }

    ::SetLastError(ERROR_SUCCESS);
    const LONG_PTR ex_style = ::GetWindowLongPtrW(root, GWL_EXSTYLE);
    if (ex_style == 0 && ::GetLastError() != ERROR_SUCCESS) {
      SetFailureMessage(error_message, "GetWindowLongPtrW(root ex style)");
      return false;
    }
    const LONG_PTR target_ex_style =
        ex_style & ~(WS_EX_APPWINDOW | WS_EX_LAYERED | WS_EX_TRANSPARENT);
    if (target_ex_style != ex_style &&
        !SetWindowLongPtrChecked(root, GWL_EXSTYLE, target_ex_style)) {
      SetFailureMessage(error_message, "SetWindowLongPtrW(root ex style)");
      return false;
    }

    if (!::SetWindowPos(root, nullptr, 0, 0, width, height,
                        SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED)) {
      SetFailureMessage(error_message, "SetWindowPos(root initial size)");
      return false;
    }

    if (::GetParent(root) != host_window_handle_ || ::GetParent(view) != root) {
      if (error_message != nullptr) {
        *error_message = "embedded root/view parent chain mismatch";
      }
      return false;
    }
    return true;
  }

 protected:
  bool OnCreate() override {
    flutter::DartProject project(ResolveFlutterDataPath());
    project.set_dart_entrypoint("panelEmbeddedMain");
    project.set_dart_entrypoint_arguments(
        std::vector<std::string>{
            std::string("embedded_panel"),
            BuildEmbeddedPanelLaunchPayloadJson(
                key_.instance_id, key_.panel_id, host_window_handle_,
                channel_name_, generation_)});

    flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
        initial_width_, initial_height_, project);
    if (!flutter_controller_ || !flutter_controller_->engine() ||
        !flutter_controller_->view()) {
      return false;
    }
    RegisterEmbeddedPanelPlugins(flutter_controller_->engine());
    SetChildContent(flutter_controller_->view()->GetNativeWindow());
    return true;
  }

  void OnDestroy() override { flutter_controller_ = nullptr; }

  DWORD GetWindowStyle() const override {
    return WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  }

  DWORD GetWindowExStyle() const override { return 0; }

  HWND GetParentWindow() const override { return nullptr; }

  bool UseMonitorScaleFactorForInitialBounds() const override { return false; }

  LRESULT MessageHandler(HWND hwnd,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override {
    if (flutter_controller_) {
      std::optional<LRESULT> result =
          flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                        lparam);
      if (result.has_value()) {
        return result.value();
      }
    }
    if (message == WM_FONTCHANGE) {
      ReloadSystemFontsIfEngineAlive(flutter_controller_);
    }
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

 private:
  DesktopPanelHostWindowKey key_;
  HWND host_window_handle_ = nullptr;
  std::string channel_name_;
  int generation_ = 0;
  int initial_width_ = 1;
  int initial_height_ = 1;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

EmbeddedPanelNativeHost& EmbeddedPanelNativeHost::Instance() {
  static EmbeddedPanelNativeHost instance;
  return instance;
}

EmbeddedPanelNativeHost::EmbeddedPanelNativeHost() = default;
EmbeddedPanelNativeHost::~EmbeddedPanelNativeHost() = default;

EmbeddedPanelNativeCreateStatus EmbeddedPanelNativeHost::CreatePanel(
    const EmbeddedPanelNativeCreateRequest& request,
    EmbeddedPanelNativeCreateResult* result,
    std::string* error_message) {
  DestroyPanel(request.key);
  if (!::IsWindow(request.host_window_handle)) {
    if (error_message != nullptr) {
      *error_message = "host window handle is not valid";
    }
    return EmbeddedPanelNativeCreateStatus::kFailure;
  }
  const std::optional<RECT> host_rect =
      GetClientRectSafe(request.host_window_handle);
  if (!host_rect.has_value()) {
    if (error_message != nullptr) {
      *error_message = "failed to read host client rect";
    }
    return EmbeddedPanelNativeCreateStatus::kFailure;
  }
  const int width = host_rect->right - host_rect->left;
  const int height = host_rect->bottom - host_rect->top;
  if (width <= 0 || height <= 0) {
    if (error_message != nullptr) {
      *error_message = "host client surface is not ready";
    }
    return EmbeddedPanelNativeCreateStatus::kSurfaceUnavailable;
  }

  auto panel_window =
      std::make_unique<EmbeddedPanelWindow>(request, width, height);
  if (!panel_window->Create(L"", Win32Window::Point(0, 0),
                            Win32Window::Size(width, height))) {
    if (error_message != nullptr) {
      *error_message = "failed to create embedded panel window";
    }
    return EmbeddedPanelNativeCreateStatus::kFailure;
  }
  const HWND root = panel_window->surface_window_handle();
  const HWND view = panel_window->view_window_handle();
  std::string attach_error;
  if (!::IsWindow(root) || !::IsWindow(view) ||
      !panel_window->AttachToHost(width, height, &attach_error)) {
    if (error_message != nullptr) {
      *error_message = attach_error.empty()
                           ? "failed to prepare embedded panel"
                           : attach_error;
    }
    panel_window->Destroy();
    return EmbeddedPanelNativeCreateStatus::kFailure;
  }
  ::ShowWindow(root, SW_HIDE);
  if (result != nullptr) {
    result->root_window_handle = root;
    result->view_window_handle = view;
  }
  windows_[request.key] = std::move(panel_window);
  return EmbeddedPanelNativeCreateStatus::kSuccess;
}

bool EmbeddedPanelNativeHost::ResizePanel(
    const DesktopPanelHostWindowKey& key,
    int width,
    int height) {
  const auto it = windows_.find(key);
  if (it == windows_.end() || !it->second || width <= 0 || height <= 0) {
    return false;
  }
  const HWND surface = it->second->surface_window_handle();
  return ::IsWindow(surface) &&
         ::SetWindowPos(surface, nullptr, 0, 0, width, height,
                        SWP_NOZORDER | SWP_NOACTIVATE) != FALSE;
}

bool EmbeddedPanelNativeHost::SetPanelVisibility(
    const DesktopPanelHostWindowKey& key,
    bool visible) {
  const auto it = windows_.find(key);
  if (it == windows_.end() || !it->second) {
    return false;
  }
  const HWND surface = it->second->surface_window_handle();
  if (!::IsWindow(surface)) {
    return false;
  }
  ::ShowWindow(surface, visible ? SW_SHOWNOACTIVATE : SW_HIDE);
  return (::IsWindowVisible(surface) != FALSE) == visible;
}

void EmbeddedPanelNativeHost::DestroyPanel(
    const DesktopPanelHostWindowKey& key) {
  const auto it = windows_.find(key);
  if (it == windows_.end()) {
    return;
  }
  if (it->second) {
    it->second->Destroy();
  }
  windows_.erase(it);
}
