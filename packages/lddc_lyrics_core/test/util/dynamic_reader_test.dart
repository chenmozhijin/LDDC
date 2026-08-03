import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  test('DynamicReader 宽松读取 Map 与基础数字布尔值', () {
    expect(DynamicReader.asMap(<String, Object?>{'a': 1})['a'], 1);
    expect(DynamicReader.asMap('bad'), isEmpty);

    expect(DynamicReader.asInt('42'), 42);
    expect(DynamicReader.asInt(' 42 '), 42);
    expect(DynamicReader.asInt(3.0), 3);
    expect(DynamicReader.asInt(3.8), isNull);
    expect(DynamicReader.asInt(double.nan), isNull);
    expect(DynamicReader.asInt(double.infinity), isNull);
    expect(DynamicReader.asInt('x'), isNull);

    expect(DynamicReader.asDouble('1.5'), 1.5);
    expect(DynamicReader.asDouble(2), 2.0);
    expect(DynamicReader.asDouble('NaN'), isNull);
    expect(DynamicReader.asDouble('Infinity'), isNull);
    expect(DynamicReader.asDouble('x'), isNull);

    expect(DynamicReader.asBool(' TRUE '), isTrue);
    expect(DynamicReader.asBool('false'), isFalse);
    expect(DynamicReader.asBool(<String, Object?>{'value': true}), isNull);
    expect(DynamicReader.asBool('yes'), isNull);
  });

  test('DynamicReader 宽松读取字符串和字符串列表', () {
    expect(DynamicReader.asString(null), isNull);
    expect(DynamicReader.asString(123), '123');
    expect(DynamicReader.asString(<String, Object?>{'value': 1}), isNull);
    expect(
      DynamicReader.asStringList(<Object?>[
        ' a ',
        1,
        null,
        '  ',
        <String, Object?>{'bad': true},
      ]),
      <String>['a', '1'],
    );
    expect(
      DynamicReader.asStringListPreserveEmpty(<Object?>['a', null]),
      <String>['a', ''],
    );
    expect(DynamicReader.asStringList('bad'), isEmpty);
  });

  test('DynamicReader token 列表会 trim、去重并按语义归一', () {
    expect(
      DynamicReader.readTokenList(<Object?>[
        ' a ',
        'a',
        '',
        null,
        'B',
      ], normalizer: (String raw) => raw.toLowerCase()),
      <String>['a', 'b'],
    );
  });
}
