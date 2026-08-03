import 'dart:collection';

/// 模型层共享工具。
///
/// 这些 helper 只处理 Python 版外部数据常见的宽松输入，不承担业务兜底。
/// 统一放在这里可以避免多个模型各写一份解析/格式化逻辑，后续规则调整也不容易漏改。
int? parseNullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.isFinite ? value.toInt() : null;
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

/// 格式化毫秒时长为 `mm:ss`。
String formatDurationMmSs(int? durationMs) {
  if (durationMs == null) {
    return '';
  }
  final int totalSeconds = (durationMs < 0 ? 0 : durationMs) ~/ 1000;
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// 保序去重。
///
/// 使用 [LinkedHashSet] 可以保持插入顺序，同时避免 `List.contains` 的 O(n²) 扫描。
List<T> orderedUnique<T>(Iterable<T> values) {
  return LinkedHashSet<T>.from(values).toList(growable: false);
}

/// 支持 code/name/value 三种形式的 Python 版枚举解析。
T parsePythonEnum<T extends Enum>({
  required Object? rawValue,
  required List<T> values,
  required int Function(T value) codeOf,
  required String Function(T value) wireValueOf,
  required String enumName,
}) {
  if (rawValue is T) {
    return rawValue;
  }
  if (rawValue is int) {
    for (final T value in values) {
      if (codeOf(value) == rawValue) {
        return value;
      }
    }
  }
  if (rawValue is String) {
    final String normalized = rawValue.trim().toLowerCase();
    for (final T value in values) {
      if (value.name.toLowerCase() == normalized ||
          wireValueOf(value).toLowerCase() == normalized) {
        return value;
      }
    }
  }
  throw ArgumentError.value(rawValue, 'value', 'Unsupported $enumName value');
}

/// `copyWith` 使用的哨兵值。
///
/// Dart 的 nullable 参数无法区分“不传”和“显式传 null”，因此 nullable 字段统一用
/// `Object? field = copyWithSentinel` 表示未传，传入 `null` 则表示清空。
const Object copyWithSentinel = Object();
