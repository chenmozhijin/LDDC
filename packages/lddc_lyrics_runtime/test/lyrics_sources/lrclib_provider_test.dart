import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('LrclibLyricsProvider', () {
    test('search(SONG) 对齐分页与字段映射', () async {
      final _FakeLrclibExecutor executor = _FakeLrclibExecutor(
        <String, List<Object?>>{
          '/search': <Object?>[
            <Object?>[
              for (int index = 1; index <= 25; index += 1)
                <String, Object?>{
                  'id': index,
                  'trackName': '标题$index',
                  'artistName': '歌手$index',
                  'albumName': '专辑$index',
                  'duration': 12.3,
                  'instrumental': index == 25,
                },
            ],
          ],
        },
      );
      final LrclibLyricsProvider provider = LrclibLyricsProvider(
        requestExecutor: executor.call,
      );

      final APIResultList<SourceAware> result = await provider.search(
        keyword: '标题',
        searchType: SearchType.song,
        page: 2,
      );

      expect(result.length, 5);
      final SongInfo first = result.first as SongInfo;
      final SongInfo last = result.last as SongInfo;
      expect(first.id, '21');
      expect(first.title, '标题21');
      expect(first.artist?.values, <String>['歌手21']);
      expect(first.album, '专辑21');
      expect(first.durationMs, 12300);
      expect(first.language, Language.other);
      expect(last.id, '25');
      expect(last.language, Language.instrumental);

      final SourceRange range = result.sourceRanges[Source.lrclib]!;
      expect(range.start, 20);
      expect(range.end, 24);
      expect(range.total, 25);

      final ({String endpoint, Map<String, String>? params}) call =
          executor.calls.single;
      expect(call.endpoint, '/search');
      expect(call.params?['q'], '标题');
    });

    test('search 非 SONG 类型抛参数异常', () async {
      final LrclibLyricsProvider provider = LrclibLyricsProvider(
        requestExecutor: ({required endpoint, params}) async => <Object?>[],
      );

      await expectLater(
        () => provider.search(keyword: 'x', searchType: SearchType.album),
        throwsA(isA<LddcApiParamsException>()),
      );
    });

    test('search 返回 error 时抛请求异常', () async {
      final _FakeLrclibExecutor executor = _FakeLrclibExecutor(
        <String, List<Object?>>{
          '/search': <Object?>[
            <String, Object?>{'error': 'bad request'},
          ],
        },
      );
      final LrclibLyricsProvider provider = LrclibLyricsProvider(
        requestExecutor: executor.call,
      );

      await expectLater(
        () => provider.search(keyword: 'x', searchType: SearchType.song),
        throwsA(isA<LddcApiRequestException>()),
      );
    });

    test('getLyrics 优先解析 syncedLyrics', () async {
      final _FakeLrclibExecutor executor = _FakeLrclibExecutor(
        <String, List<Object?>>{
          '/get': <Object?>[
            <String, Object?>{
              'id': 9,
              'trackName': '歌名',
              'artistName': '原歌手',
              'albumName': '专辑A',
              'duration': 120.5,
              'syncedLyrics': '[ar:解析歌手]\n[00:01.00]你好',
              'plainLyrics': '纯文本备用',
            },
          ],
        },
      );
      final LrclibLyricsProvider provider = LrclibLyricsProvider(
        requestExecutor: executor.call,
      );

      final SongInfo info = SongInfo(
        source: Source.lrclib,
        id: '9',
        title: '歌名',
        artist: SongArtist(<String>['输入歌手']),
        album: '专辑A',
        durationMs: 120000,
      );
      final Lyrics lyrics = await provider.getLyrics(info);

      expect(lyrics.id, '9');
      expect(lyrics.durationMs, 120500);
      expect(lyrics.tags['ti'], '歌名');
      expect(lyrics.tags['al'], '专辑A');
      expect(lyrics.tags['ar'], '解析歌手');
      expect(lyrics.data['orig']?.first.words.first.text, '你好');
      expect(lyrics.types['orig'], LyricsType.lineByLine);

      final ({String endpoint, Map<String, String>? params}) call =
          executor.calls.single;
      expect(call.endpoint, '/get');
      expect(call.params?['track_name'], '歌名');
      expect(call.params?['artist_name'], '输入歌手');
      expect(call.params?['album_name'], '专辑A');
      expect(call.params?['duration'], '120.0');
    });

    test('getLyrics 无 syncedLyrics 时回退 plainLyrics', () async {
      final _FakeLrclibExecutor executor = _FakeLrclibExecutor(
        <String, List<Object?>>{
          '/get': <Object?>[
            <String, Object?>{
              'trackName': '歌名',
              'artistName': '歌手',
              'albumName': '专辑',
              'duration': 100,
              'plainLyrics': '第一行\n第二行',
            },
          ],
        },
      );
      final LrclibLyricsProvider provider = LrclibLyricsProvider(
        requestExecutor: executor.call,
      );

      final Lyrics lyrics = await provider.getLyrics(
        SongInfo(
          source: Source.lrclib,
          title: '歌名',
          artist: SongArtist(<String>['歌手']),
          album: '专辑',
          durationMs: 100000,
        ),
      );

      expect(lyrics.data['orig']?.length, 2);
      expect(lyrics.data['orig']?.first.words.first.text, '第一行');
      expect(lyrics.types['orig'], LyricsType.plainText);
    });

    test('getLyrics 缺少必要参数时抛异常', () async {
      final LrclibLyricsProvider provider = LrclibLyricsProvider(
        requestExecutor: ({required endpoint, params}) async =>
            <String, Object?>{},
      );

      await expectLater(
        () => provider.getLyrics(
          const SongInfo(source: Source.lrclib, title: '歌名'),
        ),
        throwsA(isA<LddcApiParamsException>()),
      );
    });

    test('getSonglist/getLyricslist 显式 NotSupported', () async {
      final LrclibLyricsProvider provider = LrclibLyricsProvider(
        requestExecutor: ({required endpoint, params}) async =>
            <String, Object?>{},
      );

      await expectLater(
        () => provider.getSonglist(
          const SongListInfo(
            source: Source.lrclib,
            type: SongListType.songlist,
            id: '1',
            title: 'x',
            imgUrl: '',
            songCount: 0,
            publishTimeS: null,
            author: '',
          ),
        ),
        throwsA(isA<LddcApiNotSupportedException>()),
      );
      await expectLater(
        () => provider.getLyricslist(
          const SongInfo(source: Source.lrclib, title: 'x'),
        ),
        throwsA(isA<LddcApiNotSupportedException>()),
      );
    });
  });
}

class _FakeLrclibExecutor {
  _FakeLrclibExecutor(Map<String, List<Object?>> responses)
    : _store = <String, List<Object?>>{
        for (final MapEntry<String, List<Object?>> entry in responses.entries)
          entry.key: List<Object?>.from(entry.value),
      };

  final Map<String, List<Object?>> _store;
  final List<({String endpoint, Map<String, String>? params})> calls =
      <({String endpoint, Map<String, String>? params})>[];

  Future<Object?> call({
    required String endpoint,
    Map<String, String>? params,
  }) async {
    calls.add((
      endpoint: endpoint,
      params: params == null ? null : Map<String, String>.from(params),
    ));

    final List<Object?>? queue = _store[endpoint];
    if (queue == null || queue.isEmpty) {
      throw StateError('未配置测试响应: $endpoint');
    }

    final Object? action = queue.removeAt(0);
    if (action is Exception) {
      throw action;
    }
    return action;
  }
}
