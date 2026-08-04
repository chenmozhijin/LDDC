import XCTest

final class RunnerUITests: XCTestCase {
  private let navigationIdentifier = "lddc.nav.open_lyrics"
  private let openSongIdentifier = "lddc.open_lyrics.open_song_file"
  private var cleanupVerified = false

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testOpenPanelSelectsFixture() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    do {
      let app = launchApp()
      defer { app.terminate() }
      try openSongPanel(app: app)
      guard let fixturePath = ProcessInfo.processInfo.environment["LDDC_FIXTURE_PATH"] else {
        throw NSError(domain: "LDDCPlatformTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少 fixture path"])
      }
      app.typeKey("g", modifierFlags: [.command, .shift])
      let pathField = app.sheets.textFields.firstMatch
      try require(pathField.waitForExistence(timeout: 10), "NSOpenPanel 没有打开前往文件夹输入框")
      pathField.typeText(fixturePath)
      app.typeKey(.enter, modifierFlags: [])
      let openButton = app.buttons["Open"]
      try require(openButton.waitForExistence(timeout: 10), "NSOpenPanel 没有可访问的打开按钮")
      openButton.click()
      try require(
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "audio_sample.mp3"))
          .firstMatch.waitForExistence(timeout: 15),
        "选择结果没有回到 Flutter 页面"
      )
      addAction(&actions, capability: "filePicker", action: "ns_open_panel_select_audio")
      addAction(&actions, capability: "nativeChannels", action: "flutter_picker_round_trip")
      try terminateAndVerify(app)
      addAction(&actions, capability: "resourceCleanup", action: "application_and_panel_closed")
    } catch let error {
      failure = error
    }
    attachEvidence(scenario: "macos_open_panel_select", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testOpenPanelCancellationReturnsToFlutter() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    do {
      let app = launchApp()
      defer { app.terminate() }
      try openSongPanel(app: app)
      let cancel = app.buttons["Cancel"]
      try require(cancel.waitForExistence(timeout: 10), "NSOpenPanel 没有可访问的取消按钮")
      cancel.click()
      try require(
        app.buttons[openSongIdentifier].waitForExistence(timeout: 10),
        "取消后 Flutter 打开歌曲动作不可再次发现"
      )
      addAction(&actions, capability: "filePicker", action: "ns_open_panel_cancel")
      addAction(&actions, capability: "nativeChannels", action: "flutter_picker_cancel_round_trip")
      try terminateAndVerify(app)
      addAction(&actions, capability: "resourceCleanup", action: "application_and_panel_closed")
    } catch let error {
      failure = error
    }
    attachEvidence(scenario: "macos_open_panel_cancel", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US",
      "--lddc-enable-accessibility-for-ui-test",
    ]
    app.launch()
    return app
  }

  private func openSongPanel(app: XCUIApplication) throws {
    let navigation = app.buttons[navigationIdentifier]
    guard navigation.waitForExistence(timeout: 15) else {
      XCTFail("Flutter 没有向 XCUITest 暴露打开歌词导航 identifier")
      throw NSError(domain: "LDDCPlatformTests", code: 2, userInfo: nil)
    }
    navigation.click()
    let openSong = app.buttons[openSongIdentifier]
    try require(openSong.waitForExistence(timeout: 15), "Flutter 没有暴露打开歌曲按钮 identifier")
    openSong.click()
  }

  private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
      // XCTest 断言本身不会抛异常；同时抛出可让 evidence 与原始 xcresult 保持一致。
      XCTFail(message)
      throw NSError(
        domain: "LDDCPlatformTests",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }
  }

  private func terminateAndVerify(_ app: XCUIApplication) throws {
    app.terminate()
    try require(app.wait(for: .notRunning, timeout: 5), "LDDC 或 NSOpenPanel 未在超时内关闭")
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
    var artifacts: [[String: Any]] = []
    if scenario.hasSuffix("select"),
       let size = Int(environment["LDDC_FIXTURE_SIZE"] ?? ""),
       let sha256 = environment["LDDC_FIXTURE_SHA256"] {
      artifacts = [["name": "audio_sample.mp3", "size": size, "sha256": sha256]]
    }
    // Swift 不能在 String 与 NSNull 之间自动推断 Optional.map 的合并类型。
    // 先提升为 Any，既保留失败文本，也让成功场景稳定序列化为 JSON null。
    let errorValue: Any = failure.map { String(describing: $0) } ?? NSNull()
    let payload: [String: Any] = [
      "runId": environment["LDDC_IT_RUN_ID"] ?? "missing-run-id",
      "scenario": scenario,
      "profile": "platform",
      "platform": "macos",
      "framework": "xcuitest",
      "steps": [[
        "step": scenario,
        "success": failure == nil,
        // JSONSerialization 不能编码 Optional.none，失败为空时必须显式写入 JSON null。
        "error": errorValue,
      ]],
      "capabilityEvidence": actions,
      "resources": [
        "baseline": ["nativeWindowCount": 0],
        "final": ["nativeWindowCount": cleanupVerified ? 0 : 1],
        "thresholds": ["nativeWindowCount": 0],
      ],
      "artifacts": artifacts,
      "extra": [:],
    ]
    do {
      let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
      attachment.name = "lddc-evidence-\(scenario).json"
      attachment.lifetime = .keepAlways
      add(attachment)
    } catch {
      XCTFail("无法生成 macOS XCUITest evidence: \(error)")
    }
  }
}
