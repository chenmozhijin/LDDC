import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:path/path.dart' as p;

import 'audio_fixture_probe.dart';
import 'integration_harness.dart';

enum IntegrationAudioFormat { mp3, flac, wav }

extension on IntegrationAudioFormat {
  List<String> get codecArgs => switch (this) {
    IntegrationAudioFormat.mp3 => const <String>[
      '-c:a',
      'libmp3lame',
      '-q:a',
      '9',
    ],
    IntegrationAudioFormat.flac => const <String>['-c:a', 'flac'],
    IntegrationAudioFormat.wav => const <String>['-c:a', 'pcm_s16le'],
  };
}

class IntegrationAudioFixtureSpec {
  const IntegrationAudioFixtureSpec({
    required this.pathSegments,
    required this.format,
    required this.durationMs,
    required this.title,
    required this.artists,
    this.album,
    this.track,
    this.date,
    this.embeddedLyricsText,
  });

  final List<String> pathSegments;
  final IntegrationAudioFormat format;
  final int durationMs;
  final String title;
  final List<String> artists;
  final String? album;
  final String? track;
  final String? date;
  final String? embeddedLyricsText;
}

class IntegrationGeneratedAudioFixture {
  const IntegrationGeneratedAudioFixture({
    required this.path,
    required this.file,
    required this.spec,
  });

  final String path;
  final File file;
  final IntegrationAudioFixtureSpec spec;
}

class IntegrationAudioFixtureFactory {
  IntegrationAudioFixtureFactory({
    required this.ffmpegExecutable,
    required this.mediaGateway,
  });

  final String ffmpegExecutable;
  final IntegrationHybridMediaGateway mediaGateway;

  Future<IntegrationGeneratedAudioFixture> createAudioFixture({
    required Directory rootDirectory,
    required IntegrationAudioFixtureSpec spec,
  }) async {
    final String targetPath = p.joinAll(<String>[
      rootDirectory.path,
      ...spec.pathSegments,
    ]);
    final File targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    if (targetFile.existsSync()) {
      await targetFile.delete();
    }

    if (mediaGateway.realMediaEnabled) {
      final List<String> args = <String>[
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-f',
        'lavfi',
        '-i',
        'anullsrc=r=44100:cl=stereo',
        '-t',
        (spec.durationMs / 1000).toStringAsFixed(3),
        '-metadata',
        'title=${spec.title}',
        '-metadata',
        'artist=${spec.artists.join('/')}',
        if (spec.album != null) ...<String>['-metadata', 'album=${spec.album}'],
        if (spec.track != null) ...<String>['-metadata', 'track=${spec.track}'],
        if (spec.date != null) ...<String>['-metadata', 'date=${spec.date}'],
        ...spec.format.codecArgs,
        targetPath,
      ];
      final ProcessResult result = await Process.run(ffmpegExecutable, args);
      if (result.exitCode != 0) {
        throw TestFailure(
          'ffmpeg 生成音频失败: ${result.stderr}\n命令: $ffmpegExecutable ${args.join(' ')}',
        );
      }
    } else {
      // 离线 UI 流程只要求路径可被目录扫描器发现；音频内容、时长与标签由内存
      // 网关提供，避免移动端测试错误依赖主机可执行文件或 native taglib。
      await targetFile.writeAsBytes(const <int>[0], flush: true);
    }
    if (!targetFile.existsSync()) {
      throw TestFailure('音频夹具生成后不存在: $targetPath');
    }

    final SongInfo songInfo = SongInfo(
      source: Source.local,
      path: targetPath,
      title: spec.title,
      artist: SongArtist(spec.artists),
      album: spec.album,
      durationMs: spec.durationMs,
      id: spec.track,
    );
    final String? embeddedLyricsText = spec.embeddedLyricsText;
    await mediaGateway.registerAudioFixture(
      songPath: targetPath,
      songInfo: songInfo,
      durationMs: spec.durationMs,
      embeddedLyricsText: embeddedLyricsText,
      embeddedLyrics: embeddedLyricsText == null
          ? null
          : buildFixtureLyrics(
              songInfo: songInfo,
              lyricsText: embeddedLyricsText,
              durationMs: spec.durationMs,
            ),
    );

    return IntegrationGeneratedAudioFixture(
      path: targetPath,
      file: targetFile,
      spec: spec,
    );
  }

  Future<List<IntegrationGeneratedAudioFixture>> createAudioFixtureBatch({
    required Directory rootDirectory,
    required Iterable<IntegrationAudioFixtureSpec> specs,
  }) async {
    final List<IntegrationGeneratedAudioFixture> results =
        <IntegrationGeneratedAudioFixture>[];
    for (final IntegrationAudioFixtureSpec spec in specs) {
      results.add(
        await createAudioFixture(rootDirectory: rootDirectory, spec: spec),
      );
    }
    return results;
  }
}
