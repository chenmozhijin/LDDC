/// 文本归一化与相似度算法。
///
/// 这里的评分语义来自 Python 版 LDDC。特别是 [textDifference] 使用
/// `difflib.SequenceMatcher` 的最长连续匹配块规则，而不是常见的编辑距离；
/// 自动匹配阈值依赖这些分数，因此不能直接替换为 Levenshtein 等算法。
class TextSimilarity {
  const TextSimilarity();

  static const Map<String, String> _symbolMap = <String, String>{
    '（': '(',
    '）': ')',
    '：': ':',
    '！': '!',
    '？': '?',
    '／': '/',
    '＆': '&',
    '＊': '*',
    '＠': '@',
    '＃': '#',
    '＄': r'$',
    '％': '%',
    '＼': '\\',
    '｜': '|',
    '＝': '=',
    '＋': '+',
    '－': '-',
    '＜': '<',
    '＞': '>',
    '［': '[',
    '］': ']',
    '｛': '{',
    '｝': '}',
  };

  static final RegExp _normalizationPattern = RegExp(
    '${_symbolMap.keys.map(RegExp.escape).join('|')}|\\s',
  );

  /// 将全角符号替换为协议约定的半角形式，并把每个空白字符替换为普通空格。
  ///
  /// 这里不会折叠连续空格，因为 Python 基线使用的是逐字符替换；折叠空格会
  /// 改变标题和歌手相似度。
  String unifiedSymbol(String text) {
    return text.trim().replaceAllMapped(_normalizationPattern, (Match match) {
      final String value = match.group(0)!;
      return _symbolMap[value] ?? ' ';
    });
  }

  /// 返回两个字符串的 `SequenceMatcher.ratio()` 等价值。
  double textDifference(String text1, String text2) {
    if (text1 == text2) {
      return 1.0;
    }
    return _SequenceMatcher(
      a: text1.runes.toList(growable: false),
      b: text2.runes.toList(growable: false),
      isJunk: (int rune) => rune == 0x20,
    ).ratio();
  }

  /// 计算两组候选字符串之间的最大相似度。
  ///
  /// 每个顶层元素可以是一个字符串，也可以是同一对象的多个别名。算法先计算
  /// 所有组对的最高别名分数，再按分数从高到低做一对一贪心配对。复杂度由候选
  /// 组数量和别名数量共同决定；缓存仅存在于本次调用中，不会形成常驻增长。
  double listMaxDifference(
    List<Object> originalList1,
    List<Object> originalList2, {
    bool filterEmpty = true,
  }) {
    final Map<String, List<int>> runesCache = <String, List<int>>{};
    final Map<(String, String), double> differenceCache =
        <(String, String), double>{};

    List<int> cachedRunes(String value) {
      return runesCache.putIfAbsent(
        value,
        () => value.runes.toList(growable: false),
      );
    }

    double cachedDifference(String left, String right) {
      if (left == right) {
        return 1.0;
      }
      // SequenceMatcher 的匹配路径依赖左右顺序，因此缓存键不能排序或对称化。
      final (String, String) key = (left, right);
      final double? cached = differenceCache[key];
      if (cached != null) {
        return cached;
      }
      final double score = _SequenceMatcher(
        a: cachedRunes(left),
        b: cachedRunes(right),
        isJunk: (int rune) => rune == 0x20,
      ).ratio();
      differenceCache[key] = score;
      return score;
    }

    double bestGroupDifference(List<String> left, List<String> right) {
      if (left.isEmpty || right.isEmpty) {
        return 0.0;
      }
      double best = 0.0;
      for (final String leftText in left) {
        for (final String rightText in right) {
          final double score = cachedDifference(leftText, rightText);
          if (score == 1.0) {
            return 1.0;
          }
          if (score > best) {
            best = score;
          }
        }
      }
      return best;
    }

    final List<List<String>> list1 = _normalizeScoreInput(
      originalList1,
      filterEmpty: filterEmpty,
    );
    final List<List<String>> list2 = _normalizeScoreInput(
      originalList2,
      filterEmpty: filterEmpty,
    );
    if (list1.isEmpty || list2.isEmpty) {
      return 0.0;
    }

    final List<({int leftIndex, int rightIndex, double score})> scores =
        <({int leftIndex, int rightIndex, double score})>[];
    if (list1.length >= list2.length) {
      for (int leftIndex = 0; leftIndex < list1.length; leftIndex += 1) {
        for (int rightIndex = 0; rightIndex < list2.length; rightIndex += 1) {
          scores.add((
            leftIndex: leftIndex,
            rightIndex: rightIndex,
            score: bestGroupDifference(list1[leftIndex], list2[rightIndex]),
          ));
        }
      }
    } else {
      for (int leftIndex = 0; leftIndex < list2.length; leftIndex += 1) {
        for (int rightIndex = 0; rightIndex < list1.length; rightIndex += 1) {
          scores.add((
            leftIndex: leftIndex,
            rightIndex: rightIndex,
            score: bestGroupDifference(list2[leftIndex], list1[rightIndex]),
          ));
        }
      }
    }

    scores.sort((left, right) => right.score.compareTo(left.score));
    double totalScore = 0.0;
    final Set<int> usedLeft = <int>{};
    final Set<int> usedRight = <int>{};
    for (final score in scores) {
      if (usedLeft.contains(score.leftIndex) ||
          usedRight.contains(score.rightIndex)) {
        continue;
      }
      usedLeft.add(score.leftIndex);
      usedRight.add(score.rightIndex);
      totalScore += score.score;
      if (usedLeft.length == list1.length || usedRight.length == list2.length) {
        break;
      }
    }

    return totalScore /
        (list1.length > list2.length ? list1.length : list2.length);
  }

