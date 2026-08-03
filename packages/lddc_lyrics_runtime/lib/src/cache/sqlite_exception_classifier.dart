import 'sqlite_exception_classifier_stub.dart'
    if (dart.library.io) 'sqlite_exception_classifier_io.dart';

/// 判断错误是否为 SQLite 的 busy/locked 瞬时写入失败。
///
/// 这里刻意不直接导入 `package:sqlite3`：Flutter Web/Wasm 的 dry-run 会静态扫描
/// 生产库，只要公共缓存层碰到 sqlite3/ffi，就可能把 IO-only 依赖带进 Web 检查。
/// 条件导入让真实类型判断只存在于 dart:io 平台，非 IO 平台由 stub 返回 false，
/// 调用方仍会继续使用错误文本兜底，因此不会丢失已有的降级行为。
bool isTransientSqliteBusyError(Object error) {
  return isTransientSqliteBusyErrorImpl(error);
}
