import 'dart:convert';
import 'dart:typed_data';

/// API 层动态 JSON 读取工具。
///
/// 歌词源与翻译源的线上响应经常存在字段缺失、类型漂移或测试替身返回
/// `Map<dynamic, dynamic>` 的情况。这里统一做“宽松读取”：非法类型返回空
/// map/list，业务层继续按现有缺字段逻辑决定是空结果还是抛业务异常。
Map<String, Object?> asJsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map<String, Object?>(
      (Object? key, Object? mapValue) =>
          MapEntry<String, Object?>(key?.toString() ?? '', mapValue),
    );
  }
  return <String, Object?>{};
}

/// 将动态 JSON 数组收敛为 `List<Object?>`。
///
/// 返回空列表而不是抛异常，是为了保持旧 provider 的容错语义：字段不存在时
/// 通常表示“没有结果”，真正的错误由调用方结合状态码或必填字段自行判断。
List<Object?> asJsonList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

/// 解码 UTF-8 JSON 响应体，解析失败时由调用方构造领域异常。
Object? decodeJsonBody(
  Uint8List body, {
  required Object Function() onParseError,
}) {
  try {
    return jsonDecode(utf8.decode(body));
  } catch (error) {
    // 调用方会把解析失败转换成各自的领域异常；这里不暴露底层 JSON 解析细节。
    if (error is Error) {
      rethrow;
    }
    throw onParseError();
  }
}
