import Cocoa
import FlutterMacOS
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
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

    // Release 只保留真实运行需要的沙盒、联网和用户选择文件读写权限，调试专用权限放在 DebugProfile。
    XCTAssertEqual(plist?["com.apple.security.app-sandbox"], true)
    XCTAssertEqual(plist?["com.apple.security.network.client"], true)
    XCTAssertEqual(plist?["com.apple.security.files.user-selected.read-write"], true)
    XCTAssertNil(plist?["com.apple.security.network.server"])
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
}
