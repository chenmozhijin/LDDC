import 'dart:async';
import 'dart:typed_data';

import 'package:dart_taglib/dart_taglib.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('AndroidSafLocalMatchBatchUseCase', () {
    test('打通扫描到匹配写回全流程并输出阶段进度', () async {
      const String rootUri = 'content://tree/root';
      const String songUri = 'content://doc/song.mp3';
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: songUri,
              displayName: 'song.mp3',
              mimeType: 'audio/mpeg',
              isDirectory: false,
              isFile: true,
            ),
          ],
        },
        bytesByUri: <String, Uint8List>{},
      );
      final _FakeAndroidSafFdPort fdPort = _FakeAndroidSafFdPort(
        openedByUri: <String, AndroidSafOpenedFileDescriptor>{
          songUri: const AndroidSafOpenedFileDescriptor(
            fileDescriptor: 1,
            nameHint: 'song.mp3',
          ),
        },
      );
      final _FakeTaglibBackend backend = _FakeTaglibBackend(
        dataByFd: <int, _FakeAudioData>{
          1: _FakeAudioData(
            tags: const BasicTags(
              title: 'Song',
              artist: 'Singer',
              album: 'Album',
              track: 1,
            ),
            audioProperties: const AudioProperties(
              lengthSeconds: 180,
              bitrateKbps: 320,
              sampleRate: 44100,
              channels: 2,
            ),
            propertyMap: PropertyMap.empty(),
          ),
        },
      );
      final AndroidSafLocalMatchGetInfosUseCase getInfosUseCase =
          AndroidSafLocalMatchGetInfosUseCase(
            treePort: treePort,
            contentPort: const _FakeAndroidSafContentPort(),
            audioMetadataPort: _FakeAndroidSafAudioMetadataPort(
              fdPort: fdPort,
              dataByFd: backend.dataByFd,
            ),
          );
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway();
      final LocalMatchUseCase localMatchUseCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          final SongInfo remoteSong = SongInfo(
            source: Source.qm,
            id: 'qm-song',
            title: request.info.title ?? 'Song',
            artist: request.info.artist,
          );
          return AutoFetchResult(
            lyrics: _buildLyrics(remoteSong),
            matchedSongInfo: remoteSong,
            score: 95,
          );
        },
        mediaGateway: mediaGateway,
      );
      final AndroidSafLocalMatchBatchUseCase useCase =
          AndroidSafLocalMatchBatchUseCase(
            getInfosUseCase: getInfosUseCase,
            localMatchUseCase: localMatchUseCase,
          );
      final List<AndroidSafLocalMatchBatchProgress> progressEvents =
          <AndroidSafLocalMatchBatchProgress>[];

      final AndroidSafLocalMatchBatchResult result = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
        options: _defaultRunOptions(),
        onProgress: progressEvents.add,
      );

      expect(result.cancelled, isFalse);
      expect(result.stage, AndroidSafLocalMatchBatchStage.completed);
      expect(result.total, 1);
      expect(result.successCount, 1);
      expect(result.skipCount, 0);
      expect(result.failCount, 0);
      expect(result.scanErrors, isEmpty);
      expect(result.statuses, hasLength(1));
      expect(result.statuses.single.type, LocalMatchingStatusType.success);
      expect(result.checkpoint, isNull);
      expect(mediaGateway.tagWriteCalls, <String>[songUri]);
      final Set<AndroidSafLocalMatchBatchStage> stages = progressEvents
          .map((AndroidSafLocalMatchBatchProgress progress) => progress.stage)
          .toSet();
      expect(stages.contains(AndroidSafLocalMatchBatchStage.scanning), isTrue);
      expect(stages.contains(AndroidSafLocalMatchBatchStage.matching), isTrue);
      expect(stages.contains(AndroidSafLocalMatchBatchStage.writing), isTrue);
      expect(stages.contains(AndroidSafLocalMatchBatchStage.completed), isTrue);
    });

    test('扫描阶段取消后可通过 checkpoint 恢复并继续匹配', () async {
      const String rootUri = 'content://tree/root';
      final List<AndroidSafTreeEntry> children = <AndroidSafTreeEntry>[];
      final Map<String, AndroidSafOpenedFileDescriptor> openedByUri =
          <String, AndroidSafOpenedFileDescriptor>{};
      final Map<int, _FakeAudioData> dataByFd = <int, _FakeAudioData>{};

      for (int index = 0; index < 3; index += 1) {
        final String uri = 'content://doc/song-$index.mp3';
        final int fd = index + 1;
        children.add(
          AndroidSafTreeEntry(
            uri: uri,
            displayName: 'song-$index.mp3',
            mimeType: 'audio/mpeg',
            isDirectory: false,
            isFile: true,
          ),
        );
        openedByUri[uri] = AndroidSafOpenedFileDescriptor(
          fileDescriptor: fd,
          nameHint: 'song-$index.mp3',
        );
        dataByFd[fd] = _FakeAudioData(
          tags: BasicTags(title: 'Song $index', artist: 'Singer'),
          audioProperties: const AudioProperties(
            lengthSeconds: 180,
            bitrateKbps: 320,
            sampleRate: 44100,
            channels: 2,
          ),
          propertyMap: PropertyMap.empty(),
        );
      }
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{rootUri: children},
        bytesByUri: <String, Uint8List>{},
      );
      final _FakeAndroidSafFdPort fdPort = _FakeAndroidSafFdPort(
        openedByUri: openedByUri,
      );
      final _FakeTaglibBackend backend = _FakeTaglibBackend(dataByFd: dataByFd);
      final AndroidSafLocalMatchGetInfosUseCase getInfosUseCase =
          AndroidSafLocalMatchGetInfosUseCase(
            treePort: treePort,
            contentPort: const _FakeAndroidSafContentPort(),
            audioMetadataPort: _FakeAndroidSafAudioMetadataPort(
              fdPort: fdPort,
              dataByFd: backend.dataByFd,
            ),
          );
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway();
      final LocalMatchUseCase localMatchUseCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          final SongInfo remoteSong = SongInfo(
            source: Source.qm,
            id: 'qm-${request.info.title}',
            title: request.info.title,
            artist: request.info.artist,
          );
          return AutoFetchResult(
            lyrics: _buildLyrics(remoteSong),
            matchedSongInfo: remoteSong,
            score: 88,
          );
        },
        mediaGateway: mediaGateway,
      );
      final AndroidSafLocalMatchBatchUseCase useCase =
          AndroidSafLocalMatchBatchUseCase(
            getInfosUseCase: getInfosUseCase,
            localMatchUseCase: localMatchUseCase,
          );
      final LocalMatchCancellationToken token = LocalMatchCancellationToken();

      final AndroidSafLocalMatchBatchResult first = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
        options: _defaultRunOptions(),
        cancellationToken: token,
        onProgress: (AndroidSafLocalMatchBatchProgress progress) {
          if (progress.stage == AndroidSafLocalMatchBatchStage.scanning &&
              progress.maxValue > 0 &&
              progress.value >= 1) {
            token.cancel();
          }
        },
      );

      expect(first.cancelled, isTrue);
      expect(first.stage, AndroidSafLocalMatchBatchStage.scanning);
      expect(first.checkpoint, isNotNull);
      expect(identical(first.entries, first.checkpoint!.entries), isTrue);
      expect(first.total, greaterThan(0));
      expect(first.total, lessThan(3));
      expect(first.statuses, isEmpty);

      final AndroidSafLocalMatchBatchResult resumed = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
        options: _defaultRunOptions(),
        checkpoint: first.checkpoint,
      );

      expect(resumed.cancelled, isFalse);
      expect(resumed.stage, AndroidSafLocalMatchBatchStage.completed);
      expect(resumed.total, 3);
      expect(resumed.successCount, 3);
      expect(resumed.failCount, 0);
      expect(resumed.statuses, hasLength(3));
    });

    test('匹配阶段取消后可从 checkpoint 继续并保持累计统计', () async {
      const String rootUri = 'content://tree/root';
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{rootUri: const []},
        bytesByUri: <String, Uint8List>{},
      );
      final _FakeAndroidSafFdPort fdPort = _FakeAndroidSafFdPort(
        openedByUri: <String, AndroidSafOpenedFileDescriptor>{},
      );
      final _FakeTaglibBackend backend = _FakeTaglibBackend(
        dataByFd: <int, _FakeAudioData>{},
      );
      final AndroidSafLocalMatchGetInfosUseCase getInfosUseCase =
          AndroidSafLocalMatchGetInfosUseCase(
            treePort: treePort,
            contentPort: const _FakeAndroidSafContentPort(),
            audioMetadataPort: _FakeAndroidSafAudioMetadataPort(
              fdPort: fdPort,
              dataByFd: backend.dataByFd,
            ),
          );
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway();
      final LocalMatchUseCase localMatchUseCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          final SongInfo remoteSong = SongInfo(
            source: Source.qm,
            id: 'qm-${request.info.path}',
            title: request.info.title,
            artist: request.info.artist,
          );
          return AutoFetchResult(
            lyrics: _buildLyrics(remoteSong),
            matchedSongInfo: remoteSong,
            score: 90,
          );
        },
        mediaGateway: mediaGateway,
      );
      final AndroidSafLocalMatchBatchUseCase useCase =
          AndroidSafLocalMatchBatchUseCase(
            getInfosUseCase: getInfosUseCase,
            localMatchUseCase: localMatchUseCase,
          );

      final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[
        for (int index = 0; index < 3; index += 1)
          LocalMatchSongEntry(
            songInfo: SongInfo(
              source: Source.local,
              path: 'content://doc/manual-$index.mp3',
              title: 'Manual-$index',
              artist: SongArtist(<String>['Singer']),
            ),
            rootPath: rootUri,
          ),
      ];
      final AndroidSafLocalMatchBatchCheckpoint checkpoint =
          AndroidSafLocalMatchBatchCheckpoint(
            rootTreeUri: rootUri,
            stage: AndroidSafLocalMatchBatchStage.matching,
            scanCheckpoint: null,
            entries: entries,
            scanErrors: const <String>[],
            nextMatchIndex: 0,
            successCount: 0,
            skipCount: 0,
            statuses: const <LocalMatchingStatus>[],
          );
      final LocalMatchCancellationToken token = LocalMatchCancellationToken();

      final AndroidSafLocalMatchBatchResult first = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
        options: _defaultRunOptions(),
        checkpoint: checkpoint,
        cancellationToken: token,
        onProgress: (AndroidSafLocalMatchBatchProgress progress) {
          if (progress.stage == AndroidSafLocalMatchBatchStage.writing &&
              progress.value == 1) {
            token.cancel();
          }
        },
      );

      expect(first.cancelled, isTrue);
      expect(first.stage, AndroidSafLocalMatchBatchStage.matching);
      expect(first.successCount, 1);
      expect(first.checkpoint, isNotNull);
      expect(first.checkpoint!.nextMatchIndex, 1);
      expect(first.statuses, hasLength(1));
      expect(first.statuses.single.index, 0);

      final AndroidSafLocalMatchBatchResult resumed = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
        options: _defaultRunOptions(),
        checkpoint: first.checkpoint,
      );

      expect(resumed.cancelled, isFalse);
      expect(resumed.stage, AndroidSafLocalMatchBatchStage.completed);
      expect(resumed.total, 3);
      expect(resumed.successCount, 3);
      expect(resumed.skipCount, 0);
      expect(resumed.failCount, 0);
      expect(resumed.statuses, hasLength(3));
      expect(
        resumed.statuses.map((LocalMatchingStatus status) => status.index),
        <int>[0, 1, 2],
      );
    });

    test('当前条目在自动匹配阶段取消时 checkpoint 不会跳过该索引', () async {
      const String rootUri = 'content://tree/root';
      final Completer<void> firstAttemptStarted = Completer<void>();
      final Completer<void> releaseFirstAttempt = Completer<void>();
      int attempts = 0;
      final LocalMatchUseCase localMatchUseCase = LocalMatchUseCase(
        autoFetchExecutor: (AutoFetchRequest request) async {
          attempts += 1;
          if (attempts == 1) {
            firstAttemptStarted.complete();
            await releaseFirstAttempt.future;
            throw const AutoFetchCancelledException();
          }
          final SongInfo remoteSong = SongInfo(
            source: Source.qm,
            id: 'remote',
            title: request.info.title,
          );
          return AutoFetchResult(
            lyrics: _buildLyrics(remoteSong),
            matchedSongInfo: remoteSong,
            score: 90,
          );
        },
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );
      final AndroidSafLocalMatchBatchUseCase useCase =
          AndroidSafLocalMatchBatchUseCase(
            getInfosUseCase: AndroidSafLocalMatchGetInfosUseCase(
              treePort: _FakeAndroidSafTreePort(
                childrenByUri: <String, List<AndroidSafTreeEntry>>{
                  rootUri: const <AndroidSafTreeEntry>[],
                },
                bytesByUri: <String, Uint8List>{},
              ),
              contentPort: const _FakeAndroidSafContentPort(),
              audioMetadataPort: _FakeAndroidSafAudioMetadataPort(
                fdPort: _FakeAndroidSafFdPort(
                  openedByUri: <String, AndroidSafOpenedFileDescriptor>{},
                ),
                dataByFd: <int, _FakeAudioData>{},
              ),
            ),
            localMatchUseCase: localMatchUseCase,
          );
      final AndroidSafLocalMatchBatchCheckpoint checkpoint =
          AndroidSafLocalMatchBatchCheckpoint(
            rootTreeUri: rootUri,
            stage: AndroidSafLocalMatchBatchStage.matching,
            scanCheckpoint: null,
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: const SongInfo(
                  source: Source.local,
                  path: 'content://doc/song.mp3',
                  title: 'Song',
                ),
                rootPath: rootUri,
              ),
            ],
            scanErrors: const <String>[],
            nextMatchIndex: 0,
            successCount: 0,
            skipCount: 0,
            statuses: const <LocalMatchingStatus>[],
          );
      final LocalMatchCancellationToken token = LocalMatchCancellationToken();

      final Future<AndroidSafLocalMatchBatchResult> pending = useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri),
        options: _defaultRunOptions(),
        checkpoint: checkpoint,
        cancellationToken: token,
      );
      await firstAttemptStarted.future;
      token.cancel();
      releaseFirstAttempt.complete();
      final AndroidSafLocalMatchBatchResult cancelled = await pending;

      expect(cancelled.cancelled, isTrue);
      expect(cancelled.checkpoint!.nextMatchIndex, 0);
      expect(cancelled.statuses, isEmpty);

      final AndroidSafLocalMatchBatchResult resumed = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri),
        options: _defaultRunOptions(),
        checkpoint: cancelled.checkpoint,
      );
      expect(resumed.successCount, 1);
      expect(resumed.failCount, 0);
      expect(attempts, 2);
    });
  });
}

