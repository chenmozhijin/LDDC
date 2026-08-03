import 'package:flutter/foundation.dart';

import 'app_capability.dart';

/// 能力解析器：根据运行平台与注入标记构建 [AppCapability]。
class AppCapabilityResolver {
  const AppCapabilityResolver._();

  /// 解析指定平台的能力快照。
  static AppCapability resolve({
    required bool isWeb,
    required TargetPlatform targetPlatform,
    bool webFileSystemAccess = false,
    bool webTaglibWasmReady = false,
  }) {
    final bool isDesktop =
        !isWeb &&
        switch (targetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.macOS ||
          TargetPlatform.linux => true,
          _ => false,
        };

    final bool isAndroid = !isWeb && targetPlatform == TargetPlatform.android;
    final bool isIos = !isWeb && targetPlatform == TargetPlatform.iOS;
    final bool isMobile = isAndroid || isIos;

    return AppCapability(
      multiWindow: isDesktop,
      desktopPanelDetached: isDesktop,
      desktopPanelEmbedded: !isWeb && targetPlatform == TargetPlatform.windows,
      systemTray: isDesktop,
      globalHotkey: isDesktop,
      audioTagWrite: isDesktop || isMobile || webTaglibWasmReady,
      directoryRecursiveScan: isDesktop || isAndroid,
      androidSafTreeAccess: isAndroid,
      androidCueTrackResolve: isAndroid,
      webFileSystemAccess: isWeb && webFileSystemAccess,
      webTaglibWasmReady: isWeb && webTaglibWasmReady,
    );
  }

  /// 解析当前运行环境的能力快照。
  static AppCapability resolveCurrent({
    bool webFileSystemAccess = false,
    bool webTaglibWasmReady = false,
  }) {
    return resolve(
      isWeb: kIsWeb,
      targetPlatform: defaultTargetPlatform,
      webFileSystemAccess: webFileSystemAccess,
      webTaglibWasmReady: webTaglibWasmReady,
    );
  }
}
