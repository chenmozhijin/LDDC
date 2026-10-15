/// 批量转换启动前发现的覆盖风险汇总。
///
/// [overwritePaths] 保存**全部**会被覆盖的目标展示路径，不再采样截断：确认对话框
/// 用固定高度的惰性列表逐行展示，行数再多也只构建可见行，所以这里不需要为了控制
/// 对话框体积而丢弃条目，用户能看到每一个将被写入的目的地。真正执行时仍以
/// controller 当前快照传给 use case。
class BatchConvertOverwriteSummary {
  const BatchConvertOverwriteSummary({
    required this.sourceOverwriteCount,
    required this.existingTargetCount,
    required this.duplicateTargetGroupCount,
    required this.overwritePaths,
  });

  final int sourceOverwriteCount;
  final int existingTargetCount;
  final int duplicateTargetGroupCount;

  /// 会被覆盖的目标展示路径，按队列顺序排列，每个受影响目标一行。
  ///
  /// 长度可能达到队列条目数，调用方禁止用它做全量文本测量或一次性构建全部行。
  final List<String> overwritePaths;

  bool get hasRisk =>
      sourceOverwriteCount > 0 ||
      existingTargetCount > 0 ||
      duplicateTargetGroupCount > 0;
}
