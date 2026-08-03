import 'dart:io';

import 'package:characters/characters.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../support/ruby/ruby_vector_harness.dart';

void main() {
  group('RubyEngine 向量差分', () {
    final String jsonText = _loadPayload();

    test('schema 与 Python 基线一致', () {
      final RubyVectorRunResult result = const RubyVectorHarness().runJsonText(
        jsonText,
      );
      result.assertRequiredCategories();
      expect(result.totalCases, greaterThanOrEqualTo(60));
    });
  });

  group('RubyEngine Unicode 与性能边界', () {
    test('小写片假名 ヵ/ヶ 按 Python 特殊表折叠为普通平假名 か', () {
      expect(katakanaToHiragana('ヵヶカ'), 'かかか');
    });

    test('RubySpan 使用 grapheme index，NFKC 兼容字符不切坏 emoji', () {
      final List<RubySpan> result = generateRuby(
        buildRubyTestLine('🙂 東京'),
        buildRubyTestLine('toukyou'),
      );
      final RubySpan tokyo = result.singleWhere(
        (RubySpan span) => span.ruby == 'とうきょう',
      );
      expect('🙂 東京'.characters.elementAt(tokyo.start), '東');
      expect(tokyo.end - tokyo.start, 2);
    });

    test('超长行跳过异常 DP 段，避免同步链路制造内存峰值', () {
      final String longOrig = List<String>.filled(400, '東京').join();
      final String longRoma = List<String>.filled(400, 'toukyou').join(' ');
      final List<RubySpan> result = generateRuby(
        buildRubyTestLine(longOrig),
        buildRubyTestLine(longRoma),
      );
      expect(result, isEmpty);
    });
  });
}

String _loadPayload() {
  final File file = File('test/resources/ruby/python_ruby_vectors.json');
  if (!file.existsSync()) {
    fail('缺少向量文件: ${file.path}');
  }
  return file.readAsStringSync();
}
