import 'text_similarity.dart';

const TextSimilarity _textSimilarity = TextSimilarity();

/// 歌手字段解析结果。
///
/// [groups] 保存组合或企划名，[artists] 的每个内层列表保存同一歌手的名字与
/// 别名。构造时会冻结两层集合，调用方不能在评分过程中修改解析结果。
class ArtistParseResult {
  ArtistParseResult({
    required Iterable<String> groups,
    required Iterable<Iterable<String>> artists,
  }) : groups = List<String>.unmodifiable(groups),
       artists = List<List<String>>.unmodifiable(
         artists.map(List<String>.unmodifiable),
       );

  final List<String> groups;
  final List<List<String>> artists;
}

/// 解析歌手字段并计算歌手相似度。
class ArtistParser {
  const ArtistParser();

  static final RegExp _cvMarkerPattern = RegExp(r'[Cc][Vv][.:]');
  static final RegExp _groupedCvPattern = RegExp(
    r'^(?<group>.*)\s?\((?<characters>.+)\)/[Cc][Vv][.:]\s?(?<singers>.+)$',
  );
  static final RegExp _segmentedCvPattern = RegExp(
    r'^(?<group>.*)\s?\((?<characters>.+)[Cc][Vv][.:](?<singers>.+)\)$',
  );
  static final RegExp _groupSingersPattern = RegExp(
    r'^(?<group>.*)\s?\(+(?<singers>[^)]+)\)+$',
  );
  static final RegExp _groupPrefixPattern = RegExp(
    r'^(?<group>.*[^&])\s(?<artists>[^(&a-zA-Z].*)$',
  );
  static final RegExp _commonSeparatorPattern = RegExp(r'[,、/\\&]');
  static final RegExp _groupSingerSeparatorPattern = RegExp(r'[,、・]');
  static final RegExp _featuredSingerPattern = RegExp(
    r'^(?<singer1>.*)\s?feat\.(?<character>.*)\s?\((?<singer2>.*)\)$',
  );
  static final RegExp _aliasPairPattern = RegExp(
    r'^(?<name1>.*)\s?\((?:[Cc][Vv][.:]|[Vv][Oo][.:])?(?<name2>.*)\)$',
  );
  static final RegExp _complexArtistPattern = RegExp(r'[)(:]');
  static final RegExp _closingParenthesisDotPattern = RegExp(r'(\))\.');

  /// 将常见的“组合名、角色名、CV、别名”写法解析为稳定结构。
  ArtistParseResult parse(String artist) {
    final List<String> spaceSeparated = artist.split(' ');
    if (spaceSeparated.every((String part) => part.runes.length == 1)) {
      artist = spaceSeparated.join();
    }

    artist = artist
        .trim()
        .replaceAll('·', '・')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('：', ':');

    if (artist.contains('・') && _cvMarkerPattern.hasMatch(artist)) {
      final ArtistParseResult? grouped = _parseGroupedCv(artist);
      if (grouped != null) {
        return grouped;
      }

      final ArtistParseResult? segmented = _parseSegmentedCv(artist);
      if (segmented != null) {
        return segmented;
      }
    }

    final int leftParenCount = '('.allMatches(artist).length;
    final int rightParenCount = ')'.allMatches(artist).length;
    if (leftParenCount == rightParenCount &&
        (leftParenCount == 1 || leftParenCount == 2)) {
      final RegExpMatch? matched = _groupSingersPattern.firstMatch(artist);
      if (matched != null) {
        final List<String> singers = (matched.namedGroup('singers') ?? '')
            .split(_groupSingerSeparatorPattern);
        if (singers.length > 1) {
          return ArtistParseResult(
            groups: <String>[matched.namedGroup('group') ?? ''],
            artists: singers.map(
              (String value) => <String>[_textSimilarity.unifiedSymbol(value)],
            ),
          );
        }
      }
    }

    List<String> groups = <String>[];
    List<String>? artistTexts;
    final RegExpMatch? groupedPrefix = _groupPrefixPattern.firstMatch(artist);
    if (groupedPrefix != null) {
      groups = <String>[groupedPrefix.namedGroup('group') ?? ''];
      artist = groupedPrefix.namedGroup('artists') ?? artist;
    }

    final List<String> closingDotParts = _splitByClosingParenthesisDot(artist);
    if (closingDotParts.length > 1 && (closingDotParts.length + 1).isEven) {
      artistTexts = <String>[];
      for (int index = 0; index < closingDotParts.length; index += 1) {
        if (index.isEven) {
          artistTexts.add(
            _textSimilarity.unifiedSymbol(closingDotParts[index]),
          );
        } else {
          artistTexts[artistTexts.length - 1] += closingDotParts[index];
        }
      }
    }

    final List<String> commonParts = artist.split(_commonSeparatorPattern);
    if (commonParts.length > 1) {
      artistTexts = commonParts
          .map(_textSimilarity.unifiedSymbol)
          .toList(growable: false);
    }
    artistTexts ??= <String>[_textSimilarity.unifiedSymbol(artist)];

    final List<List<String>> artists = <List<String>>[];
    for (final String artistText in artistTexts) {
      final RegExpMatch? featured = _featuredSingerPattern.firstMatch(
        artistText,
      );
      if (featured != null) {
        artists.add(<String>[
          _textSimilarity.unifiedSymbol(featured.namedGroup('singer1') ?? ''),
        ]);
        artists.add(
          _pairAsUniqueList(
            (featured.namedGroup('singer2') ?? '').trim(),
            (featured.namedGroup('character') ?? '').trim(),
          ),
        );
        continue;
      }

      final RegExpMatch? aliasPair = _aliasPairPattern.firstMatch(artistText);
      if (aliasPair != null) {
        artists.add(
          _pairAsUniqueList(
            (aliasPair.namedGroup('name1') ?? '').trim(),
            (aliasPair.namedGroup('name2') ?? '').trim(),
          ),
        );
        continue;
      }
      artists.add(<String>[artistText]);
    }
    return ArtistParseResult(groups: groups, artists: artists);
  }

