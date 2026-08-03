import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('JsonLrcParser', () {
    test('优先从 info.songinfo 构造歌曲信息，并保留顶层歌词 metadata', () {
      final ParsedLyricsPayload payload = parseJsonLrcToMultiResult(
        <String, Object?>{
          'version': 1,
          'info': <String, Object?>{
            'source': 'QM',
            'id': 'lyrics-id',
            'duration': 3456,
            'accesskey': 'access',
            'creator': 'creator',
            'score': 88,
            'songinfo': <String, Object?>{
              'source': 'QM',
              'title': '标题',
              'artist': <String>['歌手'],
              'album': '专辑',
              'path': r'D:\music\a.flac',
              'language': 'CHINESE',
            },
          },
          'tags': <String, String>{'ti': '标题'},
          'lyrics': <String, Object?>{
            'orig': <Object?>[
              <Object?>[
                0,
                1000,
                <Object?>[
                  <Object?>[0, 1000, '歌词'],
                ],
              ],
            ],
          },
        },
      );

      final SongInfo songInfo = payload.embeddedInfo!.songInfo!;
      expect(songInfo.title, '标题');
      expect(songInfo.artist!.join(), '歌手');
      expect(songInfo.album, '专辑');
      expect(songInfo.path, r'D:\music\a.flac');
      expect(songInfo.language, Language.chinese);
      expect(payload.embeddedInfo!.id, 'lyrics-id');
      expect(payload.embeddedInfo!.accessKey, 'access');
      expect(payload.embeddedInfo!.durationMs, 3456);
      expect(payload.embeddedInfo!.creator, 'creator');
      expect(payload.embeddedInfo!.score, 88);
    });
  });
}
