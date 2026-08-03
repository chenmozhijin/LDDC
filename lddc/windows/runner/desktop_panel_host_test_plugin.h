#ifndef RUNNER_DESKTOP_PANEL_HOST_TEST_PLUGIN_H_
#define RUNNER_DESKTOP_PANEL_HOST_TEST_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <unordered_map>

class DesktopPanelHostTestPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit DesktopPanelHostTestPlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~DesktopPanelHostTestPlugin() override;

  DesktopPanelHostTestPlugin(const DesktopPanelHostTestPlugin&) = delete;
  DesktopPanelHostTestPlugin& operator=(const DesktopPanelHostTestPlugin&) =
      delete;

 private:
  struct TestHostWindowState {
    HWND handle = nullptr;
    int checker_phase = 0;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CreateTestHostWindow(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetTestHostClientSize(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetTestHostWindowState(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetTestHostCheckerPhase(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DestroyTestHostWindow(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CaptureTestHostClient(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CollectPanelState(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CollectPanelPointerTarget(
      const flutter::EncodableMap& arguments,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void CollectResourceCounts(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static LRESULT CALLBACK TestHostWindowProc(HWND window,
                                             UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam);
  static std::unordered_map<int64_t, TestHostWindowState>& TestHostWindows();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DESKTOP_PANEL_HOST_TEST_PLUGIN_H_
