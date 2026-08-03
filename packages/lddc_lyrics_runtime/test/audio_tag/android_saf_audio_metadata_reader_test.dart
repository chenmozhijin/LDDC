import 'dart:typed_data';

import 'package:dart_taglib/dart_taglib.dart' hide TaglibBackend;
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('AndroidSafAudioMetadataReader', () {
    test('成功读取 metadata 后关闭 session 和 fd', () async {
      final _FakeAndroidSafFdPort fdPort = _FakeAndroidSafFdPort(
        opened: const AndroidSafOpenedFileDescriptor(
          fileDescriptor: 9,
          nameHint: 'song.mp3',
        ),
      );
      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession(
        tags: const BasicTags(
          title: ' Song ',
          artist: ' Singer ',
          album: ' Album ',
          track: 3,
        ),
        audioProperties: const AudioProperties(
          lengthSeconds: 180,
          bitrateKbps: 320,
          sampleRate: 44100,
          channels: 2,
        ),
        propertyMap: PropertyMap(
          items: <PropertyItem>[
            PropertyItem(key: 'CUESHEET', values: const <String>[' cue ']),
          ],
        ),
      );
      final AndroidSafAudioMetadataReader reader =
          AndroidSafAudioMetadataReader(
            safFdPort: fdPort,
            taglibBackend: _FakeTaglibBackend(session),
          );

      final AndroidSafAudioMetadata metadata = await reader.readMetadata(
        uri: 'content://doc/song',
        nameHint: null,
      );

      expect(metadata.nameHint, 'song.mp3');
      expect(metadata.title, 'Song');
      expect(metadata.artist, 'Singer');
      expect(metadata.album, 'Album');
      expect(metadata.durationMs, 180000);
      expect(metadata.trackNumber, 3);
      expect(metadata.cuesheet, ' cue ');
      expect(session.closed, isTrue);
      expect(fdPort.closedFds, <int>[9]);
    });

    test('taglib 读取失败时仍关闭 session 和 fd', () async {
      final _FakeAndroidSafFdPort fdPort = _FakeAndroidSafFdPort(
        opened: const AndroidSafOpenedFileDescriptor(
          fileDescriptor: 10,
          nameHint: 'broken.mp3',
        ),
      );
      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession(
        readBasicTagsError: StateError('read failed'),
      );
      final AndroidSafAudioMetadataReader reader =
          AndroidSafAudioMetadataReader(
            safFdPort: fdPort,
            taglibBackend: _FakeTaglibBackend(session),
          );

      await expectLater(
        reader.readMetadata(uri: 'content://doc/broken', nameHint: null),
        throwsA(isA<StateError>()),
      );

      expect(session.closed, isTrue);
      expect(fdPort.closedFds, <int>[10]);
    });

    test('closeFd 失败不覆盖成功读取结果', () async {
      final _FakeAndroidSafFdPort fdPort = _FakeAndroidSafFdPort(
        opened: const AndroidSafOpenedFileDescriptor(fileDescriptor: 11),
      )..closeError = StateError('close failed');
      final _FakeTaglibBackendSession session = _FakeTaglibBackendSession(
        tags: const BasicTags(title: 'Song'),
      );
      final AndroidSafAudioMetadataReader reader =
          AndroidSafAudioMetadataReader(
            safFdPort: fdPort,
            taglibBackend: _FakeTaglibBackend(session),
          );

      final AndroidSafAudioMetadata metadata = await reader.readMetadata(
        uri: 'content://doc/song',
        nameHint: 'fallback.flac',
      );

      expect(metadata.title, 'Song');
      expect(metadata.nameHint, 'fallback.flac');
      expect(session.closed, isTrue);
      expect(fdPort.closedFds, <int>[11]);
    });
  });
}

final class _FakeAndroidSafFdPort implements AndroidSafFdPort {
  _FakeAndroidSafFdPort({required this.opened});

  final AndroidSafOpenedFileDescriptor opened;
  final List<int> closedFds = <int>[];
  Object? openError;
  Object? closeError;

  @override
  Future<void> closeFd(int fileDescriptor) async {
    closedFds.add(fileDescriptor);
    final Object? error = closeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadOnlyFd(String uri) async {
    final Object? error = openError;
    if (error != null) {
      throw error;
    }
    return opened;
  }

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadWriteFd(String uri) {
    throw UnimplementedError();
  }
}

final class _FakeTaglibBackend implements TaglibBackend {
  const _FakeTaglibBackend(this.session);

  final TaglibBackendSession session;

  @override
  TaglibBackendSession openSession(Uint8List bytes, {String? nameHint}) {
    throw UnimplementedError();
  }

  @override
  TaglibBackendSession openSessionFromFileDescriptor(
    int fileDescriptor, {
    String? nameHint,
  }) {
    return session;
  }

  @override
  TaglibBackendSession openSessionFromPath(String path) {
    throw UnimplementedError();
  }
}

final class _FakeTaglibBackendSession implements TaglibBackendSession {
  _FakeTaglibBackendSession({
    this.tags = const BasicTags(),
    this.audioProperties,
    PropertyMap? propertyMap,
    this.readBasicTagsError,
  }) : propertyMap = propertyMap ?? PropertyMap.empty();

  final BasicTags tags;
  final AudioProperties? audioProperties;
  final PropertyMap propertyMap;
  final Object? readBasicTagsError;
  bool closed = false;

  @override
  BasicTags readBasicTags() {
    final Object? error = readBasicTagsError;
    if (error != null) {
      throw error;
    }
    return tags;
  }

  @override
  AudioProperties? readAudioProperties() => audioProperties;

  @override
  PropertyMap readPropertyMap() => propertyMap;

  @override
  void close() {
    closed = true;
  }

  @override
  void clearLyrics({
    String? language,
    String? description,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  void clearSyncedLyrics({
    SyncedLyricsFilter? filter,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  Uint8List exportBytes() => Uint8List(0);

  @override
  SessionCapabilities probeCapabilities() => SessionCapabilities.unknown;

  @override
  String? readLyrics({String? language, String? description}) => null;

  @override
  List<SyncedLyricsTrack> readSyncedLyrics() => const <SyncedLyricsTrack>[];

  @override
  void saveMp3WithId3v2Version({required Id3v2Version version}) {}

  @override
  void writeLyrics(
    String text, {
    required String language,
    required String description,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  void writeSyncedLyrics(
    List<SyncedLyricsTrack> tracks, {
    required SyltMergeMode mergeMode,
    required Id3v2Version id3v2Version,
  }) {}
}
