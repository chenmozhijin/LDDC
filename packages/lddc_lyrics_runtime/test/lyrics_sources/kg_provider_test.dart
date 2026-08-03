import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('KgLyricsProvider', () {
    test('search(SONG) 对齐新接口字段映射', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('http://complexsearch.kugou.com/v2/search/song'),
            module: 'SearchSong',
            method: 'GET',
          ): <Object>[
            <String, Object?>{
              'data': <String, Object?>{
                'lists': <Object?>[
                  <String, Object?>{
                    'ID': 1,
                    'FileHash': 'hash-1',
                    'SongName': '青空',
                    'Auxiliary': 'Live',
                    'Image': 'https://img.example/{size}/cover.jpg',
                    'Singers': <Object?>[
                      <String, Object?>{'name': '甲'},
                      <String, Object?>{'name': '乙'},
                    ],
                    'AlbumName': '专辑A',
                    'Duration': 12,
                    'trans_param': <String, Object?>{'language': '英语'},
                  },
                ],
                'total': 35,
              },
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '青空',
        searchType: SearchType.song,
        page: 2,
      );

      expect(result.length, 1);
      final SongInfo song = result.first as SongInfo;
      expect(song.id, '1');
      expect(song.hash, 'hash-1');
      expect(song.title, '青空');
      expect(song.subtitle, 'Live');
      expect(song.artist?.values, <String>['甲', '乙']);
      expect(song.album, '专辑A');
      expect(song.durationMs, 12000);
      expect(song.imgUrl, 'https://img.example/240/cover.jpg');
      expect(song.language, Language.english);

      final SourceRange range = result.sourceRanges[Source.kg]!;
      expect(range.start, 20);
      expect(range.end, 20);
      expect(range.total, 21);
      expect(executor.legacyCalls, isEmpty);
    });

    test('search 新接口失败时回退旧接口', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('http://complexsearch.kugou.com/v1/search/album'),
            module: 'SearchAlbum',
            method: 'GET',
          ): <Object>[
            const LddcApiRequestException('new api failed'),
          ],
        },
        legacyResponses: <String, List<Map<String, Object?>>>{
          _legacyKey(
            keyword: '飞行',
            searchType: SearchType.album,
            page: 1,
          ): <Map<String, Object?>>[
            <String, Object?>{
              'data': <String, Object?>{
                'info': <Object?>[
                  <String, Object?>{
                    'albumid': 7,
                    'albumname': '飞行',
                    'imgurl': 'https://img/a.jpg',
                    'songcount': 9,
                    'publishtime': '2024-01-02 00:00:00',
                    'singer': '歌手X',
                  },
                ],
                'total': 10,
              },
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
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
      expect(album.imgUrl, 'https://img/a.jpg');
      expect(album.songCount, 9);
      expect(album.publishTimeS, 1704124800);
      expect(album.author, '歌手X');
      expect(executor.legacyCalls.length, 1);
    });

    test('search(ALBUM) 旧接口 singername 回退映射', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('http://complexsearch.kugou.com/v1/search/album'),
            module: 'SearchAlbum',
            method: 'GET',
          ): <Object>[
            const LddcApiRequestException('new api failed'),
          ],
        },
        legacyResponses: <String, List<Map<String, Object?>>>{
          _legacyKey(
            keyword: 'Taylor Swift',
            searchType: SearchType.album,
            page: 1,
          ): <Map<String, Object?>>[
            <String, Object?>{
              'data': <String, Object?>{
                'info': <Object?>[
                  <String, Object?>{
                    'albumid': 8,
                    'albumname': 'taylorswift',
                    'imgurl': 'https://img/t.jpg',
                    'song_count': '12',
                    'publishtime': '2024-01-02 00:00:00',
                    'singername': '牛奶味夹心阿尔卑斯',
                  },
                ],
                'total': 20,
              },
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: 'Taylor Swift',
        searchType: SearchType.album,
      );

      expect(result.length, 1);
      final SongListInfo album = result.first as SongListInfo;
      expect(album.author, '牛奶味夹心阿尔卑斯');
      expect(album.songCount, 12);
      expect(executor.legacyCalls.length, 1);
    });

    test('search(ALBUM) 新接口 singername 回退映射', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('http://complexsearch.kugou.com/v1/search/album'),
            module: 'SearchAlbum',
            method: 'GET',
          ): <Object>[
            <String, Object?>{
              'data': <String, Object?>{
                'lists': <Object?>[
                  <String, Object?>{
                    'albumid': 9,
                    'albumname': '新专辑',
                    'img': 'https://img/new.jpg',
                    'song_count': '6',
                    'publish_time': '2024-01-03',
                    'singername': '歌手新',
                  },
                ],
                'total': 6,
              },
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '新专辑',
        searchType: SearchType.album,
      );

      expect(result.length, 1);
      final SongListInfo album = result.first as SongListInfo;
      expect(album.author, '歌手新');
      expect(album.songCount, 6);
      expect(executor.legacyCalls, isEmpty);
    });

    test('getSonglist(ALBUM) 对齐字段映射与后缀裁剪', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('http://openapi.kugou.com/kmr/v1/album_songlist'),
            module: 'album_song_list',
            method: 'POST',
          ): <Object>[
            <String, Object?>{
              'data': <String, Object?>{
                'songs': <Object?>[
                  <String, Object?>{
                    'base': <String, Object?>{
                      'album_audio_id': 11,
                      'audio_name': '曲目1(伴奏)',
                      'author_name': '甲、乙',
                    },
                    'audio_info': <String, Object?>{
                      'hash': 'h11',
                      'duration': 654321,
                    },
                    'album_info': <String, Object?>{'album_name': '专辑C'},
                    'trans_param': <String, Object?>{
                      'songname_suffix': '(伴奏)',
                      'union_cover': 'https://img.example/{size}/album.jpg',
                      'language': '伴奏',
                    },
                  },
                ],
              },
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      const SongListInfo album = SongListInfo(
        source: Source.kg,
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
      final SongInfo song = songs.first;
      expect(song.id, '11');
      expect(song.hash, 'h11');
      expect(song.title, '曲目1');
      expect(song.subtitle, '(伴奏)');
      expect(song.artist?.values, <String>['甲', '乙']);
      expect(song.album, '专辑C');
      expect(song.durationMs, 654321);
      expect(song.imgUrl, 'https://img.example/240/album.jpg');
      expect(song.language, Language.instrumental);
      expect(executor.executeCalls.single.data, contains('"album_id": "77"'));
    });

    test('getSonglist(SONGLIST) 对齐标题拆分与语言映射', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse(
              'https://pubsongscdn.kugou.com/v4/get_other_list_file',
            ),
            module: 'SongList',
            method: 'GET',
          ): <Object>[
            <String, Object?>{
              'data': <String, Object?>{
                'info': <Object?>[
                  <String, Object?>{
                    'mixsongid': 22,
                    'hash': 'h22',
                    'name': '歌手 - 标题',
                    'remark': 'Python版',
                    'singerinfo': <Object?>[
                      <String, Object?>{'name': '歌手A'},
                    ],
                    'albuminfo': <String, Object?>{'name': '专辑D'},
                    'timelen': 123000,
                    'cover': 'https://img.example/{size}/songlist.jpg',
                    'trans_param': <String, Object?>{'language': '韩语'},
                  },
                ],
              },
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      const SongListInfo songlist = SongListInfo(
        source: Source.kg,
        type: SongListType.songlist,
        id: '99',
        title: '歌单',
        imgUrl: '',
        songCount: 1,
        publishTimeS: null,
        author: 'U',
      );
      final APIResultList<SongInfo> songs = await provider.getSonglist(
        songlist,
      );

      expect(songs.length, 1);
      final SongInfo song = songs.first;
      expect(song.id, '22');
      expect(song.title, '标题');
      expect(song.subtitle, 'Python版');
      expect(song.artist?.values, <String>['歌手A']);
      expect(song.album, '专辑D');
      expect(song.durationMs, 123000);
      expect(song.imgUrl, 'https://img.example/240/songlist.jpg');
      expect(song.language, Language.korean);
    });

    test('search(SONG) 新接口失败后旧接口封面字段可回退并替换尺寸', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('http://complexsearch.kugou.com/v2/search/song'),
            module: 'SearchSong',
            method: 'GET',
          ): <Object>[
            const LddcApiRequestException('new api failed'),
          ],
        },
        legacyResponses: <String, List<Map<String, Object?>>>{
          _legacyKey(
            keyword: '旧接口歌曲',
            searchType: SearchType.song,
            page: 1,
          ): <Map<String, Object?>>[
            <String, Object?>{
              'data': <String, Object?>{
                'info': <Object?>[
                  <String, Object?>{
                    'album_audio_id': 31,
                    'hash': 'h31',
                    'songname': '旧歌',
                    'topic': '',
                    'singername': '甲',
                    'album_name': '旧专辑',
                    'duration': 12,
                    'trans_param': <String, Object?>{
                      'language': '国语',
                      'union_cover': 'https://img.old/{size}/cover.jpg',
                    },
                  },
                ],
                'total': 1,
              },
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '旧接口歌曲',
        searchType: SearchType.song,
      );

      expect(result.length, 1);
      final SongInfo song = result.first as SongInfo;
      expect(song.id, '31');
      expect(song.imgUrl, 'https://img.old/240/cover.jpg');
      expect(executor.legacyCalls.length, 1);
    });

    test('getLyricslist 对齐 candidates 映射', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('https://lyrics.kugou.com/v1/search'),
            module: 'Lyric',
            method: 'GET',
          ): <Object>[
            <String, Object?>{
              'candidates': <Object?>[
                <String, Object?>{
                  'id': 99,
                  'accesskey': 'ak-99',
                  'nickname': '制作者',
                  'duration': 180000,
                  'score': 88,
                },
              ],
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      final SongInfo songInfo = SongInfo(
        source: Source.kg,
        id: '11',
        hash: 'hash-11',
        title: '标题',
        durationMs: 180000,
        artist: SongArtist(<String>['甲', '乙']),
      );
      final APIResultList<LyricInfo> lyrics = await provider.getLyricslist(
        songInfo,
      );

      expect(lyrics.length, 1);
      final LyricInfo lyric = lyrics.first;
      expect(lyric.id, '99');
      expect(lyric.accessKey, 'ak-99');
      expect(lyric.creator, '制作者');
      expect(lyric.durationMs, 180000);
      expect(lyric.score, 88);

      final Map<String, Object?> params = executor.executeCalls.single.params;
      expect(params['keyword'], '甲、乙 - 标题');
    });

    test('getLyrics(SongInfo) 自动选第一条并解析纯文本歌词', () async {
      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('https://lyrics.kugou.com/v1/search'),
            module: 'Lyric',
            method: 'GET',
          ): <Object>[
            <String, Object?>{
              'candidates': <Object?>[
                <String, Object?>{
                  'id': 9,
                  'accesskey': 'ak9',
                  'nickname': 'n9',
                  'duration': 1000,
                  'score': 90,
                },
              ],
            },
          ],
          _reqKey(
            uri: Uri.parse('http://lyrics.kugou.com/download'),
            module: 'Lyric',
            method: 'GET',
          ): <Object>[
            <String, Object?>{
              'contenttype': 2,
              'content': base64Encode(utf8.encode('第一行\n第二行')),
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      final Lyrics lyrics = await provider.getLyrics(
        SongInfo(
          source: Source.kg,
          id: '11',
          hash: 'hash-11',
          title: '标题',
          durationMs: 180000,
          artist: SongArtist(<String>['甲']),
        ),
      );

      expect(lyrics.data['orig']?.length, 2);
      expect(lyrics.data['orig']?.first.words.first.text, '第一行');
      expect(lyrics.types['orig'], LyricsType.plainText);
      expect(executor.executeCalls.length, 2);
    });

    test('getLyrics(LyricInfo) 解析 KRC 并输出标签', () async {
      final String krc = '[ar:测试歌手]\n[0,1000]<0,500,0>你<500,500,0>好';
      final Uint8List encrypted = _encryptKrc(krc);

      final _FakeKgExecutor executor = _FakeKgExecutor(
        executeActions: <String, List<Object>>{
          _reqKey(
            uri: Uri.parse('http://lyrics.kugou.com/download'),
            module: 'Lyric',
            method: 'GET',
          ): <Object>[
            <String, Object?>{
              'contenttype': 1,
              'content': base64Encode(encrypted),
            },
          ],
        },
      );
      final KgLyricsProvider provider = KgLyricsProvider(
        requestExecutor: executor,
      );

      final Lyrics lyrics = await provider.getLyrics(
        LyricInfo(
          source: Source.kg,
          id: '100',
          accessKey: 'ak100',
          songInfo: SongInfo(
            source: Source.kg,
            id: '11',
            title: '标题',
            durationMs: 180000,
          ),
        ),
      );

      expect(lyrics.tags['ar'], '测试歌手');
      expect(lyrics.types['orig'], LyricsType.verbatim);
      expect(lyrics.data['orig']?.first.words.first.text, '你');
      expect(executor.executeCalls.length, 1);
    });
  });
}

