import XCTest

private struct SystemPickerContext {
  let application: XCUIApplication
  let root: XCUIElement
}

private enum SystemPickerDestination: Equatable {
  case browseRoot
  case onMyIPhone
  case fixtureDirectory
}

final class RunnerUITests: XCTestCase {
  private let appBundleIdentifier = "com.cmzj.lddc.platformtests"
  private let fixtureName = "audio_sample.mp3"
  private let fixtureAccessibilityName = "audio_sample, mp3"
  // LRC 时间标签可能从两位毫秒规范化为三位；只约束时间点和正文，
  // 避免把等价的格式化差异误报为读取失败。
  private let fixtureLyricsAccessibilityPattern = #"^\[00:00\.\d{2,3}\]Hello LDDC$"#
  private let navigationIdentifier = "lddc.nav.open_lyrics"
  private let openSongIdentifier = "lddc.open_lyrics.open_song_file"
  private let convertIdentifier = "lddc.open_lyrics.convert"
  private let saveFileIdentifier = "lddc.open_lyrics.save_file"
  private let saveTagIdentifier = "lddc.open_lyrics.save_tag"
  private let saveTagSucceededIdentifier = "lddc.open_lyrics.notice.saveTagSucceeded"
  private let saveTagFailedIdentifier = "lddc.open_lyrics.notice.saveTagFailed"
  private let convertFailedIdentifier = "lddc.open_lyrics.notice.convertFailed"
  private let previewIdentifier = "lddc.open_lyrics.preview"
  private let exportFileNameIdentifier = "DOCPicker.filenameTextField"
  private let exportBaseName = "lddc_export"
  private let keyboardTutorialMessage = "Speed up your typing by sliding your finger across the letters to compose a word."
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
      try selectSeededAudio(app: launchedApp, actions: &actions)
      addAction(&actions, capability: "nativeChannels", action: "flutter_picker_round_trip")
      addAction(&actions, capability: "media", action: "security_scoped_fd_read_embedded_lyrics")
      try convertLoadedLyrics(app: launchedApp, actions: &actions)

