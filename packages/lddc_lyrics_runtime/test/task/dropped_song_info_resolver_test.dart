import 'dart:io';
import 'dart:async';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  group('DroppedSongInfoResolver', () {
    test('.cue + index 会按 AIMP 轨道索引解析为对应 SongInfo', () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'dropped-song-info-resolver-index-',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final File audioFile = File(
        '${directory.path}${Platform.pathSeparator}disc.wav',
      );
      await audioFile.writeAsBytes(const <int>[]);
      final File cueFile = File(
        '${directory.path}${Platform.pathSeparator}disc.cue',
      );
      await cueFile.writeAsString(_cueText());
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()..durations[audioFile.path] = 240000;
      final DroppedSongInfoResolver resolver = DroppedSongInfoResolver(
        mediaGateway: mediaGateway,
      );

      final SongInfo songInfo = await resolver.resolve(
        path: cueFile.path,
        index: '1',
      );

      expect(songInfo.fromCue, isTrue);
      expect(songInfo.id, '02');
      expect(songInfo.title, 'Second');
      expect(songInfo.path, audioFile.path);
      expect(mediaGateway.readAudioSongInfosCallCount, 0);
    });

    test('.cue + track 会按轨号选中对应歌曲', () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'dropped-song-info-resolver-track-',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final File audioFile = File(
        '${directory.path}${Platform.pathSeparator}disc.wav',
      );
      await audioFile.writeAsBytes(const <int>[]);
      final File cueFile = File(
        '${directory.path}${Platform.pathSeparator}disc.cue',
      );
      await cueFile.writeAsString(_cueText());
      final DroppedSongInfoResolver resolver = DroppedSongInfoResolver(
        mediaGateway: _FakeLocalMatchMediaGateway()
          ..durations[audioFile.path] = 240000,
      );

      final SongInfo songInfo = await resolver.resolve(
        path: cueFile.path,
        track: '2',
      );

      expect(songInfo.id, '02');
      expect(songInfo.title, 'Second');
      expect(songInfo.path, audioFile.path);
    });

    test('普通文件包含多个歌曲且未指定轨道时返回明确错误', () async {
      final DroppedSongInfoResolver resolver = DroppedSongInfoResolver(
        mediaGateway: _FakeLocalMatchMediaGateway()
          ..songInfosByPath['D:/music/demo.flac'] = <SongInfo>[
            _song(id: '01', title: 'First'),
            _song(id: '02', title: 'Second'),
          ],
      );

      await expectLater(
        resolver.resolve(path: 'D:/music/demo.flac'),
        throwsA(
          isA<DroppedSongInfoResolveException>().having(
            (DroppedSongInfoResolveException error) => error.message,
            'message',
            '文件 D:/music/demo.flac 中包含多个歌曲',
          ),
        ),
      );
    });

    test('普通音频 metadata 读取保持真实异步边界', () async {
      final Completer<void> metadataGate = Completer<void>();
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()
            ..metadataGate = metadataGate
            ..songInfosByPath['D:/music/demo.flac'] = <SongInfo>[
              _song(id: '01', title: 'First'),
            ];
      final DroppedSongInfoResolver resolver = DroppedSongInfoResolver(
        mediaGateway: mediaGateway,
      );

      final Future<SongInfo> pending = resolver.resolve(
        path: 'D:/music/demo.flac',
      );
      await Future<void>.delayed(Duration.zero);

      expect(mediaGateway.readAudioSongInfosCallCount, 1);
      expect(metadataGate.isCompleted, isFalse);
      metadataGate.complete();
      expect(await pending, isA<SongInfo>());
    });
  });
}

String _cueText() {
  return '''
TITLE "Album"
PERFORMER "Singer"
FILE "disc.wav" WAVE
  TRACK 01 AUDIO
    TITLE "First"
    PERFORMER "Singer"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Second"
    PERFORMER "Singer"
    INDEX 01 01:00:00
''';
}

SongInfo _song({required String id, required String title}) {
  return SongInfo(
    source: Source.local,
    id: id,
    title: title,
    artist: SongArtist(<String>['Singer']),
    path: 'D:/music/demo.flac',
  );
}

class _FakeLocalMatchMediaGateway implements LocalMatchMediaGateway {
  final Map<String, List<SongInfo>> songInfosByPath =
      <String, List<SongInfo>>{};
  final Map<String, int?> durations = <String, int?>{};
  int readAudioSongInfosCallCount = 0;
  Completer<void>? metadataGate;

  @override
  Future<bool> hasLyricsTag(String songPath) async => false;

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async {
    readAudioSongInfosCallCount += 1;
    await metadataGate?.future;
    return songInfosByPath[audioPath] ?? const <SongInfo>[];
  }

  @override
  Future<int?> readAudioDurationMs(String audioPath) async =>
      durations[audioPath];

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
  }) async {}
}
