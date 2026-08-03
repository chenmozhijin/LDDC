import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 构造单页搜索范围。
///
/// 多个歌词源的远端 total 经常不准，UI 只需要知道当前已经加载到哪里。
/// 因此 total 统一表示“当前页已知上界”：空页为 0，非空页为
/// `start + itemCount`。这样加载更多只依赖已拿到的数据，不被远端错误总数误导。
SourceRange buildCurrentPageRange({
  required int start,
  required int itemCount,
}) {
  final int end = itemCount == 0 ? start - 1 : start + itemCount - 1;
  return SourceRange(start: start, end: end, total: start + itemCount);
}

int? parseApiInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}
