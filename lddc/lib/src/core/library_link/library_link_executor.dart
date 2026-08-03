import 'package:drift/drift.dart';

import 'library_link_executor_stub.dart'
    if (dart.library.io) 'library_link_executor_io.dart'
    if (dart.library.html) 'library_link_executor_web.dart';

/// 创建默认关联库数据库执行器（按平台选择 IO / Web 实现）。
Future<QueryExecutor> createDefaultLibraryLinkExecutor() {
  return createDefaultLibraryLinkExecutorImpl();
}
