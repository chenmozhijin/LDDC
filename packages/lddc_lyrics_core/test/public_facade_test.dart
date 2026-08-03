import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:test/test.dart';

void main() {
  test('LyricsParser 与 LyricsConverter 复用公开模型完成解析转换', () {
    final ParsedLyricsPayload parsed = LyricsParser().parseText(
      '[00:01.00]First line\n[00:02.50]Second line\n',
      path: 'sample.lrc',
    );
    final Lyrics lyrics = Lyrics(
      songInfo: const SongInfo(source: Source.local, title: 'Sample'),
      source: Source.local,
      data: parsed.lyricsData,
      types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
      tags: parsed.tags,
    );

    final String output = const LyricsConverter().convert(
      lyrics: lyrics,
      langs: const <String>['orig'],
      format: LyricsFormat.lineByLineLrc,
    );

    expect(output, contains('[00:01.000]First line'));
    expect(output, contains('[00:02.500]Second line'));
  });
}
