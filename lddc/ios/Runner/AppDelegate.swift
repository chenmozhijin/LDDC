import Flutter
import UIKit
import Darwin
import UniformTypeIdentifiers
#if LDDC_PLATFORM_TEST
import CryptoKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    #if LDDC_PLATFORM_TEST
    do {
      try IOSPlatformTestFixtureSeeder.seedIfRequested()
    } catch {
      // PlatformTest app 若无法准备匿名 fixture，继续启动只会让 Files 选择场景
      // 以“找不到文件”失败并掩盖真实基础设施原因，因此在测试配置中直接拒绝启动。
      NSLog("LDDC PlatformTest fixture seed failed: \(error)")
      return false
    }
    #endif
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: IOSSearchAudioTagPlugin.pluginName
    ) {
      IOSSearchAudioTagPlugin.register(with: registrar)
    }
  }
}

#if LDDC_PLATFORM_TEST
/// 仅编译进 PlatformTest app 的匿名 fixture 写入器。
///
/// `xcodebuild test-without-building` 可能在每个 XCUITest 前重新安装应用并更换
/// Simulator container，宿主脚本提前复制到 Documents 的文件因此不可靠。测试进程
/// 通过 launch environment 传入仓库内匿名 fixture，应用仍把它写入真实 Documents，
/// 后续 UIDocumentPicker、security-scoped fd 与 TagLib 全部继续走生产实现。
private enum IOSPlatformTestFixtureSeeder {
  private static let fixtureNameKey = "LDDC_PLATFORM_TEST_FIXTURE_NAME"
  private static let fixtureBase64Key = "LDDC_PLATFORM_TEST_FIXTURE_BASE64"
  private static let resetKey = "LDDC_PLATFORM_TEST_RESET_FIXTURES"