String _reqKey({
  required Uri uri,
  required String module,
  required String method,
}) {
  return '$module|${uri.toString()}|${method.toUpperCase()}';
}

String _legacyKey({
  required String keyword,
  required SearchType searchType,
  required int page,
}) {
  return '${searchType.value}|$keyword|$page';
}

Uint8List _encryptKrc(String plainText) {
  const List<int> key = <int>[
    0x40,
    0x47,
    0x61,
    0x77,
    0x5E,
    0x32,
    0x74,
    0x47,
    0x51,
    0x36,
    0x31,
    0x2D,
    0xCE,
    0xD2,
    0x6E,
    0x69,
  ];

  final List<int> compressed = ZLibEncoder().convert(utf8.encode(plainText));
  final Uint8List xored = Uint8List(compressed.length);
  for (int index = 0; index < compressed.length; index += 1) {
    xored[index] = compressed[index] ^ key[index % key.length];
  }

  final BytesBuilder bytes = BytesBuilder(copy: false)
    ..add(const <int>[0x6B, 0x72, 0x63, 0x31])
    ..add(xored);
  return Uint8List.fromList(bytes.takeBytes());
}

class _FakeKgExecutor implements KgRequestExecutor {
  _FakeKgExecutor({
    Map<String, List<Object>> executeActions = const <String, List<Object>>{},
    Map<String, List<Map<String, Object?>>> legacyResponses =
        const <String, List<Map<String, Object?>>>{},
  }) : _executeActions = <String, List<Object>>{
         for (final MapEntry<String, List<Object>> entry
             in executeActions.entries)
           entry.key: List<Object>.from(entry.value),
       },
       _legacyResponses = <String, List<Map<String, Object?>>>{
         for (final MapEntry<String, List<Map<String, Object?>>> entry
             in legacyResponses.entries)
           entry.key: entry.value
               .map((Map<String, Object?> item) => _cloneMap(item))
               .toList(growable: true),
       };

