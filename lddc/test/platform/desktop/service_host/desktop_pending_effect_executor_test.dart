import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../../support/desktop_service_host_exports.dart';
import '../../../support/desktop_service_test_support.dart';

void main() {
  group('DesktopPendingEffectExecutor', () {
    test('会将远端歌词保存为 JSON 并返回后续动作', () async {
      final _FakeLibraryLinkRepository repository =
          _FakeLibraryLinkRepository();
      final _FakeLyricsSavePersistence persistence =
          _FakeLyricsSavePersistence();
      final DesktopPendingEffectExecutor executor =
          DesktopPendingEffectExecutor(
            libraryLinkRepository: repository,
            loadLinkedLyrics: (String lyricsPath) async {
              throw UnimplementedError();
            },
            runAutoFetch: (AutoFetchRequest request) async {
              throw UnimplementedError();
            },
            resolveAutoSaveDirectory: () async => Directory.systemTemp,
            fileSavePersistenceFactory: (String folder) {
              persistence.folder = folder;
              return persistence;
            },
          );

      final DesktopPendingEffectExecutionResult result = await executor
          .executeBatch(
            DesktopPendingEffectBatch(
              instanceId: 1,
              state: _session(instanceId: 1),
              effects: <DesktopSessionEffect>[
                DesktopSaveRemoteLyricsEffect(
                  lyrics: _lyrics(source: Source.qm),
                  suggestedFileName: 'Artist - Song｜QM(1).json',
                  lyricsRevision: 1,
                ),
              ],
            ),
          );

      expect(result.unhandledEffects, isEmpty);
      expect(result.followUps.single, isA<DesktopRemoteLyricsSavedFollowUp>());
      final DesktopRemoteLyricsSavedFollowUp followUp =
          result.followUps.single as DesktopRemoteLyricsSavedFollowUp;
      expect(followUp.lyricsPath, endsWith(r'Artist - Song｜QM(1).json'));
      expect(persistence.request, isNotNull);
      expect(persistence.request!.lyricsFormat, LyricsFormat.json);
      expect(persistence.request!.fileNameFormat, 'Artist - Song｜QM(1)');
      expect(
        jsonDecode(persistence.savedText!)['info']['source'],
        Source.qm.value,
      );
    });

    test('会将关联信息写回仓储', () async {
      final _FakeLibraryLinkRepository repository =
          _FakeLibraryLinkRepository();
      final DesktopPendingEffectExecutor executor =
          DesktopPendingEffectExecutor(
            libraryLinkRepository: repository,
            loadLinkedLyrics: (String lyricsPath) async {
              throw UnimplementedError();
            },
            runAutoFetch: (AutoFetchRequest request) async {
              throw UnimplementedError();
            },
          );
      final SongInfo song = _lyrics(source: Source.local).songInfo;

      final DesktopPendingEffectExecutionResult result = await executor
          .executeBatch(
            DesktopPendingEffectBatch(
              instanceId: 2,
              state: _session(instanceId: 2),
              effects: <DesktopSessionEffect>[
                DesktopPersistLibraryLinkEffect(
                  song: song,
                  lyricsPath: r'D:\lyrics\saved.json',
                  configSnapshot: const <String, Object?>{
                    'langs': <String>['orig', 'ts'],
                    'offset': 120,
                  },
                ),
              ],
            ),
          );

      expect(result.followUps, isEmpty);
      expect(result.unhandledEffects, isEmpty);
      expect(repository.savedSong, song);
      expect(repository.savedLyricsPath, r'D:\lyrics\saved.json');
      expect(repository.savedConfigSnapshot?['offset'], 120);
    });

    test('会查询关联库并返回后续动作', () async {
      final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository()
        ..queryResult = LibraryLinkItem(
          id: 7,
          song: _lyrics(source: Source.local).songInfo,
          key: LibraryLinkKey.fromSong(_lyrics(source: Source.local).songInfo),
          lyricsPath: r'D:\lyrics\linked.lrc',
          configSnapshot: const <String, Object?>{
            'langs': <String>['orig'],
          },
        );
      final DesktopPendingEffectExecutor executor =
          DesktopPendingEffectExecutor(
            libraryLinkRepository: repository,
            loadLinkedLyrics: (String lyricsPath) async {
              throw UnimplementedError();
            },
            runAutoFetch: (AutoFetchRequest request) async {
              throw UnimplementedError();
            },
          );
      final SongInfo song = _lyrics(source: Source.local).songInfo;

      final DesktopPendingEffectExecutionResult result = await executor
          .executeBatch(
            DesktopPendingEffectBatch(
              instanceId: 3,
              state: _session(instanceId: 3),
              effects: <DesktopSessionEffect>[
                DesktopQueryLibraryLinkEffect(song: song, selectionRevision: 1),
              ],
            ),
          );

      expect(result.unhandledEffects, isEmpty);
      final DesktopLibraryLinkResolvedFollowUp followUp =
          result.followUps.single as DesktopLibraryLinkResolvedFollowUp;
      expect(followUp.song, song);
      expect(followUp.libraryLink?.lyricsPath, r'D:\lyrics\linked.lrc');
    });

    test('会加载关联库歌词并返回歌词 follow-up', () async {
      final DesktopPendingEffectExecutor executor =
          DesktopPendingEffectExecutor(
            libraryLinkRepository: _FakeLibraryLinkRepository(),
            loadLinkedLyrics: (String lyricsPath) async {
              expect(lyricsPath, r'D:\lyrics\linked.lrc');
              return _lyrics(source: Source.local);
            },
            runAutoFetch: (AutoFetchRequest request) async {
              throw UnimplementedError();
            },
          );
      final SongInfo song = _lyrics(source: Source.local).songInfo;

      final DesktopPendingEffectExecutionResult result = await executor
          .executeBatch(
            DesktopPendingEffectBatch(
              instanceId: 4,
              state: _session(instanceId: 4),
              effects: <DesktopSessionEffect>[
                DesktopLoadLinkedLyricsEffect(
                  song: song,
                  lyricsPath: r'D:\lyrics\linked.lrc',
                  selectionRevision: 1,
                ),
              ],
            ),
          );

      expect(result.unhandledEffects, isEmpty);
      final DesktopLibraryLinkResolvedFollowUp followUp =
          result.followUps.single as DesktopLibraryLinkResolvedFollowUp;
      expect(followUp.song, song);
      expect(followUp.linkedLyrics?.source, Source.local);
      expect(followUp.lyricsPath, r'D:\lyrics\linked.lrc');
    });

    test('会触发自动搜索并返回结果', () async {
      final DesktopPendingEffectExecutor executor =
          DesktopPendingEffectExecutor(
            libraryLinkRepository: _FakeLibraryLinkRepository(),
            loadLinkedLyrics: (String lyricsPath) async {
              throw UnimplementedError();
            },
            runAutoFetch: (AutoFetchRequest request) async {
              return AutoFetchResult(
                lyrics: _lyrics(source: Source.qm),
                matchedSongInfo: request.info,
                score: 88,
              );
            },
          );
      final SongInfo song = _lyrics(source: Source.local).songInfo;

      final DesktopPendingEffectExecutionResult result = await executor
          .executeBatch(
            DesktopPendingEffectBatch(
              instanceId: 5,
              state: _session(instanceId: 5),
              effects: <DesktopSessionEffect>[
                DesktopStartAutoFetchEffect(
                  request: AutoFetchRequest(info: song),
                  selectionRevision: 1,
                ),
              ],
            ),
          );

      expect(result.unhandledEffects, isEmpty);
      final DesktopAutoFetchResolvedFollowUp followUp =
          result.followUps.single as DesktopAutoFetchResolvedFollowUp;
      expect(followUp.song, song);
      expect(followUp.result?.lyrics.source, Source.qm);
    });

    test('同一实例后发的自动搜索会使先发结果失效', () async {
      final List<Completer<AutoFetchResult>> requests =
          <Completer<AutoFetchResult>>[];
      final DesktopPendingEffectExecutor executor =
          DesktopPendingEffectExecutor(
            libraryLinkRepository: _FakeLibraryLinkRepository(),
            loadLinkedLyrics: (String lyricsPath) async {
              throw UnimplementedError();
            },
            runAutoFetch: (AutoFetchRequest request) {
              final Completer<AutoFetchResult> completer =
                  Completer<AutoFetchResult>();
              requests.add(completer);
              return completer.future;
            },
          );
      final SongInfo song = _lyrics(source: Source.local).songInfo;
      final DesktopPendingEffectBatch batch = DesktopPendingEffectBatch(
        instanceId: 6,
        state: _session(instanceId: 6),
        effects: <DesktopSessionEffect>[
          DesktopStartAutoFetchEffect(
            request: AutoFetchRequest(info: song),
            selectionRevision: 1,
          ),
        ],
      );

      final Future<DesktopPendingEffectExecutionResult> first = executor
          .executeBatch(batch);
      await waitForCondition(() => requests.length == 1);
      final Future<DesktopPendingEffectExecutionResult> second = executor
          .executeBatch(batch);
      await waitForCondition(() => requests.length == 2);

      requests[0].complete(
        AutoFetchResult(
          lyrics: _lyrics(source: Source.qm),
          matchedSongInfo: song,
          score: 80,
        ),
      );
      requests[1].complete(
        AutoFetchResult(
          lyrics: _lyrics(source: Source.kg),
          matchedSongInfo: song,
          score: 90,
        ),
      );

      expect((await first).followUps, isEmpty);
      final DesktopAutoFetchResolvedFollowUp followUp =
          (await second).followUps.single as DesktopAutoFetchResolvedFollowUp;
      expect(followUp.result?.lyrics.source, Source.kg);
    });

    test('clearInstance 和 dispose 都会使首次自动搜索失效', () async {
      for (final bool disposeExecutor in <bool>[false, true]) {
        final Completer<AutoFetchResult> request = Completer<AutoFetchResult>();
        final DesktopPendingEffectExecutor executor =
            DesktopPendingEffectExecutor(
              libraryLinkRepository: _FakeLibraryLinkRepository(),
              loadLinkedLyrics: (String lyricsPath) async {
                throw UnimplementedError();
              },
              runAutoFetch: (AutoFetchRequest autoFetchRequest) =>
                  request.future,
            );
        final SongInfo song = _lyrics(source: Source.local).songInfo;
        final Future<DesktopPendingEffectExecutionResult> pending = executor
            .executeBatch(
              DesktopPendingEffectBatch(
                instanceId: 7,
                state: _session(instanceId: 7),
                effects: <DesktopSessionEffect>[
                  DesktopStartAutoFetchEffect(
                    request: AutoFetchRequest(info: song),
                    selectionRevision: 1,
                  ),
                ],
              ),
            );
        await Future<void>.delayed(Duration.zero);

        if (disposeExecutor) {
          executor.dispose();
        } else {
          executor.clearInstance(7);
        }
        request.complete(
          AutoFetchResult(
            lyrics: _lyrics(source: Source.qm),
            matchedSongInfo: song,
            score: 88,
          ),
        );

        expect(
          (await pending).followUps,
          isEmpty,
          reason: disposeExecutor ? '释放后不应回灌异步结果' : '实例清理后不应回灌异步结果',
        );
      }
    });
  });
}