LocalMatchRunOptions _defaultRunOptions() {
  return LocalMatchRunOptions(
    saveMode: LocalMatchSaveMode.song,
    fileNameMode: LocalMatchFileNameMode.song,
    saveToTagMode: LocalMatchSaveToTagMode.onlyTag,
    lyricsFormat: LyricsFormat.lineByLineLrc,
    langs: <String>['orig'],
    minScore: 55,
    sources: <Source>[Source.qm],
    skipExistingLyrics: false,
  );
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

class _FakeLocalMatchMediaGateway implements LocalMatchMediaGateway {
  final Set<String> lyricsTagSongPaths = <String>{};
  final List<String> tagWriteCalls = <String>[];

  @override
  Future<bool> hasLyricsTag(String songPath) async =>
      lyricsTagSongPaths.contains(songPath);

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async {
    return <SongInfo>[
      SongInfo(source: Source.local, path: audioPath, title: audioPath),
    ];
  }

  @override
  Future<int?> readAudioDurationMs(String audioPath) async => null;

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
  }
}

class _FakeAndroidSafTreePort implements AndroidSafTreePort {
  _FakeAndroidSafTreePort({
    required this.childrenByUri,
    required this.bytesByUri,
  });

  final Map<String, List<AndroidSafTreeEntry>> childrenByUri;
  final Map<String, Uint8List> bytesByUri;

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    final List<AndroidSafTreeEntry> entries =
        childrenByUri[uri] ?? const <AndroidSafTreeEntry>[];
    final int end = offset + limit < entries.length
        ? offset + limit
        : entries.length;
    return AndroidSafTreePage(
      entries: offset >= entries.length
          ? const <AndroidSafTreeEntry>[]
          : entries.sublist(offset, end),
      nextOffset: end < entries.length ? end : null,
    );
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() async {
    return const <AndroidSafPersistedTree>[];
  }

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) {
    throw UnimplementedError();
  }

  @override
  Future<void> persistTreePermission(String uri) async {}

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    return AndroidSafWriteDocumentResult(
      uri: '$treeUri/$displayName',
      displayName: displayName,
    );
  }
}

