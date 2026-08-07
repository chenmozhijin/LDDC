import AppKit
import XCTest

private struct HybridSyncState: Codable {
  let schemaVersion: Int
  let runId: String
  let scenario: String
  let state: String
  let timestamp: String
  let appPid: Int32
  let appBundlePath: String
  let action: String
  let success: Bool?
  let error: String?
}

private struct PanelHandle {
  let application: XCUIApplication
  let root: XCUIElement
  let ownerIdentifier: String
  let wasNewProcess: Bool
}

final class RunnerUITests: XCTestCase {
  private let appBundleIdentifier = "com.cmzj.lddc"
  private var nativeDialogClosed = false
  private var panelOwnerIdentifier = "unresolved"
  private var panelUsedNewProcess = false

  override func setUpWithError() throws {
    continueAfterFailure = false
    nativeDialogClosed = false
    panelOwnerIdentifier = "unresolved"
    panelUsedNewProcess = false
    // 单场景只允许 60 秒。外层进程组监督器还会在 120 秒场景总预算内
    // 回收 xcodebuild、测试 runner 和被测 Flutter 进程，避免 XCTest 自身失联。
    executionTimeAllowance = 60
  }

  func testOpenPanelSelectsFixture() throws {
    try runScenario(
      scenario: "macos_open_panel_select",
      action: "ns_open_panel_select_audio"
    ) { panel in
      guard let fixturePath = ProcessInfo.processInfo.environment["LDDC_FIXTURE_PATH"] else {
        throw failure("缺少 fixture path")
      }
      let fixtureURL = URL(fileURLWithPath: fixturePath, isDirectory: false)
      let fixtureDirectory = fixtureURL.deletingLastPathComponent().path
      let fixtureName = fixtureURL.lastPathComponent
      panel.application.typeKey("g", modifierFlags: [.command, .shift])
      // “前往文件夹”是系统面板内的第二层原生 sheet。优先在实际面板拥有者中
      // 查询，再检查其 sheet；不使用屏幕坐标或图像识别兜底。
      let comboBox = panel.application.sheets.comboBoxes.firstMatch
      let textField = panel.application.sheets.textFields.firstMatch
      let rootComboBox = panel.root.comboBoxes.firstMatch
      let rootTextField = panel.root.textFields.firstMatch
      let pathFields = [comboBox, textField, rootComboBox, rootTextField]
      guard let pathField = firstHittableElement(pathFields, timeout: 10) else {
        throw failure("NSOpenPanel 没有打开可访问的前往文件夹输入框")
      }
      // “前往文件夹”只输入 fixture 的父目录。把完整文件路径
      // 交给该 sheet 只能证明面板关闭，不能证明列表中的文件真正
      // 被选中。进入父目录后再精确点击文件名，使原生动作与
      // Flutter 最终收到的选择结果形成同一条证据链。
      pathField.click()
      panel.application.typeKey("a", modifierFlags: [.command])
      pathField.typeText(fixtureDirectory)
      panel.application.typeKey(.enter, modifierFlags: [])
      try require(
        waitForElementToDisappear(pathField, timeout: 10),
        "NSOpenPanel 的前往文件夹 sheet 没有关闭"
      )
      // 在查询文件候选前保存面板树。xcresult attachment 导出可能在原生断言
      // 失败后损坏，这份前置树能保留真实 AX 角色和 identifier 证据。
      attachText(
        name: "lddc-macos-panel-before-fixture-selection.txt",
        value: panel.root.debugDescription
      )
      let fixtureCandidates = [
        panel.root.outlineRows[fixtureName],
        panel.root.cells[fixtureName],
        panel.root.staticTexts[fixtureName],
      ]
      guard let fixture = waitForExactlyOneHittableElement(
        fixtureCandidates,
        timeout: 10
      ) else {
        throw failure("NSOpenPanel 的精确 fixture 候选数量不是一个可命中目标")
      }
      fixture.click()
      try require(
        waitForSelectedElement(fixture, timeout: 10),
        "NSOpenPanel 点击 fixture 后没有进入选中状态"
      )
      let openButton = panel.root.buttons["Open"]
      try require(
        waitForHittableElement(openButton, timeout: 10),
        "选中精确 fixture 后 NSOpenPanel 的打开按钮不可点击"
      )
      try require(openButton.isEnabled, "选中精确 fixture 后 NSOpenPanel 的打开按钮未启用")
      openButton.click()
    }
  }