  static func seedIfRequested(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) throws {
    guard let rawName = environment[fixtureNameKey],
          !rawName.isEmpty,
          URL(fileURLWithPath: rawName).lastPathComponent == rawName,
          !rawName.contains("/"),
          !rawName.contains("\\")
    else {
      throw seedError("fixture name 缺失或不是单一文件名")
    }
    guard let rawBase64 = environment[fixtureBase64Key],
          let bytes = Data(base64Encoded: rawBase64),
          !bytes.isEmpty
    else {
      throw seedError("fixture base64 缺失或无效")
    }
    guard let documents = fileManager.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first else {
      throw seedError("无法解析 PlatformTest Documents 目录")
    }
    try fileManager.createDirectory(
      at: documents,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let shouldReset = environment[resetKey] == "1"
    if shouldReset {
      // PlatformTest 使用独立 bundle id 和独立容器。每个 XCTest 首次启动只清理
      // 该测试容器，避免前一场景的导出物或已写标签音频污染下一场景。
      for entry in try fileManager.contentsOfDirectory(
        at: documents,
        includingPropertiesForKeys: nil
      ) {
        try fileManager.removeItem(at: entry)
      }
    }

    let fixtureURL = documents.appendingPathComponent(rawName, isDirectory: false)
    if shouldReset || !fileManager.fileExists(atPath: fixtureURL.path) {
      try bytes.write(to: fixtureURL, options: .atomic)
    }
  }

  private static func seedError(_ message: String) -> NSError {
    NSError(
      domain: "LDDCPlatformTestFixtureSeeder",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

/// 只在 PlatformTest app 中记录真实导出 URL 的可验证摘要。
///
/// 保存目标位于系统 LocalStorage provider 时，宿主无法通过应用 data container
/// 直接读取用户文件。观察器在 delegate 收到最终 URL 的同一时刻读取文件，并把
/// 不含路径的最小 witness 写回测试容器；正式构建完全不包含这段代码。
private enum IOSPlatformExportWitnessRecorder {
  static let witnessFileName = ".lddc_platform_export_witness.json"

  static func record(
    exportedURL: URL,
    fileManager: FileManager = .default
  ) {
    let startedAccessing = exportedURL.startAccessingSecurityScopedResource()
    defer {
      if startedAccessing {
        exportedURL.stopAccessingSecurityScopedResource()
      }
    }

    var payload: [String: Any]
    do {
      let data = try Data(contentsOf: exportedURL, options: [.mappedIfSafe])
      let digest = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
      payload = [
        "schemaVersion": 1,
        "fileName": exportedURL.lastPathComponent,
        "size": data.count,
        "sha256": digest,
        "utf8Base64": data.base64EncodedString(),
        "success": true,
      ]
    } catch {
      payload = [
        "schemaVersion": 1,
        "fileName": exportedURL.lastPathComponent,
        "size": 0,
        "sha256": "",
        "utf8Base64": "",
        "success": false,
        "errorClass": String(reflecting: type(of: error)),
      ]
    }

    do {
      try fileManager.removeItem(at: exportedURL)
      payload["cleanupSucceeded"] = true
    } catch {
      // 测试输出已经完成读取和摘要后应立即删除，避免污染同一 Simulator 的后续
      // 取消场景。删除失败只进入 witness，不改变生产 delegate 的完成语义。
      payload["cleanupSucceeded"] = false
      payload["cleanupErrorClass"] = String(reflecting: type(of: error))
    }

    do {
      guard let documents = fileManager.urls(
        for: .documentDirectory,
        in: .userDomainMask
      ).first else {
        throw witnessError("无法解析 PlatformTest Documents 目录")
      }
      let witnessURL = documents.appendingPathComponent(
        witnessFileName,
        isDirectory: false
      )
      let data = try JSONSerialization.data(
        withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys]
      )
      try data.write(to: witnessURL, options: .atomic)
    } catch {
      // witness 只用于测试后验，写入失败不能改变真实保存回调；runner 会因文件
      // 缺失而让场景失败。日志只记录错误类型，禁止输出用户路径或 URL。
      NSLog("LDDC PlatformTest export witness failed: \(type(of: error))")
    }
  }

  private static func witnessError(_ message: String) -> NSError {
    NSError(
      domain: "LDDCPlatformExportWitness",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
#endif

private struct IOSOpenedAudioFileHandle {
  let url: URL
  let startedAccessingSecurityScopedResource: Bool
}

/// 统一拥有 iOS 文件描述符与 security-scoped 访问生命周期。
///
/// Dart 只持有整数 fd，系统可能在关闭后复用该整数。注册表先移除所有权再执行
/// close，使重复释放成为幂等操作，避免误关后来复用同一整数的其他文件。
final class IOSOpenedAudioFileRegistry {
  typealias CloseDescriptor = (Int32) -> Int32
  typealias StopAccessing = (URL) -> Void

  private var openedFiles: [Int32: IOSOpenedAudioFileHandle] = [:]
  private let closeDescriptor: CloseDescriptor
  private let stopAccessing: StopAccessing

  init(
    closeDescriptor: @escaping CloseDescriptor = { fileDescriptor in
      Darwin.close(fileDescriptor)
    },
    stopAccessing: @escaping StopAccessing = { url in
      url.stopAccessingSecurityScopedResource()
    }
  ) {
    self.closeDescriptor = closeDescriptor
    self.stopAccessing = stopAccessing
  }

  var count: Int {
    return openedFiles.count
  }

  @discardableResult
  func register(
    fileDescriptor: Int32,
    url: URL,
    startedAccessingSecurityScopedResource: Bool
  ) -> Bool {
    guard fileDescriptor >= 0, openedFiles[fileDescriptor] == nil else {
      return false
    }
    openedFiles[fileDescriptor] = IOSOpenedAudioFileHandle(
      url: url,
      startedAccessingSecurityScopedResource: startedAccessingSecurityScopedResource
    )
    return true
  }

  func close(fileDescriptor: Int32) {
    guard let opened = openedFiles.removeValue(forKey: fileDescriptor) else {
      return
    }
    _ = closeDescriptor(fileDescriptor)
    if opened.startedAccessingSecurityScopedResource {
      stopAccessing(opened.url)
    }
  }

  func closeAll() {
    let files = openedFiles
    openedFiles.removeAll(keepingCapacity: false)
    for (fileDescriptor, opened) in files {
      _ = closeDescriptor(fileDescriptor)
      if opened.startedAccessingSecurityScopedResource {
        stopAccessing(opened.url)
      }
    }
  }
}

enum IOSSearchFileArguments {
  static func sanitizedFileName(_ value: String) -> String {
    return value.replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\\", with: "_")
  }

  static func resolveAudioFileURL(identifier: String?, path: String?) -> URL? {
    if let rawIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawIdentifier.isEmpty,
      let url = URL(string: rawIdentifier),
      url.isFileURL
    {
      return url
    }
    if let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawPath.isEmpty
    {
      return URL(fileURLWithPath: rawPath)
    }
    return nil
  }
}

/// 管理 iOS 导出前的临时文件，保证展示给用户的文件名不包含内部 UUID。
///
/// 每次导出使用独立子目录解决并发与同名覆盖；成功、取消和正常终止都删除当前
/// 子目录。进程被系统直接杀死时不会收到清理回调，因此下次插件初始化还会清除
/// 上次残留的根目录，避免临时歌词长期占用用户空间。
final class IOSPendingExportFileStore {
  private let fileManager: FileManager
  private let rootDirectory: URL

  init(
    fileManager: FileManager = .default,
    rootDirectory: URL? = nil
  ) {
    self.fileManager = fileManager
    self.rootDirectory = rootDirectory
      ?? fileManager.temporaryDirectory.appendingPathComponent(
        "lddc_search_exports",
        isDirectory: true
      )
  }

  func cleanupStaleExports() {
    try? fileManager.removeItem(at: rootDirectory)
  }

  func create(fileName: String) throws -> URL {
    let exportDirectory = rootDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(
      at: exportDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )
    return exportDirectory.appendingPathComponent(
      IOSSearchFileArguments.sanitizedFileName(fileName),
      isDirectory: false
    )
  }

  func cleanup(fileURL: URL?) {
    guard let fileURL else {
      return
    }
    let exportDirectory = fileURL.deletingLastPathComponent().standardizedFileURL
    guard exportDirectory.deletingLastPathComponent().standardizedFileURL
      == rootDirectory.standardizedFileURL
    else {
      // 只删除当前 store 创建的唯一子目录，绝不扩大到任意调用方路径。
      return
    }
    try? fileManager.removeItem(at: exportDirectory)
  }
}

enum IOSSearchFilePendingAction: Equatable {
  case pickAudioFile
  case saveTextFile
}

/// 管理 Document Picker 请求、Flutter 回调和文件资源所有权。
///
/// UIKit delegate 只负责把系统事件转发到这里。状态机不依赖 accessibility 或
/// 测试通道，因此 RunnerTests 可以直接验证生产回调、FD、取消和导出清理契约。
final class IOSDocumentPickerRequestCoordinator {
  typealias StartAccessing = (URL) -> Bool
  typealias StopAccessing = (URL) -> Void
  typealias OpenDescriptor = (URL, Int32) -> Int32
  typealias ExportObserver = (URL) -> Void

  private var pendingResult: FlutterResult?
  private var pendingAction: IOSSearchFilePendingAction?
  private var pendingExportFileURL: URL?
  private let openedFiles: IOSOpenedAudioFileRegistry
  private let pendingExportFileStore: IOSPendingExportFileStore
  private let startAccessing: StartAccessing
  private let stopAccessing: StopAccessing
  private let openDescriptor: OpenDescriptor

  init(
    openedFiles: IOSOpenedAudioFileRegistry = IOSOpenedAudioFileRegistry(),
    pendingExportFileStore: IOSPendingExportFileStore = IOSPendingExportFileStore(),
    startAccessing: @escaping StartAccessing = { url in
      url.startAccessingSecurityScopedResource()
    },
    stopAccessing: @escaping StopAccessing = { url in
      url.stopAccessingSecurityScopedResource()
    },
    openDescriptor: @escaping OpenDescriptor = { url, flags in
      Darwin.open(url.path, flags)
    }
  ) {
    self.openedFiles = openedFiles
    self.pendingExportFileStore = pendingExportFileStore
    self.startAccessing = startAccessing
    self.stopAccessing = stopAccessing
    self.openDescriptor = openDescriptor
    pendingExportFileStore.cleanupStaleExports()
  }

  var pendingRequestCount: Int { pendingResult == nil ? 0 : 1 }
  var openFileDescriptorCount: Int { openedFiles.count }

  @discardableResult
  func begin(action: IOSSearchFilePendingAction, result: @escaping FlutterResult) -> Bool {
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "busy",
          message: action == .pickAudioFile
            ? "已有 iOS 音频选择请求未完成"
            : "已有 iOS 文件保存请求未完成",
          details: nil
        )
      )
      return false
    }
    pendingAction = action
    pendingResult = result
    return true
  }

  func prepareExport(fileName: String, bytes: Data) throws -> URL {
    let exportFileURL = try pendingExportFileStore.create(fileName: fileName)
    do {
      try bytes.write(to: exportFileURL, options: .atomic)
      pendingExportFileURL = exportFileURL
      return exportFileURL
    } catch {
      pendingExportFileStore.cleanup(fileURL: exportFileURL)
      throw error
    }
  }

  func completePickedDocuments(
    _ urls: [URL],
    exportObserver: ExportObserver? = nil
  ) {
    switch pendingAction {
    case .pickAudioFile:
      completePickedAudio(urls)
    case .saveTextFile:
      completeSavedText(urls, exportObserver: exportObserver)
    case .none:
      return
    }
  }

  func cancel() {
    finish(with: nil)
  }

  func failCurrentRequest(_ error: FlutterError) {
    finish(with: error)
  }

  func openAudioFileForWrite(
    identifier: String?,
    path: String?,
    result: @escaping FlutterResult
  ) {
    guard let url = IOSSearchFileArguments.resolveAudioFileURL(
      identifier: identifier,
      path: path
    ) else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "音频写入升级缺少有效 identifier/path",
          details: nil
        )
      )
      return
    }
    openAudioFileURL(url, flags: O_RDWR, canWrite: true, result: result)
  }

