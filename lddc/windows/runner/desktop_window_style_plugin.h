#ifndef RUNNER_DESKTOP_WINDOW_STYLE_PLUGIN_H_
#define RUNNER_DESKTOP_WINDOW_STYLE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

class DesktopWindowStylePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit DesktopWindowStylePlugin(flutter::PluginRegistrarWindows* registrar);
  ~DesktopWindowStylePlugin() override;

  DesktopWindowStylePlugin(const DesktopWindowStylePlugin&) = delete;
  DesktopWindowStylePlugin& operator=(const DesktopWindowStylePlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESKTOP_WINDOW_STYLE_PLUGIN_H_
