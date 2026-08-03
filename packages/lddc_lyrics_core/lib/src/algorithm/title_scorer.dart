import 'text_similarity.dart';

const TextSimilarity _textSimilarity = TextSimilarity();

/// 本地标题与远端标题中的歌曲版本关系。
enum SongVariantRelation { compatible, conflict, unknown }

/// 标题中可独立判断的版本信息。
class SongTitleVariant {
  const SongTitleVariant({
    required this.baseTitle,
    required this.isInstrumental,
  });

  final String baseTitle;
  final bool isInstrumental;
}

/// 分析标题版本并计算标题相似度。
class TitleScorer {
  const TitleScorer();

  static final RegExp _instrumentalPattern = RegExp(
    r'(?<![a-z0-9])(?:inst(?:rumental)?\.?|off[\s_-]*vocal(?:[\s_-]*ver(?:sion)?\.?)?|伴奏|纯音乐)(?![a-z0-9])',
    caseSensitive: false,
  );
  static final RegExp _variantSeparatorPattern = RegExp(r'[\s()\[\]{}<>._-]+');
  static final RegExp _titleTagPattern = RegExp(
    <String>[
      r'[-<(\[～]([～\]^)>-]*)[～\]^)>-]',
      r'([\p{L}\p{N}_]+ ?(?:(?:solo |size )?ver(?:sion)?\.?|size|style|mix(?:ed)?|edit(?:ed)?|版|solo))',
      r'(纯音乐|inst\.?(?:rumental)|off ?vocal(?: ?[Vv]er.)?)',
    ].join('|'),
    unicode: true,
  );
  static final RegExp _titleDecorationPattern = RegExp(r'[-><)(\]\[～]');
  static final RegExp _versionPattern = RegExp(r'ver(?:sion)?\.?');
  static final RegExp _titleInstrumentalTagPattern = RegExp(
    r'伴奏|纯音乐|inst\.?(?:rumental)|off ?vocal(?: ?[Vv]er.)?',
  );
  static final RegExp _modifierVersionPattern = RegExp(
    r'(solo|mix|edit|style|size) ver',
  );
  static final RegExp _tvSizePattern = RegExp(
    r'(?:tv|anime) ?(?:サイズ|size)?(?: ?edit)?(?: ?ver)?',
  );
  static final RegExp _ordinaryTagPattern = RegExp(
    r'(?:solo|mix|edit|style|size|inst)$',
  );

  SongTitleVariant analyzeVariant(String title) {
    final String normalized = _textSimilarity
        .unifiedSymbol(title)
        .toLowerCase()
        .trim();
    return SongTitleVariant(
      baseTitle: normalized
          .replaceAll(_instrumentalPattern, '')
          .replaceAll(_variantSeparatorPattern, ' ')
          .trim(),
      isInstrumental: _instrumentalPattern.hasMatch(normalized),
    );
  }

  /// 远端明确标注纯音乐而本地没有标注时视为冲突，避免自动匹配到无歌词版本。
  /// 本地明确为纯音乐而远端缺少标记时信息不足，交给歌词内容证据继续判断。
  SongVariantRelation classifyVariant(String localTitle, String remoteTitle) {
    final SongTitleVariant local = analyzeVariant(localTitle);
    final SongTitleVariant remote = analyzeVariant(remoteTitle);
    if (local.baseTitle.isEmpty || remote.baseTitle.isEmpty) {
      return SongVariantRelation.unknown;
    }
    if (!local.isInstrumental && remote.isInstrumental) {
      return SongVariantRelation.conflict;
    }
    if (local.isInstrumental && !remote.isInstrumental) {
      return SongVariantRelation.unknown;
    }
    return SongVariantRelation.compatible;
  }

