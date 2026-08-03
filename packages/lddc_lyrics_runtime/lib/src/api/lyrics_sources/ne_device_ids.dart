import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 按需读取 gzip 压缩设备 ID 资产的端口。
///
/// Runtime 不假设资源来自 Flutter asset、文件还是网络；具体读取方式由宿主或
/// `lddc_lyrics_flutter` 适配器提供。
typedef NeCompressedDeviceIdsLoader = Future<Uint8List> Function();

/// NE 游客登录设备 ID 样本池。
///
/// 完整样本池放在 gzip 资产中，首次 NE 匿名登录时才读取并解压，之后在内存里缓存
/// `List<String>`。这样既保留 Python 版完整随机样本分布，又避免把 1MB 级常量表
/// 编译进 Dart 源码单元，减少 analyzer、AOT 编译和启动前常量初始化压力。
class NeDeviceIdPool {
  NeDeviceIdPool({required this._compressedBytesLoader});

  final NeCompressedDeviceIdsLoader _compressedBytesLoader;
  Future<List<String>>? _loadFuture;
  List<String>? _ids;

  Future<String> pick(Random random) async {
    final List<String> ids = await load();
    return ids[random.nextInt(ids.length)];
  }

  Future<List<String>> load() {
    final List<String>? cached = _ids;
    if (cached != null) {
      return Future<List<String>>.value(cached);
    }
    final Future<List<String>>? inflight = _loadFuture;
    if (inflight != null) {
      return inflight;
    }
    final Future<List<String>> future = _load();
    _loadFuture = future;
    return future;
  }

  Future<List<String>> _load() async {
    try {
      final Uint8List compressed = await _compressedBytesLoader();
      final List<int> decompressed = GZipDecoder().decodeBytes(compressed);
      final List<String> ids = const LineSplitter()
          .convert(utf8.decode(decompressed))
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .toList(growable: false);
      if (ids.isEmpty) {
        throw const FormatException('NE 设备 ID 资产为空');
      }
      _ids = ids;
      return ids;
    } finally {
      _loadFuture = null;
    }
  }
}
