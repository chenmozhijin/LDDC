#ifndef RUNNER_DESKTOP_DRAG_DROP_PLUGIN_H_
#define RUNNER_DESKTOP_DRAG_DROP_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

class DesktopDragDropPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  DesktopDragDropPlugin(flutter::PluginRegistrarWindows* registrar, HWND hwnd);
  ~DesktopDragDropPlugin() override;

  DesktopDragDropPlugin(const DesktopDragDropPlugin&) = delete;
  DesktopDragDropPlugin& operator=(const DesktopDragDropPlugin&) = delete;

  void SendDragEvent(const char* method, IDataObject* data_object,
                     POINTL point, bool include_data);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND hwnd_ = nullptr;
  IDropTarget* drop_target_ = nullptr;
  HRESULT ole_result_ = E_FAIL;
};

#endif  // RUNNER_DESKTOP_DRAG_DROP_PLUGIN_H_