  /// 计算两个歌手字段的百分制相似度。
  ///
  /// 参数只接受单个字符串或字符串集合。显式拒绝其他元素类型，可以避免把模型
  /// 错误通过 `toString()` 静默固化成可匹配文本。
  double calculateScore(Object artist1, Object artist2) {
    double score = 0.0;
    final List<Object> artists = <Object>[
      _normalizeArtistInput(artist1),
      _normalizeArtistInput(artist2),
    ];

    for (int index = 0; index < artists.length; index += 1) {
      final Object artist = artists[index];
      if (artist is List<String>) {
        if (artist.length == 1) {
          // 单元素集合若只展开成 String，后续会因集合索引已消失而被当作
          // ArtistParseResult 强制转换，最终触发运行时类型错误。这里直接走与
          // 字符串输入相同的解析路径，既保留原有评分语义，也避免额外中间集合。
          artists[index] = parse(artist.first);
          continue;
        }
        if (artist.any(_complexArtistPattern.hasMatch)) {
          artists[index] = parse(artist.join('/'));
        }
      } else if (artist is String) {
        artists[index] = parse(artist);
      }
    }

    final List<int> listIndexes = <int>[
      for (int index = 0; index < artists.length; index += 1)
        if (artists[index] is List<String>) index,
    ];

    if (listIndexes.isEmpty) {
      final ArtistParseResult left = artists[0] as ArtistParseResult;
      final ArtistParseResult right = artists[1] as ArtistParseResult;
      score = _textSimilarity.listMaxDifference(
        _composeScoreInput(left),
        _composeScoreInput(right),
      );
      if (score == 1) {
        return 100;
      }

      final double mergedScore = _textSimilarity.textDifference(
        _flattenParsedArtist(left),
        _flattenParsedArtist(right),
      );
      score = score > mergedScore ? score : mergedScore;

      if ((left.artists.isEmpty &&
              left.groups.isNotEmpty &&
              right.groups.isNotEmpty) ||
          (right.artists.isEmpty &&
              right.groups.isNotEmpty &&
              left.groups.isNotEmpty)) {
        final double groupScore =
            _textSimilarity.listMaxDifference(left.artists, right.artists) *
            0.6;
        score = score > groupScore ? score : groupScore;
      } else if (left.artists.isNotEmpty && right.artists.isNotEmpty) {
        final double artistScore = _textSimilarity.listMaxDifference(
          left.artists,
          right.artists,
        );
        score = score > artistScore ? score : artistScore;
      }
    } else if (listIndexes.length == 2) {
      final List<String> left = artists[0] as List<String>;
      final List<String> right = artists[1] as List<String>;
      score = _textSimilarity.listMaxDifference(left, right);
      final double mergedScore = _textSimilarity.textDifference(
        left.join(),
        right.join(),
      );
      score = score > mergedScore ? score : mergedScore;
    } else {
      final int listIndex = listIndexes.single;
      final int parsedIndex = listIndex == 0 ? 1 : 0;
      final List<String> listArtist = artists[listIndex] as List<String>;
      final ArtistParseResult parsedArtist =
          artists[parsedIndex] as ArtistParseResult;

      score = _textSimilarity.listMaxDifference(
        listArtist,
        _composeScoreInput(parsedArtist),
      );
      if (score == 1) {
        return 100;
      }
      final double listVsArtistScore = _textSimilarity.listMaxDifference(
        listArtist,
        parsedArtist.artists,
      );
      score = score > listVsArtistScore ? score : listVsArtistScore;
      if (score == 1) {
        return 100;
      }

      final String parsedFlatten = <String>[
        ...parsedArtist.groups,
        ..._flattenAliases(parsedArtist.artists),
      ].join();
      final double textScore = _textSimilarity.textDifference(
        listArtist.join(),
        parsedFlatten,
      );
      score = score > textScore ? score : textScore;

      if (listArtist.length == 1 && parsedArtist.groups.isNotEmpty) {
        final double groupScore =
            _textSimilarity.listMaxDifference(listArtist, parsedArtist.groups) *
            0.6;
        score = score > groupScore ? score : groupScore;
      }
    }

    final double finalScore = score * 100;
    return finalScore > 0 ? finalScore : 0;
  }

