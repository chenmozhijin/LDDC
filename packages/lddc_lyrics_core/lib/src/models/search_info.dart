import 'package:collection/collection.dart';

import 'model_helpers.dart';
import 'model_enums.dart';

/// 搜索上下文信息，对齐Python版 `SearchInfo`。
class SearchInfo {
  SearchInfo({
    required Object source,
    required this.keyword,
    required this.searchType,
    required this.page,
  }) : source = _normalizeSource(source);

  /// 支持单源（[Source]）和多源（`List<Source>`）两种形态。
  final Object source;
  final String keyword;
  final SearchType searchType;
  final int? page;

  bool get isMultiSource => source is List<Source>;

  /// 统一返回来源列表表示。
  List<Source> get sources {
    if (source is Source) {
      return <Source>[source as Source];
    }
    return source as List<Source>;
  }

  SearchInfo copyWith({
    Object? source,
    String? keyword,
    SearchType? searchType,
    Object? page = copyWithSentinel,
  }) {
    return SearchInfo(
      source: source ?? this.source,
      keyword: keyword ?? this.keyword,
      searchType: searchType ?? this.searchType,
      page: identical(page, copyWithSentinel) ? this.page : page as int?,
    );
  }

  Map<String, Object?> toMap() {
    final Object sourceValue;
    if (source is Source) {
      sourceValue = (source as Source).value;
    } else {
      sourceValue = (source as List<Source>)
          .map((Source item) => item.value)
          .toList(growable: false);
    }
    return <String, Object?>{
      'source': sourceValue,
      'keyword': keyword,
      'search_type': searchType.value,
      'page': page,
    };
  }

  factory SearchInfo.fromMap(Map<String, Object?> map) {
    return SearchInfo(
      source: map['source'] ?? Source.local,
      keyword: map['keyword']?.toString() ?? '',
      searchType: SearchType.fromValue(map['search_type'] ?? SearchType.song),
      page: parseNullableInt(map['page']),
    );
  }

  static Object _normalizeSource(Object source) {
    if (source is Source) {
      return source;
    }
    if (source is List<Source>) {
      final List<Source> deduplicated = orderedUnique<Source>(source);
      return UnmodifiableListView<Source>(deduplicated);
    }
    if (source is Iterable<Object?>) {
      final List<Source> parsed = source
          .map((Object? item) => Source.fromValue(item))
          .toList(growable: false);
      return UnmodifiableListView<Source>(orderedUnique<Source>(parsed));
    }
    return Source.fromValue(source);
  }

  static bool _sourceEquals(Object left, Object right) {
    if (left is Source && right is Source) {
      return left == right;
    }
    if (left is List<Source> && right is List<Source>) {
      return const ListEquality<Source>().equals(left, right);
    }
    return false;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SearchInfo &&
            _sourceEquals(source, other.source) &&
            keyword == other.keyword &&
            searchType == other.searchType &&
            page == other.page);
  }

  @override
  int get hashCode {
    final Object sourceHash;
    if (source is Source) {
      sourceHash = source as Source;
    } else {
      sourceHash = Object.hashAll(source as List<Source>);
    }
    return Object.hash(sourceHash, keyword, searchType, page);
  }
}