class _FakeAndroidSafFdPort implements AndroidSafFdPort {
  _FakeAndroidSafFdPort({required this.openedByUri});

  final Map<String, AndroidSafOpenedFileDescriptor> openedByUri;
  final List<int> closedFds = <int>[];

  @override
  Future<void> closeFd(int fileDescriptor) async {
    closedFds.add(fileDescriptor);
  }

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadOnlyFd(String uri) async {
    final AndroidSafOpenedFileDescriptor? opened = openedByUri[uri];
    if (opened == null) {
      throw StateError('missing fd for $uri');
    }
    return opened;
  }

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadWriteFd(String uri) {
    throw UnimplementedError();
  }
}

class _FakeAndroidSafContentPort implements AndroidSafContentPort {
  const _FakeAndroidSafContentPort();

  @override
  Future<Uint8List> readBytes(String uri, {int? maxBytes}) {
    throw UnimplementedError();
  }
}

class _FakeAndroidSafAudioMetadataPort implements AndroidSafAudioMetadataPort {
  const _FakeAndroidSafAudioMetadataPort({
    required this.fdPort,
    required this.dataByFd,
  });

  final _FakeAndroidSafFdPort fdPort;
  final Map<int, _FakeAudioData> dataByFd;

  @override
  Future<AndroidSafAudioMetadata> readMetadata({
    required String uri,
    required String? nameHint,
  }) async {
    final AndroidSafOpenedFileDescriptor opened = await fdPort.openReadOnlyFd(
      uri,
    );
    try {
      final _FakeAudioData? data = dataByFd[opened.fileDescriptor];
      if (data == null) {
        throw StateError(
          'missing fake audio data for fd=${opened.fileDescriptor}',
        );
      }
      return AndroidSafAudioMetadata(
        nameHint: opened.nameHint ?? nameHint ?? uri,
        title: data.tags.title,
        artist: data.tags.artist,
        album: data.tags.album,
        durationMs: data.audioProperties == null
            ? null
            : data.audioProperties!.lengthSeconds * 1000,
        trackNumber: data.tags.track <= 0 ? null : data.tags.track,
        cuesheet: _readCuesheet(data.propertyMap),
      );
    } finally {
      await fdPort.closeFd(opened.fileDescriptor);
    }
  }

  String? _readCuesheet(PropertyMap propertyMap) {
    for (final PropertyItem item in propertyMap.items) {
      if (item.key.toLowerCase() != 'cuesheet') {
        continue;
      }
      for (final String value in item.values) {
        if (value.trim().isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }
}

class _FakeTaglibBackend {
  _FakeTaglibBackend({required this.dataByFd});

  final Map<int, _FakeAudioData> dataByFd;
}

class _FakeAudioData {
  const _FakeAudioData({
    required this.tags,
    required this.audioProperties,
    required this.propertyMap,
  });

  final BasicTags tags;
  final AudioProperties? audioProperties;
  final PropertyMap propertyMap;
}
