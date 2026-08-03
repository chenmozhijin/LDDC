import 'package:drift/drift.dart';
// Drift 当前仍通过 WebDatabase 暴露 web 存储入口；等上游提供稳定替代 API 后再迁移。
// ignore: deprecated_member_use
import 'package:drift/web.dart';

Future<QueryExecutor> createCacheExecutorImpl({String? databasePath}) async {
  return WebDatabase('lddc_cache');
}
