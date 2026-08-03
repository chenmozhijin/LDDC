#ifndef RUNNER_EMBEDDED_PANEL_CHANNEL_PLUGIN_H_
#define RUNNER_EMBEDDED_PANEL_CHANNEL_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>

class EmbeddedPanelChannelPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit EmbeddedPanelChannelPlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~EmbeddedPanelChannelPlugin() override;

  EmbeddedPanelChannelPlugin(const EmbeddedPanelChannelPlugin&) = delete;
  EmbeddedPanelChannelPlugin& operator=(const EmbeddedPanelChannelPlugin&) =
      delete;

  void InvokeMethod(const std::string& channel,
                    const flutter::EncodableValue& arguments,
                    std::unique_ptr<flutter::MethodResult<>> result);

 private:
  void HandleMethodCall(const flutter::MethodCall<>& call,
                        std::unique_ptr<flutter::MethodResult<>> result);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<>> channel_;
  std::vector<std::string> registered_channels_;
};

#endif  // RUNNER_EMBEDDED_PANEL_CHANNEL_PLUGIN_H_
