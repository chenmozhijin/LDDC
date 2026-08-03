import 'package:collection/collection.dart';

import '../models/models.dart';

/// 在原文、译文与罗马音时间轴之间建立行索引映射。
class LyricsLineMatcher {
  const LyricsLineMatcher();

  static final RegExp _sameLineCleanPattern = RegExp(r'[(（][^）)]*[）)]|\s+');

  /// 忽略括号内注释与空白后，判断两行歌词是否表达同一文本。
  bool isSameLine(LyricsLine line1, LyricsLine line2) {
    final String text1 = _lineText(line1);
    final String text2 = _lineText(line2);
    if (text1 == text2) {
      return true;
    }
    final String cleaned1 = text1.replaceAll(_sameLineCleanPattern, '');
    final String cleaned2 = text2.replaceAll(_sameLineCleanPattern, '');
    return cleaned1 == cleaned2 && cleaned2.isNotEmpty;
  }

  /// 按来源规则和开始时间，为 [data1] 中的行寻找 [data2] 中的一对一匹配。
  ///
  /// 通用路径与 Python 版一样，按时间差从小到大贪心选边。直接构造全部
  /// `left * right` 候选会在长歌词上产生平方级内存；这里为每个左侧行维护一个
  /// 按时间差有序的惰性迭代器，再用最小堆合并所有迭代器。输出顺序仍等价于
  /// 对完整候选表按“时间差、左索引、右索引”稳定排序，额外内存为 `O(n+m)`。
  Map<int, int> findClosestMatch(
    List<LyricsLine> data1,
    List<LyricsLine> data2, {
    List<LyricsLine>? data3,
    Source? source,
  }) {
    if (source == Source.ne && data3 != null && data3.isNotEmpty) {
      final Map<int, int> remainingMiddleMatches = findClosestMatch(
        data3,
        data2,
        source: Source.ne,
      );
      final Map<int, int> matched = <int, int>{};
      for (int leftIndex = 0; leftIndex < data1.length; leftIndex += 1) {
        int? consumedMiddleIndex;
        int? translatedIndex;
        for (final MapEntry<int, int> entry in remainingMiddleMatches.entries) {
          if (isSameLine(data1[leftIndex], data3[entry.key])) {
            consumedMiddleIndex = entry.key;
            translatedIndex = entry.value;
            break;
          }
        }
        if (consumedMiddleIndex != null) {
          matched[leftIndex] = translatedIndex!;
          remainingMiddleMatches.remove(consumedMiddleIndex);
        }
      }
      if (matched.isNotEmpty) {
        return matched;
      }
    }

    List<_IndexedLyricsLine> left = _indexLines(data1);
    List<_IndexedLyricsLine> right = _indexLines(data2);
    if (source == Source.qm || source == Source.kg) {
      if (left.length == right.length) {
        return _samePositionMapping(left, right);
      }
      left = left
          .where((_IndexedLyricsLine item) => item.line.words.isNotEmpty)
          .toList(growable: false);
      right = right
          .where((_IndexedLyricsLine item) => item.line.words.isNotEmpty)
          .toList(growable: false);
      if (left.length == right.length) {
        return _samePositionMapping(left, right);
      }
    }

    final List<_IndexedLyricsLine> timedLeft = left
        .where((_IndexedLyricsLine item) => item.line.startMs != null)
        .toList(growable: false);
    final List<_IndexedLyricsLine> timedRight =
        right
            .where((_IndexedLyricsLine item) => item.line.startMs != null)
            .toList(growable: false)
          ..sort((_IndexedLyricsLine left, _IndexedLyricsLine right) {
            final int timeOrder = left.line.startMs!.compareTo(
              right.line.startMs!,
            );
            return timeOrder != 0
                ? timeOrder
                : left.originalIndex.compareTo(right.originalIndex);
          });
    if (timedLeft.isEmpty || timedRight.isEmpty) {
      return <int, int>{};
    }

    final HeapPriorityQueue<_TimeMatchCandidate> candidates =
        HeapPriorityQueue<_TimeMatchCandidate>(_compareCandidates);
    for (final _IndexedLyricsLine leftLine in timedLeft) {
      final _NearestRightIterator iterator = _NearestRightIterator(
        sortedRight: timedRight,
        targetStartMs: leftLine.line.startMs!,
      );
      final ({int diffMs, _IndexedLyricsLine line})? first = iterator.next();
      if (first != null) {
        candidates.add(
          _TimeMatchCandidate(
            left: leftLine,
            right: first.line,
            diffMs: first.diffMs,
            iterator: iterator,
          ),
        );
      }
    }

    final int targetCount = timedLeft.length < timedRight.length
        ? timedLeft.length
        : timedRight.length;
    final Map<int, int> matched = <int, int>{};
    final Set<int> usedLeft = <int>{};
    final Set<int> usedRight = <int>{};
    while (candidates.isNotEmpty && matched.length < targetCount) {
      final _TimeMatchCandidate candidate = candidates.removeFirst();
      final int leftIndex = candidate.left.originalIndex;
      if (usedLeft.contains(leftIndex)) {
        continue;
      }

      final int rightIndex = candidate.right.originalIndex;
      if (!usedRight.contains(rightIndex)) {
        usedLeft.add(leftIndex);
        usedRight.add(rightIndex);
        matched[leftIndex] = rightIndex;
        continue;
      }

      final ({int diffMs, _IndexedLyricsLine line})? next = candidate.iterator
          .next();
      if (next != null) {
        candidates.add(
          _TimeMatchCandidate(
            left: candidate.left,
            right: next.line,
            diffMs: next.diffMs,
            iterator: candidate.iterator,
          ),
        );
      }
    }
    return matched;
  }

