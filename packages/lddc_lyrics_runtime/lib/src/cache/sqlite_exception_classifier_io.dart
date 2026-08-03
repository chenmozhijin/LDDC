import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// IO 平台保留 sqlite3 的强类型判断。
///
/// SQLite 的 `SQLITE_BUSY` 和 `SQLITE_LOCKED` 结果码分别是 5 和 6，这类错误通常
/// 来自短时间文件锁竞争；调用方会做有限次数退避重试或跳过缓存写入，不影响业务结果。
bool isTransientSqliteBusyErrorImpl(Object error) {
  return error is sqlite3.SqliteException &&
      (error.resultCode == 5 || error.resultCode == 6);
}