  /// 计算两个标题的百分制相似度。
  ///
  /// 标题公共前缀和尾部版本标签分别计分。长度必须按 Unicode 码点计算，才能
  /// 与 Python 的 `len(str)` 一致；Dart 的 `String.length` 是 UTF-16 单元数，
  /// 对表情符号等非 BMP 字符会多计一次。
  double calculateScore(String title1, String title2) {
    final String normalizedTitle1 = _textSimilarity
        .unifiedSymbol(title1)
        .toLowerCase();
    final String normalizedTitle2 = _textSimilarity
        .unifiedSymbol(title2)
        .toLowerCase();
    if (normalizedTitle1 == normalizedTitle2) {
      return 100;
    }

    final double baseDifference = _textSimilarity.textDifference(
      normalizedTitle1,
      normalizedTitle2,
    );
    final double baseScore = (baseDifference >= 0 ? baseDifference : 0) * 100;
    final List<int> runes1 = normalizedTitle1.runes.toList(growable: false);
    final List<int> runes2 = normalizedTitle2.runes.toList(growable: false);
    final int maxPrefixLength = runes1.length < runes2.length
        ? runes1.length
        : runes2.length;
    int prefixRuneCount = 0;
    while (prefixRuneCount < maxPrefixLength &&
        runes1[prefixRuneCount] == runes2[prefixRuneCount]) {
      prefixRuneCount += 1;
    }
    if (prefixRuneCount == 0 ||
        prefixRuneCount == runes1.length ||
        prefixRuneCount == runes2.length) {
      return baseScore;
    }

    final String commonPrefix = String.fromCharCodes(
      runes1.take(prefixRuneCount),
    );
    final _TitleTagInfo tags1 = _extractTags(
      normalizedTitle1.substring(commonPrefix.length),
    );
    final _TitleTagInfo tags2 = _extractTags(
      normalizedTitle2.substring(commonPrefix.length),
    );
    String remaining1 = tags1.other;
    String remaining2 = tags2.other;

    final List<String> unmatched1 = <String>[];
    final List<String> unmatched2 = List<String>.from(tags2.tags);
    for (final String tag1 in tags1.tags) {
      if (tags2.tags.contains(tag1)) {
        unmatched2.remove(tag1);
      } else if (_ordinaryTagPattern.hasMatch(tag1)) {
        unmatched1.add(tag1);
      } else if (remaining2.contains(tag1)) {
        remaining1 += tag1;
      }
    }

    // 删除元素发生在副本上，避免遍历同一列表时修改集合导致并发修改异常。
    for (final String tag2 in List<String>.from(unmatched2)) {
      if (!_ordinaryTagPattern.hasMatch(tag2) && remaining1.contains(tag2)) {
        remaining2 += tag2;
        unmatched2.remove(tag2);
      }
    }

    final int remainingLength1 = remaining1.runes.length;
    final int remainingLength2 = remaining2.runes.length;
    final double prefixWeight =
        prefixRuneCount /
        (((remainingLength1 + remainingLength2) / 2) + prefixRuneCount);
    final double tailDifference = _textSimilarity.textDifference(
      remaining1,
      remaining2,
    );
    final double tagIndependentScore =
        100 * prefixWeight +
        (tailDifference >= 0 ? tailDifference : 0) * (1 - prefixWeight);

    if (unmatched1.isEmpty && unmatched2.isEmpty) {
      final double score = tagIndependentScore * 0.7 + 30;
      return score > baseScore ? score : baseScore;
    }

    double leftTagScore = 0;
    double rightTagScore = 0;
    if (unmatched1.isNotEmpty && unmatched2.isNotEmpty) {
      for (final String tag1 in unmatched1) {
        double best = 0;
        for (final String tag2 in unmatched2) {
          final double difference = _textSimilarity.textDifference(tag1, tag2);
          if (difference > best) {
            best = difference;
          }
        }
        leftTagScore += best * (30 / unmatched1.length);
      }

      for (final String tag2 in unmatched2) {
        double best = 0;
        for (final String tag1 in unmatched1) {
          final double difference = _textSimilarity.textDifference(tag1, tag2);
          if (difference > best) {
            best = difference;
          }
        }
        rightTagScore += best * (30 / unmatched2.length);
      }
    }

    final double score =
        tagIndependentScore * 0.7 +
        (leftTagScore > rightTagScore ? leftTagScore : rightTagScore);
    return score > baseScore ? score : baseScore;
  }

  static _TitleTagInfo _extractTags(String text) {
    final List<String> tags = <String>[];
    for (final RegExpMatch match in _titleTagPattern.allMatches(text)) {
      for (
        int groupIndex = 1;
        groupIndex <= match.groupCount;
        groupIndex += 1
      ) {
        final String? value = match.group(groupIndex);
        if (value != null && value.isNotEmpty) {
          tags.add(value.trim());
        }
      }
    }

    final List<String> escapedTags = tags
        .map(RegExp.escape)
        .toList(growable: false);
    final String tagPattern = <String>[
      if (escapedTags.isNotEmpty) escapedTags.join('|'),
      _titleDecorationPattern.pattern,
    ].join('|');
    final String other = text.replaceAll(RegExp(tagPattern), '');

    for (int index = 0; index < tags.length; index += 1) {
      String normalized = tags[index]
          .replaceAll(_versionPattern, 'ver')
          .replaceAll(_titleInstrumentalTagPattern, 'inst')
          .replaceAll('mixed', 'mix')
          .replaceAll('edited', 'edit');
      normalized = normalized.replaceAllMapped(
        _modifierVersionPattern,
        (Match match) => match.group(1) ?? '',
      );
      tags[index] = normalized.replaceAll(_tvSizePattern, 'tv size');
    }
    return _TitleTagInfo(tags: tags, other: other);
  }
}

class _TitleTagInfo {
  const _TitleTagInfo({required this.tags, required this.other});

  final List<String> tags;
  final String other;
}
