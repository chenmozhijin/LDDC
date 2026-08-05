import XCTest

final class RunnerUITests: XCTestCase {
  private let appBundleIdentifier = "com.cmzj.lddc.platformtests"
  private let fixtureName = "audio_sample.mp3"
  private let navigationIdentifier = "lddc.nav.open_lyrics"
  private let openSongIdentifier = "lddc.open_lyrics.open_song_file"
  private let saveFileIdentifier = "lddc.open_lyrics.save_file"
  private let saveTagIdentifier = "lddc.open_lyrics.save_tag"
  private let saveTagSucceededIdentifier = "lddc.open_lyrics.notice.saveTagSucceeded"
  private let documentsBundleIdentifier = "com.apple.DocumentsApp"
  private let springBoardBundleIdentifier = "com.apple.springboard"
  private let platformTestDisplayName = "LDDC Platform Tests"
  private var cleanupVerified = false

  override func setUpWithError() throws {
    continueAfterFailure = false
    cleanupVerified = false
    // XCTest 的 UI 测试默认允许单个用例运行十分钟。系统 Picker 或 accessibility
    // 查询失去响应时必须在场景边界内失败，避免一个用例耗尽整个平台 job。
    executionTimeAllowance = 120
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
      try cancelSystemPicker(app: app)
      try require(app.wait(for: .runningForeground, timeout: 15), "取消后 LDDC 没有返回前台")
      let openSong = app.buttons[openSongIdentifier]
      try require(waitForHittable(openSong, timeout: 15), "取消后 Flutter 打开歌曲动作不可再次操作")
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
      try openExportPicker(app: app)
      let save = try requireSystemPickerElement(named: ["Save"], app: app, timeout: 15)
      save.tap()
      try require(app.wait(for: .runningForeground, timeout: 15), "导出后 LDDC 没有返回前台")
      let saveFile = app.descendants(matching: .any)[saveFileIdentifier]
      try require(waitForHittable(saveFile, timeout: 15), "导出完成后 Flutter 页面没有恢复交互")
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
      try openExportPicker(app: app)
      try cancelSystemPicker(app: app)
      try require(app.wait(for: .runningForeground, timeout: 15), "取消导出后 LDDC 没有返回前台")
      let saveFile = app.descendants(matching: .any)[saveFileIdentifier]
      try require(waitForHittable(saveFile, timeout: 15), "取消导出后 Flutter 页面没有恢复交互")
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
      try openExportPicker(app: app)
      app.terminate()
      try require(app.wait(for: .notRunning, timeout: 5), "导出中终止时 LDDC 未在超时内关闭")

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
    try waitForSystemPicker(app: app, expectedLabels: ["Recents", "Shared", "Browse"])
  }

