import 'dart:io';
import 'dart:typed_data';

import 'package:dart_taglib/dart_taglib.dart' hide TaglibBackend;
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('AudioTagLyricsPayload', () {
    test('构造后防御性复制 syncedTracks 与 entries', () {
      final List<AudioTagSyncedEntry> entries = <AudioTagSyncedEntry>[
        const AudioTagSyncedEntry(timeMs: 0, text: 'a'),
      ];
      final AudioTagSyncedTrack track = AudioTagSyncedTrack(
        language: 'eng',
        description: 'LYRICS',
        entries: entries,
      );
      final List<AudioTagSyncedTrack> tracks = <AudioTagSyncedTrack>[track];
      final AudioTagLyricsPayload payload = AudioTagLyricsPayload(
        plainText: null,
        syncedTracks: tracks,
      );

      entries.add(const AudioTagSyncedEntry(timeMs: 100, text: 'b'));
      tracks.clear();

      expect(payload.syncedTracks, hasLength(1));
      expect(payload.syncedTracks.single.entries, hasLength(1));
      expect(payload.hasLyrics, isTrue);
      expect(
        () => payload.syncedTracks.add(
          AudioTagSyncedTrack(
            language: 'jpn',
            description: 'LYRICS',
            entries: const <AudioTagSyncedEntry>[],
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => payload.syncedTracks.single.entries.add(
          const AudioTagSyncedEntry(timeMs: 200, text: 'c'),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('DartTaglibAudioTagPort', () {
    test('readMeta 优先使用 path 会话，不走 bytes 会话', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-read-path-first-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.mp3';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackend backend = _FakeTaglibBackend(
        _FakeTaglibBackendSession(),
      );
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: backend,
      );

      port.readMeta(songPath);
      expect(backend.openPathCallCount, 1);
      expect(backend.openBytesCallCount, 0);
    });

    test('readMeta 在 path 不支持时回退 bytes 会话', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-read-path-fallback-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.mp3';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackend backend = _FakeTaglibBackend(
        _FakeTaglibBackendSession(),
      )..openPathError = UnsupportedError('path unsupported');
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: backend,
      );

      port.readMeta(songPath);
      expect(backend.openPathCallCount, 1);
      expect(backend.openBytesCallCount, 1);
    });

    test('hasLyrics 在 plain 为空时可回退到 SYLT', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-has-lyrics-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.mp3';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession()
        ..plainLyrics = null
        ..syncedLyrics = <SyncedLyricsTrack>[
          SyncedLyricsTrack(
            language: 'eng',
            description: 'LYRICS',
            entries: <SyncedLyricsEntry>[SyncedLyricsEntry(time: 0, text: 'a')],
          ),
        ];
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: _FakeTaglibBackend(session),
      );

      expect(port.hasLyrics(songPath), isTrue);
    });

    test('readLyrics 在 plain 存在时优先 plain 且不读取 SYLT', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-read-priority-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.mp3';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession()
        ..plainLyrics = 'plain-first'
        ..readSyncedLyricsError = StateError('should not read synced');
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: _FakeTaglibBackend(session),
      );

      final AudioTagLyricsPayload payload = port.readLyrics(songPath);
      expect(payload.plainText, 'plain-first');
      expect(payload.syncedTracks, isEmpty);
      expect(session.readSyncedLyricsCallCount, 0);
    });

    test('readLyrics 在 plain 为空且 SYLT 不支持时返回空结果', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-read-sylt-unsupported-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.flac';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession()
        ..plainLyrics = null
        ..readSyncedLyricsError = _UnsupportedReadError();
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: _FakeTaglibBackend(session),
      );

      final AudioTagLyricsPayload payload = port.readLyrics(songPath);
      expect(payload.plainText, isNull);
      expect(payload.syncedTracks, isEmpty);
      expect(session.readSyncedLyricsCallCount, 1);
    });

    test('readLyrics 在 plain 为空时可回退拼接 SYLT 文本', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-read-sylt-fallback-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.mp3';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession()
        ..plainLyrics = null
        ..syncedLyrics = <SyncedLyricsTrack>[
          SyncedLyricsTrack(
            language: 'eng',
            description: 'LYRICS',
            entries: <SyncedLyricsEntry>[
              SyncedLyricsEntry(time: 0, text: '甲'),
              SyncedLyricsEntry(time: 100, text: '乙'),
            ],
          ),
        ];
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: _FakeTaglibBackend(session),
      );

      final AudioTagLyricsPayload payload = port.readLyrics(songPath);
      expect(payload.plainText, '甲乙');
      expect(payload.syncedTracks, hasLength(1));
      expect(session.readSyncedLyricsCallCount, 1);
    });

    test('writeLyrics 在 mp3 写入时按配置写入 USLT/SYLT', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-write-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.mp3';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackendSession writeSession = _FakeTaglibBackendSession()
        ..tags = const BasicTags(
          title: 'title',
          artist: 'artist',
          album: 'album',
          comment: 'comment',
          genre: 'pop',
          year: 2024,
          track: 7,
        );
      final _FakeTaglibBackend backend = _FakeTaglibBackend(writeSession);
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: backend,
      );

      port.writeLyrics(
        AudioTagWriteRequest(
          songPath: songPath,
          plainLyricsText: '[00:00.000]歌词',
          lyrics: _buildTimedLyrics(songPath),
          id3Version: Id3Version.v23,
        ),
      );

      expect(writeSession.lastWriteLyricsText, '[00:00.000]歌词');
      expect(writeSession.lastWriteLyricsVersion, Id3v2Version.v23);
      expect(writeSession.savedMp3Version, Id3v2Version.v23);
      expect(writeSession.lastWriteSyncedTracks, isNotNull);
      expect(writeSession.lastWriteSyncedTracks!, hasLength(1));
      expect(
        writeSession.lastWriteSyncedTracks!.first.entries.map((e) => e.text),
        orderedEquals(<String>['第一行', '\n第二行']),
      );
      expect(backend.openPathCallCount, 1);
      expect(backend.openBytesCallCount, 0);
      expect(File(songPath).readAsBytesSync(), <int>[1, 2, 3]);
    });

    test('writeLyrics 在 aac 上不因扩展名门禁被拦截', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-write-aac-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.aac';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession()
        ..capabilities = _aacCapabilities
        ..exportedBytes = Uint8List.fromList(<int>[4, 5, 6]);
      final _FakeTaglibBackend backend = _FakeTaglibBackend(session);
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: backend,
      );

      port.writeLyrics(
        AudioTagWriteRequest(
          songPath: songPath,
          plainLyricsText: 'aac lyrics',
          lyrics: _buildTimedLyrics(songPath),
          id3Version: Id3Version.v24,
        ),
      );

      expect(session.lastWriteLyricsText, 'aac lyrics');
      expect(session.savedMp3Version, isNull);
      expect(backend.openPathCallCount, 1);
      expect(backend.openBytesCallCount, 0);
      expect(File(songPath).readAsBytesSync(), <int>[1, 2, 3]);
    });

    test('writeLyrics 在提供 fd 时优先使用 fd 会话', () {
      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession()
        ..tags = const BasicTags(
          title: 'title',
          artist: 'artist',
          album: 'album',
          comment: 'comment',
          genre: 'pop',
          year: 2024,
          track: 7,
        );
      final _FakeTaglibBackend backend = _FakeTaglibBackend(session);
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: backend,
      );

      port.writeLyrics(
        AudioTagWriteRequest(
          songPath: 'content://media/external/audio/media/1',
          plainLyricsText: 'lyrics',
          lyrics: _buildTimedLyrics(r'D:\song.mp3'),
          id3Version: Id3Version.v24,
          fileDescriptor: 100,
          fileDescriptorNameHint: 'demo.mp3',
        ),
      );

      expect(backend.openFileDescriptorCallCount, 1);
      expect(backend.lastOpenFileDescriptor, 100);
      expect(backend.lastOpenFileDescriptorNameHint, 'demo.mp3');
      expect(backend.openPathCallCount, 0);
      expect(backend.openBytesCallCount, 0);
    });

    test('writeLyrics 在 path 不支持时回退 bytes 覆盖写入', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-write-bytes-fallback-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.mp3';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession()
        ..tags = const BasicTags(
          title: 'title',
          artist: 'artist',
          album: 'album',
          comment: 'comment',
          genre: 'pop',
          year: 2024,
          track: 7,
        )
        ..exportedBytes = Uint8List.fromList(<int>[9, 8, 7]);
      final _FakeTaglibBackend backend = _FakeTaglibBackend(session)
        ..openPathError = UnsupportedError('path unsupported');
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: backend,
      );

      port.writeLyrics(
        AudioTagWriteRequest(
          songPath: songPath,
          plainLyricsText: 'lyrics',
          lyrics: _buildTimedLyrics(songPath),
          id3Version: Id3Version.v24,
        ),
      );

      expect(backend.openPathCallCount, 1);
      expect(backend.openBytesCallCount, 2);
      expect(File(songPath).readAsBytesSync(), <int>[9, 8, 7]);
    });

    test('writeLyrics 回读校验发现非歌词字段变化时返回 writeFailed', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-verify-fail-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.mp3';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final _FakeTaglibBackendSession writeSession = _FakeTaglibBackendSession()
        ..tags = const BasicTags(
          title: 'before-title',
          artist: 'artist',
          album: 'album',
          comment: 'comment',
          genre: 'pop',
          year: 2024,
          track: 1,
        )
        ..readBasicTagsSequence = <BasicTags>[
          const BasicTags(
            title: 'before-title',
            artist: 'artist',
            album: 'album',
            comment: 'comment',
            genre: 'pop',
            year: 2024,
            track: 1,
          ),
          const BasicTags(
            title: 'after-title',
            artist: 'artist',
            album: 'album',
            comment: 'comment',
            genre: 'pop',
            year: 2024,
            track: 1,
          ),
        ]
        ..plainLyrics = 'lyrics';
      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: _FakeTaglibBackend(writeSession),
      );

      expect(
        () => port.writeLyrics(
          AudioTagWriteRequest(
            songPath: songPath,
            plainLyricsText: 'lyrics',
            lyrics: _buildTimedLyrics(songPath),
            id3Version: Id3Version.v24,
          ),
        ),
        throwsA(
          isA<AudioTagException>().having(
            (AudioTagException error) => error.code,
            'code',
            AudioTagErrorCode.writeFailed,
          ),
        ),
      );
    });

    test('writeLyrics 在不支持格式上返回 frameUnsupported', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-tag-port-unsupported-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String songPath = '${dir.path}\\demo.wav';
      await File(songPath).writeAsBytes(<int>[1, 2, 3]);

      final DartTaglibAudioTagPort port = DartTaglibAudioTagPort(
        backend: _FakeTaglibBackend(
          _FakeTaglibBackendSession()
            ..capabilities = SessionCapabilities.unknown
            ..writeLyricsError = _UnsupportedWriteError(),
        ),
      );

      expect(
        () => port.writeLyrics(
          AudioTagWriteRequest(
            songPath: songPath,
            plainLyricsText: 'lyrics',
            lyrics: _buildTimedLyrics(songPath),
            id3Version: Id3Version.v24,
          ),
        ),
        throwsA(
          isA<AudioTagException>().having(
            (AudioTagException error) => error.code,
            'code',
            AudioTagErrorCode.frameUnsupported,
          ),
        ),
      );
    });
  });
}

