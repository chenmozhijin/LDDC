import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LyricsPathTemplateFormatter', () {
    test('search 与 local match 共享同一组路径模板规则', () {
      final String songRoot = p.join(
        Directory.systemTemp.path,
        'lddc_path_template_song',
      );
      final String saveRoot = p.join(
        Directory.systemTemp.path,
        'lddc_path_template_lyrics',
      );
      final SongInfo info = SongInfo(
        source: Source.qm,
        path: p.join(songRoot, 'Singer', 'Demo.flac'),
        id: '12:3',
        title: 'Ti/tle:01',
        artist: SongArtist(<String>['Ar/tist', 'Second']),
        album: 'Al:bum',
      );

      final String searchPath = SearchPathFormatter.buildSavePath(
        folder: saveRoot,
        fileNameFormat: '%<artist> - %<title> (%<id>) [%<langs>].lrc',
        songInfo: info,
        lyricLangs: const <String>['orig', 'ts'],
      );
      final LocalMatchSavePathResolution resolution =
          LocalMatchSavePathResolver.resolve(
            saveMode: LocalMatchSaveMode.specify,
            fileNameMode: LocalMatchFileNameMode.formatByLyrics,
            localInfo: info,
            lyricsFormat: LyricsFormat.lineByLineLrc,
            fileNameFormat: '%<artist> - %<title> (%<id>) [%<langs>]',
            langs: const <String>['orig', 'ts'],
            saveRootPath: saveRoot,
            cloudInfo: info,
            allowPlaceholder: false,
            songRootPath: null,
          );

      expect(
        searchPath,
        p.join(saveRoot, 'Ar／tist／Second - Ti／tle：01 (12：3) [orig-ts].lrc'),
      );
      expect(resolution, isA<LocalMatchSavePathResolved>());
      expect((resolution as LocalMatchSavePathResolved).path, searchPath);
    });

    test('缺失 id 时 search 与 local match 都会移除占位块', () {
      final SongInfo info = SongInfo(
        source: Source.qm,
        path: r'D:\Music\Singer\OnlyTitle.flac',
        title: 'OnlyTitle',
        artist: SongArtist(<String>['Singer']),
      );

      final String searchPath = SearchPathFormatter.buildSavePath(
        folder: 'lyrics',
        fileNameFormat: '%<title> (%<id>).lrc',
        songInfo: info,
        lyricLangs: const <String>['orig'],
      );
      final LocalMatchSavePathResolution resolution =
          LocalMatchSavePathResolver.resolve(
            saveMode: LocalMatchSaveMode.specify,
            fileNameMode: LocalMatchFileNameMode.formatByLyrics,
            localInfo: info,
            lyricsFormat: LyricsFormat.lineByLineLrc,
            fileNameFormat: '%<title> (%<id>)',
            langs: const <String>['orig'],
            saveRootPath: 'lyrics',
            cloudInfo: info,
            allowPlaceholder: false,
            songRootPath: null,
          );

      expect(p.basename(searchPath), 'OnlyTitle.lrc');
      expect(searchPath, isNot(contains('%<id>')));
      expect(resolution, isA<LocalMatchSavePathResolved>());
      expect(
        p.basename((resolution as LocalMatchSavePathResolved).path),
        'OnlyTitle.lrc',
      );
    });

    test('sanitizePath 会保留 Windows 盘符并转义非法字符', () {
      expect(
        LyricsPathTemplateFormatter.sanitizePath(r'C:\Music:Root\A|B'),
        r'C:\Music：Root\A｜B',
      );
      expect(
        LyricsPathTemplateFormatter.sanitizePath(r'c:\Music:Root\A|B'),
        r'c:\Music：Root\A｜B',
      );
      expect(
        LyricsPathTemplateFormatter.sanitizePath('C:/Music:Root/A|B'),
        'C:/Music：Root/A｜B',
      );
    });

    test('sanitizeFileName 清理控制字符、尾随点空格和 Windows 设备名', () {
      expect(
        LyricsPathTemplateFormatter.sanitizeFileName('CON.lrc'),
        '＿CON.lrc',
      );
      expect(
        LyricsPathTemplateFormatter.sanitizeFileName('line\r\n.lrc. '),
        'line.lrc．　',
      );
      expect(LyricsPathTemplateFormatter.sanitizeFileName('\u0000'), '未命名');
    });
  });
}
