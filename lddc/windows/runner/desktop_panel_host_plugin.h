#ifndef RUNNER_DESKTOP_PANEL_HOST_PLUGIN_H_
#define RUNNER_DESKTOP_PANEL_HOST_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

#include "desktop_panel_host_registry.h"

// Windows 侧 embedded Panel 原生宿主插件。
class DesktopPanelHostPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit DesktopPanelHostPlugin(flutter::PluginRegistrarWindows* registrar);
  ~DesktopPanelHostPlugin() override;

  DesktopPanelHostPlugin(const DesktopPanelHostPlugin&) = delete;
  DesktopPanelHostPlugin& operator=(const DesktopPanelHostPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CreatePanel(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void UpdatePanelSurface(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetPanelVisibility(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DestroyPanel(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESKTOP_PANEL_HOST_PLUGIN_H_
