import 'dart:io';
import 'dart:typed_data';

import 'package:dart_taglib/dart_taglib.dart' hide TaglibBackend;
import 'package:path/path.dart' as p;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../audio_tag/audio_tag_port.dart';
import 'dart_taglib_backend.dart';

typedef _BasicTagSnapshot = ({
  String? title,
  String? artist,
  String? album,
  String? comment,
  String? genre,
  int year,
  int track,
});

enum _WriteSessionMode { fileDescriptor, path, bytes }

typedef _OpenedWriteSession = ({
  TaglibBackendSession session,
  String nameHint,
  _WriteSessionMode mode,
});

/// 基于 `dart_taglib` 的音频标签端口（Native）。
class DartTaglibAudioTagPort implements AudioTagPort {
  DartTaglibAudioTagPort({TaglibBackend? backend})
    : _backend = backend ?? DartTaglibBackend();

  final TaglibBackend _backend;

  static const String _defaultLyricsLanguage = 'eng';
  static const String _defaultLyricsDescription = 'LYRICS';

  @override
  AudioTagMeta readMeta(String songPath) {
    final ({TaglibBackendSession session, String nameHint}) opened =
        _openSessionForRead(songPath);
    try {
      final BasicTags tags = opened.session.readBasicTags();
      final AudioProperties? properties = opened.session.readAudioProperties();
      return AudioTagMeta(
        title: _trimOrNull(tags.title),
        artist: _trimOrNull(tags.artist),
        album: _trimOrNull(tags.album),
        durationMs: properties == null ? null : properties.lengthSeconds * 1000,
        trackNumber: tags.track <= 0 ? null : tags.track,
      );
    } catch (error) {
      throw _mapReadError(error, songPath);
    } finally {
      opened.session.close();
    }
  }