      let saveTag = launchedApp.descendants(matching: .any)[saveTagIdentifier]
      try requireHittable(saveTag, in: launchedApp, message: "Flutter 未暴露可点击的写入歌曲标签按钮")
      saveTag.tap()
      try waitForSaveTagResult(app: launchedApp, timeout: 20)
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
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    var app: XCUIApplication?
    do {
      let launchedApp = try launchApp()
      app = launchedApp
      let openSong = launchedApp.buttons[openSongIdentifier]
      _ = try openDocumentPicker(app: launchedApp)
      try cancelSystemPicker(
        app: launchedApp,
        returnControl: openSong,
        actions: &actions
      )
      try require(launchedApp.wait(for: .runningForeground, timeout: 15), "第 \(round) 轮取消后 LDDC 没有返回前台")
      try require(
        waitForHittable(openSong, timeout: 15),
        "第 \(round) 轮取消后 Flutter 打开歌曲动作不可再次操作"
      )
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
      try terminateAndVerify(launchedApp)
      addAction(&actions, capability: "resourceCleanup", action: "application_and_picker_closed")
    } catch let error {
      failure = error
    }
    captureFailureAndCleanup(app: app, scenario: scenario, failure: failure)
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
      try convertLoadedLyrics(app: launchedApp, actions: &actions)
      _ = try openExportPicker(app: launchedApp)
      let picker = try navigatePickerToOnMyIPhone(app: launchedApp)
      try replaceExportBaseName(in: picker)
      addAction(&actions, capability: "filePicker", action: "document_picker_export_name_replaced")
      try dismissKeyboardTutorialIfPresented(in: picker, actions: &actions)
      // 系统教学层关闭会刷新远程 Document Picker 的 AX snapshot，必须重新解析
      // typed 根节点后再查询 Save，不能继续复用遮罩出现前的陈旧元素代理。
      let resumedPicker = try waitForSystemPicker(app: launchedApp, timeout: 5)
      let save = try requireEnabledTypedButton(named: "Save", in: resumedPicker, timeout: 15)
      save.tap()
      addAction(&actions, capability: "filePicker", action: "document_picker_export_save_tapped")
      let saveFile = launchedApp.descendants(matching: .any)[saveFileIdentifier]
      try require(launchedApp.wait(for: .runningForeground, timeout: 15), "导出后 LDDC 没有返回前台")
      try require(
        waitForHittable(saveFile, timeout: 15),
        "导出保存后 Flutter 页面没有恢复可操作状态"
      )
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
      try convertLoadedLyrics(app: launchedApp, actions: &actions)
      _ = try openExportPicker(app: launchedApp)
      let saveFile = launchedApp.descendants(matching: .any)[saveFileIdentifier]
      try cancelSystemPicker(
        app: launchedApp,
        returnControl: saveFile,
        actions: &actions
      )
      try require(launchedApp.wait(for: .runningForeground, timeout: 15), "取消导出后 LDDC 没有返回前台")
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
      try convertLoadedLyrics(app: launchedApp, actions: &actions)
      _ = try openExportPicker(app: launchedApp)
      _ = try normalizePickerToBrowseRoot(app: launchedApp)
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
    try requireHittable(
      navigation,
      in: app,
      message: "Flutter 没有向 XCUITest 暴露可操作的打开歌词导航 identifier"
    )
    navigation.tap()
    let openSong = app.buttons[openSongIdentifier]
    try requireHittable(openSong, in: app, message: "Flutter 没有暴露可操作的打开歌曲按钮 identifier")
    openSong.tap()
    return try waitForSystemPicker(app: app, timeout: 15)
  }

  private func selectSeededAudio(
    app: XCUIApplication,
    actions: inout [String: [[String: Any]]]
  ) throws {
    _ = try openDocumentPicker(app: app)
    let picker = try navigatePickerToFixtureDirectory(app: app)
    let fixture = try requireFixtureCell(in: picker, timeout: 15)
    try selectFixture(fixture, app: app, actions: &actions)
  }

  private func selectFixture(
    _ fixture: XCUIElement,
    app: XCUIApplication,
    actions: inout [String: [[String: Any]]]
  ) throws {
    try require(fixture.exists && fixture.isHittable && fixture.isEnabled, "匿名音频 fixture 不可点击")
    let openSong = app.buttons[openSongIdentifier]
    fixture.tap()
    addAction(&actions, capability: "filePicker", action: "document_picker_fixture_cell_tapped")
    // Files 的远程 accessibility Cell 没有公开、稳定的“选择后激活”契约。
    // 诊断已经证明追加 doubleTap 可能把第一次形成的选择反向取消，因此完整
    // Files 导航只保留一次精确点击和原有十五秒结果预算。该流程属于 observation；
    // 阻断门禁由真实 Picker 取消、原生 delegate 和媒体组件测试共同承担。
    try require(
      waitForPickerDismissal(
        app: app,
        returnControl: openSong,
        timeout: 15
      ),
      "单击匿名音频后系统 Picker 没有关闭，记录 Files AX 激活观察失败"
    )
    try require(app.wait(for: .runningForeground, timeout: 15), "选择文件后 LDDC 没有返回前台")
    try require(
      waitForHittable(openSong, timeout: 15),
      "选择文件后 Flutter 打开歌曲动作没有恢复，Picker 回调尚未完成"
    )
    try require(
      app.otherElements[previewIdentifier].waitForExistence(timeout: 15),
      "选择结果没有回到 Flutter 预览区域"
    )
    let preview = app.otherElements[previewIdentifier]
    try require(
      waitForPreviewLyricsValue(preview: preview, timeout: 15),
      "预览没有显示规范化后的匿名内嵌歌词内容"
    )
    // 只有 Picker 关闭、应用回到前台、Flutter 控件恢复且匿名歌词确实出现后，
    // 才能把系统动作记录为完成。单击动作本身不能证明 delegate 已经回调。
    addAction(&actions, capability: "filePicker", action: "document_picker_select_audio")
  }

  private func openExportPicker(app: XCUIApplication) throws -> SystemPickerContext {
    let saveFile = app.descendants(matching: .any)[saveFileIdentifier]
    try requireHittable(saveFile, in: app, message: "Flutter 未暴露可点击的歌词导出按钮")
    saveFile.tap()
    return try waitForSystemPicker(app: app, timeout: 15)
  }

  private func convertLoadedLyrics(
    app: XCUIApplication,
    actions: inout [String: [[String: Any]]]
  ) throws {
    let convert = app.descendants(matching: .any)[convertIdentifier]
    try requireHittable(convert, in: app, message: "Flutter 未暴露已启用的歌词转换按钮")
    convert.tap()

    let saveFile = app.descendants(matching: .any)[saveFileIdentifier]
    let saveTag = app.descendants(matching: .any)[saveTagIdentifier]
    let convertFailed = app.descendants(matching: .any)[convertFailedIdentifier]
    let deadline = Date().addingTimeInterval(20)
    repeat {
      if convertFailed.exists {
        let rawMessage = [convertFailed.label, convertFailed.value as? String]
          .compactMap { $0 }
          .first { !$0.isEmpty } ?? "unknown"
        throw testFailure("歌词转换返回失败提示: \(redactDynamicPaths(rawMessage))")
      }
      if saveFile.exists, saveFile.isEnabled, saveTag.exists, saveTag.isEnabled {
        addAction(&actions, capability: "nativeChannels", action: "flutter_lyrics_conversion_completed")
        return
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw testFailure("歌词转换后保存文件和写入标签按钮没有同时进入启用状态")
  }

  private func replaceExportBaseName(in picker: SystemPickerContext) throws {
    let fileName = try requireUniquePickerElement(
      queries: [
        picker.application.textFields.matching(
          NSPredicate(format: "identifier == %@", exportFileNameIdentifier)
        ),
      ],
      in: picker,
      timeout: 15,
      description: "导出文件名输入框"
    )
    try require(fileName.isEnabled, "系统保存 Picker 的文件名输入框未启用")
    fileName.tap()
    let currentValue = fileName.value as? String ?? ""
    // 系统保存器没有公开稳定的“全选”菜单 identifier。向已经聚焦的输入框
    // 写入与当前值等长的 Delete 键，可以只清空该字段，不依赖坐标、长按菜单
    // 或语言文案；最终值断言会拒绝任何未完整清空的结果。
    if !currentValue.isEmpty {
      fileName.typeText(
        String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
      )
    }
    fileName.typeText(exportBaseName)
    try require(
      waitForStringValue(fileName, equals: exportBaseName, timeout: 5),
      "系统保存 Picker 没有接受脱敏导出文件名"
    )
  }

  private func dismissKeyboardTutorialIfPresented(
    in picker: SystemPickerContext,
    actions: inout [String: [[String: Any]]]
  ) throws {
    let message = picker.application.staticTexts[keyboardTutorialMessage]
    let continueButton = picker.application.buttons["Continue"]
    let tutorialAppeared = message.waitForExistence(timeout: 2)
      || continueButton.waitForExistence(timeout: 0)
    guard tutorialAppeared else {
      return
    }
    // 新建 Simulator 首次聚焦文本框时，系统键盘会显示教学遮罩并禁用 Save。
    // 诊断 hierarchy 已确认遮罩提供唯一 typed Continue Button；只在精确文案
    // 存在时点击该按钮，避免把应用或 Picker 中其他同名按钮当成系统教学层。
    let continueButtons = picker.application.buttons.matching(
      NSPredicate(format: "label == %@ OR identifier == %@", "Continue", "Continue")
    ).allElementsBoundByIndex.filter {
      $0.exists && $0.isHittable && $0.isEnabled
    }
    try require(continueButtons.count == 1, "系统键盘教学层的 Continue Button 不是唯一可点击控件")
    continueButtons[0].tap()
    // 远程 Document Picker 可能继续保留已关闭教学层的陈旧 AX 元素代理。
    // 调用方会重新解析 typed Picker，并以 Save 唯一、可命中且已启用作为
    // 正向完成证据，避免把系统的 snapshot 延迟误判成教学层仍未关闭。
    addAction(&actions, capability: "filePicker", action: "keyboard_tutorial_dismissed")
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

  private func requireEnabledTypedButton(
    named name: String,
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    let predicate = NSPredicate(
      format: "label ==[c] %@ OR identifier ==[c] %@",
      name,
      name
    )
    let deadline = Date().addingTimeInterval(timeout)
    var sawCandidate = false
    var sawDisabled = false
    repeat {
      let candidates = pickerElements(
        queries: [picker.application.buttons.matching(predicate)],
        in: picker,
        requireHittable: false
      )
      try require(candidates.count < 2, "系统文件界面的 \(name) 按钮存在多个 typed 候选")
      if let candidate = candidates.first {
        sawCandidate = true
        if !candidate.isEnabled {
          sawDisabled = true
        } else if candidate.isHittable {
          return candidate
        }
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    if !sawCandidate {
      throw testFailure("系统文件界面没有找到 typed \(name) 按钮")
    }
    if sawDisabled {
      throw testFailure("系统文件界面的 typed \(name) 按钮存在但未启用")
    }
    throw testFailure("系统文件界面的 typed \(name) 按钮已启用但不可命中")
  }

  private func navigatePickerToFixtureDirectory(
    app: XCUIApplication
  ) throws -> SystemPickerContext {
    let browseRoot = try normalizePickerToBrowseRoot(app: app)
    let onMyIPhone = try requireOnMyIPhoneLocation(in: browseRoot, timeout: 10)
    onMyIPhone.tap()
    guard let localRoot = waitForPickerDestination(
      app: app,
      destination: .onMyIPhone,
      timeout: 10
    ) else {
      throw testFailure("点击 On My iPhone 后没有进入本机文件根目录")
    }
    let folder = try requirePlatformTestFolder(in: localRoot, timeout: 10)
    folder.tap()
    guard let fixtureDirectory = waitForPickerDestination(
      app: app,
      destination: .fixtureDirectory,
      timeout: 10
    ) else {
      throw testFailure("点击测试目录后没有进入匿名 fixture 目录")
    }
    return fixtureDirectory
  }

  private func navigatePickerToOnMyIPhone(
    app: XCUIApplication
  ) throws -> SystemPickerContext {
    let browseRoot = try normalizePickerToBrowseRoot(app: app)
    let onMyIPhone = try requireOnMyIPhoneLocation(in: browseRoot, timeout: 10)
    onMyIPhone.tap()
    guard let localRoot = waitForPickerDestination(
      app: app,
      destination: .onMyIPhone,
      timeout: 10
    ) else {
      throw testFailure("点击 On My iPhone 后没有进入可写的本机文件根目录")
    }
    return localRoot
  }

  private func normalizePickerToBrowseRoot(
    app: XCUIApplication
  ) throws -> SystemPickerContext {
    var picker = try waitForSystemPicker(app: app, timeout: 5)
    if let browseTab = waitForBrowseTabButton(in: picker, timeout: 2) {
      browseTab.tap()
      picker = try waitForSystemPicker(app: app, timeout: 5)
    }

    for _ in 0..<4 {
      if waitForOnMyIPhoneLocation(in: picker, timeout: 0) != nil {
        return picker
      }
      guard let backButton = waitForBackButton(in: picker, timeout: 5) else {
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
      guard let parent = waitForBackNavigation(
        app: app,
        expectedBackButtonLabel: expectedBackButtonLabel,
        timeout: 10
      ) else {
        throw testFailure("系统 Picker 点击 BackButton 后没有进入预期父页面")
      }
      picker = parent
    }
    throw testFailure("系统 Picker 在四次有界返回后仍未进入 Browse 根页")
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

  private func pickerDestination(
    _ picker: SystemPickerContext
  ) -> SystemPickerDestination? {
    if waitForOnMyIPhoneLocation(in: picker, timeout: 0) != nil {
      return .browseRoot
    }
    if hasPickerTitle("On My iPhone", in: picker),
       waitForPlatformTestFolder(in: picker, timeout: 0) != nil {
      return .onMyIPhone
    }
    if waitForFixtureCell(in: picker, timeout: 0) != nil,
       waitForBackButton(in: picker, label: "On My iPhone", timeout: 0) != nil {
      return .fixtureDirectory
    }
    return nil
  }

  private func waitForPickerDestination(
    app: XCUIApplication,
    destination: SystemPickerDestination,
    timeout: TimeInterval
  ) -> SystemPickerContext? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let picker = systemPickerContext(app: app), pickerDestination(picker) == destination {
        return picker
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

  private func hasPickerTitle(
    _ title: String,
    in picker: SystemPickerContext
  ) -> Bool {
    !pickerElements(
      queries: [
        picker.application.staticTexts.matching(
          NSPredicate(format: "label ==[c] %@", title)
        ),
      ],
      in: picker,
      requireHittable: false
    ).isEmpty
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
    guard let fixture = waitForFixtureCell(in: picker, timeout: timeout) else {
      throw testFailure("系统文件界面没有可点击的 \(fixtureAccessibilityName) 文件单元格")
    }
    return fixture
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

  private func requireOnMyIPhoneLocation(
    in picker: SystemPickerContext,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    guard let location = waitForOnMyIPhoneLocation(in: picker, timeout: timeout) else {
      throw testFailure("系统文件界面的 On My iPhone 位置不是唯一可点击的 typed 控件")
    }
    return location
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
    queries.flatMap { $0.allElementsBoundByIndex }.filter {
      $0.exists
        && (!requireHittable || ($0.isHittable && $0.isEnabled))
        && elementBelongsToPicker($0, picker: picker)
    }
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
    returnControl: XCUIElement?,
    actions: inout [String: [[String: Any]]]
  ) throws {
    let picker = try normalizePickerToBrowseRoot(app: app)
    let cancelPredicate = NSPredicate(
      format: "label ==[c] %@ OR identifier ==[c] %@",
      "Cancel",
      "Cancel"
    )
    guard let cancel = try waitForTypedCancelButton(
      in: picker,
      predicate: cancelPredicate,
      timeout: 5
    ) else {
      throw testFailure(
        "experimental_ax_cancel_unavailable: 系统保存 Picker 已返回 Browse 根页，但没有唯一、启用且可命中的 typed Cancel Button"
      )
    }
    cancel.tap()
    addAction(
      &actions,
      capability: "filePicker",
      action: "document_picker_typed_cancel_tapped"
    )
    try require(
      waitForPickerDismissal(
        app: app,
        returnControl: returnControl,
        timeout: 10
      ),
      "点击 Cancel 后系统 Picker 没有关闭"
    )
    if let returnControl {
      try require(
        waitForHittable(returnControl, timeout: 10),
        "点击 Cancel 后 Flutter 页面没有恢复可操作状态"
      )
    }
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

  private func cancelSystemPicker(
    app: XCUIApplication,
    returnControl: XCUIElement?
  ) throws {
    var cleanupActions: [String: [[String: Any]]] = [:]
    try cancelSystemPicker(
      app: app,
      returnControl: returnControl,
      actions: &cleanupActions
    )
  }

  private func waitForStringValue(
    _ element: XCUIElement,
    equals expected: String,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if element.value as? String == expected {
        return true
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return false
  }

  private func waitForPreviewLyricsValue(
    preview: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      // 预览根节点由 Flutter 直接暴露有界 value。不要再查询视觉文本子节点：
      // iOS 远程 AX 会把长文本显示为省略值，导致完整歌词已经读取成功却假红。
      if preview.exists,
         let value = preview.value as? String,
         value.range(of: fixtureLyricsAccessibilityPattern, options: .regularExpression) != nil {
        return true
      }
      Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return false
  }

  private func waitForSaveTagResult(
    app: XCUIApplication,
    timeout: TimeInterval
  ) throws {
    let succeeded = app.descendants(matching: .any)[saveTagSucceededIdentifier]
    let failed = app.descendants(matching: .any)[saveTagFailedIdentifier]
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if succeeded.exists {
        return
      }
      if failed.exists {
        let rawMessage = [failed.label, failed.value as? String]
          .compactMap { $0 }
          .first { !$0.isEmpty } ?? "unknown"
        throw testFailure(
          "歌词标签写入返回失败提示: \(redactDynamicPaths(rawMessage))"
        )
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw testFailure("读写 fd 升级后没有返回成功或失败提示")
  }

  private func redactDynamicPaths(_ value: String) -> String {
    let redacted = value.replacingOccurrences(
      of: #"(?:file://)?/(?:Users|private|var)/[^\s,;]+"#,
      with: "<path>",
      options: .regularExpression
    )
    return String(redacted.prefix(512))
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

  private func waitForPickerDismissal(
    app: XCUIApplication,
    returnControl: XCUIElement?,
    timeout: TimeInterval
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if systemPickerContext(app: app) == nil {
        return true
      }
      // iOS 远程 Files 服务可能短暂保留已关闭页面的旧 AX 根。只有宿主应用内的
      // Picker 根已经消失，并且此前被系统界面遮挡的 Flutter 控件重新可命中，
      // 才把该旧根视为陈旧快照；这不会接受仍覆盖在应用上的 Picker。
      if typedSystemPickerRoot(in: app) == nil,
         let returnControl,
         returnControl.exists,
         returnControl.isHittable,
         returnControl.isEnabled {
        return true
      }
      Thread.sleep(forTimeInterval: 0.1)
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
    if element.waitForExistence(timeout: 3), element.isHittable, element.isEnabled {
      return
    }
    let scrollView = app.scrollViews.firstMatch
    try require(scrollView.waitForExistence(timeout: 5), "Flutter 页面没有暴露可滚动语义容器")
    for _ in 0..<6 {
      scrollView.swipeUp()
      if element.waitForExistence(timeout: 1), element.isHittable, element.isEnabled {
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
        try cancelSystemPicker(app: app, returnControl: nil)
        let returnControls = [
          app.buttons[openSongIdentifier],
          app.descendants(matching: .any)[saveFileIdentifier],
        ]
        pickerDismissed = returnControls.contains {
          waitForHittable($0, timeout: 2)
        }
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
