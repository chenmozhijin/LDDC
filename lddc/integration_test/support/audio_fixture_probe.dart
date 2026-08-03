import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

class IntegrationAudioProbeResult {
  const IntegrationAudioProbeResult({
    required this.durationMs,
    required this.songInfos,
    required this.embeddedLyricsText,
  });

  final int? durationMs;
  final List<SongInfo> songInfos;
  final String? embeddedLyricsText;
}

Future<IntegrationAudioProbeResult> probeAudioFixture({
  required LocalMatchMediaGateway mediaGateway,
  required String songPath,
}) async {
  final int? durationMs = await mediaGateway.readAudioDurationMs(songPath);
  final List<SongInfo> songInfos = await mediaGateway.readAudioSongInfos(
    songPath,
  );
  final String? embeddedLyricsText = await mediaGateway.readAudioLyricsText(
    songPath: songPath,
  );
  return IntegrationAudioProbeResult(
    durationMs: durationMs,
    songInfos: songInfos,
    embeddedLyricsText: embeddedLyricsText,
  );
}

void expectProbeDurationWithin({
  required int expectedDurationMs,
  required int? actualDurationMs,
  int toleranceMs = 1500,
}) {
  expect(actualDurationMs, isNotNull);
  expect(
    (actualDurationMs! - expectedDurationMs).abs(),
    lessThanOrEqualTo(toleranceMs),
  );
}

Lyrics buildFixtureLyrics({
  required SongInfo songInfo,
  required String lyricsText,
  required int durationMs,
}) {
  return Lyrics(
    songInfo: songInfo,
    source: songInfo.source,
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: durationMs,
          words: <LyricsWord>[
            LyricsWord(startMs: 0, endMs: durationMs, text: lyricsText),
          ],
        ),
      ],
    },
  );
}
