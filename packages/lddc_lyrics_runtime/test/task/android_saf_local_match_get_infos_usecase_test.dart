import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  group('AndroidSafLocalMatchGetInfosUseCase', () {
    test('先解析外部 cue 并排除已覆盖音频，再解析普通音频', () async {
      const String rootUri = 'content://tree/root';
      const String cueUri = 'content://doc/disc.cue';
      const String discUri = 'content://doc/disc.flac';
      const String extraUri = 'content://doc/extra.mp3';
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: cueUri,
              displayName: 'disc.cue',
              mimeType: 'text/plain',
              isDirectory: false,
              isFile: true,
            ),
            AndroidSafTreeEntry(
              uri: discUri,
              displayName: 'disc.flac',
              mimeType: 'audio/flac',
              isDirectory: false,
              isFile: true,
            ),
            AndroidSafTreeEntry(
              uri: extraUri,
              displayName: 'extra.mp3',
              mimeType: 'audio/mpeg',
              isDirectory: false,
              isFile: true,
            ),
          ],
        },
        bytesByUri: <String, Uint8List>{},
      );
      final _FakeAndroidSafContentPort contentPort = _FakeAndroidSafContentPort(
        bytesByUri: <String, Uint8List>{
          cueUri: Uint8List.fromList(
            '''
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Cue Track 1"
    PERFORMER "Cue Artist"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Cue Track 2"
    PERFORMER "Cue Artist"
    INDEX 01 01:00:00
'''
                .codeUnits,
          ),
        },
      );
      final _FakeAndroidSafAudioMetadataPort metadataPort =
          _FakeAndroidSafAudioMetadataPort(
            metadataByUri: const <String, AndroidSafAudioMetadata>{
              discUri: AndroidSafAudioMetadata(
                nameHint: 'disc.flac',
                title: 'Disc',
                artist: 'Cue Artist',
                album: 'Cue Album',
                durationMs: 180000,
                trackNumber: 1,
                cuesheet: null,
              ),
              extraUri: AndroidSafAudioMetadata(
                nameHint: 'extra.mp3',
                title: 'Extra',
                artist: 'Extra Artist',
                album: 'Extra Album',
                durationMs: 200000,
                trackNumber: 7,
                cuesheet: null,
              ),
            },
          );
      final AndroidSafLocalMatchGetInfosUseCase useCase =
          AndroidSafLocalMatchGetInfosUseCase(
            treePort: treePort,
            contentPort: contentPort,
            audioMetadataPort: metadataPort,
          );
      final List<LocalMatchGetInfosProgress> progress =
          <LocalMatchGetInfosProgress>[];

      final AndroidSafLocalMatchGetInfosResult result = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
        onProgress: progress.add,
      );

      expect(result.cancelled, isFalse);
      expect(result.errors, isEmpty);
      expect(result.entries, hasLength(3));
      expect(
        result.entries
            .where((LocalMatchSongEntry item) => item.songInfo.path == discUri)
            .length,
        2,
      );
      expect(
        result.entries
            .where((LocalMatchSongEntry item) => item.songInfo.path == extraUri)
            .length,
        1,
      );
      expect(
        result.entries.every(
          (LocalMatchSongEntry item) => item.rootPath == rootUri,
        ),
        isTrue,
      );
      expect(progress.first.text, '遍历文件...');
      expect(progress.last.text, isEmpty);
    });

    test('音频内嵌 cuesheet 优先按多轨输出 SongInfo', () async {
      const String rootUri = 'content://tree/root';
      const String albumUri = 'content://doc/album.flac';
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: albumUri,
              displayName: 'album.flac',
              mimeType: 'audio/flac',
              isDirectory: false,
              isFile: true,
            ),
          ],
        },
        bytesByUri: <String, Uint8List>{},
      );
      final _FakeAndroidSafAudioMetadataPort metadataPort =
          _FakeAndroidSafAudioMetadataPort(
            metadataByUri: const <String, AndroidSafAudioMetadata>{
              albumUri: AndroidSafAudioMetadata(
                nameHint: 'album.flac',
                title: 'Album',
                artist: 'Album Artist',
                album: 'Album',
                durationMs: 180000,
                trackNumber: 1,
                cuesheet: '''
FILE "album.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Track A"
    PERFORMER "Singer A"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Track B"
    PERFORMER "Singer B"
    INDEX 01 01:00:00
''',
              ),
            },
          );
      final AndroidSafLocalMatchGetInfosUseCase useCase =
          AndroidSafLocalMatchGetInfosUseCase(
            treePort: treePort,
            contentPort: const _FakeAndroidSafContentPort(
              bytesByUri: <String, Uint8List>{},
            ),
            audioMetadataPort: metadataPort,
          );

      final AndroidSafLocalMatchGetInfosResult result = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
      );

      expect(result.cancelled, isFalse);
      expect(result.errors, isEmpty);
      expect(result.entries, hasLength(2));
      expect(result.entries[0].songInfo.title, 'Track A');
      expect(result.entries[1].songInfo.title, 'Track B');
      expect(
        result.entries.every(
          (LocalMatchSongEntry item) => item.songInfo.fromCue,
        ),
        isTrue,
      );
    });

    test('支持 >1000 文件扫描、取消与 checkpoint 恢复', () async {
      const String rootUri = 'content://tree/root';
      final Map<String, List<AndroidSafTreeEntry>> childrenByUri =
          <String, List<AndroidSafTreeEntry>>{};
      final Map<String, AndroidSafAudioMetadata> metadataByUri =
          <String, AndroidSafAudioMetadata>{};
      final List<AndroidSafTreeEntry> children = <AndroidSafTreeEntry>[];

      for (int i = 0; i < 1005; i += 1) {
        final String uri = 'content://doc/song-$i.mp3';
        final String displayName = 'song-$i.mp3';
        children.add(
          AndroidSafTreeEntry(
            uri: uri,
            displayName: displayName,
            mimeType: 'audio/mpeg',
            isDirectory: false,
            isFile: true,
          ),
        );
        metadataByUri[uri] = AndroidSafAudioMetadata(
          nameHint: displayName,
          title: 'Song $i',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          trackNumber: i + 1,
          cuesheet: null,
        );
      }
      childrenByUri[rootUri] = children;

      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: childrenByUri,
        bytesByUri: <String, Uint8List>{},
      );
      final _FakeAndroidSafAudioMetadataPort metadataPort =
          _FakeAndroidSafAudioMetadataPort(metadataByUri: metadataByUri);
      final AndroidSafLocalMatchGetInfosUseCase useCase =
          AndroidSafLocalMatchGetInfosUseCase(
            treePort: treePort,
            contentPort: const _FakeAndroidSafContentPort(
              bytesByUri: <String, Uint8List>{},
            ),
            audioMetadataPort: metadataPort,
          );

      final LocalMatchCancellationToken token = LocalMatchCancellationToken();
      final List<LocalMatchSongEntry> deliveredEntries =
          <LocalMatchSongEntry>[];
      final List<int> deliveredBatchSizes = <int>[];
      final AndroidSafLocalMatchGetInfosResult first = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
        cancellationToken: token,
        collectEntries: false,
        onEntries: (List<LocalMatchSongEntry> entries) {
          deliveredBatchSizes.add(entries.length);
          deliveredEntries.addAll(entries);
        },
        onProgress: (LocalMatchGetInfosProgress value) {
          if (value.maxValue > 1000 && value.value >= 10) {
            token.cancel();
          }
        },
      );

      expect(first.cancelled, isTrue);
      expect(first.checkpoint, isNotNull);
      expect(first.entries, isEmpty);
      expect(deliveredEntries.length, greaterThan(0));
      expect(deliveredEntries.length, lessThan(1005));
      expect(first.checkpoint!.stage, AndroidSafScanStage.audioParsing);
      expect(first.checkpoint!.pendingFiles.length, lessThanOrEqualTo(128));
      expect(first.checkpoint!.seenFileUris.length, lessThan(1005));

      final AndroidSafLocalMatchGetInfosResult resumed = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri, displayName: 'root'),
        checkpoint: first.checkpoint,
        collectEntries: false,
        onEntries: (List<LocalMatchSongEntry> entries) {
          deliveredBatchSizes.add(entries.length);
          deliveredEntries.addAll(entries);
        },
      );

      expect(resumed.cancelled, isFalse);
      expect(resumed.entries, isEmpty);
      expect(deliveredEntries.length, 1005);
      expect(deliveredBatchSizes.every((int size) => size <= 64), isTrue);
    });

    test('连续扫描不同目录树后不会复用上一轮 metadata 缓存', () async {
      const String firstRootUri = 'content://tree/first';
      const String secondRootUri = 'content://tree/second';
      const String sharedAudioUri = 'content://doc/shared.mp3';
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          firstRootUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: sharedAudioUri,
              displayName: 'shared.mp3',
              mimeType: 'audio/mpeg',
              isDirectory: false,
              isFile: true,
            ),
          ],
          secondRootUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: sharedAudioUri,
              displayName: 'shared.mp3',
              mimeType: 'audio/mpeg',
              isDirectory: false,
              isFile: true,
            ),
          ],
        },
        bytesByUri: <String, Uint8List>{},
      );
      final Map<String, AndroidSafAudioMetadata> metadataByUri =
          <String, AndroidSafAudioMetadata>{
            sharedAudioUri: const AndroidSafAudioMetadata(
              nameHint: 'shared.mp3',
              title: 'First',
              artist: 'Artist',
              album: 'Album',
              durationMs: 1000,
              trackNumber: 1,
              cuesheet: null,
            ),
          };
      final _FakeAndroidSafAudioMetadataPort metadataPort =
          _FakeAndroidSafAudioMetadataPort(metadataByUri: metadataByUri);
      final AndroidSafLocalMatchGetInfosUseCase useCase =
          AndroidSafLocalMatchGetInfosUseCase(
            treePort: treePort,
            contentPort: const _FakeAndroidSafContentPort(
              bytesByUri: <String, Uint8List>{},
            ),
            audioMetadataPort: metadataPort,
          );

      final AndroidSafLocalMatchGetInfosResult first = await useCase.run(
        rootTree: const AndroidSafTreeToken(
          uri: firstRootUri,
          displayName: 'first',
        ),
      );
      metadataByUri[sharedAudioUri] = const AndroidSafAudioMetadata(
        nameHint: 'shared.mp3',
        title: 'Second',
        artist: 'Artist',
        album: 'Album',
        durationMs: 2000,
        trackNumber: 2,
        cuesheet: null,
      );
      final AndroidSafLocalMatchGetInfosResult second = await useCase.run(
        rootTree: const AndroidSafTreeToken(
          uri: secondRootUri,
          displayName: 'second',
        ),
      );

      expect(first.entries.single.songInfo.title, 'First');
      expect(second.entries.single.songInfo.title, 'Second');
      expect(metadataPort.readUris, <String>[sharedAudioUri, sharedAudioUri]);
    });

    test('目录环和重复文档 URI 不会造成无限遍历或重复歌曲', () async {
      const String rootUri = 'content://tree/root';
      const String audioUri = 'content://doc/song.mp3';
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: rootUri,
              displayName: 'loop',
              mimeType: null,
              isDirectory: true,
              isFile: false,
            ),
            AndroidSafTreeEntry(
              uri: audioUri,
              displayName: 'song.mp3',
              mimeType: 'audio/mpeg',
              isDirectory: false,
              isFile: true,
            ),
            AndroidSafTreeEntry(
              uri: audioUri,
              displayName: 'song-copy.mp3',
              mimeType: 'audio/mpeg',
              isDirectory: false,
              isFile: true,
            ),
          ],
        },
        bytesByUri: <String, Uint8List>{},
      );
      final AndroidSafLocalMatchGetInfosUseCase useCase =
          AndroidSafLocalMatchGetInfosUseCase(
            treePort: treePort,
            contentPort: const _FakeAndroidSafContentPort(
              bytesByUri: <String, Uint8List>{},
            ),
            audioMetadataPort: _FakeAndroidSafAudioMetadataPort(
              metadataByUri: const <String, AndroidSafAudioMetadata>{
                audioUri: AndroidSafAudioMetadata(
                  nameHint: 'song.mp3',
                  title: 'Song',
                  artist: 'Artist',
                  album: null,
                  durationMs: 1000,
                  trackNumber: 1,
                  cuesheet: null,
                ),
              },
            ),
          );

      final AndroidSafLocalMatchGetInfosResult result = await useCase.run(
        rootTree: const AndroidSafTreeToken(uri: rootUri),
      );

      expect(result.cancelled, isFalse);
      expect(result.entries, hasLength(1));
      expect(treePort.listCalls[rootUri], 2);
    });
  });
}

