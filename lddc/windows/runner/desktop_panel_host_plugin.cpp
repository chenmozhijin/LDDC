#include "desktop_panel_host_plugin.h"

#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>

#include "embedded_panel_native_host.h"

namespace {

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
  if (const auto* number = std::get_if<double>(value)) {
    return static_cast<int64_t>(*number);
  }
  return std::nullopt;
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

std::optional<DesktopPanelHostWindowKey> GetPanelKey(
    const flutter::EncodableMap& map) {
  const std::optional<int64_t> instance_id = GetInt64(map, "instanceId");
  const std::optional<int64_t> panel_id = GetInt64(map, "panelId");
  const std::optional<int64_t> owner_token = GetInt64(map, "ownerToken");
  if (!instance_id.has_value() || !panel_id.has_value() ||
      !owner_token.has_value()) {
    return std::nullopt;
  }
  return DesktopPanelHostWindowKey{
      static_cast<int>(*instance_id), static_cast<int>(*panel_id),
      *owner_token};
}

int GetWindowDpiSafe(HWND window_handle) {
  if (!::IsWindow(window_handle)) {
    return 96;
  }
  const UINT dpi = ::GetDpiForWindow(window_handle);
  return dpi == 0 ? 96 : static_cast<int>(dpi);
}

std::optional<SIZE> GetHostClientSize(HWND host_window_handle) {
  if (!::IsWindow(host_window_handle)) {
    return std::nullopt;
  }
  RECT rect = {0};
  if (!::GetClientRect(host_window_handle, &rect)) {
    return std::nullopt;
  }
  return SIZE{rect.right - rect.left, rect.bottom - rect.top};
}

flutter::EncodableValue BuildSurfaceState(
    DesktopPanelHostWindowState& state) {
  const std::optional<SIZE> client_size =
      GetHostClientSize(state.host_window_handle);
  if (client_size.has_value()) {
    state.client_width_px = std::max(client_size->cx, 0L);
    state.client_height_px = std::max(client_size->cy, 0L);
  } else {
    state.client_width_px = 0;
    state.client_height_px = 0;
  }
  state.dpi = GetWindowDpiSafe(state.host_window_handle);
  state.visible = ::IsWindow(state.root_window_handle) &&
                  ::IsWindowVisible(state.root_window_handle) != FALSE;
  const bool attached = ::IsWindow(state.host_window_handle) &&
                        ::IsWindow(state.root_window_handle) &&
                        ::GetParent(state.root_window_handle) ==
                            state.host_window_handle;
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("surfaceRevision"),
       flutter::EncodableValue(state.surface_revision)},
      {flutter::EncodableValue("attached"),
       flutter::EncodableValue(attached)},
      {flutter::EncodableValue("visible"),
       flutter::EncodableValue(state.visible)},
      {flutter::EncodableValue("clientWidthPx"),
       flutter::EncodableValue(
           static_cast<double>(state.client_width_px))},
      {flutter::EncodableValue("clientHeightPx"),
       flutter::EncodableValue(
           static_cast<double>(state.client_height_px))},
      {flutter::EncodableValue("dpi"), flutter::EncodableValue(state.dpi)},
  });
}

void DestroyRegistryEntry(
    DesktopPanelHostWindowRegistry::iterator entry,
    DesktopPanelHostWindowRegistry& registry) {
  EmbeddedPanelNativeHost::Instance().DestroyPanel(entry->first);
  registry.erase(entry);
}

void PruneInvalidPanels() {
  DesktopPanelHostWindowRegistry& registry = DesktopPanelHostRegistry();
  for (auto it = registry.begin(); it != registry.end();) {
    if (!::IsWindow(it->second.host_window_handle) ||
        !::IsWindow(it->second.root_window_handle)) {
      const auto stale = it++;
      DestroyRegistryEntry(stale, registry);
      continue;
    }
    ++it;
  }
}

DesktopPanelHostWindowState* FindPanelState(
    const DesktopPanelHostWindowKey& key) {
  PruneInvalidPanels();
  DesktopPanelHostWindowRegistry& registry = DesktopPanelHostRegistry();
  const auto it = registry.find(key);
  return it == registry.end() ? nullptr : &it->second;
}

}  // namespace

void DesktopPanelHostPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<DesktopPanelHostPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

DesktopPanelHostPlugin::DesktopPanelHostPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar_->messenger(), "lddc/windows_desktop_panel_host",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleMethodCall(call, std::move(result)); });
}

DesktopPanelHostPlugin::~DesktopPanelHostPlugin() {
  DesktopPanelHostWindowRegistry& registry = DesktopPanelHostRegistry();
  while (!registry.empty()) {
    DestroyRegistryEntry(registry.begin(), registry);
  }
  channel_ = nullptr;
}

void DesktopPanelHostPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (arguments == nullptr) {
    result->Error("invalid_arguments", "panel arguments must be a map");
    return;
  }
  const std::string& method = method_call.method_name();
  if (method == "createPanel") {
    CreatePanel(*arguments, std::move(result));
    return;
  }
  if (method == "updatePanelSurface") {
    UpdatePanelSurface(*arguments, std::move(result));
    return;
  }
  if (method == "setPanelVisibility") {
    SetPanelVisibility(*arguments, std::move(result));
    return;
  }
  if (method == "destroyPanel") {
    DestroyPanel(*arguments, std::move(result));
    return;
  }
  result->NotImplemented();
}

