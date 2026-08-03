import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

final class RubyVectorRunResult {
  const RubyVectorRunResult({required this.executedCases});

  final Map<String, int> executedCases;

  int get totalCases =>
      executedCases.values.fold<int>(0, (int sum, int value) => sum + value);

  void assertRequiredCategories() {
    final List<String> failures = <String>[];
    for (final _RubyVectorCategory category in _rubyVectorCategories) {
      final int actual = executedCases[category.name] ?? 0;
      if (actual < category.minimumCases) {
        failures.add(
          '${category.name}: actual=$actual min=${category.minimumCases}',
        );
      }
    }
    if (failures.isNotEmpty) {
      throw StateError('ruby Python 向量覆盖不足: ${failures.join(', ')}');
    }
  }
}

final class _RubyVectorCategory {
  const _RubyVectorCategory({required this.name, required this.minimumCases});

  final String name;
  final int minimumCases;
}

const List<_RubyVectorCategory> _rubyVectorCategories = <_RubyVectorCategory>[
  _RubyVectorCategory(name: 'generate_ruby', minimumCases: 50),
  _RubyVectorCategory(name: 'roma_to_hiragana', minimumCases: 10),
];

final class RubyVectorHarness {
  const RubyVectorHarness();

  RubyVectorRunResult runJsonText(String jsonText) {
    final dynamic raw = jsonDecode(jsonText);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('ruby 向量 payload 必须是对象');
    }
    return runPayload(raw);
  }

  RubyVectorRunResult runPayload(Map<String, dynamic> payload) {
    final dynamic vectorsRaw = payload['vectors'];
    if (vectorsRaw is! Map) {
      throw const FormatException('ruby 向量 vectors 必须是对象');
    }
    final Map<String, dynamic> vectors = vectorsRaw.cast<String, dynamic>();
    return RubyVectorRunResult(
      executedCases: <String, int>{
        'generate_ruby': _runGenerateRuby(vectors),
        'roma_to_hiragana': _runRomaToHiragana(vectors),
      },
    );
  }

  int _runGenerateRuby(Map<String, dynamic> vectors) {
    final List<dynamic> cases = _readCaseList(vectors, 'generate_ruby');
    for (final dynamic item in cases) {
      final Map<String, dynamic> vector = _asMap(item, 'generate_ruby item');
      final String name = _readString(vector, 'name');
      final String origText = _readString(vector, 'origText');
      final String romaText = _readString(vector, 'romaText');
      final List<dynamic> expectedRaw = _readList(vector, 'expected');
      final List<String> actualNormalized = _normalizeSpans(
        generateRuby(buildRubyTestLine(origText), buildRubyTestLine(romaText)),
      );
      final List<String> expectedNormalized = _normalizeExpected(expectedRaw);
      if (!const ListEquality<String>().equals(
        actualNormalized,
        expectedNormalized,
      )) {
        throw StateError(
          'generate_ruby 向量不一致: $name, expected=$expectedNormalized, actual=$actualNormalized',
        );
      }
    }
    return cases.length;
  }

  int _runRomaToHiragana(Map<String, dynamic> vectors) {
    final List<dynamic> cases = _readCaseList(vectors, 'roma_to_hiragana');
    for (final dynamic item in cases) {
      final Map<String, dynamic> vector = _asMap(item, 'roma_to_hiragana item');
      final String input = _readString(vector, 'input');
      final String expected = _readString(vector, 'expected');
      final String actual = romaToHiragana(input);
      if (actual != expected) {
        throw StateError(
          'roma_to_hiragana 向量不一致: input=$input, expected=$expected, actual=$actual',
        );
      }
    }
    return cases.length;
  }
}

LyricsLine buildRubyTestLine(String text) {
  return LyricsLine(
    startMs: 0,
    endMs: 0,
    words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 0, text: text)],
  );
}

List<dynamic> _readCaseList(Map<String, dynamic> vectors, String key) {
  final dynamic raw = vectors[key];
  if (raw is List<dynamic>) {
    return raw;
  }
  throw FormatException('ruby 向量类别 $key 必须是数组');
}

Map<String, dynamic> _asMap(dynamic raw, String label) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return raw.cast<String, dynamic>();
  }
  throw FormatException('$label 必须是对象');
}

String _readString(Map<String, dynamic> map, String key) {
  final dynamic raw = map[key];
  if (raw is String) {
    return raw;
  }
  throw FormatException('字段 $key 必须是字符串');
}

List<dynamic> _readList(Map<String, dynamic> map, String key) {
  final dynamic raw = map[key];
  if (raw is List<dynamic>) {
    return raw;
  }
  throw FormatException('字段 $key 必须是数组');
}

List<String> _normalizeSpans(List<RubySpan> spans) {
  final List<String> values = spans
      .map((RubySpan span) => '${span.start}:${span.end}:${span.ruby}')
      .toList(growable: false);
  values.sort();
  return values;
}

List<String> _normalizeExpected(List<dynamic> raw) {
  final List<String> values = raw
      .map((dynamic item) {
        final List<dynamic> row = item as List<dynamic>;
        return '${row[0]}:${row[1]}:${row[2]}';
      })
      .toList(growable: false);
  values.sort();
  return values;
}
