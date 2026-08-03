import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('NeLyricsProvider', () {
    test('search(SONG) 对齐字段映射', () async {
      final _FakeNeExecutor executor = _FakeNeExecutor(
        <String, List<Map<String, Object?>>>{
          '/eapi/search/song/list/page': <Map<String, Object?>>[
            <String, Object?>{
              'data': <String, Object?>{
                'resources': <Object?>[
                  <String, Object?>{
                    'baseInfo': <String, Object?>{
                      'simpleSongData': _songPayload(
                        id: 1,
                        name: '青空',
                        alias: 'Live',
                        artistNames: <String>['A', 'B'],
                        albumName: '专辑A',
                        albumPicUrl: 'http://p3.music.126.net/song-1.jpg',
                        durationMs: 123456,
                      ),
                    },
                  },
                ],
                'totalCount': 40,
              },
            },
          ],
        },
      );
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: executor.call,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '青空',
        searchType: SearchType.song,
      );

      expect(result.length, 1);
      final SongInfo song = result.first as SongInfo;
      expect(song.source, Source.ne);
      expect(song.id, '1');
      expect(song.title, '青空');
      expect(song.subtitle, 'Live');
      expect(song.artist?.values, <String>['A', 'B']);
      expect(song.album, '专辑A');
      expect(song.imgUrl, 'https://p3.music.126.net/song-1.jpg');
      expect(song.durationMs, 123456);

      final SourceRange range = result.sourceRanges[Source.ne]!;
      expect(range.start, 0);
      expect(range.end, 0);
      expect(range.total, 1);
      expect(executor.calls.single.path, '/eapi/search/song/list/page');
    });

    test('search(SONGID) 走 song detail 分支', () async {
      final _FakeNeExecutor executor = _FakeNeExecutor(
        <String, List<Map<String, Object?>>>{
          '/eapi/v3/song/detail': <Map<String, Object?>>[
            <String, Object?>{
              'songs': <Object?>[
                _songPayload(
                  id: 9527,
                  name: '夜曲',
                  alias: '',
                  artistNames: <String>['周'],
                  albumName: '专辑B',
                  durationMs: 210000,
                ),
              ],
            },
          ],
        },
      );
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: executor.call,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '9527',
        searchType: SearchType.songId,
      );

      expect(result.length, 1);
      expect((result.first as SongInfo).id, '9527');
      expect(executor.calls.single.path, '/eapi/v3/song/detail');
    });

    test('search(SONGID) 非数字时抛异常', () async {
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: ({required path, required params}) async =>
            <String, Object?>{},
      );

      await expectLater(
        () => provider.search(keyword: 'abc', searchType: SearchType.songId),
        throwsA(isA<LddcApiParamsException>()),
      );
    });

    test('search(ALBUM) 映射专辑字段', () async {
      final _FakeNeExecutor executor = _FakeNeExecutor(
        <String, List<Map<String, Object?>>>{
          '/eapi/v1/search/album/get': <Map<String, Object?>>[
            <String, Object?>{
              'result': <String, Object?>{
                'albumCount': 10,
                'albums': <Object?>[
                  <String, Object?>{
                    'id': 7,
                    'name': '飞行',
                    'picUrl': 'http://p4.music.126.net/album-7.jpg',
                    'size': 9,
                    'publishTime': 1700000000000,
                    'artists': <Object?>[
                      <String, Object?>{'name': '歌手X'},
                    ],
                  },
                ],
              },
            },
          ],
        },
      );
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: executor.call,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '飞行',
        searchType: SearchType.album,
      );

      expect(result.length, 1);
      final SongListInfo album = result.first as SongListInfo;
      expect(album.type, SongListType.album);
      expect(album.id, '7');
      expect(album.title, '飞行');
      expect(album.imgUrl, 'https://p4.music.126.net/album-7.jpg');
      expect(album.songCount, 9);
      expect(album.publishTimeS, 1700000000);
      expect(album.author, '歌手X');
    });

    test('search(SONGLIST) 解析歌单封面并只提升NE CDN 到 HTTPS', () async {
      final _FakeNeExecutor executor = _FakeNeExecutor(
        <String, List<Map<String, Object?>>>{
          '/eapi/v1/search/playlist/get': <Map<String, Object?>>[
            <String, Object?>{
              'result': <String, Object?>{
                'playlists': <Object?>[
                  <String, Object?>{
                    'id': 9,
                    'name': '测试歌单',
                    'coverImgUrl': 'http://p1.music.126.net/playlist-9.jpg',
                    'trackCount': 12,
                    'creator': <String, Object?>{'nickname': '用户A'},
                  },
                  <String, Object?>{
                    'id': 10,
                    'name': '第三方封面歌单',
                    'coverImgUrl': 'http://images.example.test/playlist.jpg',
                    'trackCount': 1,
                    'creator': <String, Object?>{'nickname': '用户B'},
                  },
                ],
              },
            },
          ],
        },
      );
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: executor.call,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '测试',
        searchType: SearchType.songlist,
      );

      expect(result, hasLength(2));
      expect(
        (result.first as SongListInfo).imgUrl,
        'https://p1.music.126.net/playlist-9.jpg',
      );
      expect(
        (result.last as SongListInfo).imgUrl,
        'http://images.example.test/playlist.jpg',
      );
    });

    test('getSonglist(ALBUM) 带 cache_key 并解析 songs', () async {
      final _FakeNeExecutor executor = _FakeNeExecutor(
        <String, List<Map<String, Object?>>>{
          '/eapi/album/v3/detail': <Map<String, Object?>>[
            <String, Object?>{
              'songs': <Object?>[
                _songPayload(
                  id: 11,
                  name: '曲目1',
                  alias: '',
                  artistNames: <String>['甲'],
                  albumName: '专辑C',
                  albumPicUrl: 'https://img.song/11.jpg',
                  durationMs: 111000,
                ),
              ],
            },
          ],
        },
      );
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: executor.call,
      );

      const SongListInfo album = SongListInfo(
        source: Source.ne,
        type: SongListType.album,
        id: '77',
        title: '专辑C',
        imgUrl: '',
        songCount: 1,
        publishTimeS: null,
        author: '甲',
      );
      final APIResultList<SongInfo> songs = await provider.getSonglist(album);

      expect(songs.length, 1);
      expect(songs.first.id, '11');
      expect(songs.first.imgUrl, 'https://img.song/11.jpg');
      final String cacheKey = executor.calls.single.params['cache_key']!
          .toString();
      expect(eapiCacheKeyDecrypt(cacheKey), 'e_r=true&id=77');
    });

    test('getSonglist(SONGLIST) 对齐 trackIds -> song detail 语义', () async {
      final _FakeNeExecutor executor = _FakeNeExecutor(
        <String, List<Map<String, Object?>>>{
          '/eapi/v1/playlist/detail': <Map<String, Object?>>[
            <String, Object?>{
              'playlist': <String, Object?>{
                'trackIds': <Object?>[
                  <String, Object?>{'id': 21},
                  <String, Object?>{'id': 22},
                ],
              },
            },
          ],
          '/eapi/v3/song/detail': <Map<String, Object?>>[
            <String, Object?>{
              'songs': <Object?>[
                _songPayload(
                  id: 21,
                  name: 'A',
                  alias: '',
                  artistNames: <String>['A1'],
                  albumName: 'X',
                  durationMs: 120000,
                ),
                _songPayload(
                  id: 22,
                  name: 'B',
                  alias: '',
                  artistNames: <String>['B1'],
                  albumName: 'Y',
                  durationMs: 130000,
                ),
              ],
            },
          ],
        },
      );
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: executor.call,
      );

      const SongListInfo songlist = SongListInfo(
        source: Source.ne,
        type: SongListType.songlist,
        id: '99',
        title: '歌单',
        imgUrl: '',
        songCount: 2,
        publishTimeS: null,
        author: 'U',
      );
      final APIResultList<SongInfo> songs = await provider.getSonglist(
        songlist,
      );

      expect(songs.length, 2);
      expect(songs.first.id, '21');
      expect(songs.last.id, '22');
      expect(
        executor.calls.map((({String path, Map<String, Object?> params}) call) {
          return call.path;
        }).toList(),
        <String>['/eapi/v1/playlist/detail', '/eapi/v3/song/detail'],
      );
      final String cJson = executor.calls.last.params['c']?.toString() ?? '[]';
      expect(cJson, contains('"id":"21"'));
      expect(cJson, contains('"id":"22"'));
    });

    test('getLyrics 对齐 yrc/lrc 与标签映射语义', () async {
      final _FakeNeExecutor executor = _FakeNeExecutor(
        <String, List<Map<String, Object?>>>{
          '/eapi/song/lyric/v1': <Map<String, Object?>>[
            <String, Object?>{
              'yrc': <String, Object?>{
                'lyric': '[0,1000](0,500,0)你(500,500,0)好',
              },
              'tlyric': <String, Object?>{'lyric': '[00:00.00]你好'},
              'romalrc': <String, Object?>{'lyric': '[00:00.00]ni hao'},
              'lrc': <String, Object?>{'lyric': '[00:00.00]你好'},
              'lyricUser': <String, Object?>{'nickname': '作词A'},
              'transUser': <String, Object?>{'nickname': '翻译B'},
            },
          ],
        },
      );
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: executor.call,
      );

      final Lyrics lyrics = await provider.getLyrics(
        SongInfo(
          source: Source.ne,
          id: '123',
          title: '歌名',
          album: '专辑',
          artist: SongArtist(<String>['歌手']),
        ),
      );

      expect(lyrics.tags['ar'], '歌手');
      expect(lyrics.tags['al'], '专辑');
      expect(lyrics.tags['ti'], '歌名');
      expect(lyrics.tags['by'], '作词A & 翻译B');
      expect(
        lyrics.data.keys,
        containsAll(<String>['orig', 'ts', 'roma', 'orig_lrc']),
      );
      expect(lyrics.types['orig'], LyricsType.verbatim);
    });

    test('getLyricslist 显式 NotSupported', () async {
      final NeLyricsProvider provider = NeLyricsProvider(
        requestExecutor: ({required path, required params}) async =>
            <String, Object?>{},
      );

      await expectLater(
        () => provider.getLyricslist(
          const SongInfo(source: Source.ne, id: '1', title: 'x'),
        ),
        throwsA(isA<LddcApiNotSupportedException>()),
      );
    });
  });
}

Map<String, Object?> _songPayload({
  required int id,
  required String name,
  required String alias,
  required List<String> artistNames,
  required String albumName,
  String albumPicUrl = '',
  required int durationMs,
}) {
  return <String, Object?>{
    'id': id,
    'name': name,
    'alia': alias.isEmpty ? const <Object?>[] : <Object?>[alias],
    'ar': <Object?>[
      for (final String artistName in artistNames)
        <String, Object?>{'name': artistName},
    ],
    'al': <String, Object?>{'name': albumName, 'picUrl': albumPicUrl},
    'dt': durationMs,
  };
}

class _FakeNeExecutor {
  _FakeNeExecutor(this._responses);

  final Map<String, List<Map<String, Object?>>> _responses;
  final List<({String path, Map<String, Object?> params})> calls =
      <({String path, Map<String, Object?> params})>[];

  Future<Map<String, Object?>> call({
    required String path,
    required Map<String, Object?> params,
  }) async {
    calls.add((path: path, params: Map<String, Object?>.from(params)));
    final List<Map<String, Object?>>? queue = _responses[path];
    if (queue == null || queue.isEmpty) {
      throw StateError('未配置测试响应: $path');
    }
    return Map<String, Object?>.from(queue.removeAt(0));
  }
}
