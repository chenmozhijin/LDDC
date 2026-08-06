import XCTest

private struct SystemPickerContext {
  let root: XCUIElement
}

final class RunnerUITests: XCTestCase {
  private let appBundleIdentifier = "com.cmzj.lddc.platformtests"
  private let fixtureName = "audio_sample.mp3"
  private let fixtureAccessibilityName = "audio_sample, mp3"
  private let navigationIdentifier = "lddc.nav.open_lyrics"
  private let openSongIdentifier = "lddc.open_lyrics.open_song_file"
  private let saveFileIdentifier = "lddc.open_lyrics.save_file"
  private let saveTagIdentifier = "lddc.open_lyrics.save_tag"
  private let saveTagSucceededIdentifier = "lddc.open_lyrics.notice.saveTagSucceeded"
  private let documentsBundleIdentifier = "com.apple.DocumentsApp"
  private let springBoardBundleIdentifier = "com.apple.springboard"
  private let documentBrowsingRootPrefix = "DOC.browsingRoot Source: "
  private let platformTestDisplayName = "LDDC Platform Tests"
  private var cleanupVerified = false
  private var cleanupDiagnostics: [String: Any] = [:]

  override func setUpWithError() throws {
    continueAfterFailure = false
    cleanupVerified = false
    cleanupDiagnostics = [:]
    // XCTest 的 UI 测试默认允许单个用例运行十分钟。系统 Picker 或 accessibility
    // 查询失去响应时必须在场景边界内失败，避免一个用例耗尽整个平台 job。
    executionTimeAllowance = 120
  }

