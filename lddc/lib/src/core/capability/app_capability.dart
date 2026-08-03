/// 平台能力开关集合。
///
/// 约束：UI 层仅消费该对象，不直接判断平台类型。
class AppCapability {
  const AppCapability({
    required this.multiWindow,
    required this.desktopPanelDetached,
    required this.desktopPanelEmbedded,
    required this.systemTray,
    required this.globalHotkey,
    required this.audioTagWrite,
    required this.directoryRecursiveScan,
    required this.androidSafTreeAccess,
    required this.androidCueTrackResolve,
    required this.webFileSystemAccess,
    required this.webTaglibWasmReady,
  });

  final bool multiWindow;
  final bool desktopPanelDetached;
  final bool desktopPanelEmbedded;
  final bool systemTray;
  final bool globalHotkey;
  final bool audioTagWrite;
  final bool directoryRecursiveScan;
  final bool androidSafTreeAccess;
  final bool androidCueTrackResolve;
  final bool webFileSystemAccess;
  final bool webTaglibWasmReady;

  /// 转为可序列化字典，方便日志与调试输出。
  Map<String, bool> toMap() {
    return <String, bool>{
      'multiWindow': multiWindow,
      'desktopPanelDetached': desktopPanelDetached,
      'desktopPanelEmbedded': desktopPanelEmbedded,
      'systemTray': systemTray,
      'globalHotkey': globalHotkey,
      'audioTagWrite': audioTagWrite,
      'directoryRecursiveScan': directoryRecursiveScan,
      'androidSafTreeAccess': androidSafTreeAccess,
      'androidCueTrackResolve': androidCueTrackResolve,
      'webFileSystemAccess': webFileSystemAccess,
      'webTaglibWasmReady': webTaglibWasmReady,
    };
  }
}
