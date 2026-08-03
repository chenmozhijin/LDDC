#include "runner_plugin_registrant.h"

#include "desktop_panel_host_plugin.h"
#include "desktop_drag_drop_plugin.h"
#include "desktop_window_style_plugin.h"
#ifdef LDDC_ENABLE_PANEL_HOST_TEST_PLUGIN
#include "desktop_panel_host_test_plugin.h"
#endif
#include "embedded_panel_channel_plugin.h"
#include "file_selector_windows/file_selector_windows.h"
#include "flutter/generated_plugin_registrant.h"
#include "window_manager/window_manager_plugin.h"

namespace {

flutter::PluginRegistrarWindows* GetRegistrar(flutter::FlutterEngine* engine,
                                              const char* plugin_name) {
  if (engine == nullptr) {
    return nullptr;
  }
  return flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(
          engine->GetRegistrarForPlugin(plugin_name));
}

void RegisterEmbeddedPanelChannel(flutter::FlutterEngine* engine) {
  auto* registrar = GetRegistrar(engine, "EmbeddedPanelChannelPlugin");
  if (registrar != nullptr) {
    EmbeddedPanelChannelPlugin::RegisterWithRegistrar(registrar);
  }
}

void RegisterPanelHostPlugin(flutter::FlutterEngine* engine) {
  auto* registrar = GetRegistrar(engine, "DesktopPanelHostPlugin");
  if (registrar != nullptr) {
    DesktopPanelHostPlugin::RegisterWithRegistrar(registrar);
  }
}

void RegisterDesktopWindowStylePlugin(flutter::FlutterEngine* engine) {
  auto* registrar = GetRegistrar(engine, "DesktopWindowStylePlugin");
  if (registrar != nullptr) {
    DesktopWindowStylePlugin::RegisterWithRegistrar(registrar);
  }
}

void RegisterDesktopDragDropPlugin(flutter::FlutterEngine* engine) {
  auto* registrar = GetRegistrar(engine, "DesktopDragDropPlugin");
  if (registrar != nullptr) {
    DesktopDragDropPlugin::RegisterWithRegistrar(registrar);
  }
}

#ifdef LDDC_ENABLE_PANEL_HOST_TEST_PLUGIN
void RegisterPanelHostTestPlugin(flutter::FlutterEngine* engine) {
  auto* registrar = GetRegistrar(engine, "DesktopPanelHostTestPlugin");
  if (registrar != nullptr) {
    DesktopPanelHostTestPlugin::RegisterWithRegistrar(registrar);
  }
}
#endif

}  // namespace

void RegisterMainWindowPlugins(flutter::FlutterEngine* engine) {
  RegisterPlugins(engine);
  RegisterEmbeddedPanelChannel(engine);
  RegisterPanelHostPlugin(engine);
  RegisterDesktopDragDropPlugin(engine);
  RegisterDesktopWindowStylePlugin(engine);
#ifdef LDDC_ENABLE_PANEL_HOST_TEST_PLUGIN
  RegisterPanelHostTestPlugin(engine);
#endif
}

void RegisterDesktopMultiWindowChildPlugins(flutter::FlutterEngine* engine) {
  if (engine == nullptr) {
    return;
  }
  // desktop_multi_window 会在 Create() 内部注册自己的窗口通道，不能在
  // callback 中重复注册。浮窗和选择器只补齐显隐、标题、关闭、原生样式
  // 和选择器打开本地歌词所需插件；FileSelectorWindows 只在实际调用时
  // 创建 IFileDialog，不会让未使用该能力的浮窗常驻原生文件对话框。
  WindowManagerPluginRegisterWithRegistrar(
      engine->GetRegistrarForPlugin("WindowManagerPlugin"));
  FileSelectorWindowsRegisterWithRegistrar(
      engine->GetRegistrarForPlugin("FileSelectorWindows"));
  RegisterDesktopWindowStylePlugin(engine);
}

void RegisterEmbeddedPanelPlugins(flutter::FlutterEngine* engine) {
  if (engine == nullptr) {
    return;
  }
  // embedded panel child-engine 只能注册最小桥接插件。
  // 任何带“顶层窗口”假设的插件（例如 window_manager/tray_manager）
  // 都可能在 create 期接管错误的 HWND 层级，污染 panel root/view 父链。
  RegisterEmbeddedPanelChannel(engine);
}
