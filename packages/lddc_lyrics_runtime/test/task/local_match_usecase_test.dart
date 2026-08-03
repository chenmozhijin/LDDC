import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LocalMatchGetInfosUseCase', () {
    test('先解析 cue 并排除其引用音频，再解析普通音频', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-getinfos-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String rootDir = p.join(dir.path, 'root');
      await Directory(rootDir).create(recursive: true);

      final String cuePath = p.join(rootDir, 'disc.cue');
      final String cueAudioPath = p.join(rootDir, 'disc.flac');
      final String extraAudioPath = p.join(rootDir, 'extra.mp3');
      final String standaloneAudioPath = p.join(dir.path, 'standalone.mp3');

      await File(cuePath).writeAsString('''
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Cue Track 1"
    PERFORMER "Cue Artist"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Cue Track 2"
    PERFORMER "Cue Artist"
    INDEX 01 01:00:00
''');
      await File(cueAudioPath).writeAsString('cue-audio');
      await File(extraAudioPath).writeAsString('extra-audio');
      await File(standaloneAudioPath).writeAsString('standalone-audio');

      final _FakeLocalMatchMediaGateway gateway = _FakeLocalMatchMediaGateway()
        ..audioInfosByPath[extraAudioPath] = <SongInfo>[
          SongInfo(
            source: Source.local,
            path: extraAudioPath,
            title: 'Extra',
            artist: SongArtist(<String>['Artist']),
          ),
        ]
        ..audioInfosByPath[standaloneAudioPath] = <SongInfo>[
          SongInfo(
            source: Source.local,
            path: standaloneAudioPath,
            title: 'Standalone',
            artist: SongArtist(<String>['Artist']),
          ),
        ]
        ..durationByPath[cueAudioPath] = 180000;
      final LocalMatchGetInfosUseCase useCase = LocalMatchGetInfosUseCase(
        mediaGateway: gateway,
      );
      final List<LocalMatchGetInfosProgress> progressEvents =
          <LocalMatchGetInfosProgress>[];

      final LocalMatchGetInfosResult result = await useCase.run(
        inputPaths: <String>[rootDir, standaloneAudioPath],
        onProgress: progressEvents.add,
      );

      expect(result.cancelled, isFalse);
      expect(result.errors, isEmpty);
      expect(result.entries.length, 4);
      expect(
        result.entries.where(
          (LocalMatchSongEntry entry) => entry.songInfo.fromCue,
        ),
        hasLength(2),
      );
      expect(gateway.audioReadCalls, contains(extraAudioPath));
      expect(gateway.audioReadCalls, contains(standaloneAudioPath));
      expect(gateway.audioReadCalls, isNot(contains(cueAudioPath)));
      expect(progressEvents.first.text, '遍历文件...');
      expect(progressEvents.last.text, isEmpty);
    });

    test('重叠输入去重，并报告不存在的路径', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-deduplicate-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = p.join(dir.path, 'song.mp3');
      await File(songPath).writeAsString('song');
      final LocalMatchGetInfosUseCase useCase = LocalMatchGetInfosUseCase(
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

      final LocalMatchGetInfosResult result = await useCase.run(
        inputPaths: <String>[
          songPath,
          dir.path,
          songPath,
          p.join(dir.path, 'missing.mp3'),
        ],
      );

      expect(result.entries, hasLength(1));
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('不存在或不可访问'));
    });

    test('超过1000个文件时按有界批次交付且可不收集结果列表', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-streaming-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      const int fileCount = 1025;
      // 测试数据只需要可被扫描到，不需要真实音频内容。同步写入可避免
      // 同时创建上千个 Future 干扰本测试要验证的扫描内存边界。
      for (int index = 0; index < fileCount; index += 1) {
        File(
          p.join(dir.path, 'song_$index.mp3'),
        ).writeAsBytesSync(const <int>[0]);
      }
      final List<int> batchSizes = <int>[];
      int deliveredCount = 0;

      final LocalMatchGetInfosResult result =
          await LocalMatchGetInfosUseCase(
            mediaGateway: _FakeLocalMatchMediaGateway(),
          ).run(
            inputPaths: <String>[dir.path],
            collectEntries: false,
            onEntries: (List<LocalMatchSongEntry> entries) {
              batchSizes.add(entries.length);
              deliveredCount += entries.length;
            },
          );

      expect(result.cancelled, isFalse);
      expect(result.entries, isEmpty);
      expect(deliveredCount, fileCount);
      expect(batchSizes.length, greaterThan(1));
      expect(batchSizes.every((int size) => size <= 64), isTrue);
    });

    test('消费首批后取消不会继续交付后续文件', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-stream-cancel-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      for (int index = 0; index < 200; index += 1) {
        File(
          p.join(dir.path, 'song_$index.mp3'),
        ).writeAsBytesSync(const <int>[0]);
      }
      final LocalMatchCancellationToken token = LocalMatchCancellationToken();
      int deliveredCount = 0;

      final LocalMatchGetInfosResult result =
          await LocalMatchGetInfosUseCase(
            mediaGateway: _FakeLocalMatchMediaGateway(),
          ).run(
            inputPaths: <String>[dir.path],
            cancellationToken: token,
            collectEntries: false,
            onEntries: (List<LocalMatchSongEntry> entries) {
              deliveredCount += entries.length;
              token.cancel();
            },
          );

      expect(result.cancelled, isTrue);
      expect(result.entries, isEmpty);
      expect(deliveredCount, 64);
    });
  });

  group('LocalMatchUseCase', () {
    test('成功写入歌词文件并返回 success 状态', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-success-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String songPath = p.join(dir.path, 'demo.mp3');
      await File(songPath).writeAsString('song');
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: songPath,
        title: 'Demo',
        artist: SongArtist(<String>['Singer']),
      );
      final SongInfo remoteSong = SongInfo(
        source: Source.qm,
        id: 'qm-demo',
        title: 'Demo',
        artist: SongArtist(<String>['Singer']),
      );
      final Lyrics lyrics = _buildLyrics(remoteSong);

      final _FakeLocalMatchMediaGateway gateway = _FakeLocalMatchMediaGateway();
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async => AutoFetchResult(
          lyrics: lyrics,
          matchedSongInfo: remoteSong,
          score: 98,
        ),
        mediaGateway: gateway,
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(songInfo: localSong, rootPath: null),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
      );

      final String outputPath = p.join(dir.path, 'demo.lrc');
      expect(result.total, 1);
      expect(result.successCount, 1);
      expect(result.skipCount, 0);
      expect(result.failCount, 0);
      expect(result.cancelled, isFalse);
      expect(result.statuses.single.type, LocalMatchingStatusType.success);
      expect(File(outputPath).existsSync(), isTrue);
      expect(File(outputPath).readAsStringSync(), contains('[00:00.000]'));
    });

    test('skipExistingLyrics 生效时跳过已存在歌词文件', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-skip-existing-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String songPath = p.join(dir.path, 'exists.mp3');
      final String lrcPath = p.join(dir.path, 'exists.lrc');
      await File(songPath).writeAsString('song');
      await File(lrcPath).writeAsString('already');

      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: songPath,
        title: 'Exists',
      );
      int autoFetchCalls = 0;
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) {
          autoFetchCalls += 1;
          throw StateError('不应触发自动匹配');
        },
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(songInfo: localSong, rootPath: null),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: true,
        ),
      );

      expect(autoFetchCalls, 0);
      expect(result.successCount, 0);
      expect(result.skipCount, 1);
      expect(result.failCount, 0);
      expect(result.statuses.single.type, LocalMatchingStatusType.skipExisting);
    });

    test('content:// 已有内嵌歌词且 onlyTag 时跳过自动匹配和写入', () async {
      const String songUri = 'content://media/external/audio/media/1';
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: songUri,
        title: 'SafSong',
      );
      int autoFetchCalls = 0;
      final _FakeLocalMatchMediaGateway gateway = _FakeLocalMatchMediaGateway()
        ..lyricsTagSongPaths.add(songUri);
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          autoFetchCalls += 1;
          throw StateError('已有内嵌歌词时不应自动匹配');
        },
        mediaGateway: gateway,
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(songInfo: localSong, rootPath: null),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyTag,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: true,
        ),
      );

      expect(autoFetchCalls, 0);
      expect(gateway.tagWriteCalls, isEmpty);
      expect(result.successCount, 0);
      expect(result.skipCount, 1);
      expect(result.failCount, 0);
      expect(result.statuses.single.type, LocalMatchingStatusType.skipExisting);
    });

    test('传入 lyricsPersistencePort 时通过端口写入歌词文件', () async {
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: 'content://doc/song.mp3',
        title: 'Persisted',
        artist: SongArtist(<String>['Singer']),
      );
      final SongInfo remoteSong = SongInfo(
        source: Source.qm,
        id: 'qm-persisted',
        title: 'Persisted',
        artist: SongArtist(<String>['Singer']),
      );
      final _FakeLyricsSavePersistence persistence =
          _FakeLyricsSavePersistence();
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async => AutoFetchResult(
          lyrics: _buildLyrics(remoteSong),
          matchedSongInfo: remoteSong,
          score: 99,
        ),
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(
            songInfo: localSong,
            rootPath: 'content://tree/root',
          ),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
        lyricsPersistencePort: persistence,
      );

      expect(result.successCount, 1);
      expect(result.failCount, 0);
      expect(result.statuses.single.path, 'content://tree/root/Persisted.lrc');
      expect(persistence.savedRequests, hasLength(1));
      expect(persistence.savedRequests.single.songInfo.title, 'Persisted');
      expect(persistence.savedTexts.single, contains('[00:00.000]'));
    });

    test('skipExistingLyrics 可复用 lyricsPersistencePort 的 exists 判定', () async {
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: 'content://doc/existing.mp3',
        title: 'Existing',
      );
      int autoFetchCalls = 0;
      final _FakeLyricsSavePersistence persistence =
          _FakeLyricsSavePersistence()..existsResult = true;
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          autoFetchCalls += 1;
          throw StateError('不应触发自动匹配');
        },
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(
            songInfo: localSong,
            rootPath: 'content://tree/root',
          ),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: true,
        ),
        lyricsPersistencePort: persistence,
      );

      expect(autoFetchCalls, 0);
      expect(result.skipCount, 1);
      expect(result.statuses.single.type, LocalMatchingStatusType.skipExisting);
      expect(persistence.existsRequests, hasLength(1));
    });

    test('标签写回失败归类为 saveFail', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-tag-fail-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String songPath = p.join(dir.path, 'tag.mp3');
      await File(songPath).writeAsString('song');
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: songPath,
        title: 'TagSong',
      );
      final SongInfo remoteSong = SongInfo(
        source: Source.qm,
        id: 'qm-tag',
        title: 'TagSong',
      );

      final _FakeLocalMatchMediaGateway gateway = _FakeLocalMatchMediaGateway()
        ..tagWriteErrorByPath[songPath] = LocalMatchTagWriteException(
          'tag write failed',
        );
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async => AutoFetchResult(
          lyrics: _buildLyrics(remoteSong),
          matchedSongInfo: remoteSong,
          score: 90,
        ),
        mediaGateway: gateway,
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(songInfo: localSong, rootPath: null),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyTag,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
      );

      expect(result.successCount, 0);
      expect(result.skipCount, 0);
      expect(result.failCount, 1);
      expect(result.statuses.single.type, LocalMatchingStatusType.saveFail);
    });

    test('标签写回结果未知时停止后续批量任务', () async {
      final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[
        LocalMatchSongEntry(
          songInfo: SongInfo(
            source: Source.local,
            path: r'C:\music\unknown-0.mp3',
            title: 'Unknown 0',
          ),
          rootPath: null,
        ),
        LocalMatchSongEntry(
          songInfo: SongInfo(
            source: Source.local,
            path: r'C:\music\unknown-1.mp3',
            title: 'Unknown 1',
          ),
          rootPath: null,
        ),
      ];
      int autoFetchCalls = 0;
      final _FakeLocalMatchMediaGateway gateway = _FakeLocalMatchMediaGateway()
        ..tagWriteErrorByPath[r'C:\music\unknown-0.mp3'] =
            const LocalMatchTagWriteException(
              'write result unknown',
              writeResultUnknown: true,
            );
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          autoFetchCalls += 1;
          return AutoFetchResult(
            lyrics: _buildLyrics(request.info),
            matchedSongInfo: request.info,
            score: 90,
          );
        },
        mediaGateway: gateway,
      );

      final LocalMatchResult result = await useCase.run(
        entries: entries,
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyTag,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
      );

      expect(autoFetchCalls, 1);
      expect(gateway.tagWriteCalls, <String>[r'C:\music\unknown-0.mp3']);
      expect(result.successCount, 0);
      expect(result.skipCount, 0);
      expect(result.failCount, 2);
      expect(result.cancelled, isTrue);
      expect(result.statuses.single.type, LocalMatchingStatusType.saveFail);
      expect(result.statuses.single.text, '保存到标签结果未知');
    });

    test('onlyTag + aac 路径可走通标签写回链路', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-aac-tag-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String songPath = p.join(dir.path, 'tag.aac');
      await File(songPath).writeAsString('song');
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: songPath,
        title: 'TagAac',
      );
      final SongInfo remoteSong = SongInfo(
        source: Source.qm,
        id: 'qm-aac-tag',
        title: 'TagAac',
      );

      final _FakeLocalMatchMediaGateway gateway = _FakeLocalMatchMediaGateway();
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async => AutoFetchResult(
          lyrics: _buildLyrics(remoteSong),
          matchedSongInfo: remoteSong,
          score: 90,
        ),
        mediaGateway: gateway,
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(songInfo: localSong, rootPath: null),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyTag,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
      );

      expect(result.successCount, 1);
      expect(result.skipCount, 0);
      expect(result.failCount, 0);
      expect(result.statuses.single.type, LocalMatchingStatusType.success);
      expect(gateway.tagWriteCalls, contains(songPath));
      expect(File(p.join(dir.path, 'tag.lrc')).existsSync(), isFalse);
    });

    test('skipInstLyrics=false 时纯音乐可正常保存', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-inst-save-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String songPath = p.join(dir.path, 'inst.mp3');
      await File(songPath).writeAsString('song');
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: songPath,
        title: 'InstSong',
        language: Language.instrumental,
      );
      final SongInfo remoteSong = SongInfo(
        source: Source.qm,
        id: 'qm-inst',
        title: 'InstSong',
        language: Language.instrumental,
      );

      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async => AutoFetchResult(
          lyrics: Lyrics.instrumental(songInfo: remoteSong, source: Source.qm),
          matchedSongInfo: remoteSong,
          score: 88,
        ),
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(songInfo: localSong, rootPath: null),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
          skipInstLyrics: false,
        ),
      );

      final String outputPath = p.join(dir.path, 'inst.lrc');
      expect(result.successCount, 1);
      expect(result.skipCount, 0);
      expect(result.failCount, 0);
      expect(result.statuses.single.type, LocalMatchingStatusType.success);
      expect(File(outputPath).existsSync(), isTrue);
      expect(File(outputPath).readAsStringSync(), contains('纯音乐，请欣赏'));
    });

    test('取消后仅中断后续条目，未处理条目按Python版计入 fail', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-cancel-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[];
      for (int index = 0; index < 3; index += 1) {
        final String songPath = p.join(dir.path, 'cancel-$index.mp3');
        await File(songPath).writeAsString('song-$index');
        entries.add(
          LocalMatchSongEntry(
            songInfo: SongInfo(
              source: Source.local,
              path: songPath,
              title: 'Cancel-$index',
            ),
            rootPath: null,
          ),
        );
      }
      final SongInfo remoteSong = SongInfo(
        source: Source.qm,
        id: 'qm-cancel',
        title: 'Cancel',
      );
      final Lyrics lyrics = _buildLyrics(remoteSong);
      final LocalMatchCancellationToken token = LocalMatchCancellationToken();
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async => AutoFetchResult(
          lyrics: lyrics,
          matchedSongInfo: remoteSong,
          score: 90,
        ),
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

      final LocalMatchResult result = await useCase.run(
        entries: entries,
        cancellationToken: token,
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
        onProgress: (LocalMatchProgress progress) {
          if (progress.value == 1) {
            token.cancel();
          }
        },
      );

      expect(result.cancelled, isTrue);
      expect(result.successCount, 1);
      expect(result.skipCount, 0);
      expect(result.failCount, 2);
    });

    test('autoFetch 迟到结果在取消后不会继续保存文件或写标签', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-match-deep-cancel-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String songPath = p.join(dir.path, 'late.mp3');
      await File(songPath).writeAsString('song');
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: songPath,
        title: 'Late',
      );
      final Completer<AutoFetchResult> completer = Completer<AutoFetchResult>();
      bool requestObservedCancel = false;
      final LocalMatchCancellationToken token = LocalMatchCancellationToken();
      final _FakeLocalMatchMediaGateway gateway = _FakeLocalMatchMediaGateway();
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          await completer.future;
          requestObservedCancel = request.shouldCancel?.call() ?? false;
          return completer.future;
        },
        mediaGateway: gateway,
      );

      final Future<LocalMatchResult> pending = useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(songInfo: localSong, rootPath: null),
        ],
        cancellationToken: token,
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.both,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      completer.complete(
        AutoFetchResult(
          lyrics: _buildLyrics(localSong),
          matchedSongInfo: localSong,
          score: 90,
        ),
      );

      final LocalMatchResult result = await pending;

      expect(requestObservedCancel, isTrue);
      expect(gateway.tagWriteCalls, isEmpty);
      expect(File(p.join(dir.path, 'late.lrc')).existsSync(), isFalse);
      expect(result.cancelled, isTrue);
      expect(result.statuses, isEmpty);
    });

    test('autoFetch 超时归类为 autoFetchFail', () async {
      final SongInfo localSong = SongInfo(
        source: Source.local,
        path: r'C:\music\timeout.mp3',
        title: 'Timeout',
      );
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          throw TimeoutException('超时');
        },
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          LocalMatchSongEntry(songInfo: localSong, rootPath: null),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
      );

      expect(result.failCount, 1);
      expect(
        result.statuses.single.type,
        LocalMatchingStatusType.autoFetchFail,
      );
      expect(result.statuses.single.text, contains('匹配超时'));
    });

    test('跳过检查只访问当前保存模式需要的目标', () async {
      const String songPath = 'content://doc/song.mp3';
      final _FakeLyricsSavePersistence filePersistence =
          _FakeLyricsSavePersistence()..existsResult = true;
      final _FakeLocalMatchMediaGateway onlyFileGateway =
          _FakeLocalMatchMediaGateway();
      final LocalMatchUseCase onlyFileUseCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          throw StateError('已有文件时不应自动匹配');
        },
        mediaGateway: onlyFileGateway,
      );
      final LocalMatchResult onlyFile = await onlyFileUseCase.run(
        entries: <LocalMatchSongEntry>[
          const LocalMatchSongEntry(
            songInfo: SongInfo(
              source: Source.local,
              path: songPath,
              title: 'Song',
            ),
            rootPath: null,
          ),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyFile,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: true,
        ),
        lyricsPersistencePort: filePersistence,
      );

      expect(onlyFile.skipCount, 1);
      expect(onlyFileGateway.hasLyricsTagCallCount, 0);
      expect(filePersistence.existsRequests, hasLength(1));

      final _FakeLyricsSavePersistence tagPersistence =
          _FakeLyricsSavePersistence()..existsResult = true;
      final _FakeLocalMatchMediaGateway onlyTagGateway =
          _FakeLocalMatchMediaGateway()..lyricsTagSongPaths.add(songPath);
      final LocalMatchUseCase onlyTagUseCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          throw StateError('已有标签时不应自动匹配');
        },
        mediaGateway: onlyTagGateway,
      );
      final LocalMatchResult onlyTag = await onlyTagUseCase.run(
        entries: <LocalMatchSongEntry>[
          const LocalMatchSongEntry(
            songInfo: SongInfo(
              source: Source.local,
              path: songPath,
              title: 'Song',
            ),
            rootPath: null,
          ),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyTag,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: true,
        ),
        lyricsPersistencePort: tagPersistence,
      );

      expect(onlyTag.skipCount, 1);
      expect(onlyTagGateway.hasLyricsTagCallCount, 1);
      expect(tagPersistence.existsRequests, isEmpty);
    });

    test('仅标签模式缺少歌曲路径时归类为 saveFail', () async {
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          const SongInfo remote = SongInfo(
            source: Source.qm,
            id: 'remote',
            title: 'Song',
          );
          return AutoFetchResult(
            lyrics: _buildLyrics(remote),
            matchedSongInfo: remote,
            score: 90,
          );
        },
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

      final LocalMatchResult result = await useCase.run(
        entries: <LocalMatchSongEntry>[
          const LocalMatchSongEntry(
            songInfo: SongInfo(source: Source.local, title: 'Song'),
            rootPath: null,
          ),
        ],
        options: LocalMatchRunOptions(
          saveMode: LocalMatchSaveMode.song,
          fileNameMode: LocalMatchFileNameMode.song,
          saveToTagMode: LocalMatchSaveToTagMode.onlyTag,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          langs: <String>['orig'],
          minScore: 55,
          sources: <Source>[Source.qm],
          skipExistingLyrics: false,
        ),
      );

      expect(result.failCount, 1);
      expect(result.statuses.single.type, LocalMatchingStatusType.saveFail);
    });

    test('运行入口冻结条目、语言和来源列表', () async {
      final Completer<void> autoFetchStarted = Completer<void>();
      final Completer<void> autoFetchGate = Completer<void>();
      AutoFetchRequest? capturedRequest;
      final LocalMatchUseCase useCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          capturedRequest = request;
          autoFetchStarted.complete();
          await autoFetchGate.future;
          const SongInfo remote = SongInfo(
            source: Source.qm,
            id: 'remote',
            title: 'Song',
          );
          return AutoFetchResult(
            lyrics: _buildLyrics(remote),
            matchedSongInfo: remote,
            score: 90,
          );
        },
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );
      final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[
        const LocalMatchSongEntry(
          songInfo: SongInfo(
            source: Source.local,
            path: 'song.mp3',
            title: 'Song',
          ),
          rootPath: null,
        ),
      ];
      final List<String> langs = <String>['orig'];
      final List<Source> sources = <Source>[Source.qm];
      final LocalMatchRunOptions options = LocalMatchRunOptions(
        saveMode: LocalMatchSaveMode.song,
        fileNameMode: LocalMatchFileNameMode.song,
        saveToTagMode: LocalMatchSaveToTagMode.onlyTag,
        lyricsFormat: LyricsFormat.lineByLineLrc,
        langs: langs,
        minScore: 55,
        sources: sources,
        skipExistingLyrics: false,
      );

      final Future<LocalMatchResult> pending = useCase.run(
        entries: entries,
        options: options,
      );
      await autoFetchStarted.future;
      entries.clear();
      langs.clear();
      sources.clear();
      autoFetchGate.complete();
      final LocalMatchResult result = await pending;

      expect(result.successCount, 1);
      expect(capturedRequest!.sources, <Source>[Source.qm]);
      expect(options.langs, <String>['orig']);
    });
  });
}

