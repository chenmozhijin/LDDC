import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SearchPathFormatter', () {
    test('占位符替换与非法字符转义对齐Python版', () {
      final SongInfo info = SongInfo(
        source: Source.qm,
        id: '12:3',
        title: 'Ti/tle:01',
        artist: SongArtist(<String>['Ar/tist', 'Second']),
      );

      final String savePath = SearchPathFormatter.buildSavePath(
        folder: r'C:\Save\%<artist>',
        fileNameFormat: '%<artist> - %<title> (%<id>) [%<langs>].lrc',
        songInfo: info,
        lyricLangs: const <String>['orig', 'ts'],
      );

      expect(
        savePath,
        p.normalize(
          r'C:\Save\Ar／tist／Second\Ar／tist／Second - Ti／tle：01 (12：3) [orig-ts].lrc',
        ),
      );
    });

    test('缺失 id 时会移除 (%<id>) 占位块', () {
      final SongInfo info = SongInfo(
        source: Source.qm,
        title: 'OnlyTitle',
        artist: SongArtist(<String>['Singer']),
      );

      final String savePath = SearchPathFormatter.buildSavePath(
        folder: 'lyrics',
        fileNameFormat: '%<title> (%<id>).lrc',
        songInfo: info,
        lyricLangs: const <String>['orig'],
      );

      expect(savePath, isNot(contains('%<id>')));
      expect(savePath, isNot(contains('(%<id>)')));
      expect(p.basename(savePath), 'OnlyTitle.lrc');
    });

    test('buildFileName 会生成不含目录的建议文件名', () {
      final SongInfo info = SongInfo(
        source: Source.qm,
        id: 'A/01',
        title: 'Title:01',
        artist: SongArtist(<String>['Singer']),
      );

      final String fileName = SearchPathFormatter.buildFileName(
        fileNameFormat: '%<artist> - %<title> (%<id>).lrc',
        songInfo: info,
        lyricLangs: const <String>['orig'],
      );

      expect(fileName, 'Singer - Title：01 (A／01).lrc');
      expect(fileName.contains(r'\'), isFalse);
      expect(fileName.contains('/'), isFalse);
    });
  });
}
