import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('SongInfo', () {
    test('parses source/artist/path and builds formatted fields', () {
      final SongInfo info = SongInfo.fromMap(<String, Object?>{
        'source': 'Local',
        'title': 'Song',
        'subtitle': 'Live',
        'artist': <String>['Alice', 'Bob', 'Alice'],
        'album': 'Album',
        'duration': 185000,
        'imgurl': 'https://img.example/song.jpg',
        'path': 'file://C:/music/song.mp3',
        'id': 7,
      });

      expect(info.source, Source.local);
      expect(info.artist?.values, <String>['Alice', 'Bob']);
      expect(info.fullTitle, 'Song(Live)');
      expect(info.artistTitle(), 'Alice/Bob - Song');
      expect(info.artistTitle(full: true), 'Alice/Bob - Song(Live)');
      expect(info.formattedDuration, '03:05');
      expect(info.url, 'file://C:/music/song.mp3');
      expect(info.id, '7');
      expect(info.imgUrl, 'https://img.example/song.jpg');
    });

    test('artist title replacement follows original fallback semantics', () {
      const SongInfo info = SongInfo(
        source: Source.local,
        title: null,
        artist: null,
      );
      expect(info.artistTitle(), '');
      expect(info.artistTitle(replaceMissing: true), '? - ?');
    });

    test('歌曲路径会幂等规范化文件前缀并保留非文件 URI', () {
      for (final String rawPath in <String>[
        r'C:\music\song.mp3',
        r'file://C:\music\song.mp3',
        r'file://file://C:\music\song.mp3',
      ]) {
        final SongInfo info = SongInfo.fromMap(<String, Object?>{
          'source': Source.local.value,
          'path': rawPath,
        });
        expect(info.path, r'C:\music\song.mp3', reason: rawPath);
        expect(info.url, r'file://C:\music\song.mp3', reason: rawPath);
      }

      for (final String uri in <String>[
        'content://media/external/audio/42',
        'https://example.test/audio/42',
        'http://example.test/audio/42',
      ]) {
        final SongInfo info = SongInfo.fromMap(<String, Object?>{
          'source': Source.local.value,
          'path': uri,
        });
        expect(info.path, uri);
        expect(info.url, uri);
      }

      final SongInfo empty = SongInfo.fromMap(<String, Object?>{
        'source': Source.local.value,
        'path': '',
      });
      expect(empty.path, isNull);
      expect(empty.url, isNull);
    });
  });

  group('Lyrics', () {
    test('detects instrumental from language and fallback sentence', () {
      const SongInfo byLang = SongInfo(
        source: Source.local,
        language: Language.instrumental,
      );
      final Lyrics lyricsByLang = Lyrics(
        songInfo: byLang,
        source: Source.local,
      );
      expect(lyricsByLang.isInstrumental(), isTrue);

      const SongInfo byText = SongInfo(source: Source.local);
      final Lyrics lyricsByText = Lyrics(
        songInfo: byText,
        source: Source.local,
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: null,
              endMs: null,
              words: const <LyricsWord>[
                LyricsWord(startMs: null, endMs: null, text: '纯音乐，请欣赏'),
              ],
            ),
          ],
        },
      );
      expect(lyricsByText.isInstrumental(), isTrue);
    });

    test('offset keeps timestamps non-negative', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local),
        source: Source.local,
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 120,
              endMs: 300,
              words: const <LyricsWord>[
                LyricsWord(startMs: 120, endMs: 200, text: 'ab'),
                LyricsWord(startMs: 200, endMs: 300, text: 'cd'),
              ],
            ),
          ],
        },
      );
      final Lyrics shifted = lyrics.withOffset(-200);
      final LyricsLine line = shifted.data['orig']!.first;
      expect(line.startMs, 0);
      expect(line.endMs, 100);
      expect(line.words.first.startMs, 0);
      expect(line.words.last.endMs, 100);
    });

    test('duration fallback uses last line/word timestamps', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local),
        source: Source.local,
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 100,
              endMs: null,
              words: const <LyricsWord>[
                LyricsWord(startMs: 100, endMs: null, text: 'abc'),
              ],
            ),
          ],
        },
      );
      expect(lyrics.getDurationMs(), 100);
    });

    test('copyWith 只修改元数据时复用已冻结歌词结构', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local),
        source: Source.local,
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 0,
              endMs: 1000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 0, endMs: 1000, text: 'line'),
              ],
            ),
          ],
        },
        types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
        tags: const <String, String>{'ar': 'Artist'},
      );

      final Lyrics copied = lyrics.copyWith(cached: true);

      expect(identical(copied.data, lyrics.data), isTrue);
      expect(identical(copied.types, lyrics.types), isTrue);
      expect(identical(copied.tags, lyrics.tags), isTrue);
      expect(() => copied.data.clear(), throwsUnsupportedError);
      expect(() => copied.data['orig']!.clear(), throwsUnsupportedError);
    });
  });

  group('SongArtist', () {
    test('重复读取 values 复用同一不可变快照', () {
      final SongArtist artist = SongArtist(<String>['A', 'B', 'A']);

      expect(identical(artist.values, artist.values), isTrue);
      expect(artist.values, <String>['A', 'B']);
      expect(() => artist.values.add('C'), throwsUnsupportedError);
    });
  });

  group('CharProgress', () {
    test('supports index + ratio tuple semantics', () {
      const CharProgress progress = CharProgress(charIndex: 3, charRatio: 0.25);
      expect(progress.charIndex, 3);
      expect(progress.charRatio, 0.25);
    });
  });
}