class _FakeLyricsSavePersistence extends LyricsSavePersistencePort
    implements LyricsSaveExistencePort {
  final List<LyricsSaveRequest> savedRequests = <LyricsSaveRequest>[];
  final List<String> savedTexts = <String>[];
  final List<LyricsSaveRequest> existsRequests = <LyricsSaveRequest>[];
  bool existsResult = false;

  @override
  Future<bool> exists({required LyricsSaveRequest request}) async {
    existsRequests.add(request);
    return existsResult;
  }

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    savedRequests.add(request);
    savedTexts.add(String.fromCharCodes(bytes));
    return 'content://tree/root/${request.songInfo.title}${request.lyricsFormat.ext}';
  }
}

class _FakeLocalMatchMediaGateway implements LocalMatchMediaGateway {
  final Map<String, List<SongInfo>> audioInfosByPath =
      <String, List<SongInfo>>{};
  final Map<String, int?> durationByPath = <String, int?>{};
  final Set<String> lyricsTagSongPaths = <String>{};
  final Map<String, Exception> tagWriteErrorByPath = <String, Exception>{};
  final List<String> audioReadCalls = <String>[];
  final List<String> tagWriteCalls = <String>[];
  int hasLyricsTagCallCount = 0;

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async {
    audioReadCalls.add(audioPath);
    final List<SongInfo>? value = audioInfosByPath[audioPath];
    if (value != null) {
      return value;
    }
    return <SongInfo>[
      SongInfo(
        source: Source.local,
        path: audioPath,
        title: p.basenameWithoutExtension(audioPath),
      ),
    ];
  }

  @override
  Future<int?> readAudioDurationMs(String audioPath) async =>
      durationByPath[audioPath];

  @override
  Future<bool> hasLyricsTag(String songPath) async {
    hasLyricsTagCallCount += 1;
    return lyricsTagSongPaths.contains(songPath);
  }

  @override
  Future<String?> readAudioLyricsText({
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    return null;
  }

  @override
  Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    tagWriteCalls.add(songPath);
    final Exception? error = tagWriteErrorByPath[songPath];
    if (error != null) {
      throw error;
    }
  }
}

Lyrics _buildLyrics(SongInfo songInfo) {
  return Lyrics(
    songInfo: songInfo,
    source: songInfo.source,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: const <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: '歌词'),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}
