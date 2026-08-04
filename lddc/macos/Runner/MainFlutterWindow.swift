import Cocoa
import FlutterMacOS
import desktop_multi_window

#if DEBUG
enum MacOsUiTestAccessibility {
  static let launchArgument = "--lddc-enable-accessibility-for-ui-test"
  private static let notificationName = Notification.Name(
    "NSApplicationDidChangeAccessibilityEnhancedUserInterfaceNotification"
  )

  static func enableIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
    guard arguments.contains(launchArgument) else {
      return
    }
    // Flutter macOS 尚未提供公开的强制 accessibility API（flutter/flutter#90673）。
    // Engine 自身依赖此系统通知创建 native bridge；仅 Debug UI test 显式请求时投递，
    // 避免开启 VoiceOver、修改 TCC 或调用 FlutterEngine_Internal 私有属性。
    NotificationCenter.default.post(
      name: notificationName,
      object: nil,
      userInfo: ["AXEnhancedUserInterface": true]
    )
  }
}
#endif

enum DesktopDragDropPayloadBuilder {
  static func flutterY(localY: CGFloat, contentHeight: CGFloat) -> Double {
    return Double(contentHeight - localY)
  }

  static func filePaths(from urls: [URL]) -> [String] {
    return urls.filter { $0.isFileURL }.map { $0.path }
  }
}

enum DesktopWindowGeometry {
  static let preferredContentSize = NSSize(width: 1280, height: 720)
  static let minimumContentSize = NSSize(width: 960, height: 540)

  static func fittedContentSize(
    preferred: NSSize,
    available: NSSize
  ) -> NSSize {
    guard preferred.width > 0, preferred.height > 0 else {
      return NSSize(width: 1, height: 1)
    }
    let scale = min(
      1,
      min(
        max(available.width, 1) / preferred.width,
        max(available.height, 1) / preferred.height
      )
    )
    return NSSize(
      width: max(minimumContentSize.width, floor(preferred.width * scale)),
      height: max(minimumContentSize.height, floor(preferred.height * scale))
    )
  }

  static func applyInitialBounds(to window: NSWindow) {
    let preferred = preferredContentSize
    // contentMinSize 使用内容区语义，不包含标题栏。必须在 Flutter controller
    // 创建前设置，避免用户缩小时先生成无效 surface 再被系统拉回。
    window.contentMinSize = minimumContentSize
    guard let screen = window.screen ?? NSScreen.main else {
      window.setContentSize(preferred)
      return
    }
    let preferredFrame = window.frameRect(
      forContentRect: NSRect(origin: .zero, size: preferred)
    )
    let frameExtraWidth = max(0, preferredFrame.width - preferred.width)
    let frameExtraHeight = max(0, preferredFrame.height - preferred.height)
    let availableContent = NSSize(
      width: max(1, screen.visibleFrame.width - frameExtraWidth),
      height: max(1, screen.visibleFrame.height - frameExtraHeight)
    )

    // visibleFrame 已排除菜单栏与 Dock。先在 Flutter controller 创建前完成
    // 尺寸适配，可避免首帧之后重建 Metal surface 或出现可见的二次缩放。
    window.setContentSize(
      fittedContentSize(preferred: preferred, available: availableContent)
    )
    window.center()
  }
}

class MainFlutterWindow: NSWindow {
  private var desktopDragDropChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    DesktopWindowGeometry.applyInitialBounds(to: self)
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    desktopDragDropChannel = FlutterMethodChannel(
      name: "lddc/desktop_drag_drop",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    registerForDraggedTypes([.fileURL])

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()

    #if DEBUG
    // 下一轮主队列执行时 engine 已完成 observer 注册和 view attachment，确保通知能够
    // 同时创建 accessibility bridge 并请求首棵 semantics tree。
    DispatchQueue.main.async {
      MacOsUiTestAccessibility.enableIfRequested()
    }
    #endif
  }

  @objc func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    sendDesktopDragEvent(method: "dragEnter", sender: sender, includeFiles: false)
    return .copy
  }

  @objc func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    sendDesktopDragEvent(method: "dragUpdate", sender: sender, includeFiles: false)
    return .copy
  }

  @objc func draggingExited(_ sender: NSDraggingInfo?) {
    if let sender {
      sendDesktopDragEvent(method: "dragLeave", sender: sender, includeFiles: false)
    } else {
      desktopDragDropChannel?.invokeMethod("dragLeave", arguments: [
        "platform": "macos",
        "x": 0.0,
        "y": 0.0,
        "coordinateSpace": "logical",
        "formats": [],
        "files": [],
        "privateData": [:],
      ])
    }
  }

  @objc func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    sendDesktopDragEvent(method: "performDrop", sender: sender, includeFiles: true)
    return true
  }

  private func sendDesktopDragEvent(
    method: String,
    sender: NSDraggingInfo,
    includeFiles: Bool
  ) {
    guard let contentView else {
      return
    }
    let localPoint = contentView.convert(sender.draggingLocation, from: nil)
    let pasteboard = sender.draggingPasteboard
    let formats = pasteboard.types?.map { $0.rawValue } ?? []
    var files: [String] = []
    if includeFiles,
      let urls = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
      ) as? [URL]
    {
      files = DesktopDragDropPayloadBuilder.filePaths(from: urls)
    }

    // macOS 拖放坐标原点在左下角；Dart 侧命中测试使用 Flutter 的左上角坐标。
    desktopDragDropChannel?.invokeMethod(method, arguments: [
      "platform": "macos",
      "x": Double(localPoint.x),
      "y": DesktopDragDropPayloadBuilder.flutterY(
        localY: localPoint.y,
        contentHeight: contentView.bounds.height
      ),
      "coordinateSpace": "logical",
      "formats": formats,
      "files": files,
      "privateData": [:],
    ])
  }
}
