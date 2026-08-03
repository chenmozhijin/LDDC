#ifndef RUNNER_RUNNER_PLUGIN_REGISTRANT_H_
#define RUNNER_RUNNER_PLUGIN_REGISTRANT_H_

#include <flutter/flutter_engine.h>

// 主窗口 engine 使用的插件集合。
void RegisterMainWindowPlugins(flutter::FlutterEngine* engine);

// `desktop_multi_window` 子窗口继续沿用原有插件集合。
void RegisterDesktopMultiWindowChildPlugins(flutter::FlutterEngine* engine);

// embedded panel child engine 使用的最小插件集合。
void RegisterEmbeddedPanelPlugins(flutter::FlutterEngine* engine);

#endif  // RUNNER_RUNNER_PLUGIN_REGISTRANT_H_