void DesktopPanelHostPlugin::CreatePanel(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::optional<DesktopPanelHostWindowKey> key = GetPanelKey(arguments);
  const std::optional<int64_t> host_window_id =
      GetInt64(arguments, "hostWindowId");
  const std::optional<int64_t> generation =
      GetInt64(arguments, "generation");
  const std::string channel_name = GetString(arguments, "channelName");
  if (!key.has_value() || !host_window_id.has_value() ||
      !generation.has_value() || channel_name.empty()) {
    result->Error("invalid_arguments", "panel create payload is incomplete");
    return;
  }

  DesktopPanelHostWindowRegistry& registry = DesktopPanelHostRegistry();
  const auto existing = registry.find(*key);
  if (existing != registry.end()) {
    DestroyRegistryEntry(existing, registry);
  }

  EmbeddedPanelNativeCreateRequest request;
  request.key = *key;
  request.host_window_handle = reinterpret_cast<HWND>(
      static_cast<intptr_t>(*host_window_id));
  request.channel_name = channel_name;
  request.generation = static_cast<int>(*generation);
  EmbeddedPanelNativeCreateResult native_result;
  std::string error_message;
  const EmbeddedPanelNativeCreateStatus status =
      EmbeddedPanelNativeHost::Instance().CreatePanel(
          request, &native_result, &error_message);
  if (status == EmbeddedPanelNativeCreateStatus::kSurfaceUnavailable) {
    result->Error("surface_unready", error_message);
    return;
  }
  if (status != EmbeddedPanelNativeCreateStatus::kSuccess) {
    result->Error("create_failed", error_message);
    return;
  }

  const std::optional<SIZE> client_size =
      GetHostClientSize(request.host_window_handle);
  if (!client_size.has_value() || client_size->cx <= 0 ||
      client_size->cy <= 0) {
    EmbeddedPanelNativeHost::Instance().DestroyPanel(*key);
    result->Error("surface_unready", "host client surface is not ready");
    return;
  }
  DesktopPanelHostWindowState state;
  state.host_window_handle = request.host_window_handle;
  state.root_window_handle = native_result.root_window_handle;
  state.view_window_handle = native_result.view_window_handle;
  state.surface_revision = 1;
  state.client_width_px = client_size->cx;
  state.client_height_px = client_size->cy;
  state.dpi = GetWindowDpiSafe(request.host_window_handle);
  state.visible = false;
  registry[*key] = state;
  result->Success(BuildSurfaceState(registry[*key]));
}

void DesktopPanelHostPlugin::UpdatePanelSurface(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::optional<DesktopPanelHostWindowKey> key = GetPanelKey(arguments);
  if (!key.has_value()) {
    result->Error("invalid_arguments", "panel key is missing");
    return;
  }
  DesktopPanelHostWindowState* state = FindPanelState(*key);
  if (state == nullptr) {
    result->Error("panel_not_created", "panel has not been created");
    return;
  }
  const std::optional<SIZE> client_size =
      GetHostClientSize(state->host_window_handle);
  if (!client_size.has_value()) {
    result->Error("host_invalid", "panel host window is invalid");
    return;
  }
  const int width = std::max(client_size->cx, 0L);
  const int height = std::max(client_size->cy, 0L);
  const int dpi = GetWindowDpiSafe(state->host_window_handle);
  if (width != state->client_width_px || height != state->client_height_px ||
      dpi != state->dpi) {
    state->surface_revision += 1;
    state->client_width_px = width;
    state->client_height_px = height;
    state->dpi = dpi;
  }
  if (width <= 0 || height <= 0) {
    EmbeddedPanelNativeHost::Instance().SetPanelVisibility(*key, false);
    state->visible = false;
    result->Success(BuildSurfaceState(*state));
    return;
  }
  if (!EmbeddedPanelNativeHost::Instance().ResizePanel(*key, width, height)) {
    result->Error("resize_failed", "failed to resize embedded panel root");
    return;
  }
  result->Success(BuildSurfaceState(*state));
}

void DesktopPanelHostPlugin::SetPanelVisibility(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::optional<DesktopPanelHostWindowKey> key = GetPanelKey(arguments);
  const std::optional<bool> visible = GetBool(arguments, "visible");
  if (!key.has_value() || !visible.has_value()) {
    result->Error("invalid_arguments", "panel visibility payload is invalid");
    return;
  }
  DesktopPanelHostWindowState* state = FindPanelState(*key);
  if (state == nullptr) {
    result->Error("panel_not_created", "panel has not been created");
    return;
  }
  if (*visible &&
      (state->client_width_px <= 0 || state->client_height_px <= 0)) {
    result->Error("surface_unready", "panel surface is not ready");
    return;
  }
  if (!EmbeddedPanelNativeHost::Instance().SetPanelVisibility(*key,
                                                               *visible)) {
    result->Error("visibility_failed", "failed to change panel visibility");
    return;
  }
  state->visible = *visible;
  result->Success(flutter::EncodableValue(true));
}

void DesktopPanelHostPlugin::DestroyPanel(
    const flutter::EncodableMap& arguments,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::optional<DesktopPanelHostWindowKey> key = GetPanelKey(arguments);
  if (!key.has_value()) {
    result->Error("invalid_arguments", "panel key is missing");
    return;
  }
  DesktopPanelHostWindowRegistry& registry = DesktopPanelHostRegistry();
  const auto it = registry.find(*key);
  if (it != registry.end()) {
    DestroyRegistryEntry(it, registry);
  } else {
    EmbeddedPanelNativeHost::Instance().DestroyPanel(*key);
  }
  result->Success(flutter::EncodableValue(true));
}
