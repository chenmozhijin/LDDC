import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  group('LyricsPreviewComposer', () {
    test('buildPreviewText 在未选择有效语言时返回空字符串', () {
      final Lyrics lyrics = _buildLyrics();

      final String preview = LyricsPreviewComposer.buildPreviewText(
        lyrics: lyrics,
        selectedLangs: const <String>['roma'],
        lyricsFormat: LyricsFormat.verbatimLrc,
        offsetMs: 0,
        options: LyricsConvertOptions(),
      );

      expect(preview, isEmpty);
    });

    test('歌词语言摘要兼容 LDDC_ts 并只输出本地化展示名称', () {
      final Lyrics lyrics = _buildLyrics(withTranslation: true);

      final String summary = lyricsLanguageSummaryText(
        lyrics: lyrics,
        strings: LyricsUiStrings.zhHans(),
      );

      expect(summary, '原文（逐行） · 译文（逐行）');
      expect(summary, isNot(contains('orig')));
      expect(summary, isNot(contains('lineByLine')));
    });

    test('歌词语言摘要忽略只有类型但没有数据的语言', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local, title: 'Demo'),
        source: Source.local,
        data: _buildLyrics().data,
        types: const <String, LyricsType>{
          'orig': LyricsType.lineByLine,
          'ts': LyricsType.lineByLine,
        },
      );

      expect(
        lyricsLanguageSummaryText(
          lyrics: lyrics,
          strings: LyricsUiStrings.zhHans(),
        ),
        '原文（逐行）',
      );
    });

    test('歌词语言摘要可从旧翻译数据推断缺失类型', () {
      final Lyrics lyrics = _buildLyrics(
        withTranslation: true,
        withTranslationType: false,
      );

      expect(
        lyricsLanguageSummaryText(
          lyrics: lyrics,
          strings: LyricsUiStrings.zhHans(),
        ),
        '原文（逐行） · 译文（逐行）',
      );
    });

    test('buildPreviewText 归一旧翻译键并去除重复选择', () {
      final String preview = LyricsPreviewComposer.buildPreviewText(
        lyrics: _buildLyrics(withTranslation: true),
        selectedLangs: const <String>['LDDC_ts', 'ts', 'unknown'],
        lyricsFormat: LyricsFormat.lineByLineLrc,
        offsetMs: 0,
        options: LyricsConvertOptions(),
      );

      expect(preview, contains('译文'));
    });
  });
}

Lyrics _buildLyrics({
  bool withTranslation = false,
  bool withTranslationType = true,
}) {
  return Lyrics(
    songInfo: const SongInfo(source: Source.local, title: 'Demo'),
    source: Source.local,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: const <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: '原文'),
          ],
        ),
      ],
      if (withTranslation)
        'LDDC_ts': <LyricsLine>[
          LyricsLine(
            startMs: 0,
            endMs: 1000,
            words: const <LyricsWord>[
              LyricsWord(startMs: 0, endMs: 1000, text: '译文'),
            ],
          ),
        ],
    },
    types: <String, LyricsType>{
      'orig': LyricsType.lineByLine,
      if (withTranslation && withTranslationType) 'ts': LyricsType.lineByLine,
    },
  );
}
