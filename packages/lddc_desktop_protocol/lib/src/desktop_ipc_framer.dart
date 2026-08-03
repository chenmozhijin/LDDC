import 'dart:convert';
import 'dart:typed_data';

/// 桌面 IPC 单帧 JSON 负载上限。
///
/// 桌面歌词协议只承载控制消息和歌词状态快照，正常消息远小于 1MB。
/// 设置硬上限可以避免异常客户端发送超长帧时持续占用内存。
const int kDesktopIpcDefaultMaxFrameLength = 1024 * 1024;

/// Python版桌面歌词协议长度帧编解码器。
///
/// 帧格式固定为：
/// - 前 4 字节：大端无符号整数，表示 UTF-8 JSON 负载长度
/// - 后 N 字节：UTF-8 JSON 文本
final class DesktopIpcFramer {
  const DesktopIpcFramer();

  /// 将 JSON 字典编码为Python版长度帧。
  Uint8List encodeJson(Map<String, Object?> payload) {
    return encodeString(jsonEncode(payload));
  }

  /// 将 UTF-8 文本编码为Python版长度帧。
  Uint8List encodeString(String payload) {
    final Uint8List payloadBytes = Uint8List.fromList(utf8.encode(payload));
    return encodeBytes(payloadBytes);
  }

  /// 将字节数组编码为Python版长度帧。
  Uint8List encodeBytes(Uint8List payloadBytes) {
    final ByteData header = ByteData(4)..setUint32(0, payloadBytes.length);
    final Uint8List frame = Uint8List(4 + payloadBytes.length);
    frame.setRange(0, 4, header.buffer.asUint8List());
    frame.setRange(4, frame.length, payloadBytes);
    return frame;
  }
}

/// 长度帧缓冲区：支持拆包/粘包场景下的增量解码。
final class DesktopIpcFrameBuffer {
  DesktopIpcFrameBuffer({
    this.maxFrameLength = kDesktopIpcDefaultMaxFrameLength,
  }) {
    if (maxFrameLength < 0) {
      throw RangeError.range(maxFrameLength, 0, null, 'maxFrameLength');
    }
  }

  /// 单条负载允许的最大字节数，超过后视为协议错误。
  final int maxFrameLength;

  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  /// 当前尚未解出的缓冲区字节数。
  int get pendingByteCount => _buffer.length - _offset;

  /// 当前是否还存在未消费的缓冲数据。
  bool get hasPendingBytes => pendingByteCount > 0;

  /// 清空缓冲区。
  void clear() {
    _buffer = Uint8List(0);
    _offset = 0;
  }

  /// 追加新的分片，并返回本次成功解出的完整负载。
  List<Uint8List> addChunk(List<int> chunk) {
    if (chunk.isEmpty) {
      return const <Uint8List>[];
    }

    // 先检查累计长度再复制分片，避免异常客户端用超大 chunk 触发一次无意义的
    // 大内存分配。超限时同时丢弃旧缓冲，调用方可以关闭连接或从干净状态重建。
    if (pendingByteCount + chunk.length > maxFrameLength + 4) {
      clear();
      throw FormatException('桌面 IPC 长度帧超过上限：$maxFrameLength bytes');
    }
    _appendChunk(chunk);
    final List<Uint8List> frames = <Uint8List>[];
    while (pendingByteCount >= 4) {
      final int length = _readLength(_buffer, _offset);
      if (length > maxFrameLength) {
        clear();
        throw FormatException('桌面 IPC 单帧负载超过上限：$length bytes');
      }
      final int frameStart = _offset + 4;
      final int frameEnd = frameStart + length;
      if (_buffer.length < frameEnd) {
        break;
      }
      frames.add(Uint8List.sublistView(_buffer, frameStart, frameEnd));
      _offset = frameEnd;
    }
    _compactIfNeeded();
    return frames;
  }

  void _appendChunk(List<int> chunk) {
    _compactIfNeeded(force: _offset > 0);
    final Uint8List next = Uint8List(_buffer.length + chunk.length);
    next.setRange(0, _buffer.length, _buffer);
    next.setRange(_buffer.length, next.length, chunk);
    _buffer = next;
  }

  void _compactIfNeeded({bool force = false}) {
    if (_offset == 0) {
      return;
    }
    if (!force && _offset < _buffer.length ~/ 2) {
      return;
    }
    if (_offset >= _buffer.length) {
      clear();
      return;
    }
    _buffer = Uint8List.sublistView(_buffer, _offset);
    _offset = 0;
  }

  static int _readLength(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }
}
