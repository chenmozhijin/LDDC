// ignore_for_file: avoid_slow_async_io
// 缓存数据库初始化可能发生在应用启动链路，使用异步文件状态检查可以避免阻塞 UI isolate。

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

Future<QueryExecutor> createCacheExecutorImpl({String? databasePath}) async {
  final String normalizedPath = databasePath?.trim() ?? '';
  if (normalizedPath.isEmpty) {
    throw ArgumentError('IO 平台创建持久缓存时必须提供 databasePath');
  }
  final File dbFile = File(normalizedPath);
  final Directory dbDir = dbFile.parent;
  if (!await dbDir.exists()) {
    await dbDir.create(recursive: true);
  }
  return NativeDatabase.createInBackground(dbFile);
}
