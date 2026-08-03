import 'dart:collection';

import 'model_helpers.dart';
import 'model_enums.dart';
import 'search_info.dart';

/// 单来源分页范围：`[start, end, total]`。
class SourceRange {
  const SourceRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;

  /// 当前结果集中该来源的条目数。
  int get length => end - start + 1;

  List<int> toList() => <int>[start, end, total];

  factory SourceRange.fromList(List<Object?> values) {
    if (values.length != 3) {
      throw ArgumentError.value(values, 'values', 'must contain 3 items');
    }
    return SourceRange(
      start: _parseInt(values[0], key: 'start'),
      end: _parseInt(values[1], key: 'end'),
      total: _parseInt(values[2], key: 'total'),
    );
  }

  static int _parseInt(Object? value, {required String key}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw ArgumentError.value(value, key, 'must be int compatible');
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SourceRange &&
            start == other.start &&
            end == other.end &&
            total == other.total);
  }

  @override
  int get hashCode => Object.hash(start, end, total);
}

/// API 结果列表，对齐Python版 `APIResultList` 的聚合与范围语义。
class APIResultList<T extends SourceAware> extends IterableBase<T> {
  APIResultList(
    Iterable<T> result, {
    this.info,
    Object? ranges,
    this.cached = false,
    bool preserveOrder = false,
  }) {
    final List<T> snapshot = List<T>.unmodifiable(result);
    final Map<Source, SourceRange> processedRanges = _processRanges(
      ranges,
      _snapshotSources(snapshot),
      snapshot.length,
    );
    _sourceRanges = Map<Source, SourceRange>.unmodifiable(processedRanges);
    _items = preserveOrder
        ? snapshot
        : List<T>.unmodifiable(_createOrderedItems(snapshot, _sourceRanges));
    _validateRanges();
  }

  APIResultList._reuse({
    required this._items,
    required this._sourceRanges,
    required this.info,
    required this.cached,
  }) {
    _validateRanges();
  }

  late final List<T> _items;
  late final Map<Source, SourceRange> _sourceRanges;
  final Object? info;
  final bool cached;

  /// 按来源输出范围信息。
  Map<Source, SourceRange> get sourceRanges => _sourceRanges;

  /// 当前结果集涉及的数据源（按来源枚举顺序）。
  List<Source> get sources => Source.values
      .where((Source source) => _sourceRanges.containsKey(source))
      .toList(growable: false);

  /// 仍有下一页的来源集合。
  List<Source> get more => sourceRanges.entries
      .where(
        (MapEntry<Source, SourceRange> entry) =>
            entry.value.length < entry.value.total,
      )
      .map((MapEntry<Source, SourceRange> entry) => entry.key)
      .toList(growable: false);

  @override
  Iterator<T> get iterator => _items.iterator;

  @override
  int get length => _items.length;

  T operator [](int index) => _items[index];

  /// 复制当前结果，并可覆写 `info/cached`。
  APIResultList<T> copyWith({Object? info = copyWithSentinel, bool? cached}) {
    return APIResultList._reuse(
      items: _items,
      sourceRanges: _sourceRanges,
      info: identical(info, copyWithSentinel) ? this.info : info,
      cached: cached ?? this.cached,
    );
  }

  /// 合并两个相邻分页结果（要求来源范围可拼接）。
  APIResultList<T> operator +(APIResultList<T> other) {
    final Object? leftInfo = info;
    final Object? rightInfo = other.info;
    if (leftInfo != null &&
        rightInfo != null &&
        leftInfo.runtimeType != rightInfo.runtimeType) {
      throw ArgumentError(
        '无法合并不同 info 类型：${leftInfo.runtimeType} vs ${rightInfo.runtimeType}',
      );
    }

    final List<T> mergedItems = <T>[..._items, ...other._items];
    return APIResultList<T>(
      mergedItems,
      info: _mergeInfo(other),
      ranges: _mergeRanges(other),
      cached: cached && other.cached,
    );
  }

  Object? _mergeInfo(APIResultList<T> other) {
    if (info is SearchInfo && other.info is SearchInfo) {
      final SearchInfo selfSearch = info! as SearchInfo;
      final List<Source> mergedSources = <Source>[...sources, ...other.sources];
      final List<Source> deduplicated = <Source>[];
      for (final Source source in mergedSources) {
        if (!deduplicated.contains(source)) {
          deduplicated.add(source);
        }
      }
      return SearchInfo(
        source: deduplicated,
        keyword: selfSearch.keyword,
        searchType: selfSearch.searchType,
        page: null,
      );
    }
    return info;
  }

