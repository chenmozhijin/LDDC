import 'dart:io';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CueParser', () {
    late Directory tempDir;
    late File cueFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lddc-cue-parser-');
      cueFile = File(p.join(tempDir.path, 'album.cue'));
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('parseCue 可解析全局与轨道级字段', () async {
      const String cueText = '''
TITLE "Album Title"
PERFORMER "Album Artist"
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Song A"
    PERFORMER "Track Artist"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    SONGWRITER "Writer B"
    PREGAP 00:00:10
    POSTGAP 00:00:20
    INDEX 01 01:00:00
    REM REPLAYGAIN_TRACK_GAIN "-5.00 dB"
''';
      await cueFile.writeAsString(cueText);

      final CueData cue = parseCue(cuePath: cueFile.path);
      expect(cue.title, 'Album Title');
      expect(cue.performer, 'Album Artist');
      expect(cue.files.length, 1);
      expect(cue.files.single.filename, 'disc.flac');
      expect(cue.files.single.tracks.length, 2);

      final CueTrack track1 = cue.files.single.tracks[0];
      expect(track1.id, '01');
      expect(track1.title, 'Song A');
      expect(track1.performer, 'Track Artist');
      expect(track1.indexes['01'], 0);

      final CueTrack track2 = cue.files.single.tracks[1];
      expect(track2.songwriter, 'Writer B');
      expect(track2.pregapMs, 133);
      expect(track2.postgapMs, 266);
      expect(track2.indexes['01'], 60000);
      expect(track2.replaygain['REPLAYGAIN_TRACK_GAIN'], '-5.00 dB');
    });

    test('CueData 可序列化后回放到主 isolate 继续消费', () async {
      const String cueText = '''
TITLE "Album Title"
PERFORMER "Album Artist"
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Song A"
    PERFORMER "Track Artist"
    INDEX 01 00:00:00
''';
      await cueFile.writeAsString(cueText);

      final CueData parsed = parseCue(cuePath: cueFile.path);
      final CueData restored = CueData.fromMap(parsed.toMap());

      expect(restored.path, cueFile.path);
      expect(restored.title, 'Album Title');
      expect(restored.performer, 'Album Artist');
      expect(restored.files, hasLength(1));
      expect(restored.files.single.filename, 'disc.flac');
      expect(restored.files.single.tracks.single.title, 'Song A');
      expect(restored.files.single.tracks.single.performer, 'Track Artist');
      expect(restored.files.single.tracks.single.indexes['01'], 0);
    });

    test('toSongInfos 可按 INDEX/PREGAP/POSTGAP 计算时长并映射 artist', () async {
      final File audioFile = File(p.join(tempDir.path, 'disc.flac'));
      await audioFile.writeAsBytes(<int>[0x00]);

      const String cueText = '''
TITLE "Album Title"
PERFORMER "Album Artist"
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Song A"
    PERFORMER "Track Artist"
    INDEX 01 00:00:00
    POSTGAP 00:00:10
  TRACK 02 AUDIO
    TITLE "Song B"
    INDEX 01 01:00:00
''';
      await cueFile.writeAsString(cueText);

      final CueData cue = parseCue(cuePath: cueFile.path);
      final List<SongInfo> infos = cue.toSongInfos(
        durationResolver: (String _) => 90000,
      );

      expect(infos.length, 2);

      final SongInfo first = infos[0];
      expect(first.title, 'Song A');
      expect(first.id, '01');
      expect(first.durationMs, 60133);
      expect(first.artist!.join('/'), 'Track Artist/Album Artist');
      expect(first.album, 'Album Title');
      expect(first.fromCue, isTrue);
      expect(first.path, audioFile.path);

      final SongInfo second = infos[1];
      expect(second.title, 'Song B');
      expect(second.id, '02');
      expect(second.durationMs, 30000);
      expect(second.artist!.join('/'), 'Album Artist');
      expect(second.fromCue, isTrue);
      expect(second.path, audioFile.path);
    });

    test('getAudioPath 支持同目录同名扩展回退', () async {
      final File fallbackAudio = File(p.join(tempDir.path, 'album.flac'));
      await fallbackAudio.writeAsBytes(<int>[0x01]);

      const String cueText = '''
FILE "missing.bin" WAVE
  TRACK 01 AUDIO
    TITLE "Song A"
    INDEX 01 00:00:00
''';
      await cueFile.writeAsString(cueText);

      final CueData cue = parseCue(cuePath: cueFile.path);
      final String? resolved = cue.getAudioPath(cue.files.single);
      expect(resolved, fallbackAudio.path);
      expect(cue.getAudioPaths(), <String>[fallbackAudio.path]);
    });

    test('toSongInfos 在缺少 INDEX 01 时抛出错误', () async {
      const String cueText = '''
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "No Index"
''';
      await cueFile.writeAsString(cueText);

      final CueData cue = parseCue(cuePath: cueFile.path);
      expect(
        () => cue.toSongInfos(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('INDEX 01'),
          ),
        ),
      );
    });

    test('toSongInfos 支持注入 audioPathResolver 与音频存在性判断', () async {
      const String cueText = '''
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    TITLE "Song A"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Song B"
    INDEX 01 00:30:00
''';
      await cueFile.writeAsString(cueText);
      final CueData cue = parseCue(cuePath: cueFile.path);

      final List<SongInfo> infos = cue.toSongInfos(
        audioPathResolver: (CueData _, CueAudioFile unusedFile) =>
            'content://media/external/audio/media/11',
        audioExistsChecker: (String path) => path.startsWith('content://'),
        durationResolver: (String path) =>
            path == 'content://media/external/audio/media/11' ? 60000 : null,
      );

      expect(infos, hasLength(2));
      expect(
        infos.every(
          (SongInfo item) =>
              item.path == 'content://media/external/audio/media/11',
        ),
        isTrue,
      );
      expect(infos[0].durationMs, 30000);
      expect(infos[1].durationMs, 30000);
      expect(
        cue.getAudioPaths(
          audioPathResolver: (CueData _, CueAudioFile unusedFile) =>
              'content://media/external/audio/media/11',
          audioExistsChecker: (String path) => path.startsWith('content://'),
        ),
        <String>['content://media/external/audio/media/11'],
      );
    });

    test('CUE 时间第三段按 75fps frame 解析', () {
      final CueData cue = parseCue(
        cuePath: cueFile.path,
        data: '''
FILE "disc.flac" WAVE
  TRACK 01 AUDIO
    INDEX 01 00:00:75
''',
      );

      expect(cue.files.single.tracks.single.indexes['01'], 1000);
    });

    test('新 FILE 块会清空旧轨道上下文', () {
      final CueData cue = parseCue(
        cuePath: cueFile.path,
        data: '''
FILE "disc-a.flac" WAVE
  TRACK 01 AUDIO
    TITLE "First Track"
    INDEX 01 00:00:00
FILE "disc-b.flac" WAVE
    TITLE "Stray Track Command"
''',
      );

      expect(cue.files, hasLength(2));
      expect(cue.files.first.tracks.single.title, 'First Track');
      expect(cue.files.last.tracks, isEmpty);
    });
  });
}
