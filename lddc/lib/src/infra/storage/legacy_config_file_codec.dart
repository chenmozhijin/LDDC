import '../../core/config/config_defaults.dart';
import '../../core/config/config_legacy_keys.dart';
import '../../core/config/config_migration.dart';

/// Python版 `config.json` 外部编解码器。
///
/// 设计目标：
/// - 外部文件继续使用Python版 snake_case 键名，保持与 Python 版双向兼容；
/// - Flutter 内部仍使用点分键与强类型 `AppConfig`；
/// - 未识别 key 原样保留，避免桌面端配置被裁剪。
class LegacyConfigFileCodec {
  const LegacyConfigFileCodec();

  /// 将Python版外部格式转换为 Flutter 内部 key-value 结构。
  Map<String, Object?> decode(Map<String, Object?> rawValues) {
    final Map<String, Object?> decoded = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in rawValues.entries) {
      decoded[entry.key] = _deepCopy(entry.value);
    }
    for (final MapEntry<String, String> entry
        in LegacyConfigKeyMap.legacyToCurrent.entries) {
      if (!decoded.containsKey(entry.value) && decoded.containsKey(entry.key)) {
        decoded[entry.value] = _deepCopy(decoded[entry.key]);
      }
      decoded.remove(entry.key);
    }
    decoded.putIfAbsent(
      configSchemaVersionKey,
      () => ConfigDefaults.currentSchemaVersion,
    );
    return decoded;
  }

  /// 将 Flutter 内部 key-value 结构写回Python版外部格式。
  Map<String, Object?> encode(Map<String, Object?> currentValues) {
    final Map<String, Object?> encoded = <String, Object?>{};

    for (final MapEntry<String, Object?> entry in currentValues.entries) {
      if (entry.key == configSchemaVersionKey) {
        continue;
      }
      if (LegacyConfigKeyMap.currentToLegacy.containsKey(entry.key)) {
        continue;
      }
      encoded[entry.key] = _deepCopy(entry.value);
    }

    for (final MapEntry<String, String> entry
        in LegacyConfigKeyMap.currentToLegacy.entries) {
      if (!currentValues.containsKey(entry.key)) {
        continue;
      }
      encoded[entry.value] = _deepCopy(currentValues[entry.key]);
    }

    return encoded;
  }

  Object? _deepCopy(Object? value) {
    if (value is Map) {
      final Map<Object?, Object?> copied = <Object?, Object?>{};
      for (final MapEntry<dynamic, dynamic> entry in value.entries) {
        copied[entry.key] = _deepCopy(entry.value);
      }
      return copied;
    }
    if (value is List) {
      return value.map(_deepCopy).toList(growable: false);
    }
    return value;
  }
}
