import 'package:characters/characters.dart';

import 'ruby_unicode.dart';

/// 原文索引与归一化索引映射器。
final class IndexMapper {
  IndexMapper(String originalText) {
    final ({String normalizedText, List<int> map, int originalLength}) built =
        _buildMap(originalText);
    normalizedText = built.normalizedText;
    _normalizedToOriginalMap = built.map;
    _originalLength = built.originalLength;
  }

  late final String normalizedText;
  late final List<int> _normalizedToOriginalMap;
  late final int _originalLength;

  static ({String normalizedText, List<int> map, int originalLength}) _buildMap(
    String text,
  ) {
    final StringBuffer normalizedBuilder = StringBuffer();
    final List<int> mapping = <int>[];

    int originalIndex = 0;
    for (final String originalChar in text.characters) {
      final String normalizedChar = normalizeRubyNfkc(originalChar);
      normalizedBuilder.write(normalizedChar);
      final int normalizedLength = normalizedChar.characters.length;
      for (int i = 0; i < normalizedLength; i += 1) {
        mapping.add(originalIndex);
      }
      originalIndex += 1;
    }

    return (
      normalizedText: normalizedBuilder.toString(),
      map: mapping,
      originalLength: originalIndex,
    );
  }

  /// 将归一化区间转换回原文区间。
  (int, int) toOriginalIndices(int start, int end) {
    if (_normalizedToOriginalMap.isEmpty) {
      return (start, end);
    }

    final int normalizedLength = _normalizedToOriginalMap.length;
    if (start >= normalizedLength) {
      return (_originalLength, _originalLength);
    }

    final int originalStart = _normalizedToOriginalMap[start];

    final int originalEnd;
    if (end > 0 && end <= normalizedLength) {
      final int originalEndCharIndex = _normalizedToOriginalMap[end - 1];
      originalEnd = originalEndCharIndex + 1;
    } else {
      originalEnd = _originalLength;
    }

    return (originalStart, originalEnd);
  }
}