class _FakeTaglibBackend implements TaglibBackend {
  _FakeTaglibBackend(_FakeTaglibBackendSession session)
    : _sessions = <_FakeTaglibBackendSession>[session];

  final List<_FakeTaglibBackendSession> _sessions;
  int _successfulOpenCount = 0;
  int openCallCount = 0;
  int openBytesCallCount = 0;
  int openPathCallCount = 0;
  int openFileDescriptorCallCount = 0;
  Object? openBytesError;
  Object? openPathError;
  Object? openFileDescriptorError;
  String? lastOpenPath;
  int? lastOpenFileDescriptor;
  String? lastOpenFileDescriptorNameHint;

  @override
  TaglibBackendSession openSession(Uint8List bytes, {String? nameHint}) {
    openCallCount += 1;
    openBytesCallCount += 1;
    final Object? error = openBytesError;
    if (error != null) {
      throw error;
    }
    return _takeSession();
  }

  @override
  TaglibBackendSession openSessionFromPath(String path) {
    openPathCallCount += 1;
    lastOpenPath = path;
    final Object? error = openPathError;
    if (error != null) {
      throw error;
    }
    return _takeSession();
  }

  @override
  TaglibBackendSession openSessionFromFileDescriptor(
    int fileDescriptor, {
    String? nameHint,
  }) {
    openFileDescriptorCallCount += 1;
    lastOpenFileDescriptor = fileDescriptor;
    lastOpenFileDescriptorNameHint = nameHint;
    final Object? error = openFileDescriptorError;
    if (error != null) {
      throw error;
    }
    return _takeSession();
  }

