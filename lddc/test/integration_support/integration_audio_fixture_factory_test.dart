import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../../integration_test/support/audio_fixture_factory.dart';
import '../../integration_test/support/audio_fixture_probe.dart';
import '../../integration_test/support/integration_harness.dart';

void main() {
  test('离线音频夹具使用内存元数据，不执行 ffmpeg 或真实标签库', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'lddc_offline_audio_fixture_test_',
    );
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });
    final IntegrationHybridMediaGateway gateway = IntegrationHybridMediaGateway(
      realMediaEnabled: false,
    );
    final IntegrationAudioFixtureFactory factory =
        IntegrationAudioFixtureFactory(
          ffmpegExecutable: 'missing-ffmpeg-must-not-run',
          mediaGateway: gateway,
        );
    const IntegrationAudioFixtureSpec spec = IntegrationAudioFixtureSpec(
      pathSegments: <String>['fixture', 'offline.flac'],
      format: IntegrationAudioFormat.flac,
      durationMs: 32000,
      title: 'Offline Fixture',
      artists: <String>['LDDC'],
      album: 'Integration',
      embeddedLyricsText: '[00:00.00]seed lyrics',
    );

    final IntegrationGeneratedAudioFixture fixture = await factory
        .createAudioFixture(rootDirectory: root, spec: spec);
    final IntegrationAudioProbeResult probe = await probeAudioFixture(
      mediaGateway: gateway,
      songPath: fixture.path,
    );

    expect(fixture.file.existsSync(), isTrue);
    expect(probe.durationMs, spec.durationMs);
    expect(probe.songInfos.single.title, spec.title);
    expect(probe.embeddedLyricsText, spec.embeddedLyricsText);
    expect(await gateway.hasLyricsTag(fixture.path), isTrue);
    expect(gateway.writes, isEmpty);

    final SongInfo songInfo = probe.songInfos.single;
    final Lyrics lyrics = buildFixtureLyrics(
      songInfo: songInfo,
      lyricsText: '[00:00.00]updated lyrics',
      durationMs: spec.durationMs,
    );
    await gateway.writeLyricsTag(
      songPath: fixture.path,
      lyricsText: '[00:00.00]updated lyrics',
      lyrics: lyrics,
      id3Version: Id3Version.v24,
    );

    expect(gateway.writes, hasLength(1));
    expect(
      await gateway.readAudioLyricsText(songPath: fixture.path),
      contains('updated lyrics'),
    );
  });
}
