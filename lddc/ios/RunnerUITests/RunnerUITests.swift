import XCTest

private struct SystemPickerContext {
  let application: XCUIApplication
  let root: XCUIElement
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

  func testDocumentPickerCancellationReturnsToFlutter() throws {
    var actions: [String: [[String: Any]]] = [:]
    var failure: Error?
    var app: XCUIApplication?
    do {
      let launchedApp = try launchApp()
      app = launchedApp
      _ = try openDocumentPicker(app: launchedApp)
      let openSong = launchedApp.buttons[openSongIdentifier]
      try cancelSystemPicker(app: launchedApp, returnControl: openSong)
      try require(launchedApp.wait(for: .runningForeground, timeout: 15), "取消后 LDDC 没有返回前台")
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
      try selectSeededAudio(app: launchedApp, actions: &actions)
      try convertLoadedLyrics(app: launchedApp, actions: &actions)
      let picker = try openExportPicker(app: launchedApp)
      try replaceExportBaseName(in: picker)
      addAction(&actions, capability: "filePicker", action: "document_picker_export_name_replaced")
      let save = try requireTypedButton(named: "Save", in: picker, timeout: 15)
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
      try cancelSystemPicker(app: launchedApp, returnControl: saveFile)
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
    var picker = try openDocumentPicker(app: app)
    // Files 会跨场景记住上次目录。直接点击刚打开时缓存的文件单元格在
    // iOS 26.5 上只会选中项目而不会完成 Document Picker 回调；先点击
    // typed Browse 让远程文档视图完成模式切换，再按当前 typed 页面继续。
    let browse = try requireBrowseButton(in: picker, timeout: 15)
    browse.tap()
    try require(
      waitForBrowseDestination(app: app, timeout: 15),
      "点击 Browse 后没有进入可访问的位置或目录页"
    )
    picker = try waitForSystemPicker(app: app, timeout: 5)

    if isFixtureDirectory(picker) {
      let fixture = try requireFixtureCell(app: app, timeout: 15)
      try selectFixture(fixture, app: app, actions: &actions)
      return
    }
    if let folder = waitForPlatformTestFolder(in: picker, timeout: 1) {
      folder.tap()
    } else {
      let onMyIPhone = try requireOnMyIPhoneLocation(in: picker, timeout: 15)
      onMyIPhone.tap()
      picker = try waitForSystemPicker(app: app, timeout: 5)
      let folder = try requirePlatformTestFolder(in: picker, timeout: 15)
      folder.tap()
    }

    let fixture = try requireFixtureCell(app: app, timeout: 15)
    try selectFixture(fixture, app: app, actions: &actions)
  }

  private func selectFixture(
    _ fixture: XCUIElement,
    app: XCUIApplication,
    actions: inout [String: [[String: Any]]]
  ) throws {
    try require(fixture.exists && fixture.isHittable && fixture.isEnabled, "匿名音频 fixture 不可点击")
    fixture.tap()
    addAction(&actions, capability: "filePicker", action: "document_picker_fixture_cell_tapped")
    let openSong = app.buttons[openSongIdentifier]
    if !waitForHittable(openSong, timeout: 8) {
      // iOS 26.5 的远程 Files 视图第一次单击可能只建立选中状态。
      // 重新查询同一个 typed Cell 后执行一次用户可见的双击激活；不要求
      // 远程 AX frame 连续完全相等，因为 view-service 刷新期间坐标会抖动。
      let retainedFixture = try requireFixtureCell(app: app, timeout: 10)
      retainedFixture.doubleTap()
      addAction(
        &actions,
        capability: "filePicker",
        action: "document_picker_fixture_cell_double_tap_reactivated"
      )
    }
    try require(
      waitForHittable(openSong, timeout: 15),
      "选择文件后 Flutter 打开歌曲动作没有恢复，Picker 回调尚未完成"
    )
    // 原生文件选择动作在 Picker 关闭后已经完成，先记录证据再验证 Flutter
    // 预览，避免后置语义断言失败时把真实选择动作错误报告为零动作。
    addAction(&actions, capability: "filePicker", action: "document_picker_select_audio")
    try require(app.wait(for: .runningForeground, timeout: 15), "选择文件后 LDDC 没有返回前台")
    try require(
      app.otherElements[previewIdentifier].waitForExistence(timeout: 15),
      "选择结果没有回到 Flutter 预览区域"
    )
    let preview = app.otherElements[previewIdentifier]
    try require(
      waitForPreviewLyricsValue(app: app, preview: preview, timeout: 15),
      "预览没有显示规范化后的匿名内嵌歌词内容"
    )
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
    app: XCUIApplication,
    timeout: TimeInterval
  ) throws -> XCUIElement {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      // 每次重新解析远程 Picker 根。目录切换后旧 XCUIElement 可能继续存在于
      // snapshot，复用旧 root 会把新文件单元格错误归到上一页。
      if let picker = systemPickerContext(app: app),
         isFixtureDirectory(picker),
         let candidate = waitForFixtureCell(in: picker, timeout: 0) {
        // 只要求候选当前存在、可命中且启用。远程 view-service 的 frame
        // 在刷新期间会抖动，不能把几何稳定性误当成文件不可操作。
        return candidate
      }
      Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    throw testFailure("系统文件界面没有可点击的 \(fixtureAccessibilityName) 文件单元格")
  }

  private func isFixtureDirectory(_ picker: SystemPickerContext) -> Bool {
    let rootIdentifier = picker.root.identifier
    if rootIdentifier.hasSuffix(", Title: \(platformTestDisplayName)") {
      return true
    }
    // 旧系统只暴露无标题的 Browse View 根；此时必须同时看到精确 fixture，
    // 不能把任意 Files 目录误判为测试目录。
    return rootIdentifier == "Browse View (Picker)"
      && waitForFixtureCell(in: picker, timeout: 0) != nil
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
        let location = waitForOnMyIPhoneLocation(in: picker, timeout: 0)
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
    returnControl: XCUIElement?
  ) throws {
    let picker = try waitForSystemPicker(app: app, timeout: 5)
    let cancelPredicate = NSPredicate(
      format: "label ==[c] %@ OR identifier ==[c] %@",
      "Cancel",
      "Cancel"
    )
    let cancelButtons = pickerElements(
      queries: [picker.application.buttons.matching(cancelPredicate)],
      in: picker,
      requireHittable: false
    )
    let cancel: XCUIElement
    if cancelButtons.count == 1 {
      // iOS 26.5 会把同一个物理按钮同时暴露为 Button 和包裹用 Other。
      // Button 是唯一可操作语义，优先使用它，不能把两个 AX 代理相加计数。
      cancel = cancelButtons[0]
    } else if cancelButtons.isEmpty {
      let cancelOthers = pickerElements(
        queries: [picker.application.otherElements.matching(cancelPredicate)],
        in: picker,
        requireHittable: false
      )
      try require(cancelOthers.count == 1, "系统 Picker 的 typed Cancel 控件不是唯一控件")
      cancel = cancelOthers[0]
    } else {
      throw testFailure("系统 Picker 的 typed Cancel Button 不是唯一控件")
    }
    try require(waitForHittable(cancel, timeout: 3), "系统 Picker 的 typed Cancel 控件存在但不可点击")
    cancel.tap()
    if let returnControl {
      try require(
        waitForHittable(returnControl, timeout: 10),
        "点击 Cancel 后 Flutter 页面没有恢复可操作状态"
      )
    }
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
    app: XCUIApplication,
    preview: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(
      format: "value MATCHES %@",
      fixtureLyricsAccessibilityPattern
    )
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      // iOS 26 的 Flutter 远程 AX snapshot 能在 app 级 typed query 中返回歌词
      // Other，但从父 preview 执行 descendants 查询会丢失同一节点。这里保持
      // 精确值与唯一性，并用 frame 证明节点确实属于预览区域。
      let candidates = app.otherElements.matching(predicate).allElementsBoundByIndex.filter {
        $0.exists && preview.frame.contains(
          CGPoint(x: $0.frame.midX, y: $0.frame.midY)
        )
      }
      if candidates.count == 1 {
        return true
      }
      if candidates.count > 1 {
        return false
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
