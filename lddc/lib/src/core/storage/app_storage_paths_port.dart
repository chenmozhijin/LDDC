import 'dart:io';

/// 应用持久化路径端口。
///
/// core 层只声明自己需要哪些文件或目录，不直接依赖具体平台实现。桌面、
/// Android、iOS 等目录规则由 infra/platform 层实现后在应用启动阶段注册。
abstract interface class AppStoragePathsPort {
  Future<Directory> resolveDataDirectory();

  Future<File> resolveCacheDatabaseFile();

  Future<File> resolveLibraryLinkDatabaseFile();

  Future<Directory> resolveLogDirectory();

  Future<File> resolveInfoFile();
}

/// core 层默认路径端口注册表。
///
/// 缓存、日志和关联库可能在不同 Provider 中按需初始化；统一通过这个注册表
/// 取路径端口，可以避免每个 core 模块各自导入 infra 的平台路径实现。
abstract final class AppStoragePathsRegistry {
  static AppStoragePathsPort? _current;

  static void register(AppStoragePathsPort paths) {
    _current = paths;
  }

  static AppStoragePathsPort get current {
    final AppStoragePathsPort? paths = _current;
    if (paths == null) {
      throw StateError('AppStoragePathsPort 尚未注册，无法解析持久化路径。');
    }
    return paths;
  }
}
