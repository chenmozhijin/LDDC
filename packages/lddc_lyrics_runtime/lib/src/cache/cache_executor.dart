import 'package:drift/drift.dart';

import 'cache_executor_stub.dart'
    if (dart.library.io) 'cache_executor_io.dart'
    if (dart.library.html) 'cache_executor_web.dart';

/// 为调用方提供的数据库路径创建缓存执行器。
Future<QueryExecutor> createCacheExecutor({String? databasePath}) {
  return createCacheExecutorImpl(databasePath: databasePath);
}