  func testOpenPanelCancellationReturnsToFlutter() throws {
    try runScenario(
      scenario: "macos_open_panel_cancel",
      action: "ns_open_panel_cancel"
    ) { panel in
      let cancelButton = panel.root.buttons["Cancel"]
      try require(cancelButton.waitForExistence(timeout: 10), "NSOpenPanel 没有可访问的取消按钮")
      cancelButton.click()
    }
  }

  private func runScenario(
    scenario: String,
    action: String,
    operation: (PanelHandle) throws -> Void
  ) throws {
    var actions: [String: [[String: Any]]] = [:]
    var failureValue: Error?
    var hostApplication: XCUIApplication?
    var activePanel: PanelHandle?
    do {
      let syncState = try waitForSyncState(
        scenario: scenario,
        expectedState: "picker_requested",
        timeout: 30
      )
      try require(syncState.action == expectedDialogAction(for: scenario), "hybrid action 与场景不匹配")
      let app = try exactRunningApplication(from: syncState)
      hostApplication = app
      let panelServicesBefore = currentPanelServicePids()
      let panel = try waitForOpenPanel(
        hostApplication: app,
        baselineServicePids: panelServicesBefore,
        timeout: 15
      )
      activePanel = panel
      panelOwnerIdentifier = panel.ownerIdentifier
      panelUsedNewProcess = panel.wasNewProcess
      try operation(panel)
      try require(waitForPanelToClose(panel, timeout: 15), "NSOpenPanel 操作后没有关闭")
      nativeDialogClosed = true
      _ = try waitForSyncState(
        scenario: scenario,
        expectedState: "flutter_completed",
        timeout: 15
      )
      addAction(&actions, capability: "filePicker", action: action)
      addAction(&actions, capability: "resourceCleanup", action: "native_file_panel_closed")
    } catch let error {
      failureValue = error
      let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screenshot.name = "lddc-macos-hybrid-failure.png"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      attachAccessibilityHierarchy(
        name: "lddc-macos-host-accessibility.txt",
        application: hostApplication
      )
      attachPanelServiceHierarchies()
      if let panel = activePanel, hasOpenPanelControls(panel.root) {
        let cancelButton = panel.root.buttons["Cancel"]
        if cancelButton.exists && cancelButton.isHittable {
          cancelButton.click()
          nativeDialogClosed = waitForPanelToClose(panel, timeout: 5)
        }
      }
    }
    attachEvidence(scenario: scenario, actions: actions, failure: failureValue)
    if let failureValue {
      throw failureValue
    }
  }

