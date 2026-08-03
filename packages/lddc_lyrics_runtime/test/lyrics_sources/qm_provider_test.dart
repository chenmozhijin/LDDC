import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  final List<Map<String, dynamic>> sanitizedResponseCases =
      ((jsonDecode(
                    File(
                      'test/resources/lyrics_sources/sanitized_qm_response_cases.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>)['cases']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  group('QmLyricsProvider', () {
    test('search(SONG) 对齐Python版分页与字段映射', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{
              'item_song': <Object?>[
                _songPayload(
                  id: 1357,
                  mid: 'm-song-1',
                  albumPmid: 'alb-song-1',
                  title: '夏',
                  subtitle: 'TV版',
                  singerNames: <String>['A', 'B'],
                  albumName: '专辑A',
                  intervalS: 123,
                  languageCode: 5,
                ),
              ],
            },
            'meta': <String, Object?>{'sum': 99},
          },
        },
      );
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '夏',
        searchType: SearchType.song,
        page: 1,
      );

      expect(result.length, 1);
      final SongInfo song = result.first as SongInfo;
      expect(song.source, Source.qm);
      expect(song.id, '1357');
      expect(song.mid, 'm-song-1');
      expect(song.title, '夏');
      expect(song.subtitle, 'TV版');
      expect(song.artist?.values, <String>['A', 'B']);
      expect(song.album, '专辑A');
      expect(song.durationMs, 123000);
      expect(
        song.imgUrl,
        'https://y.qq.com/music/photo_new/T002R300x300M000alb-song-1.jpg',
      );
      expect(song.language, Language.english);

      final SearchInfo info = result.info! as SearchInfo;
      expect(info.keyword, '夏');
      expect(info.searchType, SearchType.song);
      expect(info.page, 1);

      final SourceRange range = result.sourceRanges[Source.qm]!;
      expect(range.start, 0);
      expect(range.end, 0);
      expect(range.total, 99);

      expect(
        executor.calls.map((call) => '${call.module}.${call.method}').toList(),
        <String>[
          'music.getSession.session.GetSession',
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2',
        ],
      );
      expect(
        executor.calls.last.param['search_id']?.toString().endsWith(','),
        isTrue,
      );
      final String searchId = executor.calls.last.param['search_id']! as String;
      final BigInt searchValue = BigInt.parse(
        searchId.substring(0, searchId.length - 1),
      );
      expect(
        ((searchValue - BigInt.from(2)) ~/ BigInt.from(10)) %
            BigInt.from(2147483647),
        BigInt.from(9527),
      );
      expect(
        <String, Object?>{
          for (final MapEntry<String, Object?> entry
              in executor.calls.last.param.entries)
            if (entry.key != 'search_id') entry.key: entry.value,
        },
        <String, Object?>{
          'ver': 0,
          'sub_searchid': 0,
          'search_type': 0,
          'query': '夏',
          'page_id': 1,
          'page_num': 20,
          'remoteplace': '',
          'highlight': 0,
          'nqc_flag': 0,
          'grp': 1,
          'multi_zhida': 1,
          'auto_page': 1,
          'from': '8,',
          'seqno': 1,
        },
      );
    });

    test('搜索响应会清除歌曲、专辑和歌单字段中的 em 高亮标签', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{
              'item_songlist': <Object?>[
                <String, Object?>{
                  'dissid': 77,
                  'dissname': '<em>测试</em>歌单',
                  'logo': 'https://example.test/cover.jpg',
                  'songnum': 3,
                  'createtime': '2026-07-29',
                  'nickname': '<EM>创建者</EM>',
                },
              ],
            },
          },
        },
      );

      final APIResultList<SourceAware> result = await QmLyricsProvider(
        client: executor,
      ).search(keyword: '测试', searchType: SearchType.songlist);

      final SongListInfo songlist = result.single as SongListInfo;
      expect(songlist.title, '测试歌单');
      expect(songlist.author, '创建者');
      expect(executor.calls.last.param['highlight'], 0);
    });

    test('search(SONG) 兼容 album.name/title 漂移与缺失字段', () async {
      final Map<String, Object?> titleAlbum = _numberedSongPayload(2)
        ..['album'] = <String, Object?>{'title': '标题专辑', 'pmid': 'album-title'};
      final Map<String, Object?> emptyNameAlbum = _numberedSongPayload(3)
        ..['album'] = <String, Object?>{'name': '', 'title': '不应回退的标题'};
      final Map<String, Object?> missingAlbum = _numberedSongPayload(4)
        ..remove('album');
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{
              'item_song': <Object?>[
                _numberedSongPayload(1),
                titleAlbum,
                emptyNameAlbum,
                missingAlbum,
              ],
            },
            'meta': <String, Object?>{'sum': 4},
          },
        },
      );

      final APIResultList<SourceAware> result = await QmLyricsProvider(
        client: executor,
      ).search(keyword: '专辑字段', searchType: SearchType.song);
      final List<SongInfo> songs = result.cast<SongInfo>().toList();

      expect(songs.map((SongInfo song) => song.album).toList(), <String?>[
        '专辑-1',
        '标题专辑',
        '',
        '',
      ]);
      expect(
        songs[1].imgUrl,
        'https://y.qq.com/music/photo_new/T002R300x300M000album-title.jpg',
      );
      expect(songs[2].imgUrl, isNull);
      expect(songs[3].imgUrl, isNull);
    });

    test('累计搜索响应只映射当前页并可与前页无重复合并', () async {
      final _FakeQmExecutor page1Executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{
              'item_song': <Object?>[
                for (int index = 0; index < 20; index += 1)
                  _numberedSongPayload(index),
              ],
            },
            'meta': <String, Object?>{'sum': 10},
          },
        },
      );
      final _FakeQmExecutor page2Executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{
              'item_song': <Object?>[
                for (int index = 0; index < 40; index += 1)
                  _numberedSongPayload(index),
              ],
            },
            'meta': <String, Object?>{'sum': 10},
          },
        },
      );

      final APIResultList<SourceAware> page1 = await QmLyricsProvider(
        client: page1Executor,
      ).search(keyword: '累计', searchType: SearchType.song);
      final APIResultList<SourceAware> page2 = await QmLyricsProvider(
        client: page2Executor,
      ).search(keyword: '累计', searchType: SearchType.song, page: 2);

      expect(page2, hasLength(20));
      expect(
        page2.map((SourceAware item) => (item as SongInfo).id).toList(),
        <String>[for (int index = 20; index < 40; index += 1) '$index'],
      );
      expect(
        page2.sourceRanges[Source.qm],
        const SourceRange(start: 20, end: 39, total: 40),
      );

      final APIResultList<SourceAware> merged = page1 + page2;
      expect(merged, hasLength(40));
      expect(
        merged.sourceRanges[Source.qm],
        const SourceRange(start: 0, end: 39, total: 40),
      );
      expect(
        merged.map((SourceAware item) => (item as SongInfo).id).toSet(),
        hasLength(40),
      );
    });

    test('包装列表优先读取 total_num，并支持 estimate_sum', () async {
      final _FakeQmExecutor albumExecutor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{
              'item_album': <String, Object?>{
                'items': <Object?>[
                  <String, Object?>{
                    'id': 1,
                    'name': '包装专辑',
                    'pic': '',
                    'song_num': 1,
                    'publish_date': '',
                    'singer': '歌手',
                  },
                ],
                'total_num': 7,
                'estimate_sum': 8,
              },
            },
            'meta': <String, Object?>{'sum': 9},
          },
        },
      );
      final APIResultList<SourceAware> albums = await QmLyricsProvider(
        client: albumExecutor,
      ).search(keyword: '包装', searchType: SearchType.album);
      expect(albums, hasLength(1));
      expect(albums.sourceRanges[Source.qm]?.total, 7);

      final _FakeQmExecutor songlistExecutor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{
              'item_songlist': <String, Object?>{
                'items': <Object?>[],
                'estimate_sum': 30,
              },
            },
          },
        },
      );
      final APIResultList<SourceAware> songlists = await QmLyricsProvider(
        client: songlistExecutor,
      ).search(keyword: '空', searchType: SearchType.songlist, page: 2);
      expect(songlists, isEmpty);
      expect(
        songlists.sourceRanges[Source.qm],
        const SourceRange(start: 20, end: 19, total: 30),
      );
    });

    test('空页无 total 时 range end 为 start-1，total 回退为 start+count', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{'item_song': <Object?>[]},
          },
        },
      );

      final APIResultList<SourceAware> result = await QmLyricsProvider(
        client: executor,
      ).search(keyword: '空页', searchType: SearchType.song, page: 3);

      expect(result, isEmpty);
      expect(
        result.sourceRanges[Source.qm],
        const SourceRange(start: 40, end: 39, total: 40),
      );
    });

    test('search(SONGID) 使用 get_songinfo 语义', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.trackInfo.UniformRuleCtrl.CgiGetTrackInfo': <String, Object?>{
            'tracks': <Object?>[
              _songPayload(
                id: 2468,
                mid: 'm-song-2',
                albumPmid: 'alb-song-2',
                title: '冬',
                subtitle: '',
                singerNames: <String>['C'],
                albumName: '专辑B',
                intervalS: 234,
                languageCode: 0,
              ),
            ],
          },
        },
      );
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '2468',
        searchType: SearchType.songId,
      );

      expect(result.length, 1);
      expect((result.first as SongInfo).id, '2468');
      expect(
        result.sourceRanges[Source.qm],
        const SourceRange(start: 0, end: 0, total: 1),
      );
      expect(
        executor.calls.map((call) => '${call.module}.${call.method}').toList(),
        <String>[
          'music.getSession.session.GetSession',
          'music.trackInfo.UniformRuleCtrl.CgiGetTrackInfo',
        ],
      );
    });

    test('search(SONGID) 非数字时抛参数异常', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
        },
      );
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      await expectLater(
        () => provider.search(keyword: 'abc', searchType: SearchType.songId),
        throwsA(isA<LddcApiParamsException>()),
      );
      expect(executor.calls, isEmpty);
    });

    test('search(ALBUM) 映射专辑结果并按东八区日期转 UTC 秒', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.adaptor.SearchAdaptorQMMobile.do_search_v2': <String, Object?>{
            'body': <String, Object?>{
              'item_album': <Object?>[
                <String, Object?>{
                  'id': 9,
                  'albummid': 'alb-mid-9',
                  'name': '夏影',
                  'pic': 'https://img.example/9.jpg',
                  'song_num': 12,
                  'publish_date': '2024-01-02',
                  'singer': 'Singer-X',
                },
              ],
            },
            'meta': <String, Object?>{'sum': 1},
          },
        },
      );
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '夏影',
        searchType: SearchType.album,
      );

      expect(result.length, 1);
      final SongListInfo album = result.first as SongListInfo;
      expect(album.type, SongListType.album);
      expect(album.id, '9');
      expect(album.mid, 'alb-mid-9');
      expect(album.title, '夏影');
      expect(album.imgUrl, 'https://img.example/9.jpg');
      expect(album.songCount, 12);
      expect(album.publishTimeS, 1704124800);
      expect(album.author, 'Singer-X');
    });

    test('getSonglist 对齐Python版 album 分支', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.musichallAlbum.AlbumSongList.GetAlbumSongList':
              <String, Object?>{
                'songList': <Object?>[
                  <String, Object?>{
                    'songInfo': _songPayload(
                      id: 111,
                      mid: 'mid-111',
                      albumPmid: 'alb-111',
                      title: '曲目1',
                      subtitle: '',
                      singerNames: <String>['甲'],
                      albumName: '专辑C',
                      intervalS: 99,
                      languageCode: 3,
                    ),
                  },
                ],
              },
        },
      );
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      const SongListInfo album = SongListInfo(
        source: Source.qm,
        type: SongListType.album,
        id: '77',
        title: '专辑C',
        imgUrl: '',
        songCount: 1,
        publishTimeS: null,
        author: '',
      );
      final APIResultList<SongInfo> songs = await provider.getSonglist(album);

      expect(songs.length, 1);
      expect(songs.first.id, '111');
      expect(songs.first.title, '曲目1');
      expect(
        songs.first.imgUrl,
        'https://y.qq.com/music/photo_new/T002R300x300M000alb-111.jpg',
      );
      expect(songs.first.language, Language.japanese);
      expect(
        songs.sourceRanges[Source.qm],
        const SourceRange(start: 0, end: 0, total: 1),
      );
    });

    test('getLyrics 解析脱敏真实 success 结构与自定义 QRC 密文', () async {
      final _FakeQmExecutor executor =
          _FakeQmExecutor(<String, Map<String, Object?>>{
            'music.getSession.session.GetSession': _sessionPayload(),
            'music.musichallSong.PlayLyricInfo.GetPlayLyricInfo':
                _sanitizedQmResponse(sanitizedResponseCases, 'success'),
          });
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      final Lyrics lyrics = await provider.getLyrics(
        SongInfo(
          source: Source.qm,
          id: '1',
          title: 'Synthetic Signal',
          album: 'Fixture Collection',
          durationMs: 4000,
          artist: SongArtist(<String>['Unit Alpha']),
        ),
      );

      expect(lyrics.source, Source.qm);
      expect(lyrics.data.keys, containsAll(<String>['orig', 'ts', 'roma']));
      expect(lyrics.data['orig']!.first.text, 'alpha');
      expect(lyrics.data['ts']!.first.text, 'translated');
      expect(lyrics.data['roma']!.first.text, 'a l p h a');
      expect(lyrics.types['orig'], LyricsType.verbatim);
      expect(lyrics.types['ts'], LyricsType.lineByLine);
      expect(lyrics.types['roma'], LyricsType.lineByLine);
    });

    test('getLyrics 对脱敏真实 not_found 结构返回空歌词', () async {
      final _FakeQmExecutor executor =
          _FakeQmExecutor(<String, Map<String, Object?>>{
            'music.getSession.session.GetSession': _sessionPayload(),
            'music.musichallSong.PlayLyricInfo.GetPlayLyricInfo':
                _sanitizedQmResponse(sanitizedResponseCases, 'not_found'),
          });
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      final Lyrics lyrics = await provider.getLyrics(
        const SongInfo(
          source: Source.qm,
          id: '2',
          title: 'Synthetic Missing',
          album: 'Fixture Collection',
          durationMs: 4000,
        ),
      );

      expect(lyrics.isEmpty, isTrue);
      expect(lyrics.data, isEmpty);
      expect(lyrics.types, isEmpty);
      expect(executor.calls.last.method, 'GetPlayLyricInfo');
    });

    test('getLyrics 允许 QM 搜索结果中的空专辑名', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
          'music.musichallSong.PlayLyricInfo.GetPlayLyricInfo':
              <String, Object?>{
                'lyric': '',
                'qrc_t': 0,
                'lrc_t': '0',
                'trans': base64Encode(utf8.encode('[00:01.00]空专辑')),
                'trans_t': '1',
                'roma': '',
                'roma_t': '0',
              },
        },
      );
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      final Lyrics lyrics = await provider.getLyrics(
        SongInfo(
          source: Source.qm,
          id: '435076772',
          title: 'Eutopia',
          album: '',
          durationMs: 198000,
          artist: SongArtist(<String>['钟岚珠']),
        ),
      );

      expect(lyrics.data['ts']!.first.words.first.text, '空专辑');
      expect(
        executor.calls.map((call) => '${call.module}.${call.method}').toList(),
        <String>[
          'music.getSession.session.GetSession',
          'music.musichallSong.PlayLyricInfo.GetPlayLyricInfo',
        ],
      );
      expect(executor.calls.last.param['albumName'], '');
    });

    test('getLyrics 缺少必要参数时抛异常', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
        },
      );
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      await expectLater(
        () => provider.getLyrics(
          const SongInfo(source: Source.qm, id: '1', title: 'only-title'),
        ),
        throwsA(isA<LddcApiParamsException>()),
      );
      expect(executor.calls, isEmpty);
    });

    test('getLyricslist 显式 NotSupported', () async {
      final _FakeQmExecutor executor = _FakeQmExecutor(
        <String, Map<String, Object?>>{
          'music.getSession.session.GetSession': _sessionPayload(),
        },
      );
      final QmLyricsProvider provider = QmLyricsProvider(client: executor);

      await expectLater(
        () => provider.getLyricslist(
          const SongInfo(source: Source.qm, id: '1', title: 'x'),
        ),
        throwsA(isA<LddcApiNotSupportedException>()),
      );
    });
  });
}

