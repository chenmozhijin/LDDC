import '../../core/capability/capability.dart';
import '../../core/config/config.dart';
import '../../core/logging/logging.dart';
import 'app_bootstrap_storage.dart'
    if (dart.library.io) 'app_bootstrap_storage_io.dart';

/// 启动期引导：初始化配置与能力开关。
class AppBootstrap {
  AppBootstrap._();

  static final ConfigRepository _defaultConfigRepository =
      _createDefaultConfigRepository();
  static ConfigRepository _configRepository = _defaultConfigRepository;
  static AppConfig _config = ConfigDefaults.current;
  static AppCapability _capability = AppCapabilityResolver.resolveCurrent();
  static bool _corePortsRegistered = false;
  static Future<void>? _initializationBarrier;

  static ConfigRepository get configRepository => _configRepository;
  static AppConfig get config => _config;
  static AppCapability get capability => _capability;

  /// 注册 core 层需要的默认端口实现。
  ///
  /// 日志、缓存和关联库可能早于页面 Provider 初始化，因此启动入口需要先调用
  /// 这个方法，把平台路径实现交给 core 层的端口注册表。
  static void ensureCorePortsRegistered() {
    if (_corePortsRegistered) {
      return;
    }
    registerBootstrapStoragePorts();
    _corePortsRegistered = true;
  }

  /// 初始化启动快照。
  ///
  /// 默认使用平台文件仓储；Web 与测试可通过 override 替换。
  static Future<void> ensureInitialized({
    ConfigRepository? configRepository,
    AppCapability? capabilityOverride,
    WebCapabilityProbe webCapabilityProbe = const DefaultWebCapabilityProbe(),
  }) {
    // 配置读取和能力探测都可能跨越异步边界。若两个入口同时初始化，直接并发
    // 执行会让较慢的旧调用覆盖较新的快照。这里使用 Future 链按调用顺序提交，
    // 同时把失败从内部屏障中消费掉，使一次启动失败不会永久阻塞后续重试。
    final Future<void> previous =
        _initializationBarrier ?? Future<void>.value();
    final Future<void> operation = previous.then((_) {
      return _initialize(
        configRepository: configRepository,
        capabilityOverride: capabilityOverride,
        webCapabilityProbe: webCapabilityProbe,
      );
    });
    late final Future<void> barrier;
    barrier = operation.then<void>(
      (_) {
        if (identical(_initializationBarrier, barrier)) {
          _initializationBarrier = null;
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_initializationBarrier, barrier)) {
          _initializationBarrier = null;
        }
      },
    );
    _initializationBarrier = barrier;
    return operation;
  }

  static Future<void> _initialize({
    required ConfigRepository? configRepository,
    required AppCapability? capabilityOverride,
    required WebCapabilityProbe webCapabilityProbe,
  }) async {
    ensureCorePortsRegistered();
    if (configRepository != null) {
      _configRepository = configRepository;
    }
    _config = await _configRepository.load();
    AppLogRuntime.updateLevel(_config.app.logLevel);
    if (capabilityOverride != null) {
      _capability = capabilityOverride;
      return;
    }
    final WebCapabilitySnapshot webCapabilities = await webCapabilityProbe
        .probe();
    _capability = AppCapabilityResolver.resolveCurrent(
      webFileSystemAccess: webCapabilities.fileSystemAccess,
      webTaglibWasmReady: webCapabilities.taglibWasmReady,
    );
  }

  /// 测试重置：避免静态快照跨测试泄漏。
  static void resetForTest() {
    ensureCorePortsRegistered();
    // Future 会记住创建它的 Zone。测试重置只清空队列，不在旧 FakeAsync Zone
    // 中创建替代 Future；下一次初始化会在调用方当前 Zone 内建立新屏障。
    _initializationBarrier = null;
    _configRepository = _defaultConfigRepository;
    _config = ConfigDefaults.current;
    _capability = AppCapabilityResolver.resolveCurrent(
      webFileSystemAccess: false,
      webTaglibWasmReady: false,
    );
  }

  /// 测试销毁：当前与重置语义保持一致。
  static Future<void> disposeForTest() async {
    await _initializationBarrier;
    resetForTest();
    await AppLogRuntime.resetForTest();
  }

  static ConfigRepository _createDefaultConfigRepository() {
    return createBootstrapConfigRepository();
  }
}
