/// 动态数据宽松读取工具。
///
/// 桌面窗口 payload、旧配置迁移和外部 API 解码都会遇到 `Object?`、`Map<dynamic,
/// dynamic>` 或字符串数字。这里集中提供“尽量读出可用值，读不出就返回 null/空集合”
/// 的基础规则；具体协议是否允许缺字段，仍由各自 decoder 决定。
class DynamicReader {
  const DynamicReader._();

  static Map<Object?, Object?> asMap(Object? value) {
    if (value is Map<Object?, Object?>) {
      return value;
    }
    return const <Object?, Object?>{};
  }

  static bool? asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is! String) {
      return null;
    }
    final String normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
    return null;
  }

  static double? asDouble(Object? value) {
    if (value is double) {
      return value.isFinite ? value : null;
    }
    if (value is num) {
      final double parsed = value.toDouble();
      return parsed.isFinite ? parsed : null;
    }
    if (value is! String) {
      return null;
    }
    final double? parsed = double.tryParse(value.trim());
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static int? asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      final double parsed = value.toDouble();
      if (!parsed.isFinite || parsed != parsed.truncateToDouble()) {
        return null;
      }
      return parsed.toInt();
    }
    return value is String ? int.tryParse(value.trim()) : null;
  }

  static String? asString(Object? value) {
    return switch (value) {
      String() => value,
      num() || bool() => value.toString(),
      _ => null,
    };
  }

  static List<String> asStringList(Object? value) {
    final Iterable<Object?>? values = _asObjectIterable(value);
    if (values == null) {
      return const <String>[];
    }
    return values
        .map((Object? item) => asString(item)?.trim())
        .whereType<String>()
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> asStringListPreserveEmpty(Object? value) {
    final Iterable<Object?>? values = _asObjectIterable(value);
    if (values == null) {
      return const <String>[];
    }
    return values
        .map((Object? item) => asString(item) ?? '')
        .toList(growable: false);
  }

  static List<String> readTokenList(
    Object? value, {
    String? Function(String raw)? normalizer,
  }) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String raw in asStringList(value)) {
      final String? token = normalizer == null ? raw : normalizer(raw);
      if (token != null && token.isNotEmpty && seen.add(token)) {
        result.add(token);
      }
    }
    return List<String>.unmodifiable(result);
  }

  static Iterable<Object?>? _asObjectIterable(Object? value) {
    if (value is List<Object?>) {
      return value;
    }
    return null;
  }
}