  _FakeTaglibBackendSession _takeSession() {
    if (_sessions.isEmpty) {
      throw StateError('至少需要一个 fake session');
    }
    final int index = _successfulOpenCount < _sessions.length
        ? _successfulOpenCount
        : _sessions.length - 1;
    _successfulOpenCount += 1;
    return _sessions[index];
  }
}

class _FakeTaglibBackendSession implements TaglibBackendSession {
  BasicTags tags = const BasicTags();
  List<BasicTags>? readBasicTagsSequence;
  int readBasicTagsCallCount = 0;
  AudioProperties? audioProperties;
  PropertyMap propertyMap = PropertyMap.empty();
  String? plainLyrics;
  List<SyncedLyricsTrack> syncedLyrics = const <SyncedLyricsTrack>[];
  Uint8List exportedBytes = Uint8List.fromList(<int>[1, 2, 3]);
  SessionCapabilities capabilities = _mp3Capabilities;

  Object? writeLyricsError;
  Object? readSyncedLyricsError;
  int readSyncedLyricsCallCount = 0;
  String? lastWriteLyricsText;
  Id3v2Version? lastWriteLyricsVersion;
  List<SyncedLyricsTrack>? lastWriteSyncedTracks;
  Id3v2Version? savedMp3Version;

  @override
  BasicTags readBasicTags() {
    final List<BasicTags>? sequence = readBasicTagsSequence;
    if (sequence != null && sequence.isNotEmpty) {
      final int index = readBasicTagsCallCount < sequence.length
          ? readBasicTagsCallCount
          : sequence.length - 1;
      readBasicTagsCallCount += 1;
      return sequence[index];
    }
    return tags;
  }