  private func exactRunningApplication(from state: HybridSyncState) throws -> XCUIApplication {
    guard #available(macOS 12.0, *) else {
      throw failure("精确 app URL 附着要求 macOS 12 或更高版本")
    }
    let bundleURL = URL(fileURLWithPath: state.appBundlePath, isDirectory: true)
      .resolvingSymlinksInPath().standardizedFileURL
    try require(bundleURL.pathExtension.lowercased() == "app", "hybrid marker 的 app bundle 路径无效")
    try require(
      Bundle(url: bundleURL)?.bundleIdentifier == appBundleIdentifier,
      "hybrid marker 的 app bundle identifier 不匹配"
    )
    var isDirectory: ObjCBool = false
    try require(
      FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory) && isDirectory.boolValue,
      "hybrid marker 指向的 app bundle 不存在"
    )
    guard let runningApplication = NSRunningApplication(processIdentifier: state.appPid),
          !runningApplication.isTerminated,
          let runningBundleURL = runningApplication.bundleURL?.resolvingSymlinksInPath().standardizedFileURL
    else {
      throw failure("hybrid marker 指向的应用 PID 已退出")
    }
    try require(runningBundleURL == bundleURL, "应用 PID 与 app bundle 路径不匹配")
    try require(
      runningApplication.bundleIdentifier == appBundleIdentifier,
      "应用 PID 与 LDDC bundle identifier 不匹配"
    )

    let app = XCUIApplication(url: bundleURL)
    try require(waitForRunningApplication(app, timeout: 5), "精确 app URL 没有绑定到运行中的 Flutter 应用")
    return app
  }

  private func waitForOpenPanel(
    hostApplication: XCUIApplication,
    baselineServicePids: Set<Int32>,
    timeout: TimeInterval
  ) throws -> PanelHandle {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      let hostSheet = hostApplication.sheets.firstMatch
      if hostSheet.exists && hasOpenPanelControls(hostSheet) {
        return PanelHandle(
          application: hostApplication,
          root: hostSheet,
          ownerIdentifier: "host-application",
          wasNewProcess: false
        )
      }

      // 从当前真实运行进程中定位 AppKit 的 open/save panel service。这里只创建
      // 已运行服务的 XCUIApplication 代理，避免向 notRunning application 发 query。
      for runningApplication in currentPanelServices() {
        guard let bundleIdentifier = runningApplication.bundleIdentifier else {
          continue
        }
        let panelApplication = XCUIApplication(bundleIdentifier: bundleIdentifier)
        guard panelApplication.state != .notRunning else {
          continue
        }
        let serviceSheet = panelApplication.sheets.firstMatch
        if serviceSheet.exists && hasOpenPanelControls(serviceSheet) {
          return PanelHandle(
            application: panelApplication,
            root: serviceSheet,
            ownerIdentifier: bundleIdentifier,
            wasNewProcess: !baselineServicePids.contains(runningApplication.processIdentifier)
          )
        }
        let serviceWindow = panelApplication.windows.firstMatch
        if serviceWindow.exists && hasOpenPanelControls(serviceWindow) {
          return PanelHandle(
            application: panelApplication,
            root: serviceWindow,
            ownerIdentifier: bundleIdentifier,
            wasNewProcess: !baselineServicePids.contains(runningApplication.processIdentifier)
          )
        }
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    throw failure("没有在 host app 或运行中的 open/save panel service 中发现生产 NSOpenPanel")
  }

  private func currentPanelServices() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { application in
      guard !application.isTerminated else {
        return false
      }
      let identity = [
        application.bundleIdentifier,
        application.localizedName,
        application.bundleURL?.lastPathComponent,
        application.executableURL?.lastPathComponent,
      ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
      return identity.contains("openandsavepanel") || identity.contains("open and save panel")
    }
  }

  private func currentPanelServicePids() -> Set<Int32> {
    Set(currentPanelServices().map(\.processIdentifier))
  }

  private func hasOpenPanelControls(_ root: XCUIElement) -> Bool {
    guard root.buttons["Cancel"].exists else {
      return false
    }
    return root.buttons["Open"].exists
      || root.buttons["Choose"].exists
      || root.buttons["Save"].exists
  }

  private func waitForPanelToClose(_ panel: PanelHandle, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if panel.application.state == .notRunning || !hasOpenPanelControls(panel.root) {
        return true
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return false
  }

  private func firstHittableElement(
    _ candidates: [XCUIElement],
    timeout: TimeInterval
  ) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let element = candidates.first(where: { $0.exists && $0.isHittable }) {
        return element
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
  }

  private func waitForExactlyOneHittableElement(
    _ candidates: [XCUIElement],
    timeout: TimeInterval
  ) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      let hittable = candidates.filter { $0.exists && $0.isHittable }
      if hittable.count == 1 {
        return hittable[0]
      }
      // 多个精确 AX 节点同时可命中时立即失败，避免随机选择造成假绿。
      if hittable.count > 1 {
        return nil
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
  }

  private func waitForHittableElement(
    _ element: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    firstHittableElement([element], timeout: timeout) != nil
  }

  private func waitForSelectedElement(
    _ element: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if element.exists && element.isSelected {
        return true
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return false
  }

  private func waitForElementToDisappear(
    _ element: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if !element.exists {
        return true
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return false
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

  private func waitForSyncState(
    scenario: String,
    expectedState: String,
    timeout: TimeInterval
  ) throws -> HybridSyncState {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let state = try readSyncState(scenario: scenario) {
        try validateSyncState(state, scenario: scenario)
        if state.state == "flutter_failed" {
          throw failure("Flutter hybrid 状态已经失败: \(state.error ?? "unknown")")
        }
        if state.state == expectedState {
          return state
        }
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw failure("等待 macOS hybrid 状态 \(expectedState) 超时")
  }

  private func readSyncState(scenario: String) throws -> HybridSyncState? {
    let url = try syncStateURL(scenario: scenario)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    do {
      return try JSONDecoder().decode(HybridSyncState.self, from: Data(contentsOf: url))
    } catch {
      throw failure("macOS hybrid 状态文件损坏: \(error)")
    }
  }

  private func syncStateURL(scenario: String) throws -> URL {
    guard let root = ProcessInfo.processInfo.environment["LDDC_MACOS_HYBRID_SYNC_DIR"],
          !root.isEmpty
    else {
      throw failure("缺少 macOS hybrid sync 目录")
    }
    return URL(fileURLWithPath: root, isDirectory: true)
      .appendingPathComponent("\(scenario).state.json", isDirectory: false)
  }

  private func validateSyncState(_ state: HybridSyncState, scenario: String) throws {
    let environment = ProcessInfo.processInfo.environment
    try require(state.schemaVersion == 1, "macOS hybrid 状态 schema 不受支持")
    try require(state.runId == environment["LDDC_IT_RUN_ID"], "macOS hybrid runId 不匹配")
    try require(state.scenario == scenario, "macOS hybrid scenario 不匹配")
    try require(state.appPid > 0, "macOS hybrid app PID 无效")
    try require(!state.appBundlePath.isEmpty, "macOS hybrid app bundle path 为空")
  }

  private func expectedDialogAction(for scenario: String) -> String {
    scenario.hasSuffix("_select") ? "select" : "cancel"
  }

  private func attachAccessibilityHierarchy(name: String, application: XCUIApplication?) {
    guard let application,
          application.state != .notRunning
    else {
      return
    }
    attachText(name: name, value: application.debugDescription)
  }

  private func attachPanelServiceHierarchies() {
    for application in currentPanelServices() {
      guard let bundleIdentifier = application.bundleIdentifier else {
        continue
      }
      let proxy = XCUIApplication(bundleIdentifier: bundleIdentifier)
      guard proxy.state != .notRunning else {
        continue
      }
      attachText(
        name: "lddc-macos-panel-service-\(application.processIdentifier).txt",
        value: proxy.debugDescription
      )
    }
  }

  private func attachText(name: String, value: String) {
    guard let data = value.data(using: .utf8) else {
      return
    }
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
      // continueAfterFailure=false 时先调用 XCTFail 会立即中断当前方法，使外层
      // catch 需要继续保存截图、evidence 和清理面板。直接抛错后
      // 由 XCTest 记录 thrown error，不会跳过完整的 hybrid 诊断链路。
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
      "extra": [
        "attachedToExistingApplication": true,
        "usedExactApplicationURL": true,
        "changedApplicationActivationState": false,
        "panelOwnerIdentifier": panelOwnerIdentifier,
        "panelUsedNewProcess": panelUsedNewProcess,
      ],
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
