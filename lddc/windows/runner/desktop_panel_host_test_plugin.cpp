#include "desktop_panel_host_test_plugin.h"

#include <dwmapi.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "desktop_panel_host_registry.h"
#include "embedded_panel_native_host.h"

namespace {

constexpr wchar_t kTestHostWindowClassName[] =
    L"LDDC_EMBEDDED_PANEL_TEST_HOST";
constexpr int kCheckerCellSize = 32;

const flutter::EncodableValue* FindValue(const flutter::EncodableMap& map,
                                         const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::optional<int64_t> GetInt64(const flutter::EncodableMap& map,
                                const char* key) {
  const flutter::EncodableValue* value = FindValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* number = std::get_if<int32_t>(value)) {
    return static_cast<int64_t>(*number);
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return *number;
  }
  return std::nullopt;
}

std::optional<int> GetInt(const flutter::EncodableMap& map, const char* key) {
  const std::optional<int64_t> value = GetInt64(map, key);
  if (!value.has_value()) {
    return std::nullopt;
  }
  return static_cast<int>(*value);
}

std::optional<bool> GetBool(const flutter::EncodableMap& map,
                            const char* key) {
  const flutter::EncodableValue* value = FindValue(map, key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (const auto* flag = std::get_if<bool>(value)) {
    return *flag;
  }
  return std::nullopt;
}

std::string GetString(const flutter::EncodableMap& map, const char* key) {
  const flutter::EncodableValue* value = FindValue(map, key);
  if (value == nullptr) {
    return std::string();
  }
  if (const auto* text = std::get_if<std::string>(value)) {
    return *text;
  }
  return std::string();
}

int64_t HwndValue(HWND window) {
  return static_cast<int64_t>(reinterpret_cast<intptr_t>(window));
}

HWND DecodeWindow(const flutter::EncodableMap& arguments,
                  const char* key) {
  const std::optional<int64_t> value = GetInt64(arguments, key);
  return value.has_value()
             ? reinterpret_cast<HWND>(static_cast<intptr_t>(*value))
             : nullptr;
}

flutter::EncodableMap EncodeRect(const RECT& rect) {
  return flutter::EncodableMap{
      {flutter::EncodableValue("left"), flutter::EncodableValue(rect.left)},
      {flutter::EncodableValue("top"), flutter::EncodableValue(rect.top)},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(rect.right - rect.left)},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(rect.bottom - rect.top)},
  };
}

RECT ReadClientRect(HWND window) {
  RECT rect = {0, 0, 0, 0};
  if (::IsWindow(window)) {
    ::GetClientRect(window, &rect);
  }
  return rect;
}

int ReadDpi(HWND window) {
  if (!::IsWindow(window)) {
    return 96;
  }
  const UINT dpi = ::GetDpiForWindow(window);
  return dpi == 0 ? 96 : static_cast<int>(dpi);
}

bool ResizeWindowClient(HWND window, int width, int height) {
  if (!::IsWindow(window) || width < 0 || height < 0) {
    return false;
  }
  const DWORD style = static_cast<DWORD>(::GetWindowLongPtrW(window, GWL_STYLE));
  const DWORD ex_style =
      static_cast<DWORD>(::GetWindowLongPtrW(window, GWL_EXSTYLE));
  RECT outer = {0, 0, width, height};
  using AdjustWindowRectExForDpi =
      BOOL(WINAPI*)(LPRECT, DWORD, BOOL, DWORD, UINT);
  const auto adjust_for_dpi = reinterpret_cast<AdjustWindowRectExForDpi>(
      ::GetProcAddress(::GetModuleHandleW(L"user32.dll"),
                       "AdjustWindowRectExForDpi"));
  const BOOL adjusted = adjust_for_dpi == nullptr
                            ? ::AdjustWindowRectEx(&outer, style, FALSE, ex_style)
                            : adjust_for_dpi(&outer, style, FALSE, ex_style,
                                             static_cast<UINT>(ReadDpi(window)));
  if (!adjusted) {
    return false;
  }
  const int outer_width =
      std::max(static_cast<int>(outer.right - outer.left), 1);
  const int outer_height =
      std::max(static_cast<int>(outer.bottom - outer.top), 1);
  return ::SetWindowPos(window, nullptr, 0, 0, outer_width, outer_height,
                        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE) != FALSE;
}