  func close(fileDescriptor: Int32) {
    openedFiles.close(fileDescriptor: fileDescriptor)
  }

  func closeAll() {
    openedFiles.closeAll()
  }

  func terminate() {
    pendingResult = nil
    pendingAction = nil
    cleanupPendingExportFile()
    openedFiles.closeAll()
  }

  private func completePickedAudio(_ urls: [URL]) {
    guard let url = urls.first else {
      finish(with: nil)
      return
    }
    guard url.isFileURL else {
      finish(
        with: FlutterError(
          code: "open_fd_failed",
          message: "选择的文件不是本地文件 URL",
          details: nil
        )
      )
      return
    }
    openAudioFileURL(url, flags: O_RDONLY, canWrite: false) { value in
      self.finish(with: value)
    }
  }

  private func completeSavedText(_ urls: [URL], exportObserver: ExportObserver?) {
    guard let url = urls.first else {
      finish(with: nil)
      return
    }
    exportObserver?(url)
    finish(with: url.isFileURL ? url.path : url.absoluteString)
  }

  private func openAudioFileURL(
    _ url: URL,
    flags: Int32,
    canWrite: Bool,
    result: @escaping FlutterResult
  ) {
    let startedAccessing = startAccessing(url)
    let fileDescriptor = openDescriptor(url, flags)
    if fileDescriptor < 0 {
      if startedAccessing {
        stopAccessing(url)
      }
      result(
        FlutterError(
          code: "open_fd_failed",
          message: "打开音频文件失败：\(String(cString: strerror(errno)))",
          details: nil
        )
      )
      return
    }
    guard openedFiles.register(
      fileDescriptor: fileDescriptor,
      url: url,
      startedAccessingSecurityScopedResource: startedAccessing
    ) else {
      _ = Darwin.close(fileDescriptor)
      if startedAccessing {
        stopAccessing(url)
      }
      result(
        FlutterError(
          code: "fd_registry_conflict",
          message: "iOS 文件描述符所有权冲突",
          details: nil
        )
      )
      return
    }
    result([
      "name": url.lastPathComponent,
      "path": url.path,
      "identifier": url.absoluteString,
      "fileDescriptor": Int(fileDescriptor),
      "fileDescriptorNameHint": url.lastPathComponent,
      "canRead": true,
      "canWrite": canWrite,
    ])
  }

