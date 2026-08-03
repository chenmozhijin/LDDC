import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

const String _bundledNeDeviceIdsAsset =
    'packages/lddc_lyrics_flutter/assets/ne_device_ids.txt.gz';

/// 创建使用共享 Flutter 包内完整样本资产的NE设备 ID 池。
///
/// 资产只在首次匿名登录时加载并由 [NeDeviceIdPool] 缓存，应用启动阶段不会产生
/// 额外 IO，也不会把约 1 MB 的样本表编译为 Dart 常量。
NeDeviceIdPool createBundledNeDeviceIdPool() {
  return NeDeviceIdPool(compressedBytesLoader: _loadBundledNeDeviceIds);
}

Future<Uint8List> _loadBundledNeDeviceIds() async {
  final ByteData data = await rootBundle.load(_bundledNeDeviceIdsAsset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
