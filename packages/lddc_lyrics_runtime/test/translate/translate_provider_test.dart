import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('BaseTranslateProvider', () {
    test('getOrigLines 按 orig 行序提取纯文本', () {
      final _EchoTranslateProvider provider = _EchoTranslateProvider();
      final List<String> lines = provider.getOrigLines(_buildLyrics());
      expect(lines, <String>['hello', 'world']);
    });

    test('textsToData 继承原文时间轴并回填译文', () {
      final _EchoTranslateProvider provider = _EchoTranslateProvider();
      final LyricsData translated = provider.textsToData(<String>[
        '你好',
        '世界',
      ], _buildLyrics());
      expect(translated.length, 2);
      expect(translated[0].startMs, 100);
      expect(translated[0].endMs, 200);
      expect(translated[0].text, '你好');
      expect(translated[1].startMs, 300);
      expect(translated[1].endMs, 400);
      expect(translated[1].text, '世界');
    });

    test('textsToData 行数不匹配时抛出异常', () {
      final _EchoTranslateProvider provider = _EchoTranslateProvider();
      expect(
        () => provider.textsToData(<String>['only-one-line'], _buildLyrics()),
        throwsA(isA<LddcTranslateException>()),
      );
    });
  });
}

class _EchoTranslateProvider extends BaseTranslateProvider {
  @override
  TranslateSource get source => TranslateSource.bing;

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    required TranslationOptions options,
  }) async {
    return textsToData(getOrigLines(lyrics), lyrics);
  }
}

Lyrics _buildLyrics() {
  return Lyrics(
    songInfo: const SongInfo(source: Source.local, title: 'song'),
    source: Source.local,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 100,
          endMs: 200,
          words: const <LyricsWord>[
            LyricsWord(startMs: 100, endMs: 200, text: 'hello'),
          ],
        ),
        LyricsLine(
          startMs: 300,
          endMs: 400,
          words: const <LyricsWord>[
            LyricsWord(startMs: 300, endMs: 400, text: 'world'),
          ],
        ),
      ],
    },
  );
}
