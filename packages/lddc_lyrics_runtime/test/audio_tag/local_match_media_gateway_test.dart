import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('LocalMatchMediaGatewayImpl', () {
    test('readAudioSongInfos 将标签元数据映射为 SongInfo', () async {
      final _FakeAudioTagPort port = _FakeAudioTagPort()
        ..meta = const AudioTagMeta(
          title: 'Song',
          artist: 'A/B',
          album: 'Album',
          durationMs: 123000,
          trackNumber: 7,
        );
      final LocalMatchMediaGatewayImpl gateway = LocalMatchMediaGatewayImpl(
        audioTagPort: port,
      );

      final List<SongInfo> infos = await gateway.readAudioSongInfos(
        r'D:\song.mp3',
      );

      expect(infos, hasLength(1));
      expect(infos.single.source, Source.local);
      expect(infos.single.path, r'D:\song.mp3');
      expect(infos.single.title, 'Song');
      expect(infos.single.artist?.values, <String>['A', 'B']);
      expect(infos.single.album, 'Album');
      expect(infos.single.durationMs, 123000);
      expect(infos.single.id, '7');
    });

    test('artist mapper 只按 / 拆分并保序去重', () async {
      final _FakeAudioTagPort port = _FakeAudioTagPort()
        ..meta = const AudioTagMeta(
          title: 'Song',
          artist: ' A / B / A / AC/DC ',
          album: null,
          durationMs: null,
          trackNumber: null,
        );
      final LocalMatchMediaGatewayImpl gateway = LocalMatchMediaGatewayImpl(
        audioTagPort: port,
      );

      final List<SongInfo> infos = await gateway.readAudioSongInfos(
        r'D:\song.mp3',
      );

      expect(infos.single.artist?.values, <String>['A', 'B', 'AC', 'DC']);
    });

    test('hasLyricsTag 在底层异常时返回 false', () async {
      final _FakeAudioTagPort port = _FakeAudioTagPort()
        ..hasLyricsError = const AudioTagException(
          code: AudioTagErrorCode.readFailed,
          message: 'read failed',
        );
      final LocalMatchMediaGatewayImpl gateway = LocalMatchMediaGatewayImpl(
        audioTagPort: port,
      );

      await expectLater(
        gateway.hasLyricsTag(r'D:\song.mp3'),
        completion(false),
      );
    });

    test('content:// hasLyricsTag 通过 SAF 只读 fd 判断已有歌词并关闭 fd', () async {
      final _FakeAudioTagPort port = _FakeAudioTagPort()
        ..lyricsPayload = AudioTagLyricsPayload(
          plainText: 'embedded lyrics',
          syncedTracks: const <AudioTagSyncedTrack>[],
        );
      final _FakeAndroidSafFdPort safFdPort = _FakeAndroidSafFdPort(
        openResult: const AndroidSafOpenedFileDescriptor(
          fileDescriptor: 55,
          nameHint: 'song.mp3',
        ),
      );
      final LocalMatchMediaGatewayImpl gateway = LocalMatchMediaGatewayImpl(
        audioTagPort: port,
        androidSafFdPort: safFdPort,
      );

      await expectLater(
        gateway.hasLyricsTag('content://media/external/audio/media/1'),
        completion(true),
      );

      expect(safFdPort.readOnlyOpenUris, <String>[
        'content://media/external/audio/media/1',
      ]);
      expect(safFdPort.closedFds, <int>[55]);
      expect(port.lastReadLyricsFileDescriptor, 55);
      expect(port.lastReadLyricsFileDescriptorNameHint, 'song.mp3');
    });

    test(
      'writeLyricsTag 将 AudioTagException 映射为 LocalMatchTagWriteException',
      () async {
        final _FakeAudioTagPort port = _FakeAudioTagPort()
          ..writeError = const AudioTagException(
            code: AudioTagErrorCode.writeFailed,
            message: 'write failed',
          );
        final LocalMatchMediaGatewayImpl gateway = LocalMatchMediaGatewayImpl(
          audioTagPort: port,
        );

        await expectLater(
          gateway.writeLyricsTag(
            songPath: r'D:\song.mp3',
            lyricsText: 'lyrics',
            lyrics: _buildLyrics(),
            id3Version: Id3Version.v24,
          ),
          throwsA(
            isA<LocalMatchTagWriteException>()
                .having(
                  (LocalMatchTagWriteException error) => error.code,
                  'code',
                  AudioTagErrorCode.writeFailed,
                )
                .having(
                  (LocalMatchTagWriteException error) => error.songPath,
                  'songPath',
                  r'D:\song.mp3',
                ),
          ),
        );
      },
    );

    test('content:// 路径通过 SAF fd 透传到 AudioTagWriteRequest', () async {
      final _FakeAudioTagPort port = _FakeAudioTagPort();
      final _FakeAndroidSafFdPort safFdPort = _FakeAndroidSafFdPort(
        openResult: const AndroidSafOpenedFileDescriptor(
          fileDescriptor: 77,
          nameHint: 'song.mp3',
        ),
      );
      final LocalMatchMediaGatewayImpl gateway = LocalMatchMediaGatewayImpl(
        audioTagPort: port,
        androidSafFdPort: safFdPort,
      );

      await gateway.writeLyricsTag(
        songPath: 'content://media/external/audio/media/1',
        lyricsText: 'lyrics',
        lyrics: _buildLyrics(),
        id3Version: Id3Version.v24,
      );

      expect(safFdPort.readWriteOpenUris, <String>[
        'content://media/external/audio/media/1',
      ]);
      expect(safFdPort.closedFds, <int>[77]);
      expect(port.lastWriteRequest?.fileDescriptor, 77);
      expect(port.lastWriteRequest?.fileDescriptorNameHint, 'song.mp3');
    });

    test('content:// 写入失败后仍会关闭 fd', () async {
      final _FakeAudioTagPort port = _FakeAudioTagPort()
        ..writeError = const AudioTagException(
          code: AudioTagErrorCode.writeFailed,
          message: 'write failed',
        );
      final _FakeAndroidSafFdPort safFdPort = _FakeAndroidSafFdPort(
        openResult: const AndroidSafOpenedFileDescriptor(
          fileDescriptor: 42,
          nameHint: 'song.mp3',
        ),
      );
      final LocalMatchMediaGatewayImpl gateway = LocalMatchMediaGatewayImpl(
        audioTagPort: port,
        androidSafFdPort: safFdPort,
      );

      await expectLater(
        gateway.writeLyricsTag(
          songPath: 'content://media/external/audio/media/2',
          lyricsText: 'lyrics',
          lyrics: _buildLyrics(),
          id3Version: Id3Version.v24,
        ),
        throwsA(isA<LocalMatchTagWriteException>()),
      );
      expect(safFdPort.closedFds, <int>[42]);
    });

    test('外部透传 fd 时直接复用，不重复打开或关闭 SAF fd', () async {
      final _FakeAudioTagPort port = _FakeAudioTagPort();
      final _FakeAndroidSafFdPort safFdPort = _FakeAndroidSafFdPort(
        openResult: const AndroidSafOpenedFileDescriptor(
          fileDescriptor: 88,
          nameHint: 'song.mp3',
        ),
      );
      final LocalMatchMediaGatewayImpl gateway = LocalMatchMediaGatewayImpl(
        audioTagPort: port,
        androidSafFdPort: safFdPort,
      );

      await gateway.writeLyricsTag(
        songPath: '/var/mobile/song.m4a',
        lyricsText: 'lyrics',
        lyrics: _buildLyrics(),
        id3Version: Id3Version.v24,
        fileDescriptor: 99,
        fileDescriptorNameHint: 'song.m4a',
      );

      expect(safFdPort.readOnlyOpenUris, isEmpty);
      expect(safFdPort.readWriteOpenUris, isEmpty);
      expect(safFdPort.closedFds, isEmpty);
      expect(port.lastWriteRequest?.fileDescriptor, 99);
      expect(port.lastWriteRequest?.fileDescriptorNameHint, 'song.m4a');
    });
  });
}

