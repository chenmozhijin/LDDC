import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('LyricsAssembler', () {
    const LyricsAssembler assembler = LyricsAssembler();

    test('优先使用 payload 内嵌 info 组装 Lyrics', () {
      final ParsedLyricsPayload payload = ParsedLyricsPayload(
        tags: <String, String>{'ar': 'artist'},
        lyricsData: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 0,
              endMs: 1000,
              words: <LyricsWord>[
                LyricsWord(startMs: 0, endMs: 500, text: 'he'),
                LyricsWord(startMs: 500, endMs: 1000, text: 'llo'),
              ],
            ),
          ],
        },
        embeddedInfo: ParsedLyricsMetadata(
          songInfo: SongInfo(
            source: Source.qm,
            title: 'title',
            artist: SongArtist(<String>['artist']),
            durationMs: 1234,
          ),
          source: Source.qm,
          id: '99',
          accessKey: 'ak',
          durationMs: 1234,
          creator: 'creator',
          score: 88,
          path: '/tmp/a.lrc',
          cached: true,
        ),
      );

      final Lyrics lyrics = assembler.assemble(payload);
      expect(lyrics.source, Source.qm);
      expect(lyrics.songInfo.source, Source.qm);
      expect(lyrics.songInfo.title, 'title');
      expect(lyrics.id, '99');
      expect(lyrics.accessKey, 'ak');
      expect(lyrics.durationMs, 1234);
      expect(lyrics.creator, 'creator');
      expect(lyrics.score, 88);
      expect(lyrics.path, '/tmp/a.lrc');
      expect(lyrics.cached, isTrue);
      expect(lyrics.types['orig'], LyricsType.verbatim);
    });

    test('无内嵌 info 时使用上下文组装', () {
      final ParsedLyricsPayload payload = ParsedLyricsPayload(
        lyricsData: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 1000,
              endMs: 2000,
              words: <LyricsWord>[
                LyricsWord(startMs: 1000, endMs: 2000, text: 'line'),
              ],
            ),
          ],
        },
      );

      final Lyrics lyrics = assembler.assemble(
        payload,
        context: const LyricsAssembleContext(
          source: Source.local,
          id: 'local-id',
          path: 'd:/lyrics/a.lrc',
          cached: false,
        ),
      );
      expect(lyrics.source, Source.local);
      expect(lyrics.songInfo.source, Source.local);
      expect(lyrics.songInfo.path, 'd:/lyrics/a.lrc');
      expect(lyrics.id, 'local-id');
      expect(lyrics.types['orig'], LyricsType.lineByLine);
    });

    test('source 解析优先级：embedded > context > payloadHint', () {
      final ParsedLyricsPayload payload = ParsedLyricsPayload(
        lyricsData: <String, LyricsData>{'orig': <LyricsLine>[]},
        embeddedInfo: const ParsedLyricsMetadata(source: Source.kg),
        sourceHint: Source.ne,
      );

      final Lyrics lyrics = assembler.assemble(
        payload,
        context: const LyricsAssembleContext(source: Source.qm),
      );
      expect(lyrics.source, Source.kg);
    });
  });
}