  static String _lineText(LyricsLine line) {
    final StringBuffer buffer = StringBuffer();
    for (final LyricsWord word in line.words) {
      buffer.write(word.text);
    }
    return buffer.toString();
  }

  static List<_IndexedLyricsLine> _indexLines(List<LyricsLine> lines) {
    return <_IndexedLyricsLine>[
      for (int index = 0; index < lines.length; index += 1)
        _IndexedLyricsLine(originalIndex: index, line: lines[index]),
    ];
  }

  static Map<int, int> _samePositionMapping(
    List<_IndexedLyricsLine> left,
    List<_IndexedLyricsLine> right,
  ) {
    return <int, int>{
      for (int index = 0; index < left.length; index += 1)
        left[index].originalIndex: right[index].originalIndex,
    };
  }

  static int _compareCandidates(
    _TimeMatchCandidate left,
    _TimeMatchCandidate right,
  ) {
    final int differenceOrder = left.diffMs.compareTo(right.diffMs);
    if (differenceOrder != 0) {
      return differenceOrder;
    }
    final int leftOrder = left.left.originalIndex.compareTo(
      right.left.originalIndex,
    );
    return leftOrder != 0
        ? leftOrder
        : left.right.originalIndex.compareTo(right.right.originalIndex);
  }
}

class _IndexedLyricsLine {
  const _IndexedLyricsLine({required this.originalIndex, required this.line});

  final int originalIndex;
  final LyricsLine line;
}

class _TimeMatchCandidate {
  const _TimeMatchCandidate({
    required this.left,
    required this.right,
    required this.diffMs,
    required this.iterator,
  });

  final _IndexedLyricsLine left;
  final _IndexedLyricsLine right;
  final int diffMs;
  final _NearestRightIterator iterator;
}

/// 按“时间差、原始右索引”顺序惰性遍历右侧行。
///
/// 右侧列表按开始时间排序后，离目标最近的元素只可能位于二分位置的左右两侧。
/// 每次取完同一时间点的分组后继续向外推进，因此不需要为每个左侧行复制全部右
/// 侧候选。左右两组距离相同时按原始索引归并，保持 Python 稳定排序的并列顺序。
class _NearestRightIterator {
  _NearestRightIterator({
    required this.sortedRight,
    required this.targetStartMs,
  }) : _rightSearch = _lowerBound(sortedRight, targetStartMs),
       _leftSearch = _lowerBound(sortedRight, targetStartMs) - 1;

  final List<_IndexedLyricsLine> sortedRight;
  final int targetStartMs;

  int _leftSearch;
  int _rightSearch;
  int _leftCursor = 0;
  int _leftEnd = 0;
  int _rightCursor = 0;
  int _rightEnd = 0;
  int _activeDiffMs = 0;

  ({int diffMs, _IndexedLyricsLine line})? next() {
    while (true) {
      final bool hasLeft = _leftCursor < _leftEnd;
      final bool hasRight = _rightCursor < _rightEnd;
      if (hasLeft || hasRight) {
        late final _IndexedLyricsLine selected;
        if (!hasRight ||
            (hasLeft &&
                sortedRight[_leftCursor].originalIndex <=
                    sortedRight[_rightCursor].originalIndex)) {
          selected = sortedRight[_leftCursor];
          _leftCursor += 1;
        } else {
          selected = sortedRight[_rightCursor];
          _rightCursor += 1;
        }
        return (diffMs: _activeDiffMs, line: selected);
      }
      if (!_loadNextDistanceGroups()) {
        return null;
      }
    }
  }

  bool _loadNextDistanceGroups() {
    final int? leftDiff = _leftSearch >= 0
        ? (targetStartMs - sortedRight[_leftSearch].line.startMs!).abs()
        : null;
    final int? rightDiff = _rightSearch < sortedRight.length
        ? (targetStartMs - sortedRight[_rightSearch].line.startMs!).abs()
        : null;
    if (leftDiff == null && rightDiff == null) {
      return false;
    }

    _activeDiffMs = switch ((leftDiff, rightDiff)) {
      (final int left, final int right) => left < right ? left : right,
      (final int left, null) => left,
      (null, final int right) => right,
      (null, null) => throw StateError('不存在可加载的时间分组'),
    };

    _leftCursor = 0;
    _leftEnd = 0;
    if (leftDiff == _activeDiffMs) {
      final int groupEnd = _leftSearch + 1;
      final int startMs = sortedRight[_leftSearch].line.startMs!;
      int groupStart = _leftSearch;
      while (groupStart > 0 &&
          sortedRight[groupStart - 1].line.startMs == startMs) {
        groupStart -= 1;
      }
      _leftCursor = groupStart;
      _leftEnd = groupEnd;
      _leftSearch = groupStart - 1;
    }

    _rightCursor = 0;
    _rightEnd = 0;
    if (rightDiff == _activeDiffMs) {
      final int startMs = sortedRight[_rightSearch].line.startMs!;
      int groupEnd = _rightSearch + 1;
      while (groupEnd < sortedRight.length &&
          sortedRight[groupEnd].line.startMs == startMs) {
        groupEnd += 1;
      }
      _rightCursor = _rightSearch;
      _rightEnd = groupEnd;
      _rightSearch = groupEnd;
    }
    return true;
  }

  static int _lowerBound(
    List<_IndexedLyricsLine> sortedLines,
    int targetStartMs,
  ) {
    int low = 0;
    int high = sortedLines.length;
    while (low < high) {
      final int middle = low + ((high - low) >> 1);
      if (sortedLines[middle].line.startMs! < targetStartMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
