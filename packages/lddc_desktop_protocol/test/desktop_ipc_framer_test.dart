import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('DesktopIpcFramer', () {
    const DesktopIpcFramer framer = DesktopIpcFramer();

    test('按Python版长度帧格式编码 JSON', () {
      final Uint8List frame = framer.encodeJson(<String, Object?>{
        'task': 'start',
        'id': 7,
      });

      final ByteData header = ByteData.sublistView(frame, 0, 4);
      final List<int> payloadBytes = frame.sublist(4);
      final Object? payload = jsonDecode(utf8.decode(payloadBytes));

      expect(header.getUint32(0), payloadBytes.length);
      expect(payload, <String, Object?>{'task': 'start', 'id': 7});
    });

    test('拆包后可重组完整负载', () {
      final Uint8List frame = framer.encodeJson(<String, Object?>{
        'task': 'sync',
        'id': 42,
      });
      final DesktopIpcFrameBuffer buffer = DesktopIpcFrameBuffer();

      final List<Uint8List> first = buffer.addChunk(frame.sublist(0, 3));
      final List<Uint8List> second = buffer.addChunk(frame.sublist(3));

      expect(first, isEmpty);
      expect(second, hasLength(1));
      expect(jsonDecode(utf8.decode(second.single)), <String, Object?>{
        'task': 'sync',
        'id': 42,
      });
      expect(buffer.hasPendingBytes, isFalse);
      expect(buffer.pendingByteCount, 0);
    });

    test('粘包场景可一次解出多条消息', () {
      final Uint8List firstFrame = framer.encodeJson(<String, Object?>{
        'task': 'start',
        'id': 1,
      });
      final Uint8List secondFrame = framer.encodeJson(<String, Object?>{
        'task': 'pause',
        'id': 1,
      });
      final Uint8List sticky = Uint8List(firstFrame.length + secondFrame.length)
        ..setRange(0, firstFrame.length, firstFrame)
        ..setRange(
          firstFrame.length,
          firstFrame.length + secondFrame.length,
          secondFrame,
        );

      final DesktopIpcFrameBuffer buffer = DesktopIpcFrameBuffer();
      final List<Uint8List> frames = buffer.addChunk(sticky);

      expect(frames, hasLength(2));
      expect(jsonDecode(utf8.decode(frames[0])), <String, Object?>{
        'task': 'start',
        'id': 1,
      });
      expect(jsonDecode(utf8.decode(frames[1])), <String, Object?>{
        'task': 'pause',
        'id': 1,
      });
    });

    test('支持零长度负载并可清空缓冲区', () {
      final Uint8List frame = framer.encodeBytes(Uint8List(0));
      final DesktopIpcFrameBuffer buffer = DesktopIpcFrameBuffer();

      final List<Uint8List> frames = buffer.addChunk(frame);

      expect(frames, hasLength(1));
      expect(frames.single, isEmpty);

      buffer.addChunk(<int>[0, 0]);
      expect(buffer.hasPendingBytes, isTrue);
      buffer.clear();
      expect(buffer.hasPendingBytes, isFalse);
      expect(buffer.pendingByteCount, 0);
    });

    test('超过最大帧长度时抛出异常并清空缓冲区', () {
      final DesktopIpcFrameBuffer buffer = DesktopIpcFrameBuffer(
        maxFrameLength: 4,
      );
      final Uint8List frame = framer.encodeString('12345');

      expect(() => buffer.addChunk(frame), throwsFormatException);
      expect(buffer.hasPendingBytes, isFalse);
      expect(buffer.pendingByteCount, 0);
    });

    test('累计缓冲超限时在读取分片前拒绝并清空', () {
      final DesktopIpcFrameBuffer buffer = DesktopIpcFrameBuffer(
        maxFrameLength: 4,
      )..addChunk(<int>[0, 0]);

      expect(() => buffer.addChunk(_UnreadableChunk(7)), throwsFormatException);
      expect(buffer.hasPendingBytes, isFalse);
      expect(buffer.pendingByteCount, 0);
    });

    test('最大帧长度不能为负数', () {
      expect(() => DesktopIpcFrameBuffer(maxFrameLength: -1), throwsRangeError);
    });
  });
}

/// 只允许读取长度；一旦实现尝试复制内容，测试会立即失败。
final class _UnreadableChunk extends ListBase<int> {
  _UnreadableChunk(this._length);

  final int _length;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('测试分片长度不可修改');

  @override
  int operator [](int index) => throw StateError('超限分片不应被读取');

  @override
  void operator []=(int index, int value) {
    throw UnsupportedError('测试分片内容不可修改');
  }
}
