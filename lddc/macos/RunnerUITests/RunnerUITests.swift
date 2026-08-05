import XCTest

final class RunnerUITests: XCTestCase {
  private let appBundleIdentifier = "com.cmzj.lddc"
  private var nativeDialogClosed = false

  override func setUpWithError() throws {
    continueAfterFailure = false
    nativeDialogClosed = false
    // 系统面板或 accessibility 附着失去响应时，让 XCTest 在单场景边界内失败；
    // 外层 runner 仍负责终止完整 xcodebuild 进程树并收集诊断。
    executionTimeAllowance = 120
  }

  func testOpenPanelSelectsFixture() throws {
    try runScenario(
      scenario: "macos_open_panel_select",
      action: "ns_open_panel_select_audio"
    ) { app, panel in
      guard let fixturePath = ProcessInfo.processInfo.environment["LDDC_FIXTURE_PATH"] else {
        throw failure("缺少 fixture path")
      }
      app.typeKey("g", modifierFlags: [.command, .shift])
      // “前往文件夹”会在 NSOpenPanel 上再打开一层原生 sheet。不同 macOS
      // 版本会把同一输入框暴露为 comboBox 或 textField，因此按原生控件类型
      // 依次查询；仍然只使用 accessibility 元素，不使用坐标回退。
      let comboBox = app.sheets.comboBoxes.firstMatch
      let textField = app.sheets.textFields.firstMatch
      let pathField = comboBox.waitForExistence(timeout: 3) ? comboBox : textField
      try require(pathField.waitForExistence(timeout: 10), "NSOpenPanel 没有打开前往文件夹输入框")
      pathField.typeText(fixturePath)
      app.typeKey(.enter, modifierFlags: [])
      let openButton = panel.buttons["Open"]
      try require(openButton.waitForExistence(timeout: 10), "NSOpenPanel 没有可访问的打开按钮")
      openButton.click()
    }
  }

  func testOpenPanelCancellationReturnsToFlutter() throws {
    try runScenario(
      scenario: "macos_open_panel_cancel",
      action: "ns_open_panel_cancel"
    ) { _, panel in
      let cancelButton = panel.buttons["Cancel"]
      try require(cancelButton.waitForExistence(timeout: 10), "NSOpenPanel 没有可访问的取消按钮")
      cancelButton.click()
    }
  }

  private func runScenario(
    scenario: String,
    action: String,
    operation: (XCUIApplication, XCUIElement) throws -> Void
  ) throws {
    var actions: [String: [[String: Any]]] = [:]
    var failureValue: Error?
    let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
    do {
      // Flutter integration_test 已经启动应用并请求了生产文件选择器。这里禁止
      // launch/activate，也不查询 Flutter semantics，只附着并操作已经打开的原生 sheet。
      try require(waitForRunningApplication(app, timeout: 15), "Flutter integration_test 没有保持 LDDC 运行")
      let panel = app.sheets.firstMatch
      try require(panel.waitForExistence(timeout: 20), "Flutter 没有打开可访问的生产 NSOpenPanel")
      try operation(app, panel)
      try require(waitForElementToDisappear(panel, timeout: 15), "NSOpenPanel 操作后没有关闭")
      nativeDialogClosed = true
      addAction(&actions, capability: "filePicker", action: action)
      addAction(&actions, capability: "resourceCleanup", action: "native_file_panel_closed")
    } catch let error {
      failureValue = error
      let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screenshot.name = "lddc-macos-hybrid-failure.png"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    }
    attachEvidence(scenario: scenario, actions: actions, failure: failureValue)
    if let failureValue {
      throw failureValue
    }
  }

  private func waitForRunningApplication(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if app.state == .runningForeground || app.state == .runningBackground {
        return true
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return false
  }

  private func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: element
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
      XCTFail(message)
      throw failure(message)
    }
  }

  private func failure(_ message: String) -> NSError {
    NSError(
      domain: "LDDCMacOsHybridTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
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
    let errorValue: Any = failure.map { String(describing: $0) } ?? NSNull()
    let payload: [String: Any] = [
      "runId": environment["LDDC_IT_RUN_ID"] ?? "missing-run-id",
      "scenario": scenario,
      "profile": "platform",
      "platform": "macos",
      "framework": "integration_test+xcuitest",
      "steps": [[
        "step": "xcuitest_native_panel_action",
        "success": failure == nil,
        "error": errorValue,
      ]],
      "capabilityEvidence": actions,
      "resources": [
        "baseline": ["nativeDialogCount": 0],
        "final": ["nativeDialogCount": nativeDialogClosed ? 0 : 1],
        "thresholds": ["nativeDialogCount": 0],
      ],
      "artifacts": [],
      "extra": ["attachedToExistingApplication": true],
    ]
    do {
      let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
      attachment.name = "lddc-evidence-\(scenario).json"
      attachment.lifetime = .keepAlways
      add(attachment)
    } catch {
      XCTFail("无法生成 macOS hybrid evidence: \(error)")
    }
  }
}