DesktopSessionState _session({required int instanceId}) {
  return DesktopSessionState.initial().copyWith(
    instanceId: instanceId,
    lyricsRuntime: DesktopLyricsRuntimeState(
      song: _lyrics(source: Source.local).songInfo,
    ),
  );
}

Lyrics _lyrics({required Source source}) {
  return Lyrics(
    songInfo: SongInfo(
      source: Source.local,
      title: 'Song',
      artist: SongArtist(<String>['Artist']),
      album: 'Album',
      durationMs: 180000,
      id: '1',
    ),
    source: source,
    id: '1',
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: 'Hello'),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}

class _FakeLyricsSavePersistence extends LyricsSavePersistencePort {
  LyricsSaveRequest? request;
  String? savedText;
  String folder = '';

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    this.request = request;
    savedText = utf8.decode(bytes);
    return '$folder\\${request.resolvedFileNameFormat}';
  }
}

class _FakeLibraryLinkRepository implements LibraryLinkRepository {
  LibraryLinkItem? queryResult;
  SongInfo? savedSong;
  String? savedLyricsPath;
  Map<String, Object?>? savedConfigSnapshot;

  @override
  Future<void> delAll() async {}

  @override
  Future<void> delItem(int id) async {}

  @override
  Future<void> delItems(Iterable<int> ids) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<int> countItems({String searchText = ''}) async => 0;

  @override
  Future<List<LibraryLinkItem>> getPage({
    required int offset,
    required int limit,
    String searchText = '',
  }) async => const <LibraryLinkItem>[];

  @override
  Future<LibraryLinkItem?> getItem(int id) async => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<LibraryLinkItem?> query(SongInfo song) async => queryResult;

  @override
  Future<LibraryLinkItem> setSong({
    required SongInfo song,
    String? lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) async {
    savedSong = song;
    savedLyricsPath = lyricsPath;
    savedConfigSnapshot = configSnapshot;
    return LibraryLinkItem(
      id: 1,
      song: song,
      key: LibraryLinkKey.fromSong(song),
      lyricsPath: lyricsPath,
      configSnapshot: configSnapshot,
    );
  }

  @override
  Future<void> setSongs(Iterable<LibraryLinkUpsertItem> items) async {}

  @override
  Future<void> replaceAll(Iterable<LibraryLinkUpsertItem> items) async {}

  @override
  Future<void> rewriteItems(Iterable<LibraryLinkRewriteItem> items) async {}

  @override
  Stream<void> watchChanges({bool emitCurrent = false}) async* {
    if (emitCurrent) {
      yield null;
    }
  }
}