  @override
  bool hasLyrics(String songPath) {
    final AudioTagLyricsPayload payload = readLyrics(songPath);
    if (_hasText(payload.plainText)) {
      return true;
    }
    for (final AudioTagSyncedTrack track in payload.syncedTracks) {
      for (final AudioTagSyncedEntry entry in track.entries) {
        if (_hasText(entry.text)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  AudioTagLyricsPayload readLyrics(
    String songPath, {
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) {
    final ({TaglibBackendSession session, String nameHint}) opened =
        _openSessionForRead(
          songPath,
          fileDescriptor: fileDescriptor,
          fileDescriptorNameHint: fileDescriptorNameHint,
        );
    try {
      final String? plain = _readPlainLyrics(opened.session);
      final List<AudioTagSyncedTrack> syncedTracks = _hasText(plain)
          ? const <AudioTagSyncedTrack>[]
          : _readSyncedTracksForFallback(opened.session);
      final String? plainText = _hasText(plain)
          ? plain
          : (syncedTracks.isEmpty ? null : _flattenSyncedTracks(syncedTracks));
      return AudioTagLyricsPayload(
        plainText: plainText,
        syncedTracks: syncedTracks,
      );
    } catch (error) {
      throw _mapReadError(error, songPath);
    } finally {
      opened.session.close();
    }
  }

  @override
  void writeLyrics(AudioTagWriteRequest request) {
    final _OpenedWriteSession opened = _openSessionForWrite(request);
    final Id3v2Version id3v2Version = _mapId3Version(request.id3Version);
    bool saveCriticalSectionReported = false;
    void reportSaveCriticalSectionOnce() {
      if (saveCriticalSectionReported) {
        return;
      }
      saveCriticalSectionReported = true;
      request.onSaveCriticalSectionEntered?.call();
    }

    try {
      final _BasicTagSnapshot tagSnapshotBeforeWrite =
          _captureNonLyricsSnapshot(opened.session.readBasicTags());
      final SessionCapabilities capabilities = _probeCapabilities(
        opened.session,
      );

      opened.session.writeLyrics(
        request.plainLyricsText,
        language: _defaultLyricsLanguage,
        description: _defaultLyricsDescription,
        id3v2Version: id3v2Version,
      );

      if (capabilities.syncedLyricsWritable) {
        final List<SyncedLyricsTrack> syltTracks = _buildSyltTracks(
          request.lyrics,
        );
        if (syltTracks.isNotEmpty) {
          opened.session.writeSyncedLyrics(
            syltTracks,
            mergeMode: SyltMergeMode.replaceByKey,
            id3v2Version: id3v2Version,
          );
        }
      }

      if (capabilities.mp3Id3SaveSupported) {
        reportSaveCriticalSectionOnce();
        opened.session.saveMp3WithId3v2Version(version: id3v2Version);
      }

      switch (opened.mode) {
        case _WriteSessionMode.bytes:
          reportSaveCriticalSectionOnce();
          final Uint8List outputBytes = opened.session.exportBytes();
          _verifyMergedWriteResultFromBytes(
            outputBytes: outputBytes,
            nameHint: opened.nameHint,
            songPath: request.songPath,
            tagSnapshotBeforeWrite: tagSnapshotBeforeWrite,
          );
          File(request.songPath).writeAsBytesSync(outputBytes, flush: true);
        case _WriteSessionMode.fileDescriptor:
        case _WriteSessionMode.path:
          _verifyMergedWriteResultInSession(
            verifySession: opened.session,
            songPath: request.songPath,
            tagSnapshotBeforeWrite: tagSnapshotBeforeWrite,
          );
      }
    } catch (error) {
      throw _mapWriteError(error, request.songPath);
    } finally {
      opened.session.close();
    }
  }

  _OpenedWriteSession _openSessionForWrite(AudioTagWriteRequest request) {
    final String defaultNameHint = _resolveNameHint(request.songPath);
    final int? fileDescriptor = request.fileDescriptor;
    if (fileDescriptor != null) {
      final String nameHint =
          request.fileDescriptorNameHint?.trim().isNotEmpty == true
          ? request.fileDescriptorNameHint!.trim()
          : defaultNameHint;
      try {
        return (
          session: _backend.openSessionFromFileDescriptor(
            fileDescriptor,
            nameHint: nameHint,
          ),
          nameHint: nameHint,
          mode: _WriteSessionMode.fileDescriptor,
        );
      } on UnsupportedError {
        // 后端不支持 fd 时继续回退到 path/bytes。
      }
    }

    if (!_isContentUri(request.songPath)) {
      try {
        return (
          session: _backend.openSessionFromPath(request.songPath),
          nameHint: defaultNameHint,
          mode: _WriteSessionMode.path,
        );
      } on UnsupportedError {
        // 后端不支持 path 时继续回退到 bytes。
      }
    }

    final ({TaglibBackendSession session, String nameHint}) openedByBytes =
        _openSessionFromBytes(request.songPath);
    return (
      session: openedByBytes.session,
      nameHint: openedByBytes.nameHint,
      mode: _WriteSessionMode.bytes,
    );
  }

  ({TaglibBackendSession session, String nameHint}) _openSessionForRead(
    String songPath, {
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) {
    final String defaultNameHint = p.basename(songPath);
    // 预埋 FD 会话入口：后续 Android SAF 事务层可显式传入 fd。
    if (fileDescriptor != null) {
      final String fdNameHint = fileDescriptorNameHint ?? defaultNameHint;
      try {
        return (
          session: _backend.openSessionFromFileDescriptor(
            fileDescriptor,
            nameHint: fdNameHint,
          ),
          nameHint: fdNameHint,
        );
      } on UnsupportedError {
        // 后端不支持 FD 打开时回退到 path/bytes。
      }
    }
    try {
      return (
        session: _backend.openSessionFromPath(songPath),
        nameHint: defaultNameHint,
      );
    } on UnsupportedError {
      return _openSessionFromBytes(songPath);
    }
  }

  ({TaglibBackendSession session, String nameHint}) _openSessionFromBytes(
    String songPath,
  ) {
    final File songFile = File(songPath);
    final Uint8List bytes = songFile.readAsBytesSync();
    final String nameHint = p.basename(songPath);
    return (
      session: _backend.openSession(bytes, nameHint: nameHint),
      nameHint: nameHint,
    );
  }

  String? _readPlainLyrics(TaglibBackendSession session) {
    final String? exact = session.readLyrics(
      language: _defaultLyricsLanguage,
      description: _defaultLyricsDescription,
    );
    if (_hasText(exact)) {
      return exact;
    }
    final String? fallback = session.readLyrics();
    return _hasText(fallback) ? fallback : null;
  }

  SessionCapabilities _probeCapabilities(TaglibBackendSession session) {
    try {
      return session.probeCapabilities();
    } catch (_) {
      return SessionCapabilities.unknown;
    }
  }

  List<AudioTagSyncedTrack> _readSyncedTracks(TaglibBackendSession session) {
    final List<SyncedLyricsTrack> tracks = session.readSyncedLyrics();
    if (tracks.isEmpty) {
      return const <AudioTagSyncedTrack>[];
    }
    return List<AudioTagSyncedTrack>.unmodifiable(
      tracks.map((SyncedLyricsTrack track) {
        return AudioTagSyncedTrack(
          language: track.language,
          description: track.description,
          entries: List<AudioTagSyncedEntry>.unmodifiable(
            track.entries.map((SyncedLyricsEntry entry) {
              return AudioTagSyncedEntry(timeMs: entry.time, text: entry.text);
            }),
          ),
        );
      }),
    );
  }

  List<AudioTagSyncedTrack> _readSyncedTracksForFallback(
    TaglibBackendSession session,
  ) {
    try {
      return _readSyncedTracks(session);
    } catch (error) {
      if (_isTaglibUnsupportedError(error)) {
        return const <AudioTagSyncedTrack>[];
      }
      rethrow;
    }
  }

  String _flattenSyncedTracks(List<AudioTagSyncedTrack> tracks) {
    final StringBuffer buffer = StringBuffer();
    for (final AudioTagSyncedTrack track in tracks) {
      for (final AudioTagSyncedEntry entry in track.entries) {
        buffer.write(entry.text);
      }
    }
    return buffer.toString();
  }

  List<SyncedLyricsTrack> _buildSyltTracks(Lyrics lyrics) {
    final LyricsData? orig = lyrics['orig'];
    if (orig == null || orig.isEmpty) {
      return const <SyncedLyricsTrack>[];
    }
    final List<SyncedLyricsEntry> entries = <SyncedLyricsEntry>[];
    for (int lineIndex = 0; lineIndex < orig.length; lineIndex += 1) {
      final LyricsLine line = orig[lineIndex];
      for (int wordIndex = 0; wordIndex < line.words.length; wordIndex += 1) {
        final LyricsWord word = line.words[wordIndex];
        final int? startMs = word.startMs ?? line.startMs;
        if (startMs == null) {
          continue;
        }
        String text = word.text;
        if (text.isEmpty) {
          continue;
        }
        // 对齐Python版：每行首词（第一行除外）追加换行标记。
        if (lineIndex != 0 && wordIndex == 0) {
          text = '\n$text';
        }
        entries.add(SyncedLyricsEntry(time: startMs, text: text));
      }
    }
    if (entries.isEmpty) {
      return const <SyncedLyricsTrack>[];
    }
    return <SyncedLyricsTrack>[
      SyncedLyricsTrack(
        language: _defaultLyricsLanguage,
        description: _defaultLyricsDescription,
        type: SyncedLyricsType.lyrics,
        timestampFormat: SyncedLyricsTimestampFormat.milliseconds,
        entries: entries,
      ),
    ];
  }

  _BasicTagSnapshot _captureNonLyricsSnapshot(BasicTags tags) {
    return (
      title: _trimOrNull(tags.title),
      artist: _trimOrNull(tags.artist),
      album: _trimOrNull(tags.album),
      comment: _trimOrNull(tags.comment),
      genre: _trimOrNull(tags.genre),
      year: tags.year,
      track: tags.track,
    );
  }

  bool _isSameNonLyricsSnapshot(
    _BasicTagSnapshot baseline,
    _BasicTagSnapshot afterWrite,
  ) {
    return baseline.title == afterWrite.title &&
        baseline.artist == afterWrite.artist &&
        baseline.album == afterWrite.album &&
        baseline.comment == afterWrite.comment &&
        baseline.genre == afterWrite.genre &&
        baseline.year == afterWrite.year &&
        baseline.track == afterWrite.track;
  }

  void _verifyMergedWriteResultFromBytes({
    required Uint8List outputBytes,
    required String nameHint,
    required String songPath,
    required _BasicTagSnapshot tagSnapshotBeforeWrite,
  }) {
    final TaglibBackendSession verifySession = _backend.openSession(
      outputBytes,
      nameHint: nameHint,
    );
    try {
      final _BasicTagSnapshot snapshotAfterWrite = _captureNonLyricsSnapshot(
        verifySession.readBasicTags(),
      );
      if (!_isSameNonLyricsSnapshot(
        tagSnapshotBeforeWrite,
        snapshotAfterWrite,
      )) {
        throw AudioTagException(
          code: AudioTagErrorCode.writeFailed,
          message: '写入标签校验失败，非歌词字段发生变化: $songPath',
        );
      }
      if (!_hasText(_readPlainLyrics(verifySession))) {
        throw AudioTagException(
          code: AudioTagErrorCode.writeFailed,
          message: '写入标签校验失败，回读歌词为空: $songPath',
        );
      }
    } catch (error) {
      if (error is AudioTagException) {
        rethrow;
      }
      throw AudioTagException(
        code: AudioTagErrorCode.writeFailed,
        message: '写入标签校验失败: $songPath',
        cause: error,
      );
    } finally {
      verifySession.close();
    }
  }

  void _verifyMergedWriteResultInSession({
    required TaglibBackendSession verifySession,
    required String songPath,
    required _BasicTagSnapshot tagSnapshotBeforeWrite,
  }) {
    try {
      final _BasicTagSnapshot snapshotAfterWrite = _captureNonLyricsSnapshot(
        verifySession.readBasicTags(),
      );
      if (!_isSameNonLyricsSnapshot(
        tagSnapshotBeforeWrite,
        snapshotAfterWrite,
      )) {
        throw AudioTagException(
          code: AudioTagErrorCode.writeFailed,
          message: '写入标签校验失败，非歌词字段发生变化: $songPath',
        );
      }
      if (!_hasText(_readPlainLyrics(verifySession))) {
        throw AudioTagException(
          code: AudioTagErrorCode.writeFailed,
          message: '写入标签校验失败，回读歌词为空: $songPath',
        );
      }
    } catch (error) {
      if (error is AudioTagException) {
        rethrow;
      }
      throw AudioTagException(
        code: AudioTagErrorCode.writeFailed,
        message: '写入标签校验失败: $songPath',
        cause: error,
      );
    }
  }

  Id3v2Version _mapId3Version(Id3Version id3Version) {
    return switch (id3Version) {
      Id3Version.v23 => Id3v2Version.v23,
      Id3Version.v24 => Id3v2Version.v24,
    };
  }

  AudioTagException _mapReadError(Object error, String songPath) {
    if (error is AudioTagException) {
      return error;
    }
    if (_isTaglibUnsupportedError(error)) {
      return AudioTagException(
        code: AudioTagErrorCode.formatUnsupported,
        message: '不支持读取该格式标签: $songPath',
        cause: error,
      );
    }
    return AudioTagException(
      code: AudioTagErrorCode.readFailed,
      message: '读取标签失败: $songPath',
      cause: error,
    );
  }

  AudioTagException _mapWriteError(Object error, String songPath) {
    if (error is AudioTagException) {
      return error;
    }
    if (_isTaglibUnsupportedError(error)) {
      return AudioTagException(
        code: AudioTagErrorCode.frameUnsupported,
        message: '文件格式不支持写入歌词标签: $songPath',
        cause: error,
      );
    }
    return AudioTagException(
      code: AudioTagErrorCode.writeFailed,
      message: '写入标签失败: $songPath',
      cause: error,
    );
  }

  static String? _trimOrNull(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;

  static bool _isContentUri(String value) => value.startsWith('content://');

  String _resolveNameHint(String songPath) {
    if (_isContentUri(songPath)) {
      final Uri? uri = Uri.tryParse(songPath);
      final String? last = uri == null || uri.pathSegments.isEmpty
          ? null
          : uri.pathSegments.last;
      if (last != null && last.trim().isNotEmpty) {
        return last;
      }
      return 'content-audio';
    }
    return p.basename(songPath);
  }

  bool _isTaglibUnsupportedError(Object error) {
    try {
      final dynamic dynamicError = error;
      final Object? statusCode = dynamicError.statusCode;
      return statusCode is int && statusCode == 3;
    } catch (_) {
      return false;
    }
  }
}