  func testDocumentPickerSelectsSeededAudio() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    var app: XCUIApplication?
    do {
      let launchedApp = try launchApp()
      app = launchedApp
      try selectSeededAudio(app: launchedApp)
      addAction(&actions, capability: "filePicker", action: "document_picker_select_audio")
      addAction(&actions, capability: "nativeChannels", action: "flutter_picker_round_trip")
      addAction(&actions, capability: "media", action: "security_scoped_fd_read_embedded_lyrics")

      let saveTag = launchedApp.descendants(matching: .any)[saveTagIdentifier]
      try requireHittable(saveTag, in: launchedApp, message: "Flutter 未暴露可点击的写入歌曲标签按钮")
      saveTag.tap()
      let saveSucceeded = launchedApp.descendants(matching: .any)[saveTagSucceededIdentifier]
      try require(saveSucceeded.waitForExistence(timeout: 20), "读写 fd 升级后没有成功保存歌词标签")
      addAction(&actions, capability: "media", action: "read_write_fd_tag_saved")

      // 终止应用会触发 fd registry 与 security-scoped 资源清理；重新启动并再次
      // 经系统 Picker 回读，才能证明写入不是同一 TagLib 会话缓存造成的假绿。
      try terminateAndVerify(launchedApp)
      relaunchPreservingFixture(launchedApp)
      try selectSeededAudio(app: launchedApp)
      addAction(&actions, capability: "media", action: "saved_tag_reopened_after_app_restart")
      try terminateAndVerify(launchedApp)
      addAction(&actions, capability: "resourceCleanup", action: "application_and_picker_closed")
    } catch let error {
      failure = error
    }
    captureFailureAndCleanup(app: app, scenario: "ios_document_picker_select", failure: failure)
    attachEvidence(scenario: "ios_document_picker_select", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testDocumentPickerCancellationReturnsToFlutter() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    var app: XCUIApplication?
    do {
      let launchedApp = try launchApp()
      app = launchedApp
      _ = try openDocumentPicker(app: launchedApp)
      try cancelSystemPicker(app: launchedApp)
      try require(launchedApp.wait(for: .runningForeground, timeout: 15), "取消后 LDDC 没有返回前台")
      let openSong = launchedApp.buttons[openSongIdentifier]
      try require(waitForHittable(openSong, timeout: 15), "取消后 Flutter 打开歌曲动作不可再次操作")
      addAction(&actions, capability: "filePicker", action: "document_picker_cancel")
      addAction(&actions, capability: "nativeChannels", action: "flutter_picker_cancel_round_trip")
      try terminateAndVerify(launchedApp)
      addAction(&actions, capability: "resourceCleanup", action: "application_and_picker_closed")
    } catch let error {
      failure = error
    }
    captureFailureAndCleanup(app: app, scenario: "ios_document_picker_cancel", failure: failure)
    attachEvidence(scenario: "ios_document_picker_cancel", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testDocumentPickerExportsLyricsFile() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    var app: XCUIApplication?
    do {
      let launchedApp = try launchApp()
      app = launchedApp
      try selectSeededAudio(app: launchedApp)
      let picker = try openExportPicker(app: launchedApp)
      let save = try requireTypedButton(named: "Save", in: picker, timeout: 15)
      save.tap()
      try require(waitForSystemPickerToClose(app: launchedApp, timeout: 15), "导出保存后系统文件界面没有关闭")
      try require(launchedApp.wait(for: .runningForeground, timeout: 15), "导出后 LDDC 没有返回前台")
      let saveFile = launchedApp.descendants(matching: .any)[saveFileIdentifier]
      try require(waitForHittable(saveFile, timeout: 15), "导出完成后 Flutter 页面没有恢复交互")
      addAction(&actions, capability: "filePicker", action: "document_picker_export_lyrics")
      addAction(&actions, capability: "nativeChannels", action: "flutter_export_round_trip")
      try terminateAndVerify(launchedApp)
      addAction(&actions, capability: "resourceCleanup", action: "export_source_and_picker_closed")
    } catch let error {
      failure = error
    }
    captureFailureAndCleanup(app: app, scenario: "ios_document_picker_export", failure: failure)
    attachEvidence(scenario: "ios_document_picker_export", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testDocumentPickerExportCancellationCleansTemporaryFile() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    var app: XCUIApplication?
    do {
      let launchedApp = try launchApp()
      app = launchedApp
      try selectSeededAudio(app: launchedApp)
      _ = try openExportPicker(app: launchedApp)
      try cancelSystemPicker(app: launchedApp)
      try require(launchedApp.wait(for: .runningForeground, timeout: 15), "取消导出后 LDDC 没有返回前台")
      let saveFile = launchedApp.descendants(matching: .any)[saveFileIdentifier]
      try require(waitForHittable(saveFile, timeout: 15), "取消导出后 Flutter 页面没有恢复交互")
      addAction(&actions, capability: "filePicker", action: "document_picker_export_cancel")
      addAction(&actions, capability: "nativeChannels", action: "flutter_export_cancel_round_trip")
      try terminateAndVerify(launchedApp)
      addAction(&actions, capability: "resourceCleanup", action: "cancelled_export_source_removed")
    } catch let error {
      failure = error
    }
    captureFailureAndCleanup(app: app, scenario: "ios_document_picker_export_cancel", failure: failure)
    attachEvidence(scenario: "ios_document_picker_export_cancel", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  func testTerminatedExportIsCleanedOnNextLaunch() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    var app: XCUIApplication?
    do {
      let launchedApp = try launchApp()
      app = launchedApp
      try selectSeededAudio(app: launchedApp)
      _ = try openExportPicker(app: launchedApp)
      launchedApp.terminate()
      try require(launchedApp.wait(for: .notRunning, timeout: 5), "导出中终止时 LDDC 未在超时内关闭")

      // 强制终止不保证 iOS 发送生命周期回调；下一次插件初始化必须删除上次
      // 遗留的临时导出目录，runner 会从 Simulator 容器进行最终空目录断言。
      relaunchPreservingFixture(launchedApp)
      try require(launchedApp.wait(for: .runningForeground, timeout: 15), "导出中终止后 LDDC 无法重新启动")
      addAction(&actions, capability: "filePicker", action: "document_picker_export_interrupted")
      addAction(&actions, capability: "nativeChannels", action: "save_text_request_interrupted_and_plugin_reinitialized")
      addAction(&actions, capability: "resourceCleanup", action: "stale_export_removed_on_next_launch")
      try terminateAndVerify(launchedApp)
    } catch let error {
      failure = error
    }
    captureFailureAndCleanup(app: app, scenario: "ios_document_picker_export_termination", failure: failure)
    attachEvidence(scenario: "ios_document_picker_export_termination", actions: actions, failure: failure)
    if let failure {
      throw failure
    }
  }

  private func launchApp() throws -> XCUIApplication {
    let environment = ProcessInfo.processInfo.environment
    guard let fixtureBase64 = environment["LDDC_FIXTURE_BASE64"],
          !fixtureBase64.isEmpty
    else {
      // 每个测试方法都有名为 failure 的局部变量，不能把它误当成错误构造函数。
      // 统一通过 testFailure 创建 NSError，既避免 Swift 名称遮蔽，也让 XCTest
      // 和结构化 evidence 得到相同的可读错误消息。
      throw testFailure("XCUITest 缺少匿名 fixture base64")
    }
    let app = XCUIApplication(bundleIdentifier: appBundleIdentifier)
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    // PlatformTest app 可能由 xcodebuild 在测试开始前重新安装。通过仅限测试配置
    // 的 launch environment 在应用实际启动时写入 Documents，避免依赖旧容器路径。
    app.launchEnvironment["LDDC_PLATFORM_TEST_FIXTURE_NAME"] = fixtureName
    app.launchEnvironment["LDDC_PLATFORM_TEST_FIXTURE_BASE64"] = fixtureBase64
    app.launchEnvironment["LDDC_PLATFORM_TEST_RESET_FIXTURES"] = "1"
    app.launch()
    return app
  }

  private func relaunchPreservingFixture(_ app: XCUIApplication) {
    // 同一场景内重启必须保留刚写入的标签或待清理的临时导出目录，不能再次
    // 执行场景级 reset；下一个独立 XCTest 会创建新的 app 代理并重新置为 1。
    app.launchEnvironment["LDDC_PLATFORM_TEST_RESET_FIXTURES"] = "0"
    app.launch()
  }

  private func openDocumentPicker(app: XCUIApplication) throws -> SystemPickerContext {
    let navigation = app.buttons[navigationIdentifier]
    try require(
      navigation.waitForExistence(timeout: 15),
      "Flutter 没有向 XCUITest 暴露打开歌词导航 identifier"
    )
    navigation.tap()
    let openSong = app.buttons[openSongIdentifier]
    try require(openSong.waitForExistence(timeout: 15), "Flutter 没有暴露打开歌曲按钮 identifier")
    openSong.tap()
    return try waitForSystemPicker(app: app, timeout: 15)
  }

  private func selectSeededAudio(app: XCUIApplication) throws {
    var picker = try openDocumentPicker(app: app)

    // Files 会记住上次的目录。先仅查找 typed file cell，可以处理
    // 已在 fixture 目录的情况，也不会把 Picker 容器或菜单按钮误当成文件。
    if let fixture = waitForFixtureCell(in: picker, timeout: 1) {
      try selectFixture(fixture, app: app)
      return
    }
    if let folder = waitForPlatformTestFolder(in: picker, timeout: 1) {
      folder.tap()
      picker = try waitForSystemPicker(app: app, timeout: 5)
      let fixture = try requireFixtureCell(in: picker, timeout: 15)
      try selectFixture(fixture, app: app)
      return
    }

    let browse = try requireBrowseButton(in: picker, timeout: 15)
    browse.tap()
    try require(
      waitForBrowseDestination(app: app, timeout: 15),
      "点击 Browse 后没有进入可访问的位置或目录页"
    )
    picker = try waitForSystemPicker(app: app, timeout: 5)

    if let fixture = waitForFixtureCell(in: picker, timeout: 1) {
      try selectFixture(fixture, app: app)
      return
    }
    if let folder = waitForPlatformTestFolder(in: picker, timeout: 1) {
      folder.tap()
    } else {
      // 只允许点击位置页的真实 On My iPhone 按钮。BackButton 即使
      // 使用相同 label 也必须排除，避免再次把返回动作误当成位置导航。
      let onMyIPhone = picker.root.buttons.matching(
        NSPredicate(format: "label ==[c] %@ AND identifier != %@", "On My iPhone", "BackButton")
      ).firstMatch
      try require(waitForHittable(onMyIPhone, timeout: 15), "Browse 中没有可点击的 On My iPhone 位置")
      onMyIPhone.tap()
      picker = try waitForSystemPicker(app: app, timeout: 5)
      let folder = try requirePlatformTestFolder(in: picker, timeout: 15)
      folder.tap()
    }

    picker = try waitForSystemPicker(app: app, timeout: 5)
    let fixture = try requireFixtureCell(in: picker, timeout: 15)
    try selectFixture(fixture, app: app)
  }

  private func selectFixture(_ fixture: XCUIElement, app: XCUIApplication) throws {
    try require(fixture.exists && fixture.isHittable, "匿名音频 fixture 不可点击")
    fixture.tap()
    try require(waitForSystemPickerToClose(app: app, timeout: 15), "选择文件后系统 Picker 没有关闭")
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

  private func openExportPicker(app: XCUIApplication) throws -> SystemPickerContext {
    let saveFile = app.descendants(matching: .any)[saveFileIdentifier]
    try requireHittable(saveFile, in: app, message: "Flutter 未暴露可点击的歌词导出按钮")
    saveFile.tap()
    return try waitForSystemPicker(app: app, timeout: 15)
  }

  private func systemPickerContext(app: XCUIApplication) -> SystemPickerContext? {
    // iOS 26 可以把 Document Picker 作为宿主应用内的远程 view
    // service 暴露，此时 hosted runner 实际提供的是 DOC.browsingRoot
    // typed Other，而不是旧系统的 Browse View (Picker)。两者均限定为
    // 系统文档浏览根节点，不使用通用 .any、进程前台状态或 SpringBoard。
    if let hostedRoot = typedSystemPickerRoot(in: app) {
      return SystemPickerContext(root: hostedRoot)
    }
    let documents = XCUIApplication(bundleIdentifier: documentsBundleIdentifier)
    if documents.state != .notRunning,
       let documentsRoot = typedSystemPickerRoot(in: documents) {
      return SystemPickerContext(root: documentsRoot)
    }
    return nil
  }

  private func typedSystemPickerRoot(in application: XCUIApplication) -> XCUIElement? {
    let documentBrowsingRoot = application.otherElements.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", documentBrowsingRootPrefix)
    ).firstMatch
    if documentBrowsingRoot.exists {
      return documentBrowsingRoot
    }

    let legacyRoot = application.otherElements["Browse View (Picker)"]
    return legacyRoot.exists ? legacyRoot : nil
  }

  private func waitForSystemPicker(
    app: XCUIApplication,
    timeout: TimeInterval
  ) throws -> SystemPickerContext {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let picker = systemPickerContext(app: app) {
        return picker
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    throw testFailure("系统文件界面没有暴露 typed Document Picker 根节点")
  }

  private func waitForSystemPickerToClose(
    app: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if systemPickerContext(app: app) == nil {
        return true
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return false
  }

  private func requireTypedButton(
    named name: String,
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    // iOS 26 的远程 Document Picker 会在 hierarchy 中暴露精确的
    // typed Button，但对同一子树使用 NSPredicate + firstMatch 会得到
    // 不可点击的查询代理。使用 XCUITest 原生精确下标同时限定
    // 了控件类型和名称，不依赖坐标、contains 或系统进程前台状态。
    let button = picker.root.buttons[name]
    try require(waitForHittable(button, timeout: timeout), "系统文件界面没有可点击的 \(name) 按钮")
    return button
  }

  private func requireBrowseButton(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    // 远程 Document Picker 的 TabBar 代理在 iOS 26 上可能存在但自身不可命中，
    // 子按钮仍然可以直接操作。只查询 typed Browse Button，避免把容器的
    // isHittable 状态误当成系统文件界面不可用，也不回退到坐标点击。
    let browse = picker.root.buttons["Browse"]
    try require(waitForHittable(browse, timeout: timeout), "系统文件界面没有可点击的 Browse 按钮")
    return browse
  }

  private func fixtureCell(in picker: SystemPickerContext) -> XCUIElement {
    picker.root.cells.matching(
      NSPredicate(
        format: "label BEGINSWITH[c] %@ OR identifier BEGINSWITH[c] %@",
        fixtureAccessibilityName,
        fixtureAccessibilityName
      )
    ).firstMatch
  }

  private func waitForFixtureCell(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) -> XCUIElement? {
    let cell = fixtureCell(in: picker)
    return waitForHittable(cell, timeout: timeout) ? cell : nil
  }

  private func requireFixtureCell(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    guard let cell = waitForFixtureCell(in: picker, timeout: timeout) else {
      throw testFailure("系统文件界面没有可点击的 \(fixtureAccessibilityName) 文件单元格")
    }
    return cell
  }

  private func waitForPlatformTestFolder(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) -> XCUIElement? {
    let predicate = NSPredicate(
      format: "label BEGINSWITH[c] %@ OR identifier BEGINSWITH[c] %@",
      "\(platformTestDisplayName),",
      "\(platformTestDisplayName),"
    )
    return waitForFirstHittable(
      { [picker.root.cells.matching(predicate).firstMatch, picker.root.links.matching(predicate).firstMatch] },
      timeout: timeout
    )
  }

  private func requirePlatformTestFolder(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    guard let folder = waitForPlatformTestFolder(in: picker, timeout: timeout) else {
      throw testFailure("系统文件界面没有可点击的 \(platformTestDisplayName) 目录单元格")
    }
    return folder
  }

  private func waitForBrowseDestination(app: XCUIApplication, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let picker = systemPickerContext(app: app) {
        let location = picker.root.buttons.matching(
          NSPredicate(format: "label ==[c] %@ AND identifier != %@", "On My iPhone", "BackButton")
        ).firstMatch
        if (location.exists && location.isHittable)
          || waitForFixtureCell(in: picker, timeout: 0) != nil
          || waitForPlatformTestFolder(in: picker, timeout: 0) != nil {
          return true
        }
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return false
  }

  private func waitForFirstHittable(
    _ candidates: () -> [XCUIElement],
    timeout: TimeInterval
  ) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let element = candidates().first(where: { $0.exists && $0.isHittable }) {
        return element
      }
      if timeout == 0 {
        return nil
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
  }

  private func cancelSystemPicker(app: XCUIApplication) throws {
    let picker = try waitForSystemPicker(app: app, timeout: 5)
    let cancel = picker.root.buttons["Cancel"]
    if cancel.exists {
      try require(waitForHittable(cancel, timeout: 3), "系统 Picker 的 typed Cancel 按钮存在但不可点击")
      cancel.tap()
      try require(waitForSystemPickerToClose(app: app, timeout: 10), "点击 Cancel 后系统 Picker 没有关闭")
      return
    }

    // 只有 typed Cancel 按钮确实不存在时，紧凑 Picker 才允许下拉关闭。
    // 按钮已经出现但暂时不可命中属于真实 UI 失败，不能通过另一条路径掩盖。
    // 手势只作用于已确认的 typed Picker 根，不使用屏幕坐标或 sheet fallback。
    try require(picker.root.exists && picker.root.isHittable, "系统 Picker 根节点不可操作")
    picker.root.swipeDown()
    try require(waitForSystemPickerToClose(app: app, timeout: 10), "下拉后系统 Picker 没有关闭")
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
      // 不能先调用 XCTFail：continueAfterFailure=false 会立即中断测试方法，使 catch、
      // evidence attachment 和资源清理都没有机会执行。直接抛错后由 XCTest 记录
      // thrown error，场景仍能先写出与失败一致的结构化证据。
      throw testFailure(message)
    }
  }

  private func testFailure(_ message: String) -> NSError {
    NSError(
      domain: "LDDCPlatformTests",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
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

  private func captureFailureAndCleanup(
    app: XCUIApplication?,
    scenario: String,
    failure: Error?
  ) {
    guard let failure else {
      return
    }
    cleanupDiagnostics["originalFailure"] = String(describing: failure)
    guard let app else {
      cleanupDiagnostics["appCreated"] = false
      cleanupVerified = false
      return
    }

    // 先保存 accessibility tree，再执行取消或终止。这样 hosted CI 即使再次遇到
    // 新系统控件名称，也能从原始层级修正 selector，而不是根据截图猜测。
    attachAccessibilityDiagnostics(app: app, scenario: scenario)
    var pickerDismissed = false
    var pickerDismissError: String?
    if app.state != .notRunning, isSystemPickerVisible(app: app) {
      do {
        try cancelSystemPicker(app: app)
        pickerDismissed = app.wait(for: .runningForeground, timeout: 5)
      } catch {
        pickerDismissError = String(describing: error)
      }
    }
    if app.state != .notRunning {
      app.terminate()
    }
    let appStopped = app.wait(for: .notRunning, timeout: 5)
    cleanupVerified = appStopped
    cleanupDiagnostics["pickerDismissedBeforeTermination"] = pickerDismissed
    cleanupDiagnostics["appStoppedAfterFailure"] = appStopped
    if let pickerDismissError {
      cleanupDiagnostics["pickerDismissError"] = pickerDismissError
    }
  }

  private func isSystemPickerVisible(app: XCUIApplication) -> Bool {
    systemPickerContext(app: app) != nil
  }

  private func attachAccessibilityDiagnostics(app: XCUIApplication, scenario: String) {
    var sections: [String] = []
    if app.state != .notRunning {
      sections.append("=== app ===\n\(app.debugDescription)")
    }
    let springBoard = XCUIApplication(bundleIdentifier: springBoardBundleIdentifier)
    if springBoard.state != .notRunning {
      sections.append("=== springboard ===\n\(springBoard.debugDescription)")
    }
    let documents = XCUIApplication(bundleIdentifier: documentsBundleIdentifier)
    if documents.state != .notRunning {
      sections.append("=== documents ===\n\(documents.debugDescription)")
    }
    // accessibility tree 可能很大。保留足以定位控件的前 128 KiB，避免单次失败
    // 生成不可控 artifact，同时不写入 Simulator 容器绝对路径。
    let text = String(sections.joined(separator: "\n\n").prefix(128 * 1024))
    let attachment = XCTAttachment(string: text)
    attachment.name = "lddc-accessibility-\(scenario).txt"
    attachment.lifetime = .keepAlways
    add(attachment)
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
      "extra": cleanupDiagnostics,
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
