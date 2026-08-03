import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';

/// 持续读取桌面服务 socket，并按 IPC frame 边界返回 JSON 对象。
///
/// TCP 的一次数据回调不等于一条完整消息：一条 frame 可能被拆成多个 chunk，多个
/// frame 也可能被合并到同一个 chunk。测试统一通过这个读取器消费数据，避免每个
/// 测试各自实现缓冲和等待队列后产生不同的边界行为。
final class TestSocketFrameReader {
  TestSocketFrameReader(Socket socket)
    : _socket = socket,
      _subscription = socket.listen(null) {
    _subscription
      ..onData(_handleChunk)
      ..onDone(_closePending)
      ..onError((Object error, StackTrace stackTrace) => _closePending());
  }

  final Socket _socket;
  final DesktopIpcFrameBuffer _buffer = DesktopIpcFrameBuffer();
  final List<Map<String, Object?>> _pendingFrames = <Map<String, Object?>>[];
  final List<Completer<Map<String, Object?>>> _waiters =
      <Completer<Map<String, Object?>>>[];
  final StreamSubscription<List<int>> _subscription;
  bool _isClosed = false;

  void _handleChunk(List<int> chunk) {
    final List<Uint8List> frames = _buffer.addChunk(chunk);
    for (final Uint8List frame in frames) {
      final Object? payload = jsonDecode(utf8.decode(frame));
      final Map<String, Object?> normalized = Map<String, Object?>.from(
        payload! as Map<Object?, Object?>,
      );
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(normalized);
      } else {
        _pendingFrames.add(normalized);
      }
    }
  }

  void _closePending() {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    while (_waiters.isNotEmpty) {
      _waiters
          .removeAt(0)
          .completeError(
            StateError('socket closed before the next IPC frame was received'),
          );
    }
  }

  Future<Map<String, Object?>> nextFrame() {
    if (_pendingFrames.isNotEmpty) {
      return Future<Map<String, Object?>>.value(_pendingFrames.removeAt(0));
    }
    if (_isClosed) {
      return Future<Map<String, Object?>>.error(
        StateError('socket is already closed'),
      );
    }
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _waiters.add(completer);
    return completer.future;
  }

  Future<Map<String, Object?>?> nextFrameOrNull({
    Duration timeout = const Duration(milliseconds: 150),
  }) async {
    try {
      return await nextFrame().timeout(timeout);
    } on TimeoutException {
      return null;
    }
  }

  Future<void> dispose() async {
    _closePending();
    await _subscription.cancel();
    _socket.destroy();
  }
}

/// 等待异步回调把可观察状态推进到指定条件。
///
/// 这类测试不能用固定延时判断完成，因为不同机器的调度速度不同。短间隔轮询只读取
/// 内存状态，并用总超时保证失败能及时结束。
Future<void> waitForCondition(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
  Duration pollInterval = const Duration(milliseconds: 10),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met within timeout');
    }
    await Future<void>.delayed(pollInterval);
  }
}
