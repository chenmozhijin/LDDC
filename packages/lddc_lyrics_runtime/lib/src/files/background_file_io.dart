import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// 本地文件后台写入入口。
///
/// 桌面端的大块文件写入放到独立 isolate，避免同步编码和磁盘写入占用 UI isolate；
/// 小文件与移动端继续使用 Dart 异步文件 API，省去创建 isolate 的固定成本。
final class BackgroundFileIo {
  BackgroundFileIo._();

  static const int _backgroundWriteThresholdBytes = 64 * 1024;

  static bool get _shouldUseBackgroundIsolate =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<String> writeBytes({
    required String path,
    required Uint8List bytes,
  }) async {
    if (!_shouldUseBackgroundIsolate ||
        bytes.lengthInBytes < _backgroundWriteThresholdBytes) {
      final File file = File(path);
      final Uint8List snapshot = Uint8List.fromList(bytes);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(snapshot, flush: true);
      return file.path;
    }

    // TransferableTypedData 在发送时转移字节所有权，避免为大块数据再构造一份
    // isolate 消息副本。调用方传入的 Uint8List 本身不会被后台任务直接持有。
    final TransferableTypedData transferable = TransferableTypedData.fromList(
      <Uint8List>[bytes],
    );
    return Isolate.run<String>(() {
      final Uint8List transferredBytes = transferable
          .materialize()
          .asUint8List();
      final File file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(transferredBytes, flush: true);
      return file.path;
    });
  }

  static Future<String> writeText({
    required String path,
    required String text,
  }) async {
    if (!_shouldUseBackgroundIsolate ||
        text.length < _backgroundWriteThresholdBytes) {
      final File file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(text, flush: true);
      return file.path;
    }
    return Isolate.run<String>(() {
      final File file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text, flush: true);
      return file.path;
    });
  }
}