  static List<List<String>> _normalizeScoreInput(
    List<Object> rawList, {
    required bool filterEmpty,
  }) {
    final List<List<String>> normalized = <List<String>>[];
    for (final Object item in rawList) {
      final Iterable<String> values;
      if (item is String) {
        values = <String>[item];
      } else if (item is Iterable<String>) {
        values = item;
      } else {
        throw ArgumentError.value(
          item,
          'item',
          'item 必须是 String 或 Iterable<String>',
        );
      }
      normalized.add(
        values
            .where((String value) => !filterEmpty || value.isNotEmpty)
            .toList(growable: false),
      );
    }
    return normalized;
  }
}

class _MatchBlock {
  const _MatchBlock({required this.a, required this.b, required this.size});

  final int a;
  final int b;
  final int size;
}

/// Python `difflib.SequenceMatcher` 中 ratio 路径所需的最小等效实现。
class _SequenceMatcher {
  _SequenceMatcher({required this.a, required this.b, this.isJunk}) {
    _chainB();
  }

  final List<int> a;
  final List<int> b;
  final bool Function(int rune)? isJunk;

  late final Map<int, List<int>> _b2j;
  late final Set<int> _bJunk;
  List<_MatchBlock>? _matchingBlocks;

  double ratio() {
    int matches = 0;
    for (final _MatchBlock block in _getMatchingBlocks()) {
      matches += block.size;
    }
    final int length = a.length + b.length;
    return length == 0 ? 1.0 : (2.0 * matches) / length;
  }

