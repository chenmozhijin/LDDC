/// 文件日志保留策略。
///
/// 清理过程同时受扫描数和删除数限制，避免日志目录异常庞大时阻塞应用启动。
class LogRetentionPolicy {
  const LogRetentionPolicy({
    this.maxAge = const Duration(days: 14),
    this.maxTotalBytes = 128 * 1024 * 1024,
    this.maxCleanupScanCount = 2048,
    this.maxDeletesPerRun = 128,
  });

  final Duration maxAge;
  final int maxTotalBytes;
  final int maxCleanupScanCount;
  final int maxDeletesPerRun;
}
