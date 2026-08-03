import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('AudioTagBackgroundExecutor', () {
    late _FakeWorkerRunner runner;

    setUp(() {
      runner = _FakeWorkerRunner();
      AudioTagBackgroundExecutor.debugSetWorkerRunnerForTest(runner);
    });

    tearDown(() {
      AudioTagBackgroundExecutor.debugResetWorkerRunnerForTest();
    });

    test('readLyricsText 通过受控 runner 执行，超时错误不会被吞掉', () async {
      runner.readError = TimeoutException('read timeout');

      await expectLater(
        AudioTagBackgroundExecutor.readLyricsText(r'C:\music\song.mp3'),
        throwsA(isA<TimeoutException>()),
      );

      expect(runner.readOperations, <String>['readLyricsText']);
    });

    test('桌面普通路径支持后台执行，content URI、fd 和空路径不支持', () {
      expect(
        AudioTagBackgroundExecutor.supportsBackgroundPath(r'C:\music\song.mp3'),
        Platform.isWindows || Platform.isLinux || Platform.isMacOS,
      );
      expect(
        AudioTagBackgroundExecutor.supportsBackgroundPath(
          'content://media/song',
        ),
        isFalse,
      );
      expect(
        AudioTagBackgroundExecutor.supportsBackgroundPath(
          r'C:\music\song.mp3',
          fileDescriptor: 7,
        ),
        isFalse,
      );
      expect(AudioTagBackgroundExecutor.supportsBackgroundPath(''), isFalse);
    });

    test('读取入口解析 SongInfo、时长、歌词存在状态和文本', () async {
      runner.readResult = <Map<String, Object?>>[
        const SongInfo(
          source: Source.local,
          path: r'C:\music\song.mp3',
          title: 'Song',
        ).toMap(),
      ];
      final List<SongInfo> infos =
          await AudioTagBackgroundExecutor.readSongInfos(r'C:\music\song.mp3');
      runner.readResult = 123000;
      final int? duration = await AudioTagBackgroundExecutor.readDurationMs(
        r'C:\music\song.mp3',
      );
      runner.readResult = true;
      final bool hasLyrics = await AudioTagBackgroundExecutor.hasLyricsTag(
        r'C:\music\song.mp3',
      );
      runner.readResult = null;
      final String? text = await AudioTagBackgroundExecutor.readLyricsText(
        r'C:\music\song.mp3',
      );

      expect(infos.single.title, 'Song');
      expect(duration, 123000);
      expect(hasLyrics, isTrue);
      expect(text, isNull);
      expect(runner.readOperations, <String>[
        'readSongInfos',
        'readDurationMs',
        'hasLyricsTag',
        'readLyricsText',
      ]);
    });

    test('metadata 端口复用后台读取入口', () async {
      const AudioTagBackgroundMetadataPort port =
          AudioTagBackgroundMetadataPort();
      runner.readResult = <Map<String, Object?>>[
        const SongInfo(source: Source.local, title: 'Port Song').toMap(),
      ];
      expect((await port.readSongInfos('song.mp3')).single.title, 'Port Song');
      runner.readResult = 456;
      expect(await port.readDurationMs('song.mp3'), 456);
    });

    test('writeLyricsTag 保留写入结果未知错误，交给批量任务停止后续条目', () async {
      runner.writeError = const AudioTagException(
        code: AudioTagErrorCode.writeFailed,
        message: 'write result unknown',
        writeResultUnknown: true,
      );

      await expectLater(
        AudioTagBackgroundExecutor.writeLyricsTag(
          songPath: r'C:\music\song.mp3',
          lyricsText: 'lyrics',
          lyrics: _buildLyrics(r'C:\music\song.mp3'),
          id3Version: Id3Version.v24,
        ),
        throwsA(
          isA<AudioTagException>().having(
            (AudioTagException error) => error.writeResultUnknown,
            'writeResultUnknown',
            isTrue,
          ),
        ),
      );

      expect(runner.writePayload?['songPath'], r'C:\music\song.mp3');
    });

    test('写入 payload 只包含 orig 时间轴并保留 ID3 版本', () async {
      await AudioTagBackgroundExecutor.writeLyricsTag(
        songPath: r'C:\music\song.mp3',
        lyricsText: 'plain lyrics',
        lyrics: _buildLyrics(r'C:\music\song.mp3'),
        id3Version: Id3Version.v24,
      );

      final Map<String, Object?> payload = runner.writePayload!;
      final Map<Object?, Object?> tagLyrics =
          payload['tagLyrics']! as Map<Object?, Object?>;
      final List<Object?> orig = tagLyrics['orig']! as List<Object?>;
      final Map<Object?, Object?> line = orig.single as Map<Object?, Object?>;
      final List<Object?> words = line['words']! as List<Object?>;

      expect(payload['lyricsText'], 'plain lyrics');
      expect(payload['id3Version'], Id3Version.v24.value);
      expect(tagLyrics.keys, <Object?>['orig']);
      expect(line['startMs'], 0);
      expect(line['endMs'], 1000);
      expect((words.single as Map<Object?, Object?>)['text'], '歌词');
    });
  });
}

final class _FakeWorkerRunner implements AudioTagBackgroundWorkerRunner {
  final List<String> readOperations = <String>[];
  Map<String, Object?>? writePayload;
  Object? readResult;
  Object? readError;
  Object? writeError;

  @override
  Future<Object?> runRead({
    required String operation,
    required Map<String, Object?> payload,
    required Duration timeout,
  }) async {
    readOperations.add(operation);
    final Object? error = readError;
    if (error != null) {
      throw error;
    }
    return readResult;
  }

  @override
  Future<void> runWrite({
    required Map<String, Object?> payload,
    required Duration timeout,
  }) async {
    writePayload = payload;
    final Object? error = writeError;
    if (error != null) {
      throw error;
    }
  }
}

Lyrics _buildLyrics(String songPath) {
  return Lyrics(
    songInfo: SongInfo(source: Source.local, path: songPath),
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