  List<_MatchBlock> _getMatchingBlocks() {
    final List<_MatchBlock>? cached = _matchingBlocks;
    if (cached != null) {
      return cached;
    }

    final int aLength = a.length;
    final int bLength = b.length;
    final List<(int, int, int, int)> queue = <(int, int, int, int)>[
      (0, aLength, 0, bLength),
    ];
    final List<_MatchBlock> matchingBlocks = <_MatchBlock>[];

    while (queue.isNotEmpty) {
      final (int alo, int ahi, int blo, int bhi) = queue.removeLast();
      final _MatchBlock block = _findLongestMatch(
        alo: alo,
        ahi: ahi,
        blo: blo,
        bhi: bhi,
      );
      if (block.size == 0) {
        continue;
      }
      matchingBlocks.add(block);
      if (alo < block.a && blo < block.b) {
        queue.add((alo, block.a, blo, block.b));
      }
      if (block.a + block.size < ahi && block.b + block.size < bhi) {
        queue.add((block.a + block.size, ahi, block.b + block.size, bhi));
      }
    }

    matchingBlocks.sort((_MatchBlock left, _MatchBlock right) {
      final int aOrder = left.a.compareTo(right.a);
      if (aOrder != 0) {
        return aOrder;
      }
      final int bOrder = left.b.compareTo(right.b);
      return bOrder != 0 ? bOrder : left.size.compareTo(right.size);
    });

    int previousA = 0;
    int previousB = 0;
    int previousSize = 0;
    final List<_MatchBlock> nonAdjacent = <_MatchBlock>[];
    for (final _MatchBlock block in matchingBlocks) {
      if (previousA + previousSize == block.a &&
          previousB + previousSize == block.b) {
        previousSize += block.size;
        continue;
      }
      if (previousSize > 0) {
        nonAdjacent.add(
          _MatchBlock(a: previousA, b: previousB, size: previousSize),
        );
      }
      previousA = block.a;
      previousB = block.b;
      previousSize = block.size;
    }
    if (previousSize > 0) {
      nonAdjacent.add(
        _MatchBlock(a: previousA, b: previousB, size: previousSize),
      );
    }
    nonAdjacent.add(_MatchBlock(a: aLength, b: bLength, size: 0));
    return _matchingBlocks = nonAdjacent;
  }

  _MatchBlock _findLongestMatch({
    required int alo,
    required int ahi,
    required int blo,
    required int bhi,
  }) {
    int bestI = alo;
    int bestJ = blo;
    int bestSize = 0;
    Map<int, int> j2Len = <int, int>{};

    for (int i = alo; i < ahi; i += 1) {
      final Map<int, int> newJ2Len = <int, int>{};
      final List<int> positions = _b2j[a[i]] ?? const <int>[];
      for (final int j in positions) {
        if (j < blo) {
          continue;
        }
        if (j >= bhi) {
          break;
        }
        final int size = (j2Len[j - 1] ?? 0) + 1;
        newJ2Len[j] = size;
        if (size > bestSize) {
          bestI = i - size + 1;
          bestJ = j - size + 1;
          bestSize = size;
        }
      }
      j2Len = newJ2Len;
    }

    bool isBJunkAt(int index) => _bJunk.contains(b[index]);

    while (bestI > alo &&
        bestJ > blo &&
        !isBJunkAt(bestJ - 1) &&
        a[bestI - 1] == b[bestJ - 1]) {
      bestI -= 1;
      bestJ -= 1;
      bestSize += 1;
    }
    while (bestI + bestSize < ahi &&
        bestJ + bestSize < bhi &&
        !isBJunkAt(bestJ + bestSize) &&
        a[bestI + bestSize] == b[bestJ + bestSize]) {
      bestSize += 1;
    }
    while (bestI > alo &&
        bestJ > blo &&
        isBJunkAt(bestJ - 1) &&
        a[bestI - 1] == b[bestJ - 1]) {
      bestI -= 1;
      bestJ -= 1;
      bestSize += 1;
    }
    while (bestI + bestSize < ahi &&
        bestJ + bestSize < bhi &&
        isBJunkAt(bestJ + bestSize) &&
        a[bestI + bestSize] == b[bestJ + bestSize]) {
      bestSize += 1;
    }
    return _MatchBlock(a: bestI, b: bestJ, size: bestSize);
  }

  void _chainB() {
    _b2j = <int, List<int>>{};
    for (int index = 0; index < b.length; index += 1) {
      _b2j.putIfAbsent(b[index], () => <int>[]).add(index);
    }

    _bJunk = <int>{};
    final bool Function(int rune)? junkPredicate = isJunk;
    if (junkPredicate != null) {
      for (final int item in _b2j.keys.toList(growable: false)) {
        if (junkPredicate(item)) {
          _bJunk.add(item);
        }
      }
      for (final int item in _bJunk) {
        _b2j.remove(item);
      }
    }

    if (b.length < 200) {
      return;
    }
    final int threshold = b.length ~/ 100 + 1;
    final List<int> popular = <int>[
      for (final MapEntry<int, List<int>> entry in _b2j.entries)
        if (entry.value.length > threshold) entry.key,
    ];
    for (final int item in popular) {
      _b2j.remove(item);
    }
  }
}
