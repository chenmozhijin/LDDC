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
  let diagnostics: [String: String]?
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
    // 原生动作最多使用 runner 注入给 Flutter hybrid 的 90 秒 test-only 预算。
    // 外层 120 秒场景总预算仍负责回收 xcodebuild、测试 runner 和 Flutter 进程。
    executionTimeAllowance = 90
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
      let goToFolder = panel.application.sheets["GoToWindow"]
      try require(
        goToFolder.waitForExistence(timeout: 10),
        "NSOpenPanel 的前往文件夹 sheet 没有出现"
      )
      let pathField = goToFolder.textFields["PathTextField"]
      try require(
        waitForHittableElement(pathField, timeout: 10),
        "NSOpenPanel 没有可点击的 PathTextField"
      )
      // “前往文件夹”只输入 fixture 的父目录。把完整文件路径
      // 交给该 sheet 只能证明面板关闭，不能证明列表中的文件真正
      // 被选中。进入父目录后再精确点击文件名，使原生动作与
      // Flutter 最终收到的选择结果形成同一条证据链。
      pathField.click()
      pathField.typeKey("a", modifierFlags: [.command])
      pathField.typeText(fixtureDirectory)
      try require(
        waitForStringValue(pathField, equals: fixtureDirectory, timeout: 10),
        "NSOpenPanel 的 PathTextField 没有保持完整父目录"
      )
      attachText(
        name: "lddc-macos-go-to-folder-accessibility.txt",
        value: panel.application.debugDescription
      )
      // hosted hierarchy 中 Touch Bar 的 Go 按钮处于 Disabled，不能作为稳定
      // 控件。对已经聚焦且完成值校验的原生输入框发送 Return，等价于用户在
      // Go To Folder sheet 中提交路径，同时不引入坐标或完整文件路径捷径。
      pathField.typeKey(.return, modifierFlags: [])
      try require(
        waitForElementToDisappear(goToFolder, timeout: 10),
        "NSOpenPanel 的前往文件夹 sheet 没有关闭"
      )
      try require(
        hasOpenPanelControls(panel.root),
        "前往父目录后 NSOpenPanel 主面板没有保持可操作状态"
      )
      // 在查询文件候选前保存面板树。xcresult attachment 导出可能在原生断言
      // 失败后损坏，这份前置树能保留真实 AX 角色和 identifier 证据。
      attachText(
        name: "lddc-macos-panel-before-fixture-selection.txt",
        value: panel.root.debugDescription
      )
      let directoryName = fixtureURL.deletingLastPathComponent().lastPathComponent
      let selectedDirectory = panel.root.textFields.matching(
        NSPredicate(format: "value == %@", directoryName)
      )
      try require(
        selectedDirectory.count == 1 && selectedDirectory.firstMatch.isSelected,
        "NSOpenPanel 进入父目录后没有保持当前目录列的精确选中状态"
      )
      // hosted NSOpenPanel 使用 Column View，目标文件列位于窗口右侧之外。
      // 当前目录已经选中且浏览器持有键盘焦点，右方向键会让原生列视图进入
      // 下一列并自动滚动到可见区域；这与用户键盘导航一致，不依赖屏幕坐标。
      panel.application.typeKey(.rightArrow, modifierFlags: [])
      let fixtureQuery = panel.root.textFields.matching(
        NSPredicate(format: "value == %@", fixtureName)
      )
      guard let fixture = waitForExactlyOneHittableElement(
        fixtureQuery,
        timeout: 10
      ) else {
        throw failure("NSOpenPanel 的精确 fixture TextField 不是唯一可命中目标")
      }
      attachText(
        name: "lddc-macos-panel-after-column-navigation.txt",
        value: panel.root.debugDescription
      )
      fixture.click()
      try require(
        waitForSelectedElement([fixture], timeout: 10),
        "NSOpenPanel 点击 fixture 后没有进入选中状态"
      )
      let openButton = panel.root.buttons["Open"]
      try require(
        waitForHittableElement(openButton, timeout: 10),
        "选中精确 fixture 后 NSOpenPanel 的打开按钮不可点击"
      )
      try require(openButton.isEnabled, "选中精确 fixture 后 NSOpenPanel 的打开按钮未启用")
      // AppKit 的 Column View 将文件暴露为 TextField 代理。先确认该代理已选中，
      // 再向已选中的原生面板发送 Return，让 NSOpenPanel 自己提交当前 URL。
      // 直接调用 TouchBar/按钮代理在 hosted XCUITest 中可能只关闭面板，
      // 却没有把 selection 写入 panel.urls，最终会被 file_selector 解释为取消。
      panel.application.typeKey(.return, modifierFlags: [])
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
      // XCUITest 只证明真实面板动作已经完成并关闭。Flutter 回调、文件类型和
      // 媒体结果由 integration_test 单独写入，runner 是两个进程的唯一汇合点。
      // 在这里等待 flutter_completed 会形成循环依赖：Flutter 业务失败时 XCTest
      // 先失败，runner 又会终止尚未来得及写诊断的 Flutter 进程。
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
      // 只观察 AppKit 的真实 open/save panel 服务。QuickLook 等系统服务可能
      // 在读取 accessibility 树前退出，宽泛枚举会让 XCTest 自身断言崩溃并
      // 覆盖真正的文件面板错误。
      return !application.isTerminated
        && application.bundleIdentifier == "com.apple.appkit.xpc.openAndSavePanelService"
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

  private func waitForExactlyOneHittableElement(
    _ query: XCUIElementQuery,
    timeout: TimeInterval
  ) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      let candidates = query.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
      if candidates.count == 1 {
        return candidates[0]
      }
      if candidates.count > 1 {
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
    _ candidates: [XCUIElement],
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if candidates.contains(where: { $0.exists && $0.isSelected }) {
        return true
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return false
  }

  private func waitForStringValue(
    _ element: XCUIElement,
    equals expected: String,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if element.exists, (element.value as? String) == expected {
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
          let diagnosticText = state.diagnostics?
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",") ?? "unavailable"
          throw failure(
            "Flutter hybrid 状态已经失败: \(state.error ?? "unknown"); diagnostics=\(diagnosticText)"
          )
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
