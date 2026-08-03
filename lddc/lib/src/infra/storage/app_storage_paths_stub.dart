import 'dart:io';

import '../../core/storage/app_storage_paths_port.dart';

class AppStoragePaths implements AppStoragePathsPort {
  Future<Directory> resolveConfigDirectory() async {
    throw UnsupportedError('当前平台不支持配置目录解析');
  }

  @override
  Future<Directory> resolveDataDirectory() async {
    throw UnsupportedError('当前平台不支持数据目录解析');
  }

  Future<Directory> resolveCacheDirectory() async {
    throw UnsupportedError('当前平台不支持缓存目录解析');
  }

  @override
  Future<Directory> resolveLogDirectory() async {
    throw UnsupportedError('当前平台不支持日志目录解析');
  }

  Future<Directory> resolveDefaultSaveLyricsDirectory() async {
    throw UnsupportedError('当前平台不支持默认歌词保存目录解析');
  }

  Future<File> resolveConfigFile() async {
    throw UnsupportedError('当前平台不支持配置文件路径解析');
  }

  @override
  Future<File> resolveCacheDatabaseFile() async {
    throw UnsupportedError('当前平台不支持缓存数据库路径解析');
  }

  @override
  Future<File> resolveLibraryLinkDatabaseFile() async {
    throw UnsupportedError('当前平台不支持关联库数据库路径解析');
  }

  @override
  Future<File> resolveInfoFile() async {
    throw UnsupportedError('当前平台不支持服务信息文件路径解析');
  }
}
