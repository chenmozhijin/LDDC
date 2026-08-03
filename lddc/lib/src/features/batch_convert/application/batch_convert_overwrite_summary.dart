/// 批量转换启动前发现的覆盖风险汇总。
///
/// 这里只保存计数和少量示例路径，避免把整条队列复制进确认对话框；真正执行时仍以
/// controller 当前快照传给 use case。
class BatchConvertOverwriteSummary {
  const BatchConvertOverwriteSummary({
    required this.sourceOverwriteCount,
    required this.existingTargetCount,
    required this.duplicateTargetGroupCount,
    required this.samplePaths,
  });

  final int sourceOverwriteCount;
  final int existingTargetCount;
  final int duplicateTargetGroupCount;
  final List<String> samplePaths;

  bool get hasRisk =>
      sourceOverwriteCount > 0 ||
      existingTargetCount > 0 ||
      duplicateTargetGroupCount > 0;
}
