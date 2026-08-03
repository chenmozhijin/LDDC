import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'audio_fixture_factory.dart';

const String kIntegrationDesktopLyricsSongTitle = 'アルカテイル';
const String kIntegrationDesktopLyricsSongArtist = '鈴木このみ';
const String kIntegrationDesktopLyricsSongAlbum =
    'PCゲーム『Summer Pockets』オープニングテーマ「アルカテイル」';

IntegrationSearchCase get kIntegrationSearchSongCase =>
    const IntegrationSearchCase(source: Source.qm, keyword: "one's future");

IntegrationSearchCase get kIntegrationSearchSongIdCase =>
    const IntegrationSearchCase(source: Source.ne, keyword: '29567189');

IntegrationSearchCase get kIntegrationSearchAlbumCase =>
    const IntegrationSearchCase(
      source: Source.qm,
      keyword: 'Kud Wafter Original SoundTrack',
    );

IntegrationSearchCase get kIntegrationSearchSongListCase =>
    const IntegrationSearchCase(source: Source.qm, keyword: 'Kud Wafter');

final List<IntegrationAudioFixtureSpec> kIntegrationLocalMatchSongs =
    <IntegrationAudioFixtureSpec>[
      const IntegrationAudioFixtureSpec(
        pathSegments: <String>['key', 'summer pockets', '鈴木このみ - アルカテイル.flac'],
        format: IntegrationAudioFormat.flac,
        durationMs: 289000,
        title: 'アルカテイル',
        artists: <String>['鈴木このみ'],
        album: 'PCゲーム『Summer Pockets』オープニングテーマ「アルカテイル」',
        date: '2018-03-28',
        track: '01',
      ),
      const IntegrationAudioFixtureSpec(
        pathSegments: <String>['key', 'summer pockets', '鈴木このみ - アスタロア.flac'],
        format: IntegrationAudioFormat.flac,
        durationMs: 278000,
        title: 'アスタロア',
        artists: <String>['鈴木このみ'],
        album: 'アスタロア/青き此方/夏の砂時計',
        date: '2020',
        track: '01',
      ),
    ];

final List<IntegrationAudioFixtureSpec> kIntegrationSearchTagTargets =
    <IntegrationAudioFixtureSpec>[
      const IntegrationAudioFixtureSpec(
        pathSegments: <String>['search', 'search_tag_target.mp3'],
        format: IntegrationAudioFormat.mp3,
        durationMs: 1000,
        title: 'アルカテイル',
        artists: <String>['鈴木このみ'],
      ),
      const IntegrationAudioFixtureSpec(
        pathSegments: <String>['search', 'search_tag_target.flac'],
        format: IntegrationAudioFormat.flac,
        durationMs: 1000,
        title: 'アルカテイル',
        artists: <String>['鈴木このみ'],
      ),
    ];

const IntegrationAudioFixtureSpec kIntegrationOpenLyricsSong =
    IntegrationAudioFixtureSpec(
      pathSegments: <String>['open_lyrics', 'open_song.flac'],
      format: IntegrationAudioFormat.flac,
      durationMs: 30000,
      title: 'Test lyrics song',
      artists: <String>['LDDC Integration'],
      album: 'Open Lyrics Fixture',
      embeddedLyricsText: '[00:00.00]内嵌歌词\n[00:10.00]第二行歌词',
    );

class IntegrationSearchCase {
  const IntegrationSearchCase({required this.source, required this.keyword});

  final Source source;
  final String keyword;
}
