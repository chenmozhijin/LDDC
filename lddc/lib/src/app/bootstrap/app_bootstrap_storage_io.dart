import '../../core/config/config.dart';
import '../../core/logging/logging.dart';
import '../../core/storage/app_storage_paths_port.dart';
import '../../infra/storage/app_storage_paths.dart';
import '../../infra/storage/default_config_storage.dart';

ConfigRepository createBootstrapConfigRepository() {
  final AppLogger logger = AppLogger.scope('config');
  return DefaultConfigRepository(
    storage: createDefaultConfigStorage(),
    defaultSavePathResolver: () async {
      final directory = await AppStoragePaths()
          .resolveDefaultSaveLyricsDirectory();
      return directory.path;
    },
    diagnosticSink: (String message, Map<String, Object?> fields) {
      logger.warning(message, fields: fields);
    },
  );
}

void registerBootstrapStoragePorts() {
  AppStoragePathsRegistry.register(AppStoragePaths());
}
