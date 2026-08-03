#ifndef RUNNER_DESKTOP_WINDOW_CONTRACT_H_
#define RUNNER_DESKTOP_WINDOW_CONTRACT_H_

namespace lddc {

// 三个桌面平台统一的首选 Flutter 内容区逻辑尺寸。Windows 创建
// 顶层窗口时会根据当前显示器 DPI 转换成物理客户区，而不是把
// 这两个数字当成包含标题栏的外框尺寸。
inline constexpr unsigned int kPreferredMainWindowContentWidth = 1280;
inline constexpr unsigned int kPreferredMainWindowContentHeight = 720;

}  // namespace lddc

#endif  // RUNNER_DESKTOP_WINDOW_CONTRACT_H_
