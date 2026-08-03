import '../../core/config/config.dart';
import '../../core/logging/logging.dart';

ConfigRepository createBootstrapConfigRepository() {
  final AppLogger logger = AppLogger.scope('config');
  return DefaultConfigRepository(
    storage: InMemoryConfigStorage(),
    diagnosticSink: (String message, Map<String, Object?> fields) {
      logger.warning(message, fields: fields);
    },
  );
}

void registerBootstrapStoragePorts() {
  // Web 没有本地 sqlite/cache/log 文件路径，不能注册基于 dart:io 的路径端口。
  // 依赖文件路径的功能页会在 Web scope 中降级为不可用状态。
}