void RefreshWindow(HWND window) {
  if (!::IsWindow(window)) {
    return;
  }
  ::InvalidateRect(window, nullptr, FALSE);
  ::RedrawWindow(window, nullptr, nullptr,
                 RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW);
  ::DwmFlush();
}

void PruneInvalidPanels() {
  auto& registry = DesktopPanelHostRegistry();
  for (auto it = registry.begin(); it != registry.end();) {
    if (::IsWindow(it->second.host_window_handle) &&
        ::IsWindow(it->second.root_window_handle)) {
      ++it;
      continue;
    }
    const DesktopPanelHostWindowKey key = it->first;
    it = registry.erase(it);
    EmbeddedPanelNativeHost::Instance().DestroyPanel(key);
  }
}

struct PanelLookup {
  DesktopPanelHostWindowState* state = nullptr;
};

std::optional<PanelLookup> FindPanel(const flutter::EncodableMap& arguments) {
  const std::optional<int> instance_id = GetInt(arguments, "instanceId");
  const std::optional<int> panel_id = GetInt(arguments, "panelId");
  if (!instance_id.has_value() || !panel_id.has_value()) {
    return std::nullopt;
  }
  PruneInvalidPanels();
  auto& registry = DesktopPanelHostRegistry();
  for (auto& entry : registry) {
    if (entry.first.instance_id == *instance_id &&
        entry.first.panel_id == *panel_id) {
      return PanelLookup{&entry.second};
    }
  }
  return std::nullopt;
}

std::optional<std::vector<uint8_t>> CaptureClientPixels(HWND window,
                                                        int* width,
                                                        int* height) {
  if (!::IsWindow(window) || ::IsWindowVisible(window) == FALSE) {
    return std::nullopt;
  }
  RECT client = ReadClientRect(window);
  *width = client.right - client.left;
  *height = client.bottom - client.top;
  if (*width <= 0 || *height <= 0) {
    return std::nullopt;
  }
  POINT origin = {0, 0};
  if (!::ClientToScreen(window, &origin)) {
    return std::nullopt;
  }
  HDC screen_dc = ::GetDC(nullptr);
  HDC memory_dc = screen_dc == nullptr ? nullptr : ::CreateCompatibleDC(screen_dc);
  if (screen_dc == nullptr || memory_dc == nullptr) {
    if (memory_dc != nullptr) {
      ::DeleteDC(memory_dc);
    }
    if (screen_dc != nullptr) {
      ::ReleaseDC(nullptr, screen_dc);
    }
    return std::nullopt;
  }
  BITMAPINFO bitmap_info{};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = *width;
  bitmap_info.bmiHeader.biHeight = -*height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;
  void* bits = nullptr;
  HBITMAP bitmap = ::CreateDIBSection(memory_dc, &bitmap_info, DIB_RGB_COLORS,
                                      &bits, nullptr, 0);
  if (bitmap == nullptr || bits == nullptr) {
    if (bitmap != nullptr) {
      ::DeleteObject(bitmap);
    }
    ::DeleteDC(memory_dc);
    ::ReleaseDC(nullptr, screen_dc);
    return std::nullopt;
  }
  HGDIOBJ previous = ::SelectObject(memory_dc, bitmap);
  ::DwmFlush();
  const BOOL copied = ::BitBlt(memory_dc, 0, 0, *width, *height, screen_dc,
                               origin.x, origin.y, SRCCOPY | CAPTUREBLT);
  std::optional<std::vector<uint8_t>> pixels;
  if (copied) {
    const std::size_t byte_count = static_cast<std::size_t>(*width) *
                                   static_cast<std::size_t>(*height) * 4;
    pixels = std::vector<uint8_t>(byte_count);
    std::memcpy(pixels->data(), bits, byte_count);
  }
  ::SelectObject(memory_dc, previous);
  ::DeleteObject(bitmap);
  ::DeleteDC(memory_dc);
  ::ReleaseDC(nullptr, screen_dc);
  return pixels;
}

