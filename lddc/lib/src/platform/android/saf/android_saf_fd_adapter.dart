import 'package:flutter/services.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

export 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart'
    show AndroidSafFdPort, AndroidSafOpenedFileDescriptor;

/// 通过 MethodChannel 调用 Android SAF 的 fd 打开/关闭能力。
class AndroidSafFdAdapter implements AndroidSafFdPort {
  const AndroidSafFdAdapter({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'lddc/android_saf_fd',
  );

  final MethodChannel _channel;

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadOnlyFd(String uri) async {
    final Map<Object?, Object?>? result = await _channel
        .invokeMapMethod<Object?, Object?>('openReadOnlyFd', <String, Object?>{
          'uri': uri,
        });
    return _parseOpenedFileDescriptor(result);
  }

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadWriteFd(String uri) async {
    final Map<Object?, Object?>? result = await _channel
        .invokeMapMethod<Object?, Object?>('openReadWriteFd', <String, Object?>{
          'uri': uri,
        });
    return _parseOpenedFileDescriptor(result);
  }

  AndroidSafOpenedFileDescriptor _parseOpenedFileDescriptor(
    Map<Object?, Object?>? result,
  ) {
    if (result == null) {
      throw StateError('Android SAF 打开 fd 失败：返回结果为空');
    }
    final Object? fileDescriptorRaw = result['fd'];
    if (fileDescriptorRaw is! int || fileDescriptorRaw < 0) {
      throw StateError('Android SAF 打开 fd 失败：fd 字段必须是非负整数');
    }
    final Object? nameHintRaw = result['nameHint'];
    if (nameHintRaw != null && nameHintRaw is! String) {
      throw StateError('Android SAF 打开 fd 失败：nameHint 字段类型错误');
    }
    return AndroidSafOpenedFileDescriptor(
      fileDescriptor: fileDescriptorRaw,
      nameHint: nameHintRaw is String && nameHintRaw.trim().isNotEmpty
          ? nameHintRaw.trim()
          : null,
    );
  }

  @override
  Future<void> closeFd(int fileDescriptor) async {
    await _channel.invokeMethod<void>('closeFd', <String, Object?>{
      'fd': fileDescriptor,
    });
  }
}
