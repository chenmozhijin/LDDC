import 'dart:async';
import 'dart:collection';

import '../logging/logging.dart';

final AppLogger _asyncDisposalLogger = AppLogger.scope('async-disposal');

/// 跟踪无法由同步 `dispose` 回调直接等待的异步资源释放任务。
///
/// Riverpod 的 `ref.onDispose` 和 Flutter 的 `State.dispose` 都是同步接口，
/// 但网络客户端、数据库和文件句柄通常返回 `Future<void>`。调用方把这些 Future
/// 交给本类后，短生命周期子 engine 可以在销毁前等待所有关闭任务完成，避免仍在
/// 执行原生回调时直接卸载 Dart isolate。
abstract final class AsyncDisposalTracker {
  static final Map<Future<void>, String> _pending =
      HashMap<Future<void>, String>.identity();

  static int get pendingCount => _pending.length;

  static void track(Future<void> disposal, {required String owner}) {
    late final Future<void> tracked;
    tracked = disposal.then<void>(
      (_) {
        _pending.remove(tracked);
      },
      onError: (Object error, StackTrace stackTrace) {
        _pending.remove(tracked);
        _asyncDisposalLogger.warning(
          'async disposal failed owner=$owner error=$error',
          fields: <String, Object?>{'stack': stackTrace.toString()},
        );
      },
    );
    _pending[tracked] = owner;
  }

  /// 等待当前 isolate 内已经登记的关闭任务全部结束。
  ///
  /// 关闭任务可能在等待期间继续登记其他关闭任务，因此这里按批次循环，直到集合
  /// 为空。超时只记录诊断并返回 `false`，不能让无法关闭的第三方资源永久阻止窗口
  /// 退出；随后销毁 engine 仍是最后的资源回收边界。
  static Future<bool> drain({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final Stopwatch elapsed = Stopwatch()..start();
    while (_pending.isNotEmpty) {
      final Duration remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        _logTimeout();
        return false;
      }
      final List<Future<void>> batch = _pending.keys.toList(growable: false);
      try {
        await Future.wait(batch).timeout(remaining);
      } on TimeoutException {
        _logTimeout();
        return false;
      }
    }
    return true;
  }

  static void _logTimeout() {
    _asyncDisposalLogger.warning(
      'async disposal timeout',
      fields: <String, Object?>{
        'pendingCount': _pending.length,
        'owners': _pending.values.toSet().toList(growable: false),
      },
    );
  }

  static void debugResetForTests() {
    _pending.clear();
  }
}
