import 'package:flutter/services.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

export 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart'
    show AndroidSafContentPort;

/// 通过 MethodChannel 调用 Android SAF 文档内容流。
class AndroidSafContentAdapter implements AndroidSafContentPort {
  const AndroidSafContentAdapter({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'lddc/android_saf_content',
  );

  final MethodChannel _channel;

  @override
  Future<Uint8List> readBytes(String uri, {int? maxBytes}) async {
    final Uint8List? data = await _channel.invokeMethod<Uint8List>(
      'readBytes',
      <String, Object?>{'uri': uri, 'maxBytes': ?maxBytes},
    );
    if (data == null) {
      throw StateError('Android SAF 读取字节失败：返回结果为空');
    }
    return data;
  }
}