  final Map<String, List<Object>> _executeActions;
  final Map<String, List<Map<String, Object?>>> _legacyResponses;

  final List<
    ({
      Uri uri,
      String module,
      Map<String, Object?> params,
      String method,
      String? data,
      Map<String, String>? headers,
    })
  >
  executeCalls =
      <
        ({
          Uri uri,
          String module,
          Map<String, Object?> params,
          String method,
          String? data,
          Map<String, String>? headers,
        })
      >[];
  final List<({String keyword, SearchType searchType, int page})> legacyCalls =
      <({String keyword, SearchType searchType, int page})>[];

  @override
  Future<Map<String, Object?>> execute({
    required Uri uri,
    required Map<String, Object?> params,
    required String module,
    String method = 'GET',
    String? data,
    Map<String, String>? headers,
  }) async {
    executeCalls.add((
      uri: uri,
      module: module,
      params: _cloneMap(params),
      method: method,
      data: data,
      headers: headers == null ? null : Map<String, String>.from(headers),
    ));

    final String key = _reqKey(uri: uri, module: module, method: method);
    final List<Object>? queue = _executeActions[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('未配置执行响应: $key');
    }

    final Object action = queue.removeAt(0);
    if (action is Exception) {
      throw action;
    }
    if (action is Error) {
      throw action;
    }
    if (action is Map<String, Object?>) {
      return _cloneMap(action);
    }
    throw StateError('不支持的执行动作类型: ${action.runtimeType}');
  }

