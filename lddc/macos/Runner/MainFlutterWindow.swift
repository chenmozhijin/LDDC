import Cocoa
import FlutterMacOS
import desktop_multi_window

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
      width: max(1, floor(preferred.width * scale)),
      height: max(1, floor(preferred.height * scale))
    )
  }

  static func applyInitialBounds(to window: NSWindow) {
    let preferred = preferredContentSize
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
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    sendDesktopDragEvent(method: "dragEnter", sender: sender, includeFiles: false)
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    sendDesktopDragEvent(method: "dragUpdate", sender: sender, includeFiles: false)
    return .copy
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
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

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
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
