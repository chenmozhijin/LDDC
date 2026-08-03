import 'dart:io';

import 'package:lddc/src/app/bootstrap/app_bootstrap.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/infra/storage/app_storage_paths_io.dart';
import 'package:lddc/src/infra/storage/config_file_storage_io.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 为单个真实应用场景提供完全隔离的配置、缓存和导出目录。
///
/// 该类型不初始化 Flutter 测试 binding，资源生命周期完全由场景控制。
/// 调用方必须在自己的 `finally` 中执行 [dispose]，避免数据库和临时目录泄漏。
class IntegrationWorkspace {
  IntegrationWorkspace._({
    required this.root,
    required this.exportsDir,
    required this.artifactsDir,
    required this.paths,
    required this.cache,
    required this.configRepository,
  });

  final Directory root;
  final Directory exportsDir;
  final Directory artifactsDir;
  final AppStoragePaths paths;
  final CacheFacade cache;
  final DefaultConfigRepository configRepository;

  static Future<IntegrationWorkspace> create(
    String scenarioName, {
    Directory? parentDirectory,
  }) async {
    final Directory workspaceParent = parentDirectory ?? Directory.systemTemp;
    await workspaceParent.create(recursive: true);
    final Directory root = await workspaceParent.createTemp(
      'lddc_it_${scenarioName}_',
    );
    final Directory exportsDir = Directory(
      '${root.path}${Platform.pathSeparator}exports',
    );
    final Directory artifactsDir = Directory(
      '${root.path}${Platform.pathSeparator}artifacts',
    );
    await exportsDir.create(recursive: true);
    await artifactsDir.create(recursive: true);
    final AppStoragePaths paths = AppStoragePaths(
      isWindows: Platform.isWindows,
      isLinux: Platform.isLinux,
      isMacOS: Platform.isMacOS,
      windowsKnownFolderResolver: (_) async => root.path,
      applicationSupportDirectoryResolver: () async => root,
      applicationCacheDirectoryResolver: () async => root,
      applicationDocumentsDirectoryResolver: () async => root,
      libraryDirectoryResolver: () async => root,
    );
    final DefaultConfigRepository repository = DefaultConfigRepository(
      storage: JsonFileConfigStorage(paths: paths),
    );
    final CacheFacade cache = createDefaultCacheFacade(
      databasePathResolver: () async =>
          (await paths.resolveCacheDatabaseFile()).path,
      memoryCapacity: 128,
    );
    await repository.load();
    return IntegrationWorkspace._(
      root: root,
      exportsDir: exportsDir,
      artifactsDir: artifactsDir,
      paths: paths,
      cache: cache,
      configRepository: repository,
    );
  }

  Future<void> dispose() async {
    await configRepository.dispose();
    await cache.dispose();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
    await AppBootstrap.disposeForTest();
  }
}
