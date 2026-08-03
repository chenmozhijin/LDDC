import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc/src/infra/storage/file_lyrics_save_persistence.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SearchBatchSaveLyricsUseCase', () {
    test('取消后不再启动后续条目', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-search-batch-cancel-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final _FakeLyricsApi api = _FakeLyricsApi();
      final List<SongInfo> songs = <SongInfo>[
        _song(id: '1', title: 'A'),
        _song(id: '2', title: 'B'),
        _song(id: '3', title: 'C'),
      ];
      api.setLyrics('1', _lyricsForSong(songs[0], text: 'A'));
      api.setLyrics('2', _lyricsForSong(songs[1], text: 'B'));
      api.setLyrics('3', _lyricsForSong(songs[2], text: 'C'));
      final SearchBatchSaveCancellationToken token =
          SearchBatchSaveCancellationToken();

      final SearchBatchSaveResult result = await _useCase(api).execute(
        songs: songs,
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.lineByLineLrc,
        saveFolder: dir.path,
        options: _options(skipInst: false),
        cancellationToken: token,
        onProgress: (SearchBatchSaveProgress progress) {
          if (progress.current == 1) {
            token.cancel();
          }
        },
      );

      expect(result.cancelled, isTrue);
      expect(result.entries.length, 1);
      expect(result.savedCount, 1);
      expect(File(p.join(dir.path, 'A.lrc')).existsSync(), isTrue);
      expect(File(p.join(dir.path, 'B.lrc')).existsSync(), isFalse);
      expect(File(p.join(dir.path, 'C.lrc')).existsSync(), isFalse);
    });

    test('单条失败不会中断后续保存', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-search-batch-fail-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo first = _song(id: 'err', title: 'ErrSong');
      final SongInfo second = _song(id: 'ok', title: 'OkSong');
      api.setError('err', const LddcLyricsNotFoundException('没有找到歌词'));
      api.setLyrics('ok', _lyricsForSong(second, text: 'ok'));

      final SearchBatchSaveResult result = await _useCase(api).execute(
        songs: <SongInfo>[first, second],
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.lineByLineLrc,
        saveFolder: dir.path,
        options: _options(skipInst: false),
      );

      expect(result.savedCount, 1);
      expect(result.failedCount, 1);
      expect(
        result.entries.map((SearchBatchSaveEntryResult entry) => entry.status),
        <SearchBatchSaveEntryStatus>[
          SearchBatchSaveEntryStatus.fetchFailed,
          SearchBatchSaveEntryStatus.saved,
        ],
      );
      expect(File(p.join(dir.path, 'OkSong.lrc')).existsSync(), isTrue);
    });

    test('skipInst 开启时会跳过纯音乐', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-search-batch-inst-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final _FakeLyricsApi api = _FakeLyricsApi();
      final SongInfo instrumental = _song(
        id: 'inst',
        title: 'Inst',
        language: Language.instrumental,
      );
      final SongInfo normal = _song(id: 'normal', title: 'Normal');
      api.setLyrics(
        'inst',
        Lyrics.instrumental(songInfo: instrumental, source: Source.qm),
      );
      api.setLyrics('normal', _lyricsForSong(normal, text: 'normal'));

      final SearchBatchSaveResult result = await _useCase(api).execute(
        songs: <SongInfo>[instrumental, normal],
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.lineByLineLrc,
        saveFolder: dir.path,
        options: _options(skipInst: true),
      );

      expect(result.savedCount, 1);
      expect(result.skippedCount, 1);
      expect(
        result.entries.first.status,
        SearchBatchSaveEntryStatus.skippedInstrumental,
      );
      expect(File(p.join(dir.path, 'Normal.lrc')).existsSync(), isTrue);
    });
  });
}

SearchBatchSaveLyricsUseCase _useCase(LyricsClient api) {
  return SearchBatchSaveLyricsUseCase(
    lyricsApi: api,
    persistenceFactory: (String folder) =>
        FileLyricsSavePersistence(folder: folder),
  );
}

SongInfo _song({
  required String id,
  required String title,
  Language? language,
}) {
  return SongInfo(
    source: Source.qm,
    id: id,
    title: title,
    artist: SongArtist(<String>['Singer']),
    language: language,
  );
}

Lyrics _lyricsForSong(SongInfo song, {required String text}) {
  return Lyrics(
    songInfo: song,
    source: song.source,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 1000, text: text)],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}

SearchBatchSaveOptions _options({required bool skipInst}) {
  return SearchBatchSaveOptions(
    fileNameFormat: '%<title>',
    skipInstrumental: skipInst,
    convertOptions: LyricsConvertOptions(),
  );
}

class _FakeLyricsApi implements LyricsClient {
  final Map<String, Object> _resultById = <String, Object>{};

  void setLyrics(String id, Lyrics lyrics) {
    _resultById[id] = lyrics;
  }

  void setError(String id, Object error) {
    _resultById[id] = error;
  }

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    throw UnsupportedError('批量保存测试场景不支持搜索');
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    throw UnsupportedError('批量保存测试场景不支持读取歌单');
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw UnsupportedError('批量保存测试场景不支持候选歌词列表');
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    throw UnsupportedError('批量保存测试场景不支持歌词解析');
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    final SongInfo song = switch (info) {
      SongInfo value => value,
      LyricInfo value => value.songInfo,
      _ => throw ArgumentError.value(info, 'info', '不支持的歌词查询输入'),
    };
    final String key = song.id ?? song.title ?? '';
    final Object? value = _resultById[key];
    if (value == null) {
      throw const LddcLyricsNotFoundException('没有找到歌词');
    }
    if (value is Exception) {
      throw value;
    }
    if (value is Error) {
      throw value;
    }
    return value as Lyrics;
  }
}
