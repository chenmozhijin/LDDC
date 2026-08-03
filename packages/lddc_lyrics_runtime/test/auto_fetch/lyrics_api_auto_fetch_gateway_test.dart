import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  test('过滤非歌曲结果时保留服务端 total 并转发歌词请求', () async {
    const SongInfo song = SongInfo(
      source: Source.qm,
      id: 'song',
      title: 'Song',
    );
    const SongListInfo album = SongListInfo(
      source: Source.qm,
      type: SongListType.album,
      id: 'album',
      title: 'Album',
      imgUrl: '',
      songCount: 10,
      publishTimeS: null,
      author: 'Artist',
    );
    final APIResultList<SourceAware> mixed = APIResultList<SourceAware>(
      const <SourceAware>[song, album],
      info: SearchInfo(
        source: Source.qm,
        keyword: 'Song',
        searchType: SearchType.song,
        page: 1,
      ),
      ranges: const <Source, SourceRange>{
        Source.qm: SourceRange(start: 0, end: 1, total: 50),
      },
    );
    final Lyrics lyrics = Lyrics(songInfo: song, source: Source.qm);
    final _FakeLyricsApi api = _FakeLyricsApi(
      searchResult: mixed,
      lyrics: lyrics,
    );
    final LyricsApiAutoFetchGateway gateway = LyricsApiAutoFetchGateway(
      lyricsApi: api,
    );

    final APIResultList<SongInfo> result = await gateway.searchSongs(
      source: Source.qm,
      keyword: 'Song',
      searchType: SearchType.song,
    );
    final Lyrics forwarded = await gateway.getLyrics(song);

    expect(result.toList(), const <SongInfo>[song]);
    expect(
      result.sourceRanges[Source.qm],
      const SourceRange(start: 0, end: 0, total: 50),
    );
    expect(forwarded, same(lyrics));
    expect(api.lastLyricsInfo, same(song));
  });
}

class _FakeLyricsApi implements LyricsClient {
  _FakeLyricsApi({required this.searchResult, required this.lyrics});

  final APIResultList<SourceAware> searchResult;
  final Lyrics lyrics;
  Object? lastLyricsInfo;

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    return searchResult;
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    lastLyricsInfo = info;
    return lyrics;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