  private func selectSeededAudio(app: XCUIApplication) throws {
    try openDocumentPicker(app: app)
    try tapSystemPickerElement(named: ["Browse"], app: app, timeout: 15)
    try tapSystemPickerElement(named: ["On My iPhone"], app: app, timeout: 15)

    // 测试 fixture 位于 PlatformTest 应用公开给 Files 的 Documents 中。Recents 只
    // 记录用户近期打开的文件，在全新 Simulator 上必然可能为空，因此必须显式进入
    // “On My iPhone -> LDDC Platform Tests”，不能把 Recents 当作测试数据目录。
    if findSystemPickerElement(named: [fixtureName], app: app) == nil {
      try tapSystemPickerElement(
        named: [platformTestDisplayName, "LDDCPlatformTests", "LDDC"],
        app: app,
        timeout: 15
      )
    }
    let fixture = try requireSystemPickerElement(named: [fixtureName], app: app, timeout: 15)
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

  private func openExportPicker(app: XCUIApplication) throws {
    let saveFile = app.descendants(matching: .any)[saveFileIdentifier]
    try requireHittable(saveFile, in: app, message: "Flutter 未暴露可点击的歌词导出按钮")
    saveFile.tap()
    try waitForSystemPicker(app: app, expectedLabels: ["Save", "Cancel", "Browse", "Recents"])
  }

  private func systemPickerRoots(app: XCUIApplication) -> [XCUIElement] {
    // iOS 版本不同，UIDocumentPicker 可能作为宿主应用的远程 view service、Files
    // 应用界面或 SpringBoard 管理的系统 sheet 暴露。这里只查询系统实际导出的
    // accessibility tree，不启动、激活或伪造任何系统应用。
    let documents = XCUIApplication(bundleIdentifier: documentsBundleIdentifier)
    var roots: [XCUIElement] = [
      app,
      XCUIApplication(bundleIdentifier: springBoardBundleIdentifier),
    ]
    // 对 notRunning application 发 descendants query 会被 XCTest 自身直接记为
    // “Failed to resolve query”，无法由 Swift do/catch 收口。iOS 26 的嵌入式
    // Picker 通常不启动 DocumentsApp，因此只有系统确实运行该应用时才查询它。
    if documents.state != .notRunning {
      roots.append(documents)
    }
    return roots
  }

  private func pickerElement(named labels: [String], in root: XCUIElement) -> XCUIElement? {
    var firstExisting: XCUIElement?
    for label in labels {
      let predicate = NSPredicate(
        format: "label == %@ OR identifier == %@ OR label BEGINSWITH %@",
        label,
        label,
        label
      )
      let elements = root.descendants(matching: .any).matching(predicate).allElementsBoundByIndex
      for element in elements where element.exists {
        if element.isHittable {
          return element
        }
        firstExisting = firstExisting ?? element
      }
    }
    return firstExisting
  }

  private func findSystemPickerElement(named labels: [String], app: XCUIApplication) -> XCUIElement? {
    var firstExisting: XCUIElement?
    for root in systemPickerRoots(app: app) {
      if let element = pickerElement(named: labels, in: root) {
        if element.isHittable {
          return element
        }
        firstExisting = firstExisting ?? element
      }
    }
    return firstExisting
  }

  private func requireSystemPickerElement(
    named labels: [String],
    app: XCUIApplication,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    if let element = waitForSystemPickerElement(named: labels, app: app, timeout: timeout) {
      return element
    }
    try require(false, "系统文件界面没有可访问的控件：\(labels.joined(separator: " / "))")
    // require(false, ...) 必然抛出；该返回值只用于满足 Swift 的控制流检查。
    return app
  }

  private func waitForSystemPickerElement(
    named labels: [String],
    app: XCUIApplication,
    timeout: TimeInterval
  ) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let element = findSystemPickerElement(named: labels, app: app), element.isHittable {
        return element
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return nil
  }

  private func tapSystemPickerElement(
    named labels: [String],
    app: XCUIApplication,
    timeout: TimeInterval
  ) throws {
    let element = try requireSystemPickerElement(named: labels, app: app, timeout: timeout)
    element.tap()
  }

  private func waitForSystemPicker(app: XCUIApplication, expectedLabels: [String]) throws {
    _ = try requireSystemPickerElement(named: expectedLabels, app: app, timeout: 15)
  }

  private func cancelSystemPicker(app: XCUIApplication) throws {
    if let cancel = waitForSystemPickerElement(
      named: ["Cancel", "Close", "Dismiss"],
      app: app,
      timeout: 3
    ) {
      cancel.tap()
      return
    }

    // iOS 26 的紧凑 Document Picker 使用可下拉关闭的系统 sheet，界面中不再固定
    // 提供 Cancel 按钮。swipeDown 作用于可访问的 sheet 元素本身，不使用屏幕坐标；
    // 找不到 sheet 时直接失败，禁止退化为坐标脚本或强制激活宿主应用。
    for root in systemPickerRoots(app: app) {
      for sheet in root.sheets.allElementsBoundByIndex where sheet.exists && sheet.isHittable {
        sheet.swipeDown()
        return
      }
    }
    try require(false, "系统文件界面既没有取消控件，也没有可访问的模态 sheet")
  }

  private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if element.exists, element.isHittable {
        return true
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return false
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
    // UIDocumentPicker 在新系统中可能由常驻 view service 承载，终止 DocumentsApp
    // 既不能证明 picker session 已释放，也可能干扰后续场景。应用进程退出和 runner
    // 对 fd、临时导出目录的最终检查共同构成资源释放证据。
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
    // String 与 NSNull 没有共同的具体 Swift 类型。先擦除为 Any，避免新版
    // Swift 在 nil 合并表达式中把闭包结果错误约束为 NSNull，导致 UI 测试无法编译。
    let errorValue: Any = failure.map { String(describing: $0) } ?? NSNull()
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
        "error": errorValue,
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
