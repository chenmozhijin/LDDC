import Flutter
import UIKit
import Darwin
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
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

private enum IOSSearchFilePendingAction {
  case pickAudioFile
  case saveTextFile
}

private final class IOSSearchAudioTagPlugin: NSObject,
  FlutterPlugin,
  UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  static let pluginName = "IOSSearchAudioTagPlugin"
  private static let channelName = "lddc/ios_search_audio_tag"

  private let channel: FlutterMethodChannel
  private var pendingResult: FlutterResult?
  private var pendingAction: IOSSearchFilePendingAction?
  private var activePicker: UIDocumentPickerViewController?
  private var pendingExportFileURL: URL?
  private let openedFiles = IOSOpenedAudioFileRegistry()
  private let pendingExportFileStore = IOSPendingExportFileStore()

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    // 上一次进程可能在系统导出界面中被直接终止；初始化时清理遗留目录，
    // 使下一次启动成为确定性的资源回收边界。
    pendingExportFileStore.cleanupStaleExports()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppWillTerminate),
      name: UIApplication.willTerminateNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    closeAllOpenedFiles()
    cleanupPendingExportFile()
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
      closeAllOpenedFiles()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handlePickAudioFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "busy",
          message: "已有 iOS 音频选择请求未完成",
          details: nil
        )
      )
      return
    }

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

    pendingResult = result
    pendingAction = .pickAudioFile
    let picker = buildAudioPicker(arguments: call.arguments as? [String: Any])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    picker.presentationController?.delegate = self
    activePicker = picker
    presenter.present(picker, animated: true)
  }

  private func handleSaveTextFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "busy",
          message: "已有 iOS 文件保存请求未完成",
          details: nil
        )
      )
      return
    }

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

    do {
      let exportFileURL = try createExportFileURL(fileName: fileName)
      pendingExportFileURL = exportFileURL
      try bytes.write(to: exportFileURL, options: .atomic)
      pendingResult = result
      pendingAction = .saveTextFile
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
      cleanupPendingExportFile()
      result(
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
    openedFiles.close(fileDescriptor: fileDescriptor)
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
    let rawIdentifier = arguments["identifier"] as? String
    let rawPath = arguments["path"] as? String
    guard let url = resolveAudioFileURL(identifier: rawIdentifier, path: rawPath) else {
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

    if #available(iOS 13.0, *),
      let initialDirectoryURL = resolveInitialDirectoryURL(arguments["initialDirectory"])
    {
      picker.directoryURL = initialDirectoryURL
    }
    return picker
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPendingRequest(with: nil)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finishPendingRequest(with: nil)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    switch pendingAction {
    case .pickAudioFile:
      handlePickedAudioFile(urls: urls)
    case .saveTextFile:
      handleSavedTextFile(urls: urls)
    case .none:
      return
    }
  }

  private func handlePickedAudioFile(urls: [URL]) {
    guard let url = urls.first else {
      finishPendingRequest(with: nil)
      return
    }

    guard url.isFileURL else {
      finishPendingRequest(
        with: FlutterError(
          code: "open_fd_failed",
          message: "选择的文件不是本地文件 URL",
          details: nil
        )
      )
      return
    }

    openAudioFileURL(url, flags: O_RDONLY, canWrite: false) { value in
      self.finishPendingRequest(with: value)
    }
  }

  private func openAudioFileURL(
    _ url: URL,
    flags: Int32,
    canWrite: Bool,
    result: @escaping FlutterResult
  ) {
    let startedAccessing = url.startAccessingSecurityScopedResource()
    let fileDescriptor = Darwin.open(url.path, flags)
    if fileDescriptor < 0 {
      if startedAccessing {
        url.stopAccessingSecurityScopedResource()
      }
      let errorMessage = String(cString: strerror(errno))
      result(
        FlutterError(
          code: "open_fd_failed",
          message: "打开音频文件失败：\(errorMessage)",
          details: nil
        )
      )
      return
    }

    // iOS 侧必须保留 fd 与 security-scoped 生命周期，Dart 业务完成后再显式释放。
    guard
      openedFiles.register(
        fileDescriptor: fileDescriptor,
        url: url,
        startedAccessingSecurityScopedResource: startedAccessing
      )
    else {
      // 相同整数仍在注册表中说明所有权冲突；立即关闭新句柄并回收访问权，
      // 不能把一个 fd 同时交给两个 Dart 会话。
      _ = Darwin.close(fileDescriptor)
      if startedAccessing {
        url.stopAccessingSecurityScopedResource()
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
    result(
      [
        "name": url.lastPathComponent,
        "path": url.path,
        "identifier": url.absoluteString,
        "fileDescriptor": Int(fileDescriptor),
        "fileDescriptorNameHint": url.lastPathComponent,
        "canRead": true,
        "canWrite": canWrite,
      ]
    )
  }

  private func handleSavedTextFile(urls: [URL]) {
    guard let url = urls.first else {
      finishPendingRequest(with: nil)
      return
    }

    // iOS 单文件导出返回用户最终确认的目标 URL，仅用于成功提示，不再回写桌面目录状态。
    let savePath = url.isFileURL ? url.path : url.absoluteString
    finishPendingRequest(with: savePath)
  }

  private func finishPendingRequest(with value: Any?) {
    activePicker?.dismiss(animated: true)
    activePicker = nil
    let completedAction = pendingAction
    pendingAction = nil
    if completedAction == .saveTextFile {
      cleanupPendingExportFile()
    }
    guard let result = pendingResult else {
      return
    }
    pendingResult = nil
    result(value)
  }

  private func createExportFileURL(fileName: String) throws -> URL {
    return try pendingExportFileStore.create(fileName: fileName)
  }

  private func cleanupPendingExportFile() {
    guard let exportFileURL = pendingExportFileURL else {
      return
    }
    pendingExportFileStore.cleanup(fileURL: exportFileURL)
    pendingExportFileURL = nil
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

  private func resolveAudioFileURL(identifier: String?, path: String?) -> URL? {
    return IOSSearchFileArguments.resolveAudioFileURL(identifier: identifier, path: path)
  }

  @objc private func handleAppWillTerminate() {
    closeAllOpenedFiles()
    activePicker = nil
    pendingAction = nil
    pendingResult = nil
    cleanupPendingExportFile()
  }

  private func closeAllOpenedFiles() {
    openedFiles.closeAll()
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