flutter::EncodableMap EncodeWindowState(HWND window) {
  const RECT client = ReadClientRect(window);
  return flutter::EncodableMap{
      {flutter::EncodableValue("windowId"),
       flutter::EncodableValue(HwndValue(window))},
      {flutter::EncodableValue("clientRect"),
       flutter::EncodableValue(EncodeRect(client))},
      {flutter::EncodableValue("visible"),
       flutter::EncodableValue(::IsWindowVisible(window) != FALSE)},
      {flutter::EncodableValue("minimized"),
       flutter::EncodableValue(::IsIconic(window) != FALSE)},
      {flutter::EncodableValue("dpi"), flutter::EncodableValue(ReadDpi(window))},
  };
}

}  // namespace

void DesktopPanelHostTestPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<DesktopPanelHostTestPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

DesktopPanelHostTestPlugin::DesktopPanelHostTestPlugin(
    flutter::PluginRegistrarWindows* registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "lddc/windows_desktop_panel_host_test",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

DesktopPanelHostTestPlugin::~DesktopPanelHostTestPlugin() {
  std::vector<HWND> windows;
  for (const auto& entry : TestHostWindows()) {
    windows.push_back(entry.second.handle);
  }
  TestHostWindows().clear();
  for (HWND window : windows) {
    if (::IsWindow(window)) {
      ::DestroyWindow(window);
    }
  }
}

std::unordered_map<int64_t, DesktopPanelHostTestPlugin::TestHostWindowState>&
DesktopPanelHostTestPlugin::TestHostWindows() {
  static std::unordered_map<int64_t, TestHostWindowState> windows;
  return windows;
}

LRESULT CALLBACK DesktopPanelHostTestPlugin::TestHostWindowProc(
    HWND window,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
  if (message == WM_ERASEBKGND) {
    return 1;
  }
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{};
    HDC dc = ::BeginPaint(window, &paint);
    RECT client = ReadClientRect(window);
    int phase = 0;
    const auto it = TestHostWindows().find(HwndValue(window));
    if (it != TestHostWindows().end()) {
      phase = it->second.checker_phase;
    }
    constexpr COLORREF palettes[][2] = {
        {RGB(24, 88, 176), RGB(244, 194, 48)},
        {RGB(38, 164, 92), RGB(224, 66, 104)},
        {RGB(116, 70, 190), RGB(42, 196, 198)},
    };
    const int palette_index = ((phase % 3) + 3) % 3;
    HBRUSH brushes[2] = {::CreateSolidBrush(palettes[palette_index][0]),
                         ::CreateSolidBrush(palettes[palette_index][1])};
    const int client_width = static_cast<int>(client.right);
    const int client_height = static_cast<int>(client.bottom);
    for (int y = 0; y < client_height; y += kCheckerCellSize) {
      for (int x = 0; x < client_width; x += kCheckerCellSize) {
        RECT cell = {
            x, y, std::min(x + kCheckerCellSize, client_width),
            std::min(y + kCheckerCellSize, client_height)};
        const int index = ((x / kCheckerCellSize) +
                           (y / kCheckerCellSize)) &
                          1;
        ::FillRect(dc, &cell, brushes[index]);
      }
    }
    ::DeleteObject(brushes[0]);
    ::DeleteObject(brushes[1]);
    ::EndPaint(window, &paint);
    return 0;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

void DesktopPanelHostTestPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  const flutter::EncodableMap empty;
  const flutter::EncodableMap& map = arguments == nullptr ? empty : *arguments;
  const std::string& method = method_call.method_name();
  if (method == "createTestHostWindow") {
    CreateTestHostWindow(map, std::move(result));
  } else if (method == "setTestHostClientSize") {
    SetTestHostClientSize(map, std::move(result));
  } else if (method == "setTestHostWindowState") {
    SetTestHostWindowState(map, std::move(result));
  } else if (method == "setTestHostCheckerPhase") {
    SetTestHostCheckerPhase(map, std::move(result));
  } else if (method == "destroyTestHostWindow") {
    DestroyTestHostWindow(map, std::move(result));
  } else if (method == "captureTestHostClient") {
    CaptureTestHostClient(map, std::move(result));
  } else if (method == "collectPanelState") {
    CollectPanelState(map, std::move(result));
  } else if (method == "collectPanelPointerTarget") {
    CollectPanelPointerTarget(map, std::move(result));
  } else if (method == "collectResourceCounts") {
    CollectResourceCounts(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void DesktopPanelHostTestPlugin::CreateTestHostWindow(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  static bool window_class_registered = false;
  if (!window_class_registered) {
    WNDCLASSW window_class{};
    window_class.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
    window_class.hInstance = ::GetModuleHandleW(nullptr);
    window_class.lpszClassName = kTestHostWindowClassName;
    window_class.lpfnWndProc = TestHostWindowProc;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    if (::RegisterClassW(&window_class) == 0 &&
        ::GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      result->Error("class_registration_failed",
                    "failed to register test host window class");
      return;
    }
    window_class_registered = true;
  }
  const int width = std::max(GetInt(arguments, "width").value_or(960), 0);
  const int height = std::max(GetInt(arguments, "height").value_or(320), 0);
  const int x = GetInt(arguments, "x").value_or(120);
  const int y = GetInt(arguments, "y").value_or(120);
  const bool visible = GetBool(arguments, "visible").value_or(true);
  const DWORD style =
      WS_POPUP | WS_BORDER | WS_CLIPCHILDREN | WS_CLIPSIBLINGS;
  HWND window = ::CreateWindowExW(WS_EX_TOOLWINDOW, kTestHostWindowClassName,
                                  L"LDDC embedded panel E2E", style, x, y, 1,
                                  1, nullptr, nullptr,
                                  ::GetModuleHandleW(nullptr), nullptr);
  if (!::IsWindow(window) || !ResizeWindowClient(window, width, height)) {
    if (::IsWindow(window)) {
      ::DestroyWindow(window);
    }
    result->Error("create_failed", "failed to create test host window");
    return;
  }
  TestHostWindowState state;
  state.handle = window;
  state.checker_phase = GetInt(arguments, "phase").value_or(0);
  TestHostWindows()[HwndValue(window)] = state;
  if (visible) {
    ::SetWindowPos(window, HWND_TOPMOST, x, y, 0, 0,
                   SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  } else {
    ::ShowWindow(window, SW_HIDE);
  }
  RefreshWindow(window);
  result->Success(flutter::EncodableValue(EncodeWindowState(window)));
}

void DesktopPanelHostTestPlugin::SetTestHostClientSize(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND window = DecodeWindow(arguments, "hostWindowId");
  const std::optional<int> width = GetInt(arguments, "width");
  const std::optional<int> height = GetInt(arguments, "height");
  if (!::IsWindow(window) || !width.has_value() || !height.has_value() ||
      !ResizeWindowClient(window, *width, *height)) {
    result->Error("resize_failed", "failed to resize test host client");
    return;
  }
  RefreshWindow(window);
  result->Success(flutter::EncodableValue(EncodeWindowState(window)));
}

void DesktopPanelHostTestPlugin::SetTestHostWindowState(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND window = DecodeWindow(arguments, "hostWindowId");
  const std::string state = GetString(arguments, "state");
  if (!::IsWindow(window)) {
    result->Error("invalid_window", "test host window is invalid");
    return;
  }
  if (state == "show" || state == "restore") {
    ::ShowWindow(window, state == "restore" ? SW_RESTORE : SW_SHOWNOACTIVATE);
    ::SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  } else if (state == "hide") {
    ::ShowWindow(window, SW_HIDE);
  } else if (state == "minimize") {
    ::ShowWindow(window, SW_MINIMIZE);
  } else {
    result->Error("invalid_state", "unknown test host window state");
    return;
  }
  RefreshWindow(window);
  result->Success(flutter::EncodableValue(EncodeWindowState(window)));
}

void DesktopPanelHostTestPlugin::SetTestHostCheckerPhase(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND window = DecodeWindow(arguments, "hostWindowId");
  const std::optional<int> phase = GetInt(arguments, "phase");
  auto it = TestHostWindows().find(HwndValue(window));
  if (!phase.has_value() || it == TestHostWindows().end()) {
    result->Error("invalid_window", "test host window is not registered");
    return;
  }
  it->second.checker_phase = *phase;
  RefreshWindow(window);
  result->Success(flutter::EncodableValue(EncodeWindowState(window)));
}

void DesktopPanelHostTestPlugin::DestroyTestHostWindow(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND window = DecodeWindow(arguments, "hostWindowId");
  TestHostWindows().erase(HwndValue(window));
  if (::IsWindow(window)) {
    ::DestroyWindow(window);
  }
  PruneInvalidPanels();
  result->Success();
}

void DesktopPanelHostTestPlugin::CaptureTestHostClient(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  HWND window = DecodeWindow(arguments, "hostWindowId");
  int width = 0;
  int height = 0;
  const std::optional<std::vector<uint8_t>> pixels =
      CaptureClientPixels(window, &width, &height);
  if (!pixels.has_value()) {
    result->Error("capture_failed", "failed to capture test host client");
    return;
  }
  result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("width"), flutter::EncodableValue(width)},
      {flutter::EncodableValue("height"), flutter::EncodableValue(height)},
      {flutter::EncodableValue("bgra"),
       flutter::EncodableValue(*pixels)},
  }));
}

void DesktopPanelHostTestPlugin::CollectPanelState(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::optional<PanelLookup> panel = FindPanel(arguments);
  if (!panel.has_value() || panel->state == nullptr) {
    result->Error("panel_not_created", "embedded panel is not registered");
    return;
  }
  const DesktopPanelHostWindowState& state = *panel->state;
  const LONG_PTR root_style =
      ::GetWindowLongPtrW(state.root_window_handle, GWL_STYLE);
  const LONG_PTR root_ex_style =
      ::GetWindowLongPtrW(state.root_window_handle, GWL_EXSTYLE);
  const LONG_PTR view_style =
      ::GetWindowLongPtrW(state.view_window_handle, GWL_STYLE);
  const LONG_PTR view_ex_style =
      ::GetWindowLongPtrW(state.view_window_handle, GWL_EXSTYLE);
  result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("hostWindowId"),
       flutter::EncodableValue(HwndValue(state.host_window_handle))},
      {flutter::EncodableValue("rootWindowId"),
       flutter::EncodableValue(HwndValue(state.root_window_handle))},
      {flutter::EncodableValue("viewWindowId"),
       flutter::EncodableValue(HwndValue(state.view_window_handle))},
      {flutter::EncodableValue("rootParentId"),
       flutter::EncodableValue(HwndValue(::GetParent(state.root_window_handle)))},
      {flutter::EncodableValue("viewParentId"),
       flutter::EncodableValue(HwndValue(::GetParent(state.view_window_handle)))},
      {flutter::EncodableValue("rootStyle"),
       flutter::EncodableValue(static_cast<int64_t>(root_style))},
      {flutter::EncodableValue("rootExStyle"),
       flutter::EncodableValue(static_cast<int64_t>(root_ex_style))},
      {flutter::EncodableValue("viewStyle"),
       flutter::EncodableValue(static_cast<int64_t>(view_style))},
      {flutter::EncodableValue("viewExStyle"),
       flutter::EncodableValue(static_cast<int64_t>(view_ex_style))},
      {flutter::EncodableValue("rootVisible"),
       flutter::EncodableValue(
           ::IsWindowVisible(state.root_window_handle) != FALSE)},
      {flutter::EncodableValue("viewVisible"),
       flutter::EncodableValue(
           ::IsWindowVisible(state.view_window_handle) != FALSE)},
      {flutter::EncodableValue("rootClientRect"),
       flutter::EncodableValue(EncodeRect(ReadClientRect(state.root_window_handle)))},
      {flutter::EncodableValue("viewClientRect"),
       flutter::EncodableValue(EncodeRect(ReadClientRect(state.view_window_handle)))},
      {flutter::EncodableValue("hostClientRect"),
       flutter::EncodableValue(EncodeRect(ReadClientRect(state.host_window_handle)))},
      {flutter::EncodableValue("surfaceRevision"),
       flutter::EncodableValue(state.surface_revision)},
      {flutter::EncodableValue("dpi"), flutter::EncodableValue(state.dpi)},
      {flutter::EncodableValue("registryCount"),
       flutter::EncodableValue(
           static_cast<int64_t>(DesktopPanelHostRegistry().size()))},
  }));
}