  @override
  AudioProperties? readAudioProperties() => audioProperties;

  @override
  SessionCapabilities probeCapabilities() => capabilities;

  @override
  PropertyMap readPropertyMap() => propertyMap;

  @override
  String? readLyrics({String? language, String? description}) => plainLyrics;

  @override
  void writeLyrics(
    String text, {
    required String language,
    required String description,
    required Id3v2Version id3v2Version,
  }) {
    final Object? error = writeLyricsError;
    if (error != null) {
      throw error;
    }
    lastWriteLyricsText = text;
    lastWriteLyricsVersion = id3v2Version;
    plainLyrics = text;
  }

  @override
  void clearLyrics({
    String? language,
    String? description,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  List<SyncedLyricsTrack> readSyncedLyrics() {
    readSyncedLyricsCallCount += 1;
    final Object? error = readSyncedLyricsError;
    if (error != null) {
      throw error;
    }
    return syncedLyrics;
  }

  @override
  void writeSyncedLyrics(
    List<SyncedLyricsTrack> tracks, {
    required SyltMergeMode mergeMode,
    required Id3v2Version id3v2Version,
  }) {
    lastWriteSyncedTracks = tracks;
    syncedLyrics = tracks;
  }

  @override
  void clearSyncedLyrics({
    SyncedLyricsFilter? filter,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  void saveMp3WithId3v2Version({required Id3v2Version version}) {
    savedMp3Version = version;
  }

  @override
  Uint8List exportBytes() => exportedBytes;

  @override
  void close() {}
}

const SessionCapabilities _mp3Capabilities = SessionCapabilities(
  plainLyricsWritable: true,
  syncedLyricsWritable: true,
  mp3Id3SaveSupported: true,
  uslt: true,
  lyrics: false,
  mp4Lyr: false,
  wmLyrics: false,
  hintBased: false,
);

const SessionCapabilities _aacCapabilities = SessionCapabilities(
  plainLyricsWritable: true,
  syncedLyricsWritable: false,
  mp3Id3SaveSupported: false,
  uslt: true,
  lyrics: false,
  mp4Lyr: false,
  wmLyrics: false,
  hintBased: false,
);

class _UnsupportedWriteError {
  final int statusCode = 3;
}

class _UnsupportedReadError {
  final int statusCode = 3;
}

Lyrics _buildTimedLyrics(String songPath) {
  return Lyrics(
    songInfo: SongInfo(source: Source.local, path: songPath, title: 'demo'),
    source: Source.local,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: const <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: '第一行'),
          ],
        ),
        LyricsLine(
          startMs: 1200,
          endMs: 2200,
          words: const <LyricsWord>[
            LyricsWord(startMs: 1200, endMs: 2200, text: '第二行'),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}
