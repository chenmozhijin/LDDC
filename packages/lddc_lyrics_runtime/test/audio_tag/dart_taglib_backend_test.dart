import 'dart:typed_data';

import 'package:dart_taglib/dart_taglib.dart';
import 'package:test/test.dart';

import '../support/internal_runtime_test_api.dart';

void main() {
  group('DartTaglibBackend', () {
    test('openSessionFromPath 透传到底层 path backend', () {
      final _FakeDartTaglibSessionFactory fakeBackend =
          _FakeDartTaglibSessionFactory();
      final DartTaglibBackend backend = DartTaglibBackend(
        sessionFactory: fakeBackend,
      );

      final TaglibBackendSession session = backend.openSessionFromPath(
        r'D:\music\demo.mp3',
      );

      expect(fakeBackend.openPathCallCount, 1);
      expect(fakeBackend.lastPath, r'D:\music\demo.mp3');
      expect(session.probeCapabilities(), SessionCapabilities.unknown);
      session.close();
    });

    test('openSessionFromFileDescriptor 透传到底层 fd backend', () {
      final _FakeDartTaglibSessionFactory fakeBackend =
          _FakeDartTaglibSessionFactory();
      final DartTaglibBackend backend = DartTaglibBackend(
        sessionFactory: fakeBackend,
      );

      final TaglibBackendSession session = backend
          .openSessionFromFileDescriptor(42, nameHint: 'demo.flac');

      expect(fakeBackend.openFileDescriptorCallCount, 1);
      expect(fakeBackend.lastFileDescriptor, 42);
      expect(fakeBackend.lastFileDescriptorNameHint, 'demo.flac');
      expect(session.probeCapabilities(), SessionCapabilities.unknown);
      session.close();
    });

    test('openSessionFromPath 在 UnsupportedError 时保持抛出', () {
      final _FakeDartTaglibSessionFactory fakeBackend =
          _FakeDartTaglibSessionFactory()
            ..openPathError = UnsupportedError('path unsupported');
      final DartTaglibBackend backend = DartTaglibBackend(
        sessionFactory: fakeBackend,
      );

      expect(
        () => backend.openSessionFromPath(r'D:\music\demo.mp3'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('openSessionFromFileDescriptor 在 UnsupportedError 时保持抛出', () {
      final _FakeDartTaglibSessionFactory fakeBackend =
          _FakeDartTaglibSessionFactory()
            ..openFileDescriptorError = UnsupportedError('fd unsupported');
      final DartTaglibBackend backend = DartTaglibBackend(
        sessionFactory: fakeBackend,
      );

      expect(
        () => backend.openSessionFromFileDescriptor(9, nameHint: 'demo.mp3'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

class _FakeDartTaglibSessionFactory implements DartTaglibSessionFactory {
  int openBytesCallCount = 0;
  int openPathCallCount = 0;
  int openFileDescriptorCallCount = 0;
  String? lastPath;
  int? lastFileDescriptor;
  String? lastFileDescriptorNameHint;
  Object? openPathError;
  Object? openFileDescriptorError;

  @override
  TaglibBackendSession openSession(Uint8List bytes, {String? nameHint}) {
    openBytesCallCount += 1;
    return _FakeTaglibBackendSession();
  }

  @override
  TaglibBackendSession openSessionFromPath(String path) {
    openPathCallCount += 1;
    lastPath = path;
    final Object? error = openPathError;
    if (error != null) {
      throw error;
    }
    return _FakeTaglibBackendSession();
  }

  @override
  TaglibBackendSession openSessionFromFileDescriptor(
    int fileDescriptor, {
    String? nameHint,
  }) {
    openFileDescriptorCallCount += 1;
    lastFileDescriptor = fileDescriptor;
    lastFileDescriptorNameHint = nameHint;
    final Object? error = openFileDescriptorError;
    if (error != null) {
      throw error;
    }
    return _FakeTaglibBackendSession();
  }
}

class _FakeTaglibBackendSession implements TaglibBackendSession {
  @override
  BasicTags readBasicTags() => const BasicTags();

  @override
  AudioProperties? readAudioProperties() => null;

  @override
  SessionCapabilities probeCapabilities() => SessionCapabilities.unknown;

  @override
  PropertyMap readPropertyMap() => PropertyMap.empty();

  @override
  String? readLyrics({String? language, String? description}) => null;

  @override
  void writeLyrics(
    String text, {
    required String language,
    required String description,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  void clearLyrics({
    String? language,
    String? description,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  void saveMp3WithId3v2Version({required Id3v2Version version}) {}

  @override
  List<SyncedLyricsTrack> readSyncedLyrics() => const <SyncedLyricsTrack>[];

  @override
  void writeSyncedLyrics(
    List<SyncedLyricsTrack> tracks, {
    required SyltMergeMode mergeMode,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  void clearSyncedLyrics({
    SyncedLyricsFilter? filter,
    required Id3v2Version id3v2Version,
  }) {}

  @override
  Uint8List exportBytes() => Uint8List.fromList(<int>[1, 2, 3]);

  @override
  void close() {}
}