void DesktopPanelHostTestPlugin::CollectPanelPointerTarget(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::optional<PanelLookup> panel = FindPanel(arguments);
  if (!panel.has_value() || panel->state == nullptr) {
    result->Error("panel_not_created", "embedded panel is not registered");
    return;
  }
  HWND view = panel->state->view_window_handle;
  RECT client = ReadClientRect(view);
  const int client_width = static_cast<int>(client.right);
  const int client_height = static_cast<int>(client.bottom);
  const int x = std::clamp(
      GetInt(arguments, "x").value_or(client_width / 3), 0,
      std::max(client_width - 1, 0));
  const int y = std::clamp(
      GetInt(arguments, "y").value_or(client_height / 3), 0,
      std::max(client_height - 1, 0));
  POINT screen_position = {x, y};
  if (!::ClientToScreen(view, &screen_position)) {
    result->Error("coordinate_conversion_failed",
                  "failed to convert panel client coordinates");
    return;
  }
  const HWND target = ::WindowFromPoint(screen_position);
  result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("screenX"),
       flutter::EncodableValue(screen_position.x)},
      {flutter::EncodableValue("screenY"),
       flutter::EncodableValue(screen_position.y)},
      {flutter::EncodableValue("viewWindowId"),
       flutter::EncodableValue(HwndValue(view))},
      {flutter::EncodableValue("targetWindowId"),
       flutter::EncodableValue(HwndValue(target))},
  }));
}

void DesktopPanelHostTestPlugin::CollectResourceCounts(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  PruneInvalidPanels();
  DWORD process_handles = 0;
  ::GetProcessHandleCount(::GetCurrentProcess(), &process_handles);
  result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("panelRegistryCount"),
       flutter::EncodableValue(
           static_cast<int64_t>(DesktopPanelHostRegistry().size()))},
      {flutter::EncodableValue("testHostWindowCount"),
       flutter::EncodableValue(static_cast<int64_t>(TestHostWindows().size()))},
      {flutter::EncodableValue("processHandleCount"),
       flutter::EncodableValue(static_cast<int64_t>(process_handles))},
      {flutter::EncodableValue("userObjectCount"),
       flutter::EncodableValue(static_cast<int64_t>(
           ::GetGuiResources(::GetCurrentProcess(), GR_USEROBJECTS)))},
      {flutter::EncodableValue("gdiObjectCount"),
       flutter::EncodableValue(static_cast<int64_t>(
           ::GetGuiResources(::GetCurrentProcess(), GR_GDIOBJECTS)))},
  }));
}
