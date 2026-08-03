/// 非 IO 平台不能引用 sqlite3/ffi，因此这里只返回 false。
///
/// 调用方还会检查错误文本中的 `database is locked/busy`，这个 stub 的目的只是
/// 避免 Web/Wasm 编译链路静态触碰本地 SQLite 类型。
bool isTransientSqliteBusyErrorImpl(Object error) => false;