  static ArtistParseResult? _parseGroupedCv(String artist) {
    final RegExpMatch? matched = _groupedCvPattern.firstMatch(artist);
    if (matched == null) {
      return null;
    }
    final String charactersText = matched.namedGroup('characters') ?? '';
    final String singersText = matched.namedGroup('singers') ?? '';
    if (!charactersText.contains('・') || !singersText.contains('・')) {
      return null;
    }
    final List<String> characters = charactersText
        .split('・')
        .map(_textSimilarity.unifiedSymbol)
        .toList(growable: false);
    final List<String> singers = singersText
        .split('・')
        .map(_textSimilarity.unifiedSymbol)
        .toList(growable: false);
    if (characters.length != singers.length) {
      return null;
    }
    return ArtistParseResult(
      groups: <String>[matched.namedGroup('group') ?? ''],
      artists: <List<String>>[
        for (int index = 0; index < characters.length; index += 1)
          _pairAsUniqueList(characters[index], singers[index]),
      ],
    );
  }

  static ArtistParseResult? _parseSegmentedCv(String artist) {
    final List<String> groups = <String>[];
    final List<List<String>> artists = <List<String>>[];
    for (final String segment in artist.split('/')) {
      final RegExpMatch? matched = _segmentedCvPattern.firstMatch(segment);
      if (matched == null) {
        return null;
      }
      final String charactersText = matched.namedGroup('characters') ?? '';
      final String singersText = matched.namedGroup('singers') ?? '';
      if (!charactersText.contains('・') || !singersText.contains('・')) {
        return null;
      }
      final List<String> characters = charactersText
          .split('・')
          .map(_textSimilarity.unifiedSymbol)
          .toList(growable: false);
      final List<String> singers = singersText
          .split('・')
          .map(_textSimilarity.unifiedSymbol)
          .toList(growable: false);
      if (characters.length != singers.length) {
        return null;
      }
      for (int index = 0; index < characters.length; index += 1) {
        artists.add(_pairAsUniqueList(characters[index], singers[index]));
      }
      groups.add(matched.namedGroup('group') ?? '');
    }
    return ArtistParseResult(groups: groups, artists: artists);
  }

  static Object _normalizeArtistInput(Object artist) {
    if (artist is String) {
      return artist;
    }
    if (artist is Iterable) {
      final List<String> values = <String>[];
      for (final Object? item in artist) {
        if (item is! String) {
          throw ArgumentError.value(
            artist,
            'artist',
            'artist 集合中的每一项都必须是 String',
          );
        }
        values.add(item);
      }
      return values;
    }
    throw ArgumentError.value(
      artist,
      'artist',
      'artist 必须是 String 或 Iterable<String>',
    );
  }

  static List<Object> _composeScoreInput(ArtistParseResult parsed) {
    return <Object>[...parsed.groups, ...parsed.artists];
  }

  static String _flattenParsedArtist(ArtistParseResult parsed) {
    return parsed.groups.join() +
        parsed.artists.map((List<String> aliases) => aliases.join()).join();
  }

  static List<String> _flattenAliases(List<List<String>> artists) {
    return <String>[for (final List<String> aliases in artists) ...aliases];
  }

  static List<String> _pairAsUniqueList(String first, String second) {
    if (first == second) {
      return <String>[first];
    }
    return <String>[first, second]..sort();
  }

  static List<String> _splitByClosingParenthesisDot(String text) {
    final List<String> result = <String>[];
    int cursor = 0;
    for (final RegExpMatch match in _closingParenthesisDotPattern.allMatches(
      text,
    )) {
      result.add(text.substring(cursor, match.start));
      result.add(')');
      cursor = match.end;
    }
    result.add(text.substring(cursor));
    return result;
  }
}
