import XCTest

private struct SystemPickerContext {
  let application: XCUIApplication
  let root: XCUIElement
}

private final class CancellationRoundContext {
  private let startedUptime: TimeInterval
  private let actionDeadline: TimeInterval
  private(set) var lastPhase = "round_started"
  private(set) var checkpoints: [[String: Any]] = []

  init(actionBudgetSeconds: TimeInterval) {
    startedUptime = ProcessInfo.processInfo.systemUptime
    actionDeadline = startedUptime + actionBudgetSeconds
    mark("round_started")
  }

  func mark(_ phase: String) {
    let now = ProcessInfo.processInfo.systemUptime
    lastPhase = phase
    checkpoints.append([
      "phase": phase,
      "elapsedMilliseconds": Int(max(0, now - startedUptime) * 1000),
      "remainingActionBudgetMilliseconds": Int(max(0, actionDeadline - now) * 1000),
    ])
  }

  func timeout(upTo maximum: TimeInterval, phase: String) throws -> TimeInterval {
    mark(phase)
    let remaining = actionDeadline - ProcessInfo.processInfo.systemUptime
    guard remaining > 0 else {
      throw NSError(
        domain: "LDDCPlatformTests",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: "取消 round 的真实 UI 动作预算已耗尽，最后阶段: \(phase)",
        ]
      )
    }
    return min(maximum, remaining)
  }

  var diagnostics: [String: Any] {
    let remaining = max(0, actionDeadline - ProcessInfo.processInfo.systemUptime)
    return [
      "actionBudgetMilliseconds": Int((actionDeadline - startedUptime) * 1000),
      "lastPhase": lastPhase,
      "remainingActionBudgetMilliseconds": Int(remaining * 1000),
      "checkpoints": checkpoints,
    ]
  }
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
  private let previewIdentifier = "lddc.open_lyrics.preview"
  private let documentsBundleIdentifier = "com.apple.DocumentsApp"
  private let springBoardBundleIdentifier = "com.apple.springboard"
  private let documentBrowsingRootPrefix = "DOC.browsingRoot Source: "
  private let platformTestDisplayName = "LDDC Platform Tests"
  // XCTest 的 120 秒限制覆盖整个测试方法。真实 UI 动作只使用其中 85 秒，
  // 为 evidence、失败报告和应用终止预留 35 秒，避免框架先于测试自身收尾。
  private let cancellationRoundActionBudgetSeconds: TimeInterval = 85
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
      try selectSeededAudio(app: launchedApp, actions: &actions)
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
      try selectSeededAudio(app: launchedApp, actions: &actions)
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

  // 三轮真实取消必须拆成独立 XCTest。XCTest 的 120 秒限制按测试方法计算，
  // 如果在一个方法内串行执行三轮，第三轮会在系统 Picker 已正确工作时被框架强制终止。
  func testDocumentPickerCancellationRound1ReturnsToFlutter() throws {
    try runDocumentPickerCancellationRound(
      scenario: "ios_document_picker_cancel_1",
      round: 1
    )
  }

  func testDocumentPickerCancellationRound2ReturnsToFlutter() throws {
    try runDocumentPickerCancellationRound(
      scenario: "ios_document_picker_cancel_2",
      round: 2
    )
  }

  func testDocumentPickerCancellationRound3ReturnsToFlutter() throws {
    try runDocumentPickerCancellationRound(
      scenario: "ios_document_picker_cancel_3",
      round: 3
    )
  }

  private func runDocumentPickerCancellationRound(
    scenario: String,
    round: Int
  ) throws {
    let context = CancellationRoundContext(
      actionBudgetSeconds: cancellationRoundActionBudgetSeconds
    )
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    var app: XCUIApplication?
    do {
      context.mark("app_launching")
      let launchedApp = try launchApp()
      app = launchedApp
      context.mark("app_launched")
      _ = try openDocumentPicker(
        app: launchedApp,
        cancellationContext: context
      )
      context.mark("picker_opened")
      try cancelSystemPicker(
        app: launchedApp,
        actions: &actions,
        cancellationContext: context,
        // 远程 Files 服务偶尔会在取消后保留 DocumentsApp 的陈旧 AX 根。这里只在
        // 宿主 Picker 根已消失时按需重新解析控件，用于区分陈旧快照；round helper
        // 仍会在下方独立完成唯一一次 Flutter 前台与可操作状态断言。
        staleRootReturnControlProvider: {
          launchedApp.buttons[self.openSongIdentifier]
        }
      )
      let foregroundTimeout = try cancellationRoundTimeout(
        15,
        context: context,
        phase: "flutter_foreground_wait"
      )
      try require(
        launchedApp.wait(for: .runningForeground, timeout: foregroundTimeout),
        "第 \(round) 轮取消后 LDDC 没有返回前台"
      )
      // Document Picker 关闭后必须重新解析 Flutter 控件；不能复用打开 Picker 前的
      // XCUIElement 代理，否则远程 AX snapshot 刷新时会把陈旧代理误判为恢复成功。
      let returnedOpenSong = launchedApp.buttons[openSongIdentifier]
      let openSongTimeout = try cancellationRoundTimeout(
        15,
        context: context,
        phase: "flutter_control_wait"
      )
      try require(
        waitForHittable(returnedOpenSong, timeout: openSongTimeout),
        "第 \(round) 轮取消后 Flutter 打开歌曲动作不可再次操作"
      )
      context.mark("flutter_ready")
      addAction(
        &actions,
        capability: "filePicker",
        action: "document_picker_cancel_round_\(round)"
      )
      addAction(
        &actions,
        capability: "nativeChannels",
        action: "flutter_picker_cancel_round_trip_\(round)"
      )
      context.mark("app_termination_started")
      try terminateAndVerify(launchedApp)
      context.mark("app_terminated")
      addAction(&actions, capability: "resourceCleanup", action: "application_and_picker_closed")
    } catch let error {
      failure = error
    }
    captureCancellationRoundFailureAndCleanup(
      app: app,
      scenario: scenario,
      failure: failure,
      context: context
    )
    cleanupDiagnostics["cancellationRound"] = context.diagnostics
    attachEvidence(scenario: scenario, actions: actions, failure: failure)
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
      try selectSeededAudio(app: launchedApp, actions: &actions)
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
      try selectSeededAudio(app: launchedApp, actions: &actions)
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
      try selectSeededAudio(app: launchedApp, actions: &actions)
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

  private func openDocumentPicker(
    app: XCUIApplication,
    cancellationContext: CancellationRoundContext? = nil
  ) throws -> SystemPickerContext {
    let navigation = app.buttons[navigationIdentifier]
    try requireHittable(
      navigation,
      in: app,
      message: "Flutter 没有向 XCUITest 暴露可操作的打开歌词导航 identifier",
      cancellationContext: cancellationContext,
      phase: "navigation_ready_wait"
    )
    navigation.tap()
    let openSong = app.buttons[openSongIdentifier]
    try requireHittable(
      openSong,
      in: app,
      message: "Flutter 没有暴露可操作的打开歌曲按钮 identifier",
      cancellationContext: cancellationContext,
      phase: "open_song_ready_wait"
    )
    openSong.tap()
    let pickerTimeout = try cancellationRoundTimeout(
      15,
      context: cancellationContext,
      phase: "picker_open_wait"
    )
    return try waitForSystemPicker(app: app, timeout: pickerTimeout)
  }

  private func selectSeededAudio(
    app: XCUIApplication,
    actions: inout [String: [[String: Any]]]
  ) throws {
    var picker = try openDocumentPicker(app: app)

    // Files 会记住上次的目录。先仅查找 typed file cell，可以处理
    // 已在 fixture 目录的情况，也不会把 Picker 容器或菜单按钮误当成文件。
    if let fixture = waitForFixtureCell(in: picker, timeout: 1) {
      try selectFixture(fixture, app: app, actions: &actions)
      return
    }
    if let folder = waitForPlatformTestFolder(in: picker, timeout: 1) {
      folder.tap()
      picker = try waitForSystemPicker(app: app, timeout: 5)
      let fixture = try requireFixtureCell(in: picker, timeout: 15)
      try selectFixture(fixture, app: app, actions: &actions)
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
      try selectFixture(fixture, app: app, actions: &actions)
      return
    }
    if let folder = waitForPlatformTestFolder(in: picker, timeout: 1) {
      folder.tap()
    } else {
      // 只允许点击位置页的真实 On My iPhone 按钮。BackButton 即使
      // 使用相同 label 也必须排除，避免再次把返回动作误当成位置导航。
      let onMyIPhone = try requireUniquePickerElement(
        queries: [
          picker.application.buttons.matching(
            NSPredicate(format: "label ==[c] %@ AND identifier != %@", "On My iPhone", "BackButton")
          ),
        ],
        in: picker,
        timeout: 15,
        description: "On My iPhone 位置"
      )
      onMyIPhone.tap()
      picker = try waitForSystemPicker(app: app, timeout: 5)
      let folder = try requirePlatformTestFolder(in: picker, timeout: 15)
      folder.tap()
    }

    picker = try waitForSystemPicker(app: app, timeout: 5)
    let fixture = try requireFixtureCell(in: picker, timeout: 15)
    try selectFixture(fixture, app: app, actions: &actions)
  }

  private func selectFixture(
    _ fixture: XCUIElement,
    app: XCUIApplication,
    actions: inout [String: [[String: Any]]]
  ) throws {
    try require(fixture.exists && fixture.isHittable, "匿名音频 fixture 不可点击")
    fixture.tap()
    try require(waitForSystemPickerToClose(app: app, timeout: 15), "选择文件后系统 Picker 没有关闭")
    // 原生文件选择动作在 Picker 关闭后已经完成，先记录证据再验证 Flutter
    // 预览，避免后置语义断言失败时把真实选择动作错误报告为零动作。
    addAction(&actions, capability: "filePicker", action: "document_picker_select_audio")
    try require(app.wait(for: .runningForeground, timeout: 15), "选择文件后 LDDC 没有返回前台")
    try require(
      app.otherElements[previewIdentifier].waitForExistence(timeout: 15),
      "选择结果没有回到 Flutter 预览区域"
    )
    let preview = app.otherElements[previewIdentifier]
    let lyricContent = preview.descendants(matching: .other).matching(
      NSPredicate(format: "label == %@ OR value == %@", "Hello LDDC", "Hello LDDC")
    ).firstMatch
    try require(
      lyricContent.waitForExistence(timeout: 15),
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
      return SystemPickerContext(application: app, root: hostedRoot)
    }
    let documents = XCUIApplication(bundleIdentifier: documentsBundleIdentifier)
    if documents.state != .notRunning,
       let documentsRoot = typedSystemPickerRoot(in: documents) {
      return SystemPickerContext(application: documents, root: documentsRoot)
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

  private func waitForPickerDismissal(
    app: XCUIApplication,
    staleRootReturnControlProvider: (() -> XCUIElement)? = nil,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if systemPickerContext(app: app) == nil {
        return true
      }
      // iOS 远程 Files 服务可能短暂保留已关闭页面的旧 AX 根。只有宿主应用内的
      // Picker 根已经消失，并且按需重新解析的 Flutter 控件重新可命中，才把该旧根
      // 视为陈旧快照；这不会缓存跨 Picker 页面的 XCUIElement，也不会接受仍覆盖
      // 在应用上的 Picker。
      if typedSystemPickerRoot(in: app) == nil,
         let returnControl = staleRootReturnControlProvider?(),
         returnControl.exists,
         returnControl.isHittable,
         returnControl.isEnabled {
        return true
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return false
  }

  private func normalizePickerToBrowseRoot(
    app: XCUIApplication,
    cancellationContext: CancellationRoundContext? = nil
  ) throws -> SystemPickerContext {
    let pickerContextTimeout = try cancellationRoundTimeout(
      5,
      context: cancellationContext,
      phase: "picker_context_wait"
    )
    var picker = try waitForSystemPicker(app: app, timeout: pickerContextTimeout)
    let browseTabTimeout = try cancellationRoundTimeout(
      2,
      context: cancellationContext,
      phase: "browse_tab_wait"
    )
    if let browseTab = waitForBrowseTabButton(in: picker, timeout: browseTabTimeout) {
      browseTab.tap()
      let refreshedPickerTimeout = try cancellationRoundTimeout(
        5,
        context: cancellationContext,
        phase: "browse_tab_transition_wait"
      )
      picker = try waitForSystemPicker(app: app, timeout: refreshedPickerTimeout)
    }

    // 当前测试只会从 On My iPhone 或匿名 fixture 目录返回 Browse 根页，最多需要
    // 两次已知 BackButton 转换。未知标签立即失败，不能用泛化回退掩盖页面状态错误。
    for _ in 0..<2 {
      if waitForOnMyIPhoneLocation(in: picker, timeout: 0) != nil {
        return picker
      }
      let backButtonTimeout = try cancellationRoundTimeout(
        5,
        context: cancellationContext,
        phase: "browse_root_back_button_wait"
      )
      guard let backButton = waitForBackButton(in: picker, timeout: backButtonTimeout) else {
        throw testFailure("系统 Picker 既不在 Browse 根页，也没有唯一可操作的 BackButton")
      }
      let expectedBackButtonLabel: String?
      switch backButton.label {
      case "On My iPhone":
        expectedBackButtonLabel = "Browse"
      case "Browse":
        expectedBackButtonLabel = nil
      default:
        throw testFailure("系统 Picker BackButton 指向未知父页面: \(backButton.label)")
      }
      backButton.tap()
      // Browse 的初始位置可能是上次访问的目录。只验证当前 BackButton 的确定标签
      // 转换，避免每一层都扫描 fixture、标题与多个远程 AX 候选；最终仍必须看到
      // Browse 根页唯一的 On My iPhone 位置，不能把任意无 BackButton 页面当作根页。
      let backNavigationTimeout = try cancellationRoundTimeout(
        10,
        context: cancellationContext,
        phase: "browse_root_transition_wait"
      )
      guard let parent = waitForBackNavigation(
        app: app,
        expectedBackButtonLabel: expectedBackButtonLabel,
        timeout: backNavigationTimeout
      ) else {
        throw testFailure("系统 Picker 点击 BackButton 后没有进入预期父页面")
      }
      picker = parent
    }
    if waitForOnMyIPhoneLocation(in: picker, timeout: 0) != nil {
      return picker
    }
    throw testFailure("系统 Picker 在两次确定 BackButton 返回后仍未进入 Browse 根页")
  }

  private func waitForBackNavigation(
    app: XCUIApplication,
    expectedBackButtonLabel: String?,
    timeout: TimeInterval
  ) -> SystemPickerContext? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let picker = systemPickerContext(app: app) {
        if let expectedBackButtonLabel {
          if waitForBackButton(
            in: picker,
            label: expectedBackButtonLabel,
            timeout: 0
          ) != nil {
            return picker
          }
        } else if waitForOnMyIPhoneLocation(in: picker, timeout: 0) != nil {
          return picker
        }
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
  }

  private func waitForBrowseTabButton(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) -> XCUIElement? {
    waitForUniquePickerElement(
      queries: [
        picker.application.buttons.matching(
          NSPredicate(
            format: "label ==[c] %@ AND identifier != %@",
            "Browse",
            "BackButton"
          )
        ),
      ],
      in: picker,
      timeout: timeout
    )
  }

  private func waitForBackButton(
    in picker: SystemPickerContext,
    label: String? = nil,
    timeout: TimeInterval
  ) -> XCUIElement? {
    let predicate: NSPredicate
    if let label {
      predicate = NSPredicate(
        format: "identifier == %@ AND label ==[c] %@",
        "BackButton",
        label
      )
    } else {
      predicate = NSPredicate(format: "identifier == %@", "BackButton")
    }
    return waitForUniquePickerElement(
      queries: [picker.application.buttons.matching(predicate)],
      in: picker,
      timeout: timeout
    )
  }

  private func waitForOnMyIPhoneLocation(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) -> XCUIElement? {
    waitForUniquePickerElement(
      queries: [
        picker.application.buttons.matching(
          NSPredicate(
            format: "label ==[c] %@ AND identifier != %@",
            "On My iPhone",
            "BackButton"
          )
        ),
        picker.application.cells.matching(
          NSPredicate(
            format: "label ==[c] %@ OR identifier == %@",
            "On My iPhone",
            "DOC.sidebar.item.On My iPhone"
          )
        ),
      ],
      in: picker,
      timeout: timeout
    )
  }

  private func requireTypedButton(
    named name: String,
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    try requireUniquePickerElement(
      queries: [
        picker.application.buttons.matching(
          NSPredicate(format: "label ==[c] %@ OR identifier ==[c] %@", name, name)
        ),
      ],
      in: picker,
      timeout: timeout,
      description: "\(name) 按钮"
    )
  }

  private func requireBrowseButton(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    // iOS 26.5 的 hosted hierarchy 明确把 Browse 暴露为宿主应用中的 typed
    // Button，但 picker.root.buttons 无法跨 remote view-service 查询边界解析它。
    // 从根节点所属 application 查询，再验证元素中心仍位于 Picker 根范围内，
    // 可以证明控件归属而不使用坐标点击或 SpringBoard fallback。
    try requireTypedButton(named: "Browse", in: picker, timeout: timeout)
  }

  private func waitForFixtureCell(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) -> XCUIElement? {
    let predicate = NSPredicate(
      format: "label BEGINSWITH[c] %@ OR identifier BEGINSWITH[c] %@",
      fixtureAccessibilityName,
      fixtureAccessibilityName
    )
    return waitForUniquePickerElement(
      queries: [picker.application.cells.matching(predicate)],
      in: picker,
      timeout: timeout
    )
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
    return waitForUniquePickerElement(
      queries: [
        picker.application.cells.matching(predicate),
        picker.application.links.matching(predicate),
      ],
      in: picker,
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
        let location = waitForUniquePickerElement(
          queries: [
            picker.application.buttons.matching(
              NSPredicate(format: "label ==[c] %@ AND identifier != %@", "On My iPhone", "BackButton")
            ),
          ],
          in: picker,
          timeout: 0
        )
        if location != nil
          || waitForFixtureCell(in: picker, timeout: 0) != nil
          || waitForPlatformTestFolder(in: picker, timeout: 0) != nil {
          return true
        }
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return false
  }

  private func waitForUniquePickerElement(
    queries: [XCUIElementQuery],
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      let candidates = pickerElements(
        queries: queries,
        in: picker,
        requireHittable: true
      )
      if candidates.count == 1 {
        return candidates[0]
      }
      if candidates.count > 1 {
        return nil
      }
      if timeout == 0 {
        return nil
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
  }

  private func pickerElements(
    queries: [XCUIElementQuery],
    in picker: SystemPickerContext,
    requireHittable: Bool
  ) -> [XCUIElement] {
    var candidates: [XCUIElement] = []
    for query in queries {
      // 只需区分零个、唯一或多个候选。远程 Files AX 的全量枚举会重复拉取大型
      // hierarchy，因此每个精确 predicate 最多检查两个候选，仍可拒绝不唯一控件。
      for index in 0...1 {
        let element = query.element(boundBy: index)
        guard element.exists else {
          break
        }
        guard (!requireHittable || (element.isHittable && element.isEnabled)),
              elementBelongsToPicker(element, picker: picker)
        else {
          continue
        }
        candidates.append(element)
        if candidates.count > 1 {
          return candidates
        }
      }
    }
    return candidates
  }

  private func requireUniquePickerElement(
    queries: [XCUIElementQuery],
    in picker: SystemPickerContext,
    timeout: TimeInterval,
    description: String
  ) throws -> XCUIElement {
    guard let element = waitForUniquePickerElement(
      queries: queries,
      in: picker,
      timeout: timeout
    ) else {
      throw testFailure("系统文件界面的 \(description) 不是唯一可点击的 typed 控件")
    }
    return element
  }

  private func elementBelongsToPicker(
    _ element: XCUIElement,
    picker: SystemPickerContext
  ) -> Bool {
    let rootFrame = picker.root.frame
    let elementFrame = element.frame
    guard !rootFrame.isEmpty, !elementFrame.isEmpty else {
      return false
    }
    return rootFrame.contains(
      CGPoint(x: elementFrame.midX, y: elementFrame.midY)
    )
  }

  private func cancelSystemPicker(
    app: XCUIApplication,
    actions: inout [String: [[String: Any]]],
    cancellationContext: CancellationRoundContext? = nil,
    staleRootReturnControlProvider: (() -> XCUIElement)? = nil
  ) throws {
    let picker = try normalizePickerToBrowseRoot(
      app: app,
      cancellationContext: cancellationContext
    )
    cancellationContext?.mark("browse_root_confirmed")
    let cancelPredicate = NSPredicate(
      format: "label ==[c] %@ OR identifier ==[c] %@",
      "Cancel",
      "Cancel"
    )
    let cancelTimeout = try cancellationRoundTimeout(
      5,
      context: cancellationContext,
      phase: "cancel_button_wait"
    )
    guard let cancel = try waitForTypedCancelButton(
      in: picker,
      predicate: cancelPredicate,
      timeout: cancelTimeout
    ) else {
      throw testFailure(
        "系统 Picker 已返回 Browse 根页，但没有唯一、启用且可命中的 typed Cancel Button"
      )
    }
    cancel.tap()
    cancellationContext?.mark("cancel_tapped")
    addAction(
      &actions,
      capability: "filePicker",
      action: "document_picker_typed_cancel_tapped"
    )
    let dismissalTimeout = try cancellationRoundTimeout(
      10,
      context: cancellationContext,
      phase: "picker_dismissal_wait"
    )
    try require(
      waitForPickerDismissal(
        app: app,
        staleRootReturnControlProvider: staleRootReturnControlProvider,
        timeout: dismissalTimeout
      ),
      "点击 Cancel 后系统 Picker 没有关闭"
    )
    cancellationContext?.mark("picker_dismissed")
  }

  private func waitForTypedCancelButton(
    in picker: SystemPickerContext,
    predicate: NSPredicate,
    timeout: TimeInterval
  ) throws -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      let candidates = pickerElements(
        queries: [picker.application.buttons.matching(predicate)],
        in: picker,
        requireHittable: true
      )
      if candidates.count == 1 {
        return candidates[0]
      }
      try require(candidates.count < 2, "系统 Picker 的可操作 typed Cancel Button 不是唯一控件")
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
  }

  private func cancelSystemPicker(app: XCUIApplication) throws {
    var cleanupActions: [String: [[String: Any]]] = [:]
    try cancelSystemPicker(
      app: app,
      actions: &cleanupActions
    )
  }

  private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if element.exists, element.isHittable, element.isEnabled {
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
    message: String,
    cancellationContext: CancellationRoundContext? = nil,
    phase: String = "flutter_control_wait"
  ) throws {
    let initialTimeout = try cancellationRoundTimeout(
      3,
      context: cancellationContext,
      phase: phase
    )
    if element.waitForExistence(timeout: initialTimeout), element.isHittable, element.isEnabled {
      return
    }
    let scrollView = app.scrollViews.firstMatch
    let scrollTimeout = try cancellationRoundTimeout(
      5,
      context: cancellationContext,
      phase: "\(phase)_scroll_container_wait"
    )
    try require(
      scrollView.waitForExistence(timeout: scrollTimeout),
      "Flutter 页面没有暴露可滚动语义容器"
    )
    for attempt in 1...6 {
      scrollView.swipeUp()
      let retryTimeout = try cancellationRoundTimeout(
        1,
        context: cancellationContext,
        phase: "\(phase)_scroll_retry_\(attempt)"
      )
      if element.waitForExistence(timeout: retryTimeout), element.isHittable, element.isEnabled {
        return
      }
    }
    try require(false, message)
  }

  private func cancellationRoundTimeout(
    _ maximum: TimeInterval,
    context: CancellationRoundContext?,
    phase: String
  ) throws -> TimeInterval {
    guard let context else {
      return maximum
    }
    return try context.timeout(upTo: maximum, phase: phase)
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

  private func captureCancellationRoundFailureAndCleanup(
    app: XCUIApplication?,
    scenario: String,
    failure: Error?,
    context: CancellationRoundContext
  ) {
    guard let failure else {
      return
    }
    // 取消 round 的动作预算已接近 XCTest 上限。失败后只记录阶段并终止应用，
    // 不能再次执行 Browse 根页导航或 Cancel，否则会消耗预留的 evidence 收尾时间。
    let failedPhase = context.lastPhase
    context.mark("failure_cleanup_started")
    cleanupDiagnostics["originalFailure"] = String(describing: failure)
    cleanupDiagnostics["failureScenario"] = scenario
    cleanupDiagnostics["failurePhase"] = failedPhase
    guard let app else {
      cleanupDiagnostics["appCreated"] = false
      cleanupVerified = false
      context.mark("failure_cleanup_without_app")
      return
    }
    if app.state != .notRunning {
      app.terminate()
    }
    let appStopped = app.wait(for: .notRunning, timeout: 5)
    cleanupVerified = appStopped
    cleanupDiagnostics["pickerCleanupStrategy"] = "terminate_app_without_repeating_picker_navigation"
    cleanupDiagnostics["appStoppedAfterFailure"] = appStopped
    context.mark(appStopped ? "failure_app_terminated" : "failure_app_termination_failed")
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
        "baseline": ["applicationProcessCount": 0],
        "final": ["applicationProcessCount": cleanupVerified ? 0 : 1],
        "thresholds": ["applicationProcessCount": 0],
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
