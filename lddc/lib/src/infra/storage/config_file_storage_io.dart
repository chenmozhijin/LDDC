// ignore_for_file: avoid_slow_async_io
// 配置文件读写属于用户可感知的启动路径，文件状态检查必须走异步 API，避免卡住 Flutter 首帧。

import 'dart:convert';
import 'dart:io';

import '../../core/config/config_repository.dart';
import 'app_storage_paths_io.dart';
import 'legacy_config_file_codec.dart';

/// 基于 `config.json` 的文件型配置存储。
///
/// 桌面端会直接复用Python版配置文件路径与外部 JSON 键名；移动端则落到统一应用目录。
class JsonFileConfigStorage implements ConfigStorage {
  JsonFileConfigStorage({AppStoragePaths? paths, LegacyConfigFileCodec? codec})
    : _paths = paths ?? AppStoragePaths(),
      _codec = codec ?? const LegacyConfigFileCodec();

  final AppStoragePaths _paths;
  final LegacyConfigFileCodec _codec;

  @override
  Future<Map<String, Object?>?> read() async {
    final File file = await _paths.resolveConfigFile();
    if (!await file.exists()) {
      return null;
    }
    final String content = await file.readAsString();
    if (content.trim().isEmpty) {
      return null;
    }
    final Object? decoded = jsonDecode(content);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('config.json 顶层必须为对象');
    }
    final Map<String, Object?> rawValues = Map<String, Object?>.fromEntries(
      decoded.entries.map(
        (MapEntry<Object?, Object?> entry) =>
            MapEntry(entry.key.toString(), entry.value),
      ),
    );
    return _codec.decode(rawValues);
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    final File file = await _paths.resolveConfigFile();
    final Directory parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final Map<String, Object?> encoded = _codec.encode(values);
    final JsonEncoder encoder = const JsonEncoder.withIndent('    ');
    await file.writeAsString(encoder.convert(encoded));
  }
}
