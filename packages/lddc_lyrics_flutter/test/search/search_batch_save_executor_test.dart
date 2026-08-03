import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_flutter/src/search/search_batch_save_executor.dart';
import 'package:test/test.dart';

void main() {
  group('SearchBatchSaveExecutor', () {
    test('文件系统与 Android SAF 后端共享相同批量保存语义', () async {
      final List<SongInfo> songs = <SongInfo>[
        _song(id: 'ok', title: 'OkSong'),
        _song(id: 'inst', title: 'InstSong', language: Language.instrumental),
        _song(id: 'missing', title: 'MissingSong'),
        _song(id: 'save-fail', title: 'SaveFailSong'),
      ];

      final List<_FakeLyricsSavePersistence> ports =
          <_FakeLyricsSavePersistence>[
            _FakeLyricsSavePersistence(
              prefix: 'fs',
              failIds: <String>{'save-fail'},
            ),
            _FakeLyricsSavePersistence(
              prefix: 'saf',
              failIds: <String>{'save-fail'},
            ),
          ];
      final List<SearchBatchSaveResult> results = <SearchBatchSaveResult>[];

      for (final _FakeLyricsSavePersistence port in ports) {
        final _FakeLyricsApi api = _FakeLyricsApi()
          ..setLyrics('ok', _lyricsForSong(songs[0], text: 'ok'))
          ..setLyrics(
            'inst',
            Lyrics.instrumental(songInfo: songs[1], source: Source.qm),
          )
          ..setError('missing', const LddcLyricsNotFoundException('没有找到歌词'))
          ..setLyrics('save-fail', _lyricsForSong(songs[3], text: 'fail'));

        final SearchBatchSaveResult result =
            await SearchBatchSaveExecutor(
              lyricsApi: api,
              persistencePort: port,
            ).execute(
              songs: songs,
              langs: const <String>['orig'],
              lyricsFormat: LyricsFormat.lineByLineLrc,
              options: _options(skipInst: true),
            );
        results.add(result);

        expect(port.savedSongIds, <String>['ok']);
        expect(port.savedPaths.single, '${port.prefix}/OkSong.lrc');
      }

      for (final SearchBatchSaveResult result in results) {
        expect(result.total, 4);
        expect(result.savedCount, 1);
        expect(result.skippedCount, 1);
        expect(result.failedCount, 2);
        expect(result.cancelled, isFalse);
        expect(
          result.entries
              .map((SearchBatchSaveEntryResult entry) => entry.status)
              .toList(growable: false),
          <SearchBatchSaveEntryStatus>[
            SearchBatchSaveEntryStatus.saved,
            SearchBatchSaveEntryStatus.skippedInstrumental,
            SearchBatchSaveEntryStatus.fetchFailed,
            SearchBatchSaveEntryStatus.saveFailed,
          ],
        );
      }
    });

    test('文件系统与 Android SAF 后端取消后都只中断后续条目', () async {
      final List<SongInfo> songs = <SongInfo>[
        _song(id: '1', title: 'A'),
        _song(id: '2', title: 'B'),
        _song(id: '3', title: 'C'),
      ];

      for (final _FakeLyricsSavePersistence port
          in <_FakeLyricsSavePersistence>[
            _FakeLyricsSavePersistence(prefix: 'fs'),
            _FakeLyricsSavePersistence(prefix: 'saf'),
          ]) {
        final _FakeLyricsApi api = _FakeLyricsApi()
          ..setLyrics('1', _lyricsForSong(songs[0], text: 'A'))
          ..setLyrics('2', _lyricsForSong(songs[1], text: 'B'))
          ..setLyrics('3', _lyricsForSong(songs[2], text: 'C'));
        final SearchBatchSaveCancellationToken token =
            SearchBatchSaveCancellationToken();

        final SearchBatchSaveResult result =
            await SearchBatchSaveExecutor(
              lyricsApi: api,
              persistencePort: port,
            ).execute(
              songs: songs,
              langs: const <String>['orig'],
              lyricsFormat: LyricsFormat.lineByLineLrc,
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
        expect(
          result.entries
              .map((SearchBatchSaveEntryResult entry) => entry.status)
              .toList(growable: false),
          <SearchBatchSaveEntryStatus>[SearchBatchSaveEntryStatus.saved],
        );
        expect(api.requestedSongIds, <String>['1']);
        expect(port.savedSongIds, <String>['1']);
      }
    });

    test('取消发生在保存写入期间时，完成当前写入后不启动下一首', () async {
      final List<SongInfo> songs = <SongInfo>[
        _song(id: '1', title: 'A'),
        _song(id: '2', title: 'B'),
      ];
      final _FakeLyricsApi api = _FakeLyricsApi()
        ..setLyrics('1', _lyricsForSong(songs[0], text: 'A'))
        ..setLyrics('2', _lyricsForSong(songs[1], text: 'B'));
      final Completer<void> saveBarrier = Completer<void>();
      final Completer<void> saveStarted = Completer<void>();
      final _FakeLyricsSavePersistence port = _FakeLyricsSavePersistence(
        prefix: 'fs',
        saveBarrier: saveBarrier,
        onSaveStarted: (String id) {
          if (id == '1' && !saveStarted.isCompleted) {
            saveStarted.complete();
          }
        },
      );
      final SearchBatchSaveCancellationToken token =
          SearchBatchSaveCancellationToken();

      final Future<SearchBatchSaveResult> pending =
          SearchBatchSaveExecutor(
            lyricsApi: api,
            persistencePort: port,
          ).execute(
            songs: songs,
            langs: const <String>['orig'],
            lyricsFormat: LyricsFormat.lineByLineLrc,
            options: _options(skipInst: false),
            cancellationToken: token,
          );
      await saveStarted.future;
      token.cancel();
      saveBarrier.complete();
      final SearchBatchSaveResult result = await pending;

      expect(result.cancelled, isTrue);
      expect(result.savedCount, 1);
      expect(api.requestedSongIds, <String>['1']);
      expect(port.savedSongIds, <String>['1']);
    });
  });
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
  final List<String> requestedSongIds = <String>[];

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
    throw UnsupportedError('批量保存 executor 测试场景不支持搜索');
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    throw UnsupportedError('批量保存 executor 测试场景不支持读取歌单');
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw UnsupportedError('批量保存 executor 测试场景不支持候选歌词列表');
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    throw UnsupportedError('批量保存 executor 测试场景不支持歌词解析');
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    final SongInfo song = switch (info) {
      SongInfo value => value,
      LyricInfo value => value.songInfo,
      _ => throw ArgumentError.value(info, 'info', '不支持的歌词查询输入'),
    };
    final String key = song.id ?? song.title ?? '';
    requestedSongIds.add(key);
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

class _FakeLyricsSavePersistence extends LyricsSavePersistencePort {
  _FakeLyricsSavePersistence({
    required this.prefix,
    Set<String>? failIds,
    this.saveBarrier,
    this.onSaveStarted,
  }) : _failIds = failIds ?? <String>{};

  final String prefix;
  final Set<String> _failIds;
  final Completer<void>? saveBarrier;
  final void Function(String id)? onSaveStarted;
  final List<String> savedSongIds = <String>[];
  final List<String> savedPaths = <String>[];

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    final String songId = request.songInfo.id ?? '';
    onSaveStarted?.call(songId);
    final Completer<void>? barrier = saveBarrier;
    if (barrier != null) {
      await barrier.future;
    }
    if (_failIds.contains(songId)) {
      throw const FileSystemException('保存失败');
    }
    savedSongIds.add(songId);
    final String path =
        '$prefix/${request.songInfo.title}${request.lyricsFormat.ext}';
    savedPaths.add(path);
    return path;
  }
}
