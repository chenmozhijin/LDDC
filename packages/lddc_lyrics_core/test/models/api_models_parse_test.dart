import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('API 模型序列化', () {
    test('SongInfo toMap/fromMap 兼容 imgurl 字段', () {
      const SongInfo info = SongInfo(
        source: Source.qm,
        id: 'song-1',
        title: 'Demo',
        imgUrl: 'https://img.example/song-1.jpg',
      );

      final SongInfo decoded = SongInfo.fromMap(info.toMap());
      expect(decoded, info);
      expect(decoded.toMap()['imgurl'], 'https://img.example/song-1.jpg');
    });

    test('SongListInfo toMap/fromMap 兼容', () {
      const SongListInfo info = SongListInfo(
        source: Source.qm,
        type: SongListType.album,
        id: '100',
        title: 'Album',
        imgUrl: 'https://example.com/a.jpg',
        songCount: 12,
        publishTimeS: 1710000000,
        author: 'Artist',
        mid: 'mid-1',
      );

      final SongListInfo decoded = SongListInfo.fromMap(info.toMap());
      expect(decoded, info);
      expect(decoded.formattedPublishTime, isNotEmpty);
    });

    test('LyricInfo 在无 songinfo 字段时可从 SongInfo 字段回退构建', () {
      final Map<String, Object?> raw = <String, Object?>{
        'source': 'Local',
        'title': 'Song',
        'artist': <String>['A'],
        'id': 'lyric-id',
        'accesskey': 'ak',
        'duration': 3000,
        'creator': 'tester',
        'score': 88,
        'path': 'file://C:/demo.lrc',
        'data': <int>[1, 2, 3],
        'cached': true,
      };

      final LyricInfo decoded = LyricInfo.fromMap(raw);
      expect(decoded.source, Source.local);
      expect(decoded.songInfo.title, 'Song');
      expect(decoded.id, 'lyric-id');
      expect(decoded.accessKey, 'ak');
      expect(decoded.path, 'C:/demo.lrc');
      expect(decoded.data, Uint8List.fromList(<int>[1, 2, 3]));
      expect(decoded.cached, isTrue);
    });

    test('LyricInfo data 不暴露内部可变缓存', () {
      final Uint8List rawData = Uint8List.fromList(<int>[1, 2, 3]);
      final LyricInfo info = LyricInfo(
        songInfo: const SongInfo(source: Source.local, title: 'Song'),
        source: Source.local,
        data: rawData,
      );

      rawData[0] = 9;
      final Uint8List getterData = info.data!;
      getterData[1] = 8;
      final Uint8List mapData = info.toMap()['data']! as Uint8List;
      mapData[2] = 7;

      expect(info.data, Uint8List.fromList(<int>[1, 2, 3]));
    });

    test('LyricInfo 拒绝非字节整数而不是静默补零', () {
      expect(
        () => LyricInfo.fromMap(<String, Object?>{
          'source': Source.local,
          'title': 'Song',
          'data': <Object?>[1, 'bad', 3],
        }),
        throwsArgumentError,
      );
      expect(
        () => LyricInfo.fromMap(<String, Object?>{
          'source': Source.local,
          'title': 'Song',
          'data': <int>[0, 256],
        }),
        throwsArgumentError,
      );
    });

    test('LyricInfo 字符串 data 按 UTF-8 转换', () {
      final LyricInfo info = LyricInfo.fromMap(<String, Object?>{
        'source': Source.local,
        'title': 'Song',
        'data': '你好',
      });

      expect(
        info.data,
        Uint8List.fromList(<int>[228, 189, 160, 229, 165, 189]),
      );
    });

    test('nullable copyWith 字段支持显式清空', () {
      const SongInfo song = SongInfo(
        source: Source.local,
        title: 'Song',
        path: 'C:/demo.mp3',
      );
      final LyricInfo lyric = LyricInfo(
        songInfo: song,
        source: Source.local,
        accessKey: 'key',
        data: Uint8List.fromList(<int>[1]),
      );
      final Lyrics lyrics = Lyrics(
        songInfo: song,
        source: Source.local,
        accessKey: 'key',
      );
      final SearchInfo search = SearchInfo(
        source: Source.qm,
        keyword: 'Song',
        searchType: SearchType.song,
        page: 2,
      );

      expect(song.copyWith(path: null).path, isNull);
      expect(lyric.copyWith(data: null).data, isNull);
      expect(lyrics.copyWith(accessKey: null).accessKey, isNull);
      expect(search.copyWith(page: null).page, isNull);
    });

    test('SearchInfo 支持单源与多源输入', () {
      final SearchInfo multi = SearchInfo.fromMap(<String, Object?>{
        'source': <String>['QM', 'NE'],
        'keyword': 'abc',
        'search_type': 'SONG',
        'page': 2,
      });
      expect(multi.isMultiSource, isTrue);
      expect(multi.sources, <Source>[Source.qm, Source.ne]);

      final SearchInfo single = SearchInfo.fromMap(<String, Object?>{
        'source': 'KG',
        'keyword': 'abc',
        'search_type': 'ALBUM',
        'page': 1,
      });
      expect(single.isMultiSource, isFalse);
      expect(single.sources, <Source>[Source.kg]);
      expect(single.searchType, SearchType.album);
    });
  });
}
