import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/i18n/lyrics_ui_host_mapper.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  test('歌词语言摘要由宿主 locale 决定英文标签和标点', () {
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));
    final Lyrics lyrics = Lyrics(
      songInfo: const SongInfo(source: Source.local, title: 'Demo'),
      source: Source.local,
      data: <String, LyricsData>{
        'orig': <LyricsLine>[_line('Original')],
        'ts': <LyricsLine>[_line('Translation')],
      },
      types: const <String, LyricsType>{
        'orig': LyricsType.lineByLine,
        'ts': LyricsType.lineByLine,
      },
    );

    expect(
      lyricsLanguageSummaryText(
        lyrics: lyrics,
        strings: l10n.toLyricsUiStrings(),
      ),
      'Original (Line-timed) · Translation (Line-timed)',
    );
  });
}

LyricsLine _line(String text) => LyricsLine(
  startMs: 0,
  endMs: 1000,
  words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 1000, text: text)],
);
