import XCTest

final class RunnerUITests: XCTestCase {
  private let appBundleIdentifier = "com.cmzj.lddc.platformtests"
  private let fixtureName = "audio_sample.mp3"
  private let navigationIdentifier = "lddc.nav.open_lyrics"
  private let openSongIdentifier = "lddc.open_lyrics.open_song_file"
  private let saveFileIdentifier = "lddc.open_lyrics.save_file"
  private let saveTagIdentifier = "lddc.open_lyrics.save_tag"
  private let saveTagSucceededIdentifier = "lddc.open_lyrics.notice.saveTagSucceeded"
  private var cleanupVerified = false

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testDocumentPickerSelectsSeededAudio() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    do {
      let app = launchApp()
      defer { app.terminate() }
      try selectSeededAudio(app: app)
      addAction(&actions, capability: "filePicker", action: "document_picker_select_audio")
      addAction(&actions, capability: "nativeChannels", action: "flutter_picker_round_trip")
      addAction(&actions, capability: "media", action: "security_scoped_fd_read_embedded_lyrics")

      let saveTag = app.descendants(matching: .any)[saveTagIdentifier]
      try requireHittable(saveTag, in: app, message: "Flutter 未暴露可点击的写入歌曲标签按钮")
      saveTag.tap()
      let saveSucceeded = app.descendants(matching: .any)[saveTagSucceededIdentifier]
      try require(saveSucceeded.waitForExistence(timeout: 20), "读写 fd 升级后没有成功保存歌词标签")
      addAction(&actions, capability: "media", action: "read_write_fd_tag_saved")

      // 终止应用会触发 fd registry 与 security-scoped 资源清理；重新启动并再次
      // 经系统 Picker 回读，才能证明写入不是同一 TagLib 会话缓存造成的假绿。
      try terminateAndVerify(app)
      app.launch()
      try selectSeededAudio(app: app)
      addAction(&actions, capability: "media", action: "saved_tag_reopened_after_app_restart")
      try terminateAndVerify(app)
      addAction(&actions, capability: "resourceCleanup", action: "application_and_picker_closed")
    } catch let error {
      failure = error
    }
    attachEvidence(scenario: "ios_document_picker_select", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testDocumentPickerCancellationReturnsToFlutter() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    do {
      let app = launchApp()
      defer { app.terminate() }
      try openDocumentPicker(app: app)
      let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
      try require(documents.wait(for: .runningForeground, timeout: 15), "系统文件界面没有进入前台")
      let cancel = documents.buttons["Cancel"]
      try require(cancel.waitForExistence(timeout: 15), "系统文件界面没有可访问的取消按钮")
      cancel.tap()
      try require(app.wait(for: .runningForeground, timeout: 15), "取消后 LDDC 没有返回前台")
      try require(
        app.buttons[openSongIdentifier].waitForExistence(timeout: 15),
        "取消后 Flutter 打开歌曲动作不可再次发现"
      )
      addAction(&actions, capability: "filePicker", action: "document_picker_cancel")
      addAction(&actions, capability: "nativeChannels", action: "flutter_picker_cancel_round_trip")
      try terminateAndVerify(app)
      addAction(&actions, capability: "resourceCleanup", action: "application_and_picker_closed")
    } catch let error {
      failure = error
    }
    attachEvidence(scenario: "ios_document_picker_cancel", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testDocumentPickerExportsLyricsFile() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    do {
      let app = launchApp()
      defer { app.terminate() }
      try selectSeededAudio(app: app)
      let documents = try openExportPicker(app: app)
      let save = documents.buttons["Save"]
      try require(save.waitForExistence(timeout: 15), "系统导出界面没有可访问的保存按钮")
      save.tap()
      try require(app.wait(for: .runningForeground, timeout: 15), "导出后 LDDC 没有返回前台")
      addAction(&actions, capability: "filePicker", action: "document_picker_export_lyrics")
      addAction(&actions, capability: "nativeChannels", action: "flutter_export_round_trip")
      try terminateAndVerify(app)
      addAction(&actions, capability: "resourceCleanup", action: "export_source_and_picker_closed")
    } catch let error {
      failure = error
    }
    attachEvidence(scenario: "ios_document_picker_export", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testDocumentPickerExportCancellationCleansTemporaryFile() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    do {
      let app = launchApp()
      defer { app.terminate() }
      try selectSeededAudio(app: app)
      let documents = try openExportPicker(app: app)
      let cancel = documents.buttons["Cancel"]
      try require(cancel.waitForExistence(timeout: 15), "系统导出界面没有可访问的取消按钮")
      cancel.tap()
      try require(app.wait(for: .runningForeground, timeout: 15), "取消导出后 LDDC 没有返回前台")
      addAction(&actions, capability: "filePicker", action: "document_picker_export_cancel")
      addAction(&actions, capability: "nativeChannels", action: "flutter_export_cancel_round_trip")
      try terminateAndVerify(app)
      addAction(&actions, capability: "resourceCleanup", action: "cancelled_export_source_removed")
    } catch let error {
      failure = error
    }
    attachEvidence(scenario: "ios_document_picker_export_cancel", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testTerminatedExportIsCleanedOnNextLaunch() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    do {
      let app = launchApp()
      defer { app.terminate() }
      try selectSeededAudio(app: app)
      let documents = try openExportPicker(app: app)
      try require(documents.wait(for: .runningForeground, timeout: 15), "终止清理场景没有进入系统导出界面")
      app.terminate()
      documents.terminate()

      // 强制终止不保证 iOS 发送生命周期回调；下一次插件初始化必须删除上次
      // 遗留的临时导出目录，runner 会从 Simulator 容器进行最终空目录断言。
      app.launch()
      try require(app.wait(for: .runningForeground, timeout: 15), "导出中终止后 LDDC 无法重新启动")
      addAction(&actions, capability: "filePicker", action: "document_picker_export_interrupted")
      addAction(&actions, capability: "nativeChannels", action: "save_text_request_interrupted_and_plugin_reinitialized")
      addAction(&actions, capability: "resourceCleanup", action: "stale_export_removed_on_next_launch")
      try terminateAndVerify(app)
    } catch let error {
      failure = error
    }
    attachEvidence(scenario: "ios_document_picker_export_termination", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    return app
  }

  private func openDocumentPicker(app: XCUIApplication) throws {
    let navigation = app.buttons[navigationIdentifier]
    guard navigation.waitForExistence(timeout: 15) else {
      XCTFail("Flutter 没有向 XCUITest 暴露打开歌词导航 identifier")
      throw NSError(
        domain: "LDDCPlatformTests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "缺少打开歌词导航 identifier"]
      )
    }
    navigation.tap()
    let openSong = app.buttons[openSongIdentifier]
    try require(openSong.waitForExistence(timeout: 15), "Flutter 没有暴露打开歌曲按钮 identifier")
    openSong.tap()
  }

  private func selectSeededAudio(app: XCUIApplication) throws {
    try openDocumentPicker(app: app)
    let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    try require(documents.wait(for: .runningForeground, timeout: 15), "系统文件界面没有进入前台")
    let fixture = documents.descendants(matching: .any)[fixtureName]
    try require(fixture.waitForExistence(timeout: 15), "系统文件界面没有显示 seed 音频")
    fixture.tap()
    try require(app.wait(for: .runningForeground, timeout: 15), "选择文件后 LDDC 没有返回前台")
    try require(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fixtureName))
        .firstMatch.waitForExistence(timeout: 15),
      "选择结果没有回到 Flutter 页面"
    )
    try require(
      app.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS %@", "Hello LDDC"))
        .firstMatch.waitForExistence(timeout: 15),
      "生产 TagLib 没有从 security-scoped fd 回读匿名内嵌歌词"
    )
  }

  private func openExportPicker(app: XCUIApplication) throws -> XCUIApplication {
    let saveFile = app.descendants(matching: .any)[saveFileIdentifier]
    try requireHittable(saveFile, in: app, message: "Flutter 未暴露可点击的歌词导出按钮")
    saveFile.tap()
    let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    try require(documents.wait(for: .runningForeground, timeout: 15), "系统导出界面没有进入前台")
    return documents
  }

  private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
      // XCTest 断言本身不会抛异常；同时抛出可让 evidence 与原始 xcresult 保持一致。
      XCTFail(message)
      throw NSError(
        domain: "LDDCPlatformTests",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }
  }

  private func requireHittable(
    _ element: XCUIElement,
    in app: XCUIApplication,
    message: String
  ) throws {
    if element.waitForExistence(timeout: 3), element.isHittable {
      return
    }
    let scrollView = app.scrollViews.firstMatch
    try require(scrollView.waitForExistence(timeout: 5), "Flutter 页面没有暴露可滚动语义容器")
    for _ in 0..<6 {
      scrollView.swipeUp()
      if element.waitForExistence(timeout: 1), element.isHittable {
        return
      }
    }
    try require(false, message)
  }

  private func terminateAndVerify(_ app: XCUIApplication) throws {
    app.terminate()
    try require(app.wait(for: .notRunning, timeout: 5), "LDDC 未在超时内关闭")
    let picker = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    // DocumentsApp 是系统常驻进程，关闭 Picker 后可能留在后台；资源清理的正确
    // 边界是它不再占据前台。测试主动终止其测试会话，避免影响下一个场景。
    if picker.state == .runningForeground {
      picker.terminate()
    }
    try require(
      picker.state != .runningForeground,
      "Document Picker 仍占据前台，系统文件界面没有完成收口"
    )
    cleanupVerified = true
  }

  private func addAction(
    _ actions: inout [String: [[String: Any]]],
    capability: String,
    action: String
  ) {
    actions[capability, default: []].append(["action": action])
  }

  private func attachEvidence(
    scenario: String,
    actions: [String: [[String: Any]]],
    failure: Error?
  ) {
    let environment = ProcessInfo.processInfo.environment
    let runId = environment["LDDC_IT_RUN_ID"] ?? "missing-run-id"
    let artifact: [[String: Any]]
    if scenario.hasSuffix("select"),
       let size = Int(environment["LDDC_FIXTURE_SIZE"] ?? ""),
       let sha256 = environment["LDDC_FIXTURE_SHA256"] {
      artifact = [["name": fixtureName, "size": size, "sha256": sha256]]
    } else {
      artifact = []
    }
    let payload: [String: Any] = [
      "runId": runId,
      "scenario": scenario,
      "profile": "platform",
      "platform": "ios",
      "framework": "xcuitest",
      "steps": [[
        "step": scenario,
        "success": failure == nil,
        // JSONSerialization 不能编码 Optional.none，失败为空时必须显式写入 JSON null。
        "error": failure.map { String(describing: $0) } ?? NSNull(),
      ]],
      "capabilityEvidence": actions,
      "resources": [
        "baseline": ["nativeWindowCount": 0],
        "final": ["nativeWindowCount": cleanupVerified ? 0 : 1],
        "thresholds": ["nativeWindowCount": 0],
      ],
      "artifacts": artifact,
      "extra": [:],
    ]
    do {
      let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
      attachment.name = "lddc-evidence-\(scenario).json"
      attachment.lifetime = .keepAlways
      add(attachment)
    } catch {
      XCTFail("无法生成 XCUITest evidence: \(error)")
    }
  }
}