  @override
  Future<Map<String, Object?>> legacySearch({
    required String keyword,
    required SearchType searchType,
    required int page,
  }) async {
    legacyCalls.add((keyword: keyword, searchType: searchType, page: page));

    final String key = _legacyKey(
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
    final List<Map<String, Object?>>? queue = _legacyResponses[key];
    if (queue == null || queue.isEmpty) {
      throw StateError('未配置旧搜索响应: $key');
    }
    return _cloneMap(queue.removeAt(0));
  }

  @override
  Future<void> close() async {}

  static Map<String, Object?> _cloneMap(Map<String, Object?> source) {
    return source.map<String, Object?>(
      (String key, Object? value) =>
          MapEntry<String, Object?>(key, _cloneValue(value)),
    );
  }

  static Object? _cloneValue(Object? value) {
    if (value is Map<String, Object?>) {
      return _cloneMap(value);
    }
    if (value is Map<Object?, Object?>) {
      return value.map<String, Object?>(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key?.toString() ?? '',
          _cloneValue(value),
        ),
      );
    }
    if (value is List<Object?>) {
      return value.map<Object?>((Object? item) => _cloneValue(item)).toList();
    }
    if (value is List<dynamic>) {
      return value.map<Object?>((dynamic item) => _cloneValue(item)).toList();
    }
    return value;
  }
}