  private func finish(with value: Any?) {
    let completedAction = pendingAction
    let result = pendingResult
    pendingAction = nil
    pendingResult = nil
    if completedAction == .saveTextFile {
      cleanupPendingExportFile()
    }
    result?(value)
  }

  private func cleanupPendingExportFile() {
    guard let pendingExportFileURL else { return }
    pendingExportFileStore.cleanup(fileURL: pendingExportFileURL)
    self.pendingExportFileURL = nil
  }
}

private final class IOSSearchAudioTagPlugin: NSObject,
  FlutterPlugin,
  UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  static let pluginName = "IOSSearchAudioTagPlugin"
  private static let channelName = "lddc/ios_search_audio_tag"

  private let channel: FlutterMethodChannel
  private var activePicker: UIDocumentPickerViewController?
  private let requestCoordinator = IOSDocumentPickerRequestCoordinator()

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppWillTerminate),
      name: UIApplication.willTerminateNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    requestCoordinator.terminate()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = IOSSearchAudioTagPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickAudioFile":
      handlePickAudioFile(call: call, result: result)
    case "openAudioFileForWrite":
      handleOpenAudioFileForWrite(call: call, result: result)
    case "saveTextFile":
      handleSaveTextFile(call: call, result: result)
    case "closeFd":
      handleCloseFd(call: call, result: result)
    case "closeAllOpenedFiles":
      requestCoordinator.closeAll()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handlePickAudioFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "unavailable",
          message: "无法获取当前页面上下文",
          details: nil
        )
      )
      return
    }
    guard requestCoordinator.begin(action: .pickAudioFile, result: result) else {
      return
    }
    let picker = buildAudioPicker(arguments: call.arguments as? [String: Any])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    picker.presentationController?.delegate = self
    activePicker = picker
    presenter.present(picker, animated: true)
  }

  private func handleSaveTextFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "unavailable",
          message: "无法获取当前页面上下文",
          details: nil
        )
      )
      return
    }

    guard let arguments = call.arguments as? [String: Any],
      let fileNameValue = arguments["fileName"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "fileName 参数不能为空",
          details: nil
        )
      )
      return
    }

    let fileName = fileNameValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fileName.isEmpty else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "fileName 参数不能为空",
          details: nil
        )
      )
      return
    }

    guard let bytes = extractBytes(arguments["bytes"]) else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "bytes 参数不能为空",
          details: nil
        )
      )
      return
    }

    guard requestCoordinator.begin(action: .saveTextFile, result: result) else {
      return
    }
    do {
      let exportFileURL = try requestCoordinator.prepareExport(
        fileName: fileName,
        bytes: bytes
      )
      let picker = buildExportPicker(
        exportFileURL: exportFileURL,
        arguments: arguments
      )
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.presentationController?.delegate = self
      activePicker = picker
      presenter.present(picker, animated: true)
    } catch {
      requestCoordinator.failCurrentRequest(
        FlutterError(
          code: "write_failed",
          message: "准备导出文件失败：\(error.localizedDescription)",
          details: nil
        )
      )
    }
  }

  private func handleCloseFd(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let fdValue = arguments["fd"] as? Int
    else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "fd 参数不能为空",
          details: nil
        )
      )
      return
    }

    let fileDescriptor = Int32(fdValue)
    // 注册表只关闭自己登记的 fd；未知或重复 fd 不会触发 Darwin.close。
    requestCoordinator.close(fileDescriptor: fileDescriptor)
    result(nil)
  }

  private func handleOpenAudioFileForWrite(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "音频写入升级参数不能为空",
          details: nil
        )
      )
      return
    }
    requestCoordinator.openAudioFileForWrite(
      identifier: arguments["identifier"] as? String,
      path: arguments["path"] as? String,
      result: result
    )
  }

  private func buildAudioPicker(arguments: [String: Any]?) -> UIDocumentPickerViewController {
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.audio],
        asCopy: false
      )
    } else {
      picker = UIDocumentPickerViewController(
        documentTypes: ["public.audio"],
        in: .open
      )
    }

    // Files 默认可能隐藏扩展名，用户会看不到同名不同格式的区别，XCUITest 也无法
    // 用真实文件名确认选择产物。显式显示扩展名属于用户可见的文件选择修复，不是
    // 测试专用分支，且不会改变返回 URL 或 security-scoped 访问语义。
    picker.shouldShowFileExtensions = true

    if #available(iOS 13.0, *),
      let initialDirectoryURL = resolveInitialDirectoryURL(arguments?["initialDirectory"])
    {
      picker.directoryURL = initialDirectoryURL
    }
    return picker
  }

  private func buildExportPicker(
    exportFileURL: URL,
    arguments: [String: Any]
  ) -> UIDocumentPickerViewController {
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [exportFileURL])
    } else {
      picker = UIDocumentPickerViewController(
        url: exportFileURL,
        in: .exportToService
      )
    }

    // 导出界面同样保留扩展名，避免用户误判最终格式，并让宿主后验检查与系统界面
    // 显示使用同一个文件名契约。
    picker.shouldShowFileExtensions = true

    if #available(iOS 13.0, *),
      let initialDirectoryURL = resolveInitialDirectoryURL(arguments["initialDirectory"])
    {
      picker.directoryURL = initialDirectoryURL
    }
    return picker
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPickerUI()
    requestCoordinator.cancel()
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finishPickerUI()
    requestCoordinator.cancel()
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finishPickerUI()
    #if LDDC_PLATFORM_TEST
    requestCoordinator.completePickedDocuments(
      urls,
      exportObserver: { url in
        IOSPlatformExportWitnessRecorder.record(exportedURL: url)
      }
    )
    #else
    requestCoordinator.completePickedDocuments(urls)
    #endif
  }

  private func finishPickerUI() {
    activePicker?.dismiss(animated: true)
    activePicker = nil
  }

  private func extractBytes(_ value: Any?) -> Data? {
    switch value {
    case let typedData as FlutterStandardTypedData:
      return typedData.data
    case let data as Data:
      return data
    case let bytes as [UInt8]:
      return Data(bytes)
    default:
      return nil
    }
  }

  private func resolveInitialDirectoryURL(_ value: Any?) -> URL? {
    guard let rawValue = value as? String else {
      return nil
    }
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      return nil
    }
    if let fileURL = URL(string: normalized), fileURL.isFileURL,
      FileManager.default.fileExists(atPath: fileURL.path)
    {
      return fileURL
    }
    if FileManager.default.fileExists(atPath: normalized) {
      return URL(fileURLWithPath: normalized, isDirectory: true)
    }
    return nil
  }

  @objc private func handleAppWillTerminate() {
    activePicker = nil
    requestCoordinator.terminate()
  }

  private func topViewController() -> UIViewController? {
    let windowScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { scene in scene.activationState == .foregroundActive }
    let keyWindow = windowScene?.windows.first { $0.isKeyWindow }
    var topController = keyWindow?.rootViewController
    while let presented = topController?.presentedViewController {
      topController = presented
    }
    return topController
  }
}
