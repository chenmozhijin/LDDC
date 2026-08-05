import Cocoa
import FlutterMacOS
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testHiddenDesktopServiceSurvivesLastWindowBeingHidden() {
    let delegate = AppDelegate()

    // 后台桌面歌词服务会把主窗口移出屏幕但继续监听 loopback。最后窗口不可见时
    // 不能由 AppKit 自动结束进程，真正退出统一经过 Dart 退出守卫完成资源回收。
    XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
  }

  func testReleaseMetadataMatchesBundle() {
    let info = Bundle.main.infoDictionary

    // 这些断言把 macOS 发布身份固定住，避免模板包名、产品名或版权文本回流。
    XCTAssertEqual(info?["CFBundleIdentifier"] as? String, "com.cmzj.lddc")
    XCTAssertEqual(info?["CFBundleName"] as? String, "LDDC")
    XCTAssertEqual(
      info?["NSHumanReadableCopyright"] as? String,
      "Copyright © 2026 沉默の金. All rights reserved."
    )
    XCTAssertEqual(Bundle(for: Self.self).bundleIdentifier, "com.cmzj.lddc.RunnerTests")
  }

  func testReleaseEntitlementsKeepRequiredCapabilities() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let entitlementsURL = testFile
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Runner/Release.entitlements")
    let data = try Data(contentsOf: entitlementsURL)
    let plist = try PropertyListSerialization.propertyList(from: data) as? [String: Bool]

    // 桌面歌词插件通过 loopback 连接 LDDC，因此 Release 必须同时允许客户端连接和服务端监听。
    // JIT 仍只属于 DebugProfile，不能因为原生测试而进入正式构建。
    XCTAssertEqual(plist?["com.apple.security.app-sandbox"], true)
    XCTAssertEqual(plist?["com.apple.security.network.client"], true)
    XCTAssertEqual(plist?["com.apple.security.network.server"], true)
    XCTAssertEqual(plist?["com.apple.security.files.user-selected.read-write"], true)
    XCTAssertNil(plist?["com.apple.security.cs.allow-jit"])
  }

  func testDragDropPayloadUsesFlutterCoordinatesAndOnlyFileUrls() {
    XCTAssertEqual(
      DesktopDragDropPayloadBuilder.flutterY(localY: 30, contentHeight: 120),
      90
    )
    let paths = DesktopDragDropPayloadBuilder.filePaths(from: [
      URL(fileURLWithPath: "/tmp/song.flac"),
      URL(string: "https://example.invalid/song.flac")!,
    ])
    XCTAssertEqual(paths, ["/tmp/song.flac"])
  }

  func testDesktopWindowGeometryKeepsPreferredContentSizeWhenItFits() {
    let preferred = DesktopWindowGeometry.preferredContentSize
    let fitted = DesktopWindowGeometry.fittedContentSize(
      preferred: preferred,
      available: NSSize(width: 1920, height: 1000)
    )

    XCTAssertEqual(preferred.width, 1280)
    XCTAssertEqual(preferred.height, 720)
    XCTAssertEqual(DesktopWindowGeometry.minimumContentSize.width, 960)
    XCTAssertEqual(DesktopWindowGeometry.minimumContentSize.height, 540)
    XCTAssertEqual(fitted, preferred)
  }

  func testDesktopWindowGeometryScalesDownWithoutChangingAspectRatio() {
    let fitted = DesktopWindowGeometry.fittedContentSize(
      preferred: DesktopWindowGeometry.preferredContentSize,
      available: NSSize(width: 1000, height: 600)
    )

    XCTAssertEqual(fitted.width, 1000)
    XCTAssertEqual(fitted.height, 562)
    XCTAssertEqual(fitted.width / fitted.height, 16.0 / 9.0, accuracy: 0.02)
  }

  func testDesktopWindowGeometryDoesNotShrinkBelowSupportedContentSize() {
    let fitted = DesktopWindowGeometry.fittedContentSize(
      preferred: DesktopWindowGeometry.preferredContentSize,
      available: NSSize(width: 800, height: 450)
    )

    XCTAssertEqual(fitted, DesktopWindowGeometry.minimumContentSize)
  }
}