  Map<Source, SourceRange> _mergeRanges(APIResultList<T> other) {
    final Map<Source, SourceRange> merged = <Source, SourceRange>{};
    final Set<Source> allSources = <Source>{
      ..._sourceRanges.keys,
      ...other._sourceRanges.keys,
    };
    for (final Source source in allSources) {
      final SourceRange? left = _sourceRanges[source];
      final SourceRange? right = other._sourceRanges[source];

      if (left == null && right != null) {
        merged[source] = right;
        continue;
      }
      if (left != null && right == null) {
        merged[source] = left;
        continue;
      }
      if (left == null || right == null) {
        continue;
      }

      if (left.end + 1 == right.start) {
        merged[source] = SourceRange(
          start: left.start,
          end: right.end,
          total: left.total > right.total ? left.total : right.total,
        );
        continue;
      }
      if (right.end + 1 == left.start) {
        merged[source] = SourceRange(
          start: right.start,
          end: left.end,
          total: left.total > right.total ? left.total : right.total,
        );
        continue;
      }

      throw ArgumentError(
        '无法合并来源 ${source.value} 的范围：${left.toList()} 与 ${right.toList()}',
      );
    }
    return merged;
  }

  void _validateRanges() {
    final Map<Source, int> itemCountBySource = <Source, int>{};
    for (final T item in _items) {
      itemCountBySource.update(
        item.source,
        (int count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    if (!itemCountBySource.keys.every(_sourceRanges.containsKey)) {
      throw ArgumentError(
        'ranges 缺少结果中已出现的来源：'
        'items=${itemCountBySource.keys.map((Source item) => item.value).toList()}, '
        'ranges=${_sourceRanges.keys.map((Source item) => item.value).toList()}',
      );
    }

    for (final MapEntry<Source, SourceRange> entry in _sourceRanges.entries) {
      final SourceRange range = entry.value;
      if (range.start < 0 ||
          range.end < range.start - 1 ||
          range.total < 0 ||
          range.start > range.total ||
          (range.length > 0 && range.end >= range.total)) {
        throw ArgumentError.value(
          range.toList(),
          'ranges[${entry.key.value}]',
          '非空范围必须满足 0 <= start <= end < total；'
              '空页必须使用 end = start - 1',
        );
      }
      final int itemCount = itemCountBySource[entry.key] ?? 0;
      if (itemCount != range.length) {
        throw ArgumentError(
          '来源 ${entry.key.value} 的 ranges 长度与条目数不一致：'
          'items=$itemCount, range=${range.toList()}',
        );
      }
    }
  }

  static Map<Source, SourceRange> _processRanges(
    Object? ranges,
    Set<Source> sources,
    int itemCount,
  ) {
    if (ranges == null) {
      if (itemCount > 0) {
        throw ArgumentError.value(
          null,
          'ranges',
          'non-empty APIResultList must provide ranges',
        );
      }
      return <Source, SourceRange>{};
    }
    if (ranges is SourceRange) {
      if (sources.length > 1) {
        throw ArgumentError('有多个数据源，但只提供了一个范围元组');
      }
      if (sources.isEmpty) {
        return <Source, SourceRange>{};
      }
      return <Source, SourceRange>{sources.first: ranges};
    }
    if (ranges is Map<Source, SourceRange>) {
      return Map<Source, SourceRange>.from(ranges);
    }
    if (ranges is Map<Object?, Object?>) {
      final Map<Source, SourceRange> parsed = <Source, SourceRange>{};
      for (final MapEntry<Object?, Object?> entry in ranges.entries) {
        final Source source = Source.fromValue(entry.key);
        final Object? value = entry.value;
        if (value is SourceRange) {
          parsed[source] = value;
          continue;
        }
        if (value is List<Object?>) {
          parsed[source] = SourceRange.fromList(value);
          continue;
        }
        throw ArgumentError.value(
          value,
          'ranges[$source]',
          'unsupported range payload',
        );
      }
      return parsed;
    }
    throw ArgumentError.value(ranges, 'ranges', 'unsupported ranges type');
  }

  static Set<Source> _snapshotSources<T extends SourceAware>(
    Iterable<T> items,
  ) {
    return items.map((T item) => item.source).toSet();
  }

  static List<T> _createOrderedItems<T extends SourceAware>(
    Iterable<T> items,
    Map<Source, SourceRange> sourceRanges,
  ) {
    if (sourceRanges.isEmpty) {
      return <T>[];
    }

    final Map<Source, List<T>> groups = <Source, List<T>>{};
    for (final T item in items) {
      groups.putIfAbsent(item.source, () => <T>[]).add(item);
    }

    final List<Source> validSources = Source.values
        .where((Source source) => groups.containsKey(source))
        .toList(growable: false);

    int maxLength = 0;
    for (final Source source in validSources) {
      final int length = groups[source]!.length;
      if (length > maxLength) {
        maxLength = length;
      }
    }

    final List<T> ordered = <T>[];
    for (int index = 0; index < maxLength; index += 1) {
      for (final Source source in validSources) {
        final List<T> group = groups[source]!;
        if (index < group.length) {
          ordered.add(group[index]);
        }
      }
    }
    return ordered;
  }
}
