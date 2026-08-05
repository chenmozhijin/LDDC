import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';

/// 按生产长度帧协议读取 socket，并为真实进程测试提供有界的单帧等待。
final class TestSocketFrameReader {
  TestSocketFrameReader(this._socket) : _subscription = _socket.listen(null) {
    _subscription
      ..onData(_handleChunk)
      ..onDone(_closePending)
      ..onError((Object error, StackTrace _) => _closePendingWithError(error));
  }

  final DesktopIpcFrameBuffer _buffer = DesktopIpcFrameBuffer();
  final Socket _socket;
  final List<Map<String, Object?>> _pending = <Map<String, Object?>>[];
  final List<Completer<Map<String, Object?>>> _waiters =
      <Completer<Map<String, Object?>>>[];
  final StreamSubscription<List<int>> _subscription;
  Object? _terminalError;

  void _handleChunk(List<int> chunk) {
    if (_terminalError != null) {
      return;
    }
    try {
      for (final Uint8List frame in _buffer.addChunk(chunk)) {
        final Object? decoded = jsonDecode(utf8.decode(frame));
        if (decoded is! Map<Object?, Object?>) {
          throw const FormatException('IPC 帧必须是 JSON 对象');
        }
        final Map<String, Object?> payload = Map<String, Object?>.from(decoded);
        if (_waiters.isEmpty) {
          _pending.add(payload);
        } else {
          _waiters.removeAt(0).complete(payload);
        }
      }
    } catch (error) {
      _closePendingWithError(error);
    }
  }

  void _closePending() {
    _closePendingWithError(StateError('服务在返回 IPC 帧前关闭连接'));
  }

  void _closePendingWithError(Object error) {
    _terminalError ??= error;
    while (_waiters.isNotEmpty) {
      _waiters.removeAt(0).completeError(_terminalError!);
    }
  }

  Future<Map<String, Object?>> nextFrame() {
    if (_pending.isNotEmpty) {
      return Future<Map<String, Object?>>.value(_pending.removeAt(0));
    }
    final Object? error = _terminalError;
    if (error != null) {
      return Future<Map<String, Object?>>.error(error);
    }
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _waiters.add(completer);
    return completer.future;
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    _socket.destroy();
  }
}

/// 读取现有 control.json v1，并通过私有控制 listener 获取桌面歌词业务端口。
Future<int> probeMacOsControlEndpoint(File controlFile) async {
  final Object? decoded = jsonDecode(await controlFile.readAsString());
  if (decoded is! Map<Object?, Object?>) {
    throw const FormatException('macOS control.json 必须是 JSON 对象');
  }
  final Map<String, Object?> endpoint = <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in decoded.entries)
      entry.key.toString(): entry.value,
  };
  const Set<String> expectedKeys = <String>{'schema', 'port', 'token'};
  if (endpoint.length != expectedKeys.length ||
      endpoint.keys.toSet().difference(expectedKeys).isNotEmpty) {
    throw const FormatException('control.json 必须保持现有 v1 三字段契约');
  }
  if (endpoint['schema'] != 'lddc.macos_singleton_control') {
    throw const FormatException('macOS control.json schema 无效');
  }
  final Object? rawControlPort = endpoint['port'];
  final Object? rawToken = endpoint['token'];
  if (rawControlPort is! int || rawControlPort <= 0 || rawControlPort > 65535) {
    throw const FormatException('macOS control.json 控制端口无效');
  }
  if (rawToken is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(rawToken)) {
    throw const FormatException('macOS control.json token 无效');
  }

  final Socket socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    rawControlPort,
    timeout: const Duration(seconds: 5),
  );
  final TestSocketFrameReader reader = TestSocketFrameReader(socket);
  try {
    const DesktopIpcFramer framer = DesktopIpcFramer();
    final Uint8List request = framer.encodeJson(<String, Object?>{
      '_lddcControl': 1,
      'token': rawToken,
      'command': 'get_service_port',
    });
    if (request.length > 4 * 1024 + 4) {
      throw const FormatException('macOS control request 超过 4 KiB');
    }
    socket.add(request);
    await socket.flush();
    final Map<String, Object?> response = await reader.nextFrame().timeout(
      const Duration(seconds: 5),
    );
    if (response['_lddcControl'] != 1 || response['ok'] != true) {
      throw const FormatException('macOS control endpoint 拒绝业务端口请求');
    }
    final Object? rawServicePort = response['port'];
    if (rawServicePort is! int ||
        rawServicePort <= 0 ||
        rawServicePort > 65535) {
      throw const FormatException('macOS control endpoint 返回的业务端口无效');
    }
    // control.json 的 port 只用于访问私有控制 listener；响应中的 port 才是
    // 桌面歌词服务端口。两者没有相等契约。
    return rawServicePort;
  } finally {
    await reader.dispose();
  }
}
