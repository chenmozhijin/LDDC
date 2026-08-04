import Flutter
import UIKit
import XCTest
import Darwin
// 应用产品名已经从 Flutter 模板的 Runner 改为 LDDC。Swift 单元测试必须导入
// PRODUCT_MODULE_NAME，而不是 Xcode target 的显示名称，否则显式模块构建会找不到宿主模块。
@testable import LDDC

final class RunnerTests: XCTestCase {
  func testReleaseMetadataMatchesBundle() {
    let info = Bundle.main.infoDictionary

    // 这些断言把 iOS 发布身份固定住，避免模板包名或显示名在 Xcode 配置变更后回流。
    XCTAssertEqual(info?["CFBundleIdentifier"] as? String, "com.cmzj.lddc")
    XCTAssertEqual(info?["CFBundleDisplayName"] as? String, "LDDC")
    XCTAssertEqual(info?["CFBundleName"] as? String, "LDDC")
    XCTAssertEqual(Bundle(for: Self.self).bundleIdentifier, "com.cmzj.lddc.RunnerTests")
  }

  func testSearchFileArgumentsSanitizeNamesAndResolveFileUrls() {
    XCTAssertEqual(IOSSearchFileArguments.sanitizedFileName("a/b\\c.lrc"), "a_b_c.lrc")
    XCTAssertNil(IOSSearchFileArguments.resolveAudioFileURL(identifier: " ", path: " "))

    let fromIdentifier = IOSSearchFileArguments.resolveAudioFileURL(
      identifier: "file:///tmp/song.flac",
      path: nil
    )
    XCTAssertEqual(fromIdentifier?.path, "/tmp/song.flac")

    let fromPath = IOSSearchFileArguments.resolveAudioFileURL(
      identifier: "https://example.invalid/song.flac",
      path: "/tmp/fallback.flac"
    )
    XCTAssertEqual(fromPath?.path, "/tmp/fallback.flac")
  }

  func testOpenedAudioFileRegistryClosesOwnedDescriptorsIdempotently() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lddc-ios-fd-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("fixture.mp3")
    try Data([1, 2, 3]).write(to: fileURL, options: .atomic)
    let fd = Darwin.open(fileURL.path, O_RDWR)
    XCTAssertGreaterThanOrEqual(fd, 0)

    var stoppedURLs: [URL] = []
    let registry = IOSOpenedAudioFileRegistry(
      stopAccessing: { url in stoppedURLs.append(url) }
    )
    XCTAssertTrue(
      registry.register(
        fileDescriptor: fd,
        url: fileURL,
        startedAccessingSecurityScopedResource: true
      )
    )
    XCTAssertFalse(
      registry.register(
        fileDescriptor: fd,
        url: fileURL,
        startedAccessingSecurityScopedResource: true
      )
    )
    XCTAssertEqual(registry.count, 1)

    registry.close(fileDescriptor: fd)
    XCTAssertEqual(registry.count, 0)
    XCTAssertEqual(stoppedURLs, [fileURL])
    XCTAssertEqual(Darwin.fcntl(fd, F_GETFD), -1)

    // fd 整数关闭后可能被系统复用，重复释放必须保持无操作。
    registry.close(fileDescriptor: fd)
    XCTAssertEqual(stoppedURLs, [fileURL])
  }

  func testOpenedAudioFileRegistryCloseAllReleasesEveryDescriptor() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lddc-ios-fd-all-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = directory.appendingPathComponent("first.mp3")
    let secondURL = directory.appendingPathComponent("second.flac")
    try Data([1]).write(to: firstURL, options: .atomic)
    try Data([2]).write(to: secondURL, options: .atomic)
    let firstFd = Darwin.open(firstURL.path, O_RDONLY)
    let secondFd = Darwin.open(secondURL.path, O_RDWR)
    XCTAssertGreaterThanOrEqual(firstFd, 0)
    XCTAssertGreaterThanOrEqual(secondFd, 0)

    var stopCount = 0
    let registry = IOSOpenedAudioFileRegistry(
      stopAccessing: { _ in stopCount += 1 }
    )
    XCTAssertTrue(
      registry.register(
        fileDescriptor: firstFd,
        url: firstURL,
        startedAccessingSecurityScopedResource: false
      )
    )
    XCTAssertTrue(
      registry.register(
        fileDescriptor: secondFd,
        url: secondURL,
        startedAccessingSecurityScopedResource: true
      )
    )

    registry.closeAll()
    XCTAssertEqual(registry.count, 0)
    XCTAssertEqual(stopCount, 1)
    XCTAssertEqual(Darwin.fcntl(firstFd, F_GETFD), -1)
    XCTAssertEqual(Darwin.fcntl(secondFd, F_GETFD), -1)
    registry.closeAll()
    XCTAssertEqual(stopCount, 1)
  }

  func testPendingExportStorePreservesUserFileNameAndCleansUniqueDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lddc-ios-export-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = IOSPendingExportFileStore(rootDirectory: root)

    let exportURL = try store.create(fileName: "artist/song\\title.lrc")
    XCTAssertEqual(exportURL.lastPathComponent, "artist_song_title.lrc")
    XCTAssertEqual(exportURL.deletingLastPathComponent().deletingLastPathComponent(), root)
    try Data("Hello LDDC".utf8).write(to: exportURL, options: .atomic)
    XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))

    store.cleanup(fileURL: exportURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: exportURL.deletingLastPathComponent().path))
    // 取消回调和 delegate dismiss 可能先后到达，重复清理必须保持幂等。
    store.cleanup(fileURL: exportURL)

    let outsideURL = root.deletingLastPathComponent()
      .appendingPathComponent("lddc-ios-export-outside-\(UUID().uuidString).lrc")
    try Data("outside".utf8).write(to: outsideURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: outsideURL) }
    store.cleanup(fileURL: outsideURL)
    XCTAssertTrue(FileManager.default.fileExists(atPath: outsideURL.path))
  }

  func testPendingExportStoreRemovesStaleFilesAtNextLaunch() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("lddc-ios-export-stale-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = IOSPendingExportFileStore(rootDirectory: root)
    let staleURL = try store.create(fileName: "stale.lrc")
    try Data("stale".utf8).write(to: staleURL, options: .atomic)

    store.cleanupStaleExports()
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }
}