class _FakeAndroidSafTreePort implements AndroidSafTreePort {
  _FakeAndroidSafTreePort({
    required this.childrenByUri,
    required this.bytesByUri,
  });

  final Map<String, List<AndroidSafTreeEntry>> childrenByUri;
  final Map<String, Uint8List> bytesByUri;
  final Map<String, int> listCalls = <String, int>{};

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    listCalls.update(uri, (int value) => value + 1, ifAbsent: () => 1);
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

class _FakeAndroidSafContentPort implements AndroidSafContentPort {
  const _FakeAndroidSafContentPort({required this.bytesByUri});

  final Map<String, Uint8List> bytesByUri;

  @override
  Future<Uint8List> readBytes(String uri, {int? maxBytes}) async {
    final Uint8List? value = bytesByUri[uri];
    if (value == null) {
      throw StateError('missing bytes for $uri');
    }
    if (maxBytes != null && value.length > maxBytes) {
      throw StateError('fake content too large for $uri');
    }
    return value;
  }
}

class _FakeAndroidSafAudioMetadataPort implements AndroidSafAudioMetadataPort {
  _FakeAndroidSafAudioMetadataPort({required this.metadataByUri});

  final Map<String, AndroidSafAudioMetadata> metadataByUri;
  final List<String> readUris = <String>[];

  @override
  Future<AndroidSafAudioMetadata> readMetadata({
    required String uri,
    required String? nameHint,
  }) async {
    readUris.add(uri);
    final AndroidSafAudioMetadata? metadata = metadataByUri[uri];
    if (metadata == null) {
      throw StateError('missing metadata for $uri');
    }
    return metadata;
  }
}
