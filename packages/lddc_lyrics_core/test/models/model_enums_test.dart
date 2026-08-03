import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:test/test.dart';

void main() {
  group('Python 枚举兼容解析', () {
    test('Direction 支持实例、code、name 和 wire value', () {
      for (final Direction value in Direction.values) {
        expect(Direction.fromValue(value), same(value));
        expect(Direction.fromValue(value.code), value);
        expect(Direction.fromValue(' ${value.name.toUpperCase()} '), value);
        expect(Direction.fromValue(value.value.toLowerCase()), value);
      }
      expect(() => Direction.fromValue('center'), throwsArgumentError);
    });

    test('Source 支持实例、code、name 和 wire value', () {
      for (final Source value in Source.values) {
        expect(Source.fromValue(value), same(value));
        expect(Source.fromValue(value.code), value);
        expect(Source.fromValue(' ${value.name.toUpperCase()} '), value);
        expect(Source.fromValue(value.value.toLowerCase()), value);
      }
      expect(() => Source.fromValue(999), throwsArgumentError);
    });

    test('SearchType 支持实例、code、name 和 wire value', () {
      for (final SearchType value in SearchType.values) {
        expect(SearchType.fromValue(value), same(value));
        expect(SearchType.fromValue(value.code), value);
        expect(SearchType.fromValue(' ${value.name.toUpperCase()} '), value);
        expect(SearchType.fromValue(value.value.toLowerCase()), value);
      }
      expect(() => SearchType.fromValue(null), throwsArgumentError);
    });

    test('Language 支持实例、code、name 和 wire value', () {
      for (final Language value in Language.values) {
        expect(Language.fromValue(value), same(value));
        expect(Language.fromValue(value.code), value);
        expect(Language.fromValue(' ${value.name.toUpperCase()} '), value);
        expect(Language.fromValue(value.value.toLowerCase()), value);
      }
      expect(() => Language.fromValue(1.5), throwsArgumentError);
    });

    test('LyricsType 支持实例、code、name 和 wire value', () {
      for (final LyricsType value in LyricsType.values) {
        expect(LyricsType.fromValue(value), same(value));
        expect(LyricsType.fromValue(value.code), value);
        expect(LyricsType.fromValue(' ${value.name.toUpperCase()} '), value);
        expect(LyricsType.fromValue(value.value.toLowerCase()), value);
      }
      expect(() => LyricsType.fromValue('word-timed'), throwsArgumentError);
    });

    test('LyricsFormat 支持实例、code、name、wire value 和扩展名契约', () {
      const Map<LyricsFormat, String> extensions = <LyricsFormat, String>{
        LyricsFormat.verbatimLrc: '.lrc',
        LyricsFormat.lineByLineLrc: '.lrc',
        LyricsFormat.enhancedLrc: '.lrc',
        LyricsFormat.srt: '.srt',
        LyricsFormat.ass: '.ass',
        LyricsFormat.qrc: '.qrc',
        LyricsFormat.krc: '.krc',
        LyricsFormat.yrc: '.yrc',
        LyricsFormat.json: '.json',
      };
      for (final LyricsFormat value in LyricsFormat.values) {
        expect(LyricsFormat.fromValue(value), same(value));
        expect(LyricsFormat.fromValue(value.code), value);
        expect(LyricsFormat.fromValue(' ${value.name.toUpperCase()} '), value);
        expect(LyricsFormat.fromValue(value.value.toLowerCase()), value);
        expect(value.ext, extensions[value]);
      }
      expect(() => LyricsFormat.fromValue('.lrc'), throwsArgumentError);
    });

    test('SongListType 支持实例、code、name 和 wire value', () {
      for (final SongListType value in SongListType.values) {
        expect(SongListType.fromValue(value), same(value));
        expect(SongListType.fromValue(value.code), value);
        expect(SongListType.fromValue(' ${value.name.toUpperCase()} '), value);
        expect(SongListType.fromValue(value.value.toLowerCase()), value);
      }
      expect(() => SongListType.fromValue('artist'), throwsArgumentError);
    });
  });

  test('各来源声明的搜索能力与协议支持范围一致', () {
    expect(Source.multi.supportedSearchTypes, <SearchType>{
      SearchType.song,
      SearchType.album,
      SearchType.songlist,
    });
    expect(Source.qm.supportedSearchTypes, <SearchType>{
      SearchType.song,
      SearchType.album,
      SearchType.songlist,
      SearchType.songId,
    });
    expect(Source.ne.supportedSearchTypes, Source.qm.supportedSearchTypes);
    expect(Source.kg.supportedSearchTypes, <SearchType>{
      SearchType.song,
      SearchType.album,
      SearchType.songlist,
    });
    expect(Source.lrclib.supportedSearchTypes, <SearchType>{SearchType.song});
    expect(Source.local.supportedSearchTypes, isEmpty);
  });
}
