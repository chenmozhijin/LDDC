#ifndef RUNNER_EMBEDDED_PANEL_NATIVE_HOST_H_
#define RUNNER_EMBEDDED_PANEL_NATIVE_HOST_H_

#include <windows.h>

#include <memory>
#include <string>
#include <unordered_map>

#include "desktop_panel_host_registry.h"

struct EmbeddedPanelNativeCreateRequest {
  DesktopPanelHostWindowKey key;
  HWND host_window_handle = nullptr;
  std::string channel_name;
  int generation = 0;
};

struct EmbeddedPanelNativeCreateResult {
  HWND root_window_handle = nullptr;
  HWND view_window_handle = nullptr;
};

enum class EmbeddedPanelNativeCreateStatus {
  kSuccess,
  kSurfaceUnavailable,
  kFailure,
};

class EmbeddedPanelNativeHost {
 public:
  static EmbeddedPanelNativeHost& Instance();

  EmbeddedPanelNativeHost(const EmbeddedPanelNativeHost&) = delete;
  EmbeddedPanelNativeHost& operator=(const EmbeddedPanelNativeHost&) = delete;

  EmbeddedPanelNativeCreateStatus CreatePanel(
      const EmbeddedPanelNativeCreateRequest& request,
      EmbeddedPanelNativeCreateResult* result,
      std::string* error_message);
  bool ResizePanel(const DesktopPanelHostWindowKey& key, int width, int height);
  bool SetPanelVisibility(const DesktopPanelHostWindowKey& key, bool visible);
  void DestroyPanel(const DesktopPanelHostWindowKey& key);

 private:
  EmbeddedPanelNativeHost();
  ~EmbeddedPanelNativeHost();

  class EmbeddedPanelWindow;

  std::unordered_map<DesktopPanelHostWindowKey,
                     std::unique_ptr<EmbeddedPanelWindow>,
                     DesktopPanelHostWindowKeyHash>
      windows_;
};

#endif  // RUNNER_EMBEDDED_PANEL_NATIVE_HOST_H_
