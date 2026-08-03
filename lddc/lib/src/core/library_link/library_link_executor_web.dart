import 'package:drift/drift.dart';

Future<QueryExecutor> createDefaultLibraryLinkExecutorImpl() {
  // 关联库依赖本地歌词数据库语义和大量桌面文件操作；当前 Web 端没有完整
  // 文件/标签能力，继续保留 deprecated WebDatabase 只会制造“似乎可用”的假入口。
  return Future<QueryExecutor>.error(UnsupportedError('当前平台不支持歌词关联库'));
}
