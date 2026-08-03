import 'dart:typed_data';

import 'package:dart_taglib/dart_taglib.dart';

/// `dart_taglib` 会话抽象，便于在业务层与测试层解耦。
abstract interface class TaglibBackendSession {
  BasicTags readBasicTags();

  AudioProperties? readAudioProperties();

  SessionCapabilities probeCapabilities();

  PropertyMap readPropertyMap();

  String? readLyrics({String? language, String? description});

  void writeLyrics(
    String text, {
    required String language,
    required String description,
    required Id3v2Version id3v2Version,
  });

  void clearLyrics({
    String? language,
    String? description,
    required Id3v2Version id3v2Version,
  });

  List<SyncedLyricsTrack> readSyncedLyrics();

  void writeSyncedLyrics(
    List<SyncedLyricsTrack> tracks, {
    required SyltMergeMode mergeMode,
    required Id3v2Version id3v2Version,
  });

  void clearSyncedLyrics({
    SyncedLyricsFilter? filter,
    required Id3v2Version id3v2Version,
  });

  void saveMp3WithId3v2Version({required Id3v2Version version});

  Uint8List exportBytes();

  void close();
}

/// `dart_taglib` 后端抽象。
abstract interface class TaglibBackend {
  TaglibBackendSession openSession(Uint8List bytes, {String? nameHint});

  TaglibBackendSession openSessionFromPath(String path);

  TaglibBackendSession openSessionFromFileDescriptor(
    int fileDescriptor, {
    String? nameHint,
  });
}

/// `DartTaglibBackend` 使用的会话工厂。
///
/// 这一层只存在于 infra 内部，用来把第三方 `TaglibApi` 和业务侧
/// `TaglibBackend` 隔开。测试可以 fake 这个接口，而不需要 import
/// `dart_taglib/src/...` 这类包内部文件。
abstract interface class DartTaglibSessionFactory {
  TaglibBackendSession openSession(Uint8List bytes, {String? nameHint});

  TaglibBackendSession openSessionFromPath(String path);

  TaglibBackendSession openSessionFromFileDescriptor(
    int fileDescriptor, {
    String? nameHint,
  });
}

/// 默认后端实现：直接包装 `TaglibApi`。
class DartTaglibBackend implements TaglibBackend {
  DartTaglibBackend({
    DartTaglibSessionFactory? sessionFactory,
    String? libraryPath,
  }) : _sessionFactory =
           sessionFactory ?? _DartTaglibApiSessionFactory(libraryPath);

  final DartTaglibSessionFactory _sessionFactory;

  @override
  TaglibBackendSession openSession(Uint8List bytes, {String? nameHint}) {
    return _sessionFactory.openSession(bytes, nameHint: nameHint);
  }

  @override
  TaglibBackendSession openSessionFromPath(String path) {
    return _sessionFactory.openSessionFromPath(path);
  }

  @override
  TaglibBackendSession openSessionFromFileDescriptor(
    int fileDescriptor, {
    String? nameHint,
  }) {
    return _sessionFactory.openSessionFromFileDescriptor(
      fileDescriptor,
      nameHint: nameHint,
    );
  }
}

class _DartTaglibApiSessionFactory implements DartTaglibSessionFactory {
  _DartTaglibApiSessionFactory(String? libraryPath)
    : _api = TaglibApi(libraryPath: libraryPath);

  final TaglibApi _api;

  @override
  TaglibBackendSession openSession(Uint8List bytes, {String? nameHint}) {
    return _DartTaglibBackendSession(
      _api.openSession(bytes, nameHint: nameHint),
    );
  }

  @override
  TaglibBackendSession openSessionFromPath(String path) {
    return _DartTaglibBackendSession(_api.openSessionFromPath(path));
  }

  @override
  TaglibBackendSession openSessionFromFileDescriptor(
    int fileDescriptor, {
    String? nameHint,
  }) {
    return _DartTaglibBackendSession(
      _api.openFileDescriptor(fileDescriptor, nameHint: nameHint),
    );
  }
}

class _DartTaglibBackendSession implements TaglibBackendSession {
  const _DartTaglibBackendSession(this._session);

  final TaglibSession _session;

  @override
  BasicTags readBasicTags() => _session.readBasicTags();

  @override
  AudioProperties? readAudioProperties() => _session.readAudioProperties();

  @override
  SessionCapabilities probeCapabilities() => _session.probeCapabilities();

  @override
  PropertyMap readPropertyMap() => _session.readPropertyMap();

  @override
  String? readLyrics({String? language, String? description}) {
    return _session.readLyrics(language: language, description: description);
  }

  @override
  void writeLyrics(
    String text, {
    required String language,
    required String description,
    required Id3v2Version id3v2Version,
  }) {
    _session.writeLyrics(
      text,
      language: language,
      description: description,
      id3v2Version: id3v2Version,
    );
  }

  @override
  void clearLyrics({
    String? language,
    String? description,
    required Id3v2Version id3v2Version,
  }) {
    _session.clearLyrics(
      language: language,
      description: description,
      id3v2Version: id3v2Version,
    );
  }

  @override
  List<SyncedLyricsTrack> readSyncedLyrics() => _session.readSyncedLyrics();

  @override
  void writeSyncedLyrics(
    List<SyncedLyricsTrack> tracks, {
    required SyltMergeMode mergeMode,
    required Id3v2Version id3v2Version,
  }) {
    _session.writeSyncedLyrics(
      tracks,
      mergeMode: mergeMode,
      id3v2Version: id3v2Version,
    );
  }

  @override
  void clearSyncedLyrics({
    SyncedLyricsFilter? filter,
    required Id3v2Version id3v2Version,
  }) {
    _session.clearSyncedLyrics(filter: filter, id3v2Version: id3v2Version);
  }

  @override
  void saveMp3WithId3v2Version({required Id3v2Version version}) {
    _session.saveMp3WithId3v2Version(version: version);
  }

  @override
  Uint8List exportBytes() => _session.exportBytes();

  @override
  void close() => _session.close();
}