Map<String, Object?> _sanitizedQmResponse(
  List<Map<String, dynamic>> cases,
  String status,
) {
  final Map<String, dynamic> item = cases.singleWhere(
    (Map<String, dynamic> value) => value['responseStatus'] == status,
  );
  return Map<String, Object?>.from(item['response'] as Map<String, dynamic>);
}

Map<String, Object?> _sessionPayload() {
  return <String, Object?>{
    'session': <String, Object?>{
      'uid': 9527,
      'sid': 'sid-1',
      'userip': '127.0.0.1',
    },
  };
}

Map<String, Object?> _songPayload({
  required int id,
  required String mid,
  required String albumPmid,
  required String title,
  required String subtitle,
  required List<String> singerNames,
  required String albumName,
  required int intervalS,
  required int languageCode,
}) {
  return <String, Object?>{
    'id': id,
    'mid': mid,
    'title': title,
    'subtitle': subtitle,
    'singer': <Object?>[
      for (final String singerName in singerNames)
        <String, Object?>{'name': singerName},
    ],
    'album': <String, Object?>{'name': albumName, 'pmid': albumPmid},
    'interval': intervalS,
    'language': languageCode,
  };
}

Map<String, Object?> _numberedSongPayload(int index) {
  return _songPayload(
    id: index,
    mid: 'mid-$index',
    albumPmid: 'album-$index',
    title: '歌曲-$index',
    subtitle: '',
    singerNames: <String>['歌手-$index'],
    albumName: '专辑-$index',
    intervalS: 180,
    languageCode: 0,
  );
}