class _FakeAudioTagPort implements AudioTagPort {
  AudioTagMeta meta = const AudioTagMeta(
    title: null,
    artist: null,
    album: null,
    durationMs: null,
    trackNumber: null,
  );
  bool hasLyricsValue = false;
  AudioTagException? hasLyricsError;
  AudioTagException? writeError;
  AudioTagWriteRequest? lastWriteRequest;
  AudioTagLyricsPayload? lyricsPayload;
  int? lastReadLyricsFileDescriptor;
  String? lastReadLyricsFileDescriptorNameHint;

  @override
  AudioTagMeta readMeta(String songPath) => meta;

  @override
  bool hasLyrics(String songPath) {
    final AudioTagException? error = hasLyricsError;
    if (error != null) {
      throw error;
    }
    return hasLyricsValue;
  }

  @override
  AudioTagLyricsPayload readLyrics(
    String songPath, {
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) {
    lastReadLyricsFileDescriptor = fileDescriptor;
    lastReadLyricsFileDescriptorNameHint = fileDescriptorNameHint;
    final AudioTagException? error = hasLyricsError;
    if (error != null) {
      throw error;
    }
    return lyricsPayload ??
        AudioTagLyricsPayload(
          plainText: null,
          syncedTracks: const <AudioTagSyncedTrack>[],
        );
  }

  @override
  void writeLyrics(AudioTagWriteRequest request) {
    lastWriteRequest = request;
    final AudioTagException? error = writeError;
    if (error != null) {
      throw error;
    }
  }
}

class _FakeAndroidSafFdPort implements AndroidSafFdPort {
  _FakeAndroidSafFdPort({required this.openResult});

  final AndroidSafOpenedFileDescriptor openResult;
  final List<String> readOnlyOpenUris = <String>[];
  final List<String> readWriteOpenUris = <String>[];
  final List<int> closedFds = <int>[];

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadOnlyFd(String uri) async {
    readOnlyOpenUris.add(uri);
    return openResult;
  }

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadWriteFd(String uri) async {
    readWriteOpenUris.add(uri);
    return openResult;
  }

  @override
  Future<void> closeFd(int fileDescriptor) async {
    closedFds.add(fileDescriptor);
  }
}

Lyrics _buildLyrics() {
  return Lyrics(
    songInfo: const SongInfo(source: Source.local, path: r'D:\song.mp3'),
    source: Source.local,
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
