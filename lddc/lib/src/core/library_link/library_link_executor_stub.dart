import 'package:drift/drift.dart';

Future<QueryExecutor> createDefaultLibraryLinkExecutorImpl() {
  return Future<QueryExecutor>.error(UnsupportedError('当前平台未实现默认关联库数据库执行器'));
}
