/// 跟踪一次异步操作从未活动到活动、再回到未活动的完整边沿。
///
/// 原生文件面板打开前后的稳定状态都可能是 `false`。如果测试只等待最终值，
/// 会在操作尚未开始时立即通过；这个跟踪器要求同一次操作先出现进入边沿，
/// 再出现退出边沿，避免把初始状态误当成完成状态。
final class OperationEdgeTracker {
  bool _started = false;
  bool _completed = false;

  bool get started => _started;
  bool get completed => _completed;

  void observe({required bool wasActive, required bool isActive}) {
    if (!wasActive && isActive) {
      _started = true;
      return;
    }
    if (_started && wasActive && !isActive) {
      _completed = true;
    }
  }
}
