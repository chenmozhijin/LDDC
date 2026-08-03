import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:test/test.dart';

void main() {
  group('LyricsLanguageRegistry', () {
    test('归一化历史 LDDC_ts 别名并过滤坏 token', () {
      final List<String> normalized = LyricsLanguageRegistry.normalizeTokenList(
        <Object?>['orig', ' LDDC_ts ', 'ts', null, '', 'unknown', 'roma'],
      );

      expect(normalized, <String>['orig', 'ts', 'roma']);
      expect(() => normalized.add('orig'), throwsUnsupportedError);
    });

    test('descriptor 匹配会 trim，但不接受未知大小写和空值', () {
      const LyricsLanguageDescriptor descriptor = LyricsLanguageDescriptor(
        key: 'ts',
        aliases: <String>{'LDDC_ts'},
      );

      expect(descriptor.matches(' ts '), isTrue);
      expect(descriptor.matches('LDDC_ts'), isTrue);
      expect(descriptor.matches('TS'), isFalse);
      expect(LyricsLanguageRegistry.normalizeKey(null), isNull);
      expect(LyricsLanguageRegistry.normalizeKey('  '), isNull);
      expect(LyricsLanguageRegistry.normalizeKey(42), isNull);
    });

    test('选择结果按 roma/orig/ts 稳定排序并保持不可变', () {
      final List<String> ordered = LyricsLanguageRegistry.orderedSelection(
        const <String>['ts', 'orig', 'LDDC_ts', 'roma'],
      );

      expect(ordered, <String>['roma', 'orig', 'ts']);
      expect(() => ordered.clear(), throwsUnsupportedError);
    });

    test('数据键优先正式 ts，并兼容历史 LDDC_ts 数据层', () {
      final Lyrics canonical = _lyrics(
        data: <String, LyricsData>{'ts': _data('canonical')},
        types: const <String, LyricsType>{'ts': LyricsType.lineByLine},
      );
      final Lyrics legacy = _lyrics(
        data: <String, LyricsData>{'LDDC_ts': _data('legacy')},
        types: const <String, LyricsType>{'ts': LyricsType.verbatim},
      );

      expect(LyricsLanguageRegistry.resolveDataKey(canonical, 'ts'), 'ts');
      expect(LyricsLanguageRegistry.resolveDataKey(legacy, 'ts'), 'LDDC_ts');
      expect(LyricsLanguageRegistry.resolveDataKey(legacy, 'unknown'), isNull);
      expect(LyricsLanguageRegistry.resolveDataKey(legacy, 'orig'), isNull);
      expect(
        LyricsLanguageRegistry.resolveType(legacy, 'LDDC_ts'),
        LyricsType.verbatim,
      );
      expect(LyricsLanguageRegistry.resolveType(legacy, 'orig'), isNull);
      expect(LyricsLanguageRegistry.resolveType(legacy, 'unknown'), isNull);
      expect(
        LyricsLanguageRegistry.hasGeneratedTranslationLayer(legacy),
        isTrue,
      );
      expect(
        LyricsLanguageRegistry.hasGeneratedTranslationLayer(canonical),
        isFalse,
      );
    });
  });
}

Lyrics _lyrics({
  required Map<String, LyricsData> data,
  required Map<String, LyricsType> types,
}) {
  return Lyrics(
    songInfo: const SongInfo(source: Source.local),
    source: Source.local,
    data: data,
    types: types,
  );
}

LyricsData _data(String text) {
  return <LyricsLine>[
    LyricsLine(
      startMs: 0,
      endMs: 1000,
      words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 1000, text: text)],
    ),
  ];
}