class _FakeQmExecutor implements QmApiClient {
  _FakeQmExecutor(this._responses);

  final Map<String, Map<String, Object?>> _responses;
  final List<({String method, String module, Map<String, Object?> param})>
  calls = <({String method, String module, Map<String, Object?> param})>[];

  bool _inited = false;

  @override
  String get sessionUid => '9527';

  @override
  Future<void> close() async {}

  @override
  Future<void> init({bool refresh = false}) async {
    if (refresh) {
      _inited = false;
    }
    if (_inited) {
      return;
    }
    _record(
      method: 'GetSession',
      module: 'music.getSession.session',
      param: const <String, Object?>{'caller': 0, 'uid': '0', 'vkey': 0},
    );
    _inited = true;
  }

  @override
  Future<Map<String, Object?>> request({
    required String method,
    required String module,
    required Map<String, Object?> param,
  }) async {
    if (!_inited) {
      await init();
    }
    return _record(method: method, module: module, param: param);
  }

  Map<String, Object?> _record({
    required String method,
    required String module,
    required Map<String, Object?> param,
  }) {
    calls.add((
      method: method,
      module: module,
      param: Map<String, Object?>.from(param),
    ));
    final String key = '$module.$method';
    final Map<String, Object?>? response = _responses[key];
    if (response == null) {
      throw StateError('未配置测试响应: $key');
    }
    return Map<String, Object?>.from(response);
  }
}
