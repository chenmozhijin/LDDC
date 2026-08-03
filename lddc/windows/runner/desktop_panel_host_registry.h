#ifndef RUNNER_DESKTOP_PANEL_HOST_REGISTRY_H_
#define RUNNER_DESKTOP_PANEL_HOST_REGISTRY_H_

#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <unordered_map>

struct DesktopPanelHostWindowKey {
  int instance_id = 0;
  int panel_id = 0;
  int64_t owner_token = 0;

  bool operator==(const DesktopPanelHostWindowKey& other) const {
    return instance_id == other.instance_id && panel_id == other.panel_id &&
           owner_token == other.owner_token;
  }
};

struct DesktopPanelHostWindowKeyHash {
  std::size_t operator()(const DesktopPanelHostWindowKey& key) const {
    return (static_cast<std::size_t>(key.instance_id) << 32) ^
           (static_cast<std::size_t>(key.panel_id) << 16) ^
           static_cast<std::size_t>(key.owner_token);
  }
};

/// 单个 embedded Panel 的原生所有权状态。
///
/// 这里只保存生命周期、真实客户区和单调 surface revision。历史上的多组
/// generation、requested geometry 与 presentation 诊断不再进入生产 registry。
struct DesktopPanelHostWindowState {
  HWND host_window_handle = nullptr;
  HWND root_window_handle = nullptr;
  HWND view_window_handle = nullptr;
  int surface_revision = 0;
  int client_width_px = 0;
  int client_height_px = 0;
  int dpi = 96;
  bool visible = false;
};

using DesktopPanelHostWindowRegistry = std::unordered_map<
    DesktopPanelHostWindowKey,
    DesktopPanelHostWindowState,
    DesktopPanelHostWindowKeyHash>;

DesktopPanelHostWindowRegistry& DesktopPanelHostRegistry();

#endif  // RUNNER_DESKTOP_PANEL_HOST_REGISTRY_H_
