import 'lyrics.dart';
import 'model_enums.dart';

/// 歌词语言键的领域描述。
///
/// LDDC 内部统一使用 `orig/ts/roma` 三个公开语言键。Python版历史数据中可能
/// 出现 `LDDC_ts`，它只在输入边界归一为 `ts`，UI 和导出选择逻辑都不再直接
/// 依赖这个私有键。
final class LyricsLanguageDescriptor {
  const LyricsLanguageDescriptor({required this.key, required this.aliases});

  final String key;
  final Set<String> aliases;

  bool matches(String value) {
    final String normalized = value.trim();
    return normalized == key || aliases.contains(normalized);
  }
}

/// 歌词语言键注册表。
final class LyricsLanguageRegistry {
  const LyricsLanguageRegistry._();

  static const String original = 'orig';
  static const String translation = 'ts';
  static const String romanized = 'roma';
  static const String legacyLddcTranslation = 'LDDC_ts';

  static const List<LyricsLanguageDescriptor> defaultDescriptors =
      <LyricsLanguageDescriptor>[
        LyricsLanguageDescriptor(key: original, aliases: <String>{}),
        LyricsLanguageDescriptor(
          key: translation,
          aliases: <String>{legacyLddcTranslation},
        ),
        LyricsLanguageDescriptor(key: romanized, aliases: <String>{}),
      ];

  static const List<String> defaultOrder = <String>[
    romanized,
    original,
    translation,
  ];

  static const List<String> previewOrder = <String>[
    original,
    translation,
    romanized,
  ];

  static String? normalizeKey(Object? value) {
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    for (final LyricsLanguageDescriptor descriptor in defaultDescriptors) {
      if (descriptor.matches(raw)) {
        return descriptor.key;
      }
    }
    return null;
  }

  static List<String> normalizeTokenList(Iterable<Object?> values) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final Object? value in values) {
      final String? key = normalizeKey(value);
      if (key != null && seen.add(key)) {
        result.add(key);
      }
    }
    return List<String>.unmodifiable(result);
  }

  static List<String> orderedSelection(Iterable<String> selected) {
    final Set<String> normalized = normalizeTokenList(selected).toSet();
    final List<String> ordered = <String>[
      for (final String key in defaultOrder)
        if (normalized.remove(key)) key,
      ...normalized,
    ];
    return List<String>.unmodifiable(ordered);
  }

  static String? resolveDataKey(Lyrics lyrics, String requestedKey) {
    final String? normalized = normalizeKey(requestedKey);
    if (normalized == null) {
      return null;
    }
    if (lyrics.data.containsKey(normalized)) {
      return normalized;
    }
    if (normalized == translation &&
        lyrics.data.containsKey(legacyLddcTranslation)) {
      return legacyLddcTranslation;
    }
    return null;
  }

  static LyricsType? resolveType(Lyrics lyrics, String requestedKey) {
    final String? normalized = normalizeKey(requestedKey);
    if (normalized == null) {
      return null;
    }
    final LyricsType? explicit = lyrics.types[normalized];
    if (explicit != null) {
      return explicit;
    }
    return null;
  }

  static bool hasGeneratedTranslationLayer(Lyrics lyrics) {
    return lyrics.data.containsKey(legacyLddcTranslation);
  }
}
