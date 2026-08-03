import 'package:flutter/services.dart';

/// 桌面 runner 提供的子窗口样式通道。
///
/// 居中和 tool window 类型都需要 Win32 直接控制，因此复用同一原生桥。
const MethodChannel desktopWindowStyleChannel = MethodChannel(
  'lddc/desktop_window_style',
);
