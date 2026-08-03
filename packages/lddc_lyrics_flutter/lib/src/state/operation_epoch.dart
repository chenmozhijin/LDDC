/// 异步操作代际守卫。
///
/// Flutter 页面里经常会出现“旧 Future 晚于新 Future 返回”的情况，例如用户
/// 连续切换歌词、取消任务后旧进度又回调、页面销毁后异步结果才回来。这个类把
/// “开启新一代、判断是否仍是当前代、让旧代失效”三件事集中起来，避免每个
/// controller 都手写一组 int 计数器和 `_isCurrent...()` 方法。
final class OperationEpoch {
  int _value = 0;

  /// 返回当前输入代际，供同一输入下启动的转换、保存等子操作绑定身份。
  int get current => _value;

  /// 开启一个新操作，并返回本次操作的代际 token。
  int next() {
    _value += 1;
    return _value;
  }

  /// 让所有已经发出的 token 失效，常用于 dispose、取消和切换输入。
  void invalidate() {
    _value += 1;
  }

  /// 判断传入 token 是否仍然代表当前操作。
  bool isCurrent(int token) => token == _value;
}

/// 多通道异步代际守卫。
///
/// 一个页面可能同时有搜索、预览、保存、翻译等互不污染的异步通道。使用字符串
/// key 可以保留这些业务边界，同时复用同一套代际逻辑。
final class OperationEpochGroup {
  final Map<String, OperationEpoch> _epochs = <String, OperationEpoch>{};

  OperationEpoch _epoch(String key) {
    return _epochs.putIfAbsent(key, OperationEpoch.new);
  }

  int next(String key) => _epoch(key).next();

  void invalidate(String key) {
    _epochs[key]?.invalidate();
  }

  void invalidateAll() {
    for (final OperationEpoch epoch in _epochs.values) {
      epoch.invalidate();
    }
  }

  bool isCurrent(String key, int token) {
    return _epochs[key]?.isCurrent(token) ?? false;
  }
}
