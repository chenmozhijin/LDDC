import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LyricsSavePlanner', () {
    test('Search 与 LocalMatch 使用相同模板时生成一致文件名', () {
      final SongInfo song = SongInfo(
        source: Source.local,
        path: r'C:\Music\demo.mp3',
        title: 'Ti/tle',
        artist: SongArtist(<String>['Ar/tist']),
      );

      final LyricsSavePlan searchPlan = LyricsSavePlanner.planSearch(
        folder: r'C:\Lyrics',
        fileNameFormat: '%<artist> - %<title> [%<langs>]',
        songInfo: song,
        lyricLangs: const <String>['orig', 'ts'],
        lyricsFormat: LyricsFormat.lineByLineLrc,
      );
      final LyricsSavePlan localPlan = LyricsSavePlanner.planLocalMatch(
        directoryMode: LyricsSaveDirectoryMode.folder,
        fileNameMode: LyricsSaveFileNameMode.templateBySong,
        localInfo: song,
        lyricsFormat: LyricsFormat.lineByLineLrc,
        fileNameFormat: '%<artist> - %<title> [%<langs>]',
        lyricLangs: const <String>['orig', 'ts'],
        saveRootPath: r'C:\Lyrics',
        lyricsInfo: null,
        allowLyricsPlaceholder: false,
        songRootPath: null,
      );

      expect(searchPlan.isSuccess, isTrue);
      expect(localPlan.isSuccess, isTrue);
      expect(localPlan.fileName, searchPlan.fileName);
      expect(localPlan.displayPath, searchPlan.displayPath);
      expect(searchPlan.fileName, 'Ar／tist - Ti／tle [orig-ts].lrc');
    });

    test('LocalMatch mirror 缺少根目录时返回明确错误', () {
      final LyricsSavePlan plan = LyricsSavePlanner.planLocalMatch(
        directoryMode: LyricsSaveDirectoryMode.mirrorSourceRoot,
        fileNameMode: LyricsSaveFileNameMode.sourceBasename,
        localInfo: const SongInfo(
          source: Source.local,
          path: r'C:\Music\demo.mp3',
        ),
        lyricsFormat: LyricsFormat.lineByLineLrc,
        fileNameFormat: '%<title>',
        lyricLangs: const <String>['orig'],
        saveRootPath: r'C:\Lyrics',
        lyricsInfo: null,
        allowLyricsPlaceholder: false,
        songRootPath: null,
      );

      expect(plan.isSuccess, isFalse);
      expect(plan.errorCode, LyricsSavePlanErrorCode.missingSongRoot);
    });

    test('LocalMatch 缺少歌曲路径或保存根时返回对应错误', () {
      final LyricsSavePlan missingSong = LyricsSavePlanner.planLocalMatch(
        directoryMode: LyricsSaveDirectoryMode.songDirectory,
        fileNameMode: LyricsSaveFileNameMode.sourceBasename,
        localInfo: const SongInfo(source: Source.local),
        lyricsFormat: LyricsFormat.lineByLineLrc,
        fileNameFormat: '%<title>',
        lyricLangs: const <String>['orig'],
        saveRootPath: null,
        lyricsInfo: null,
        allowLyricsPlaceholder: false,
        songRootPath: null,
      );
      final LyricsSavePlan missingMirrorRoot = LyricsSavePlanner.planLocalMatch(
        directoryMode: LyricsSaveDirectoryMode.mirrorSourceRoot,
        fileNameMode: LyricsSaveFileNameMode.sourceBasename,
        localInfo: const SongInfo(source: Source.local, path: 'music/demo.mp3'),
        lyricsFormat: LyricsFormat.lineByLineLrc,
        fileNameFormat: '%<title>',
        lyricLangs: const <String>['orig'],
        saveRootPath: '  ',
        lyricsInfo: null,
        allowLyricsPlaceholder: false,
        songRootPath: 'music',
      );
      final LyricsSavePlan missingFolderRoot = LyricsSavePlanner.planLocalMatch(
        directoryMode: LyricsSaveDirectoryMode.folder,
        fileNameMode: LyricsSaveFileNameMode.sourceBasename,
        localInfo: const SongInfo(source: Source.local, path: 'music/demo.mp3'),
        lyricsFormat: LyricsFormat.lineByLineLrc,
        fileNameFormat: '%<title>',
        lyricLangs: const <String>['orig'],
        saveRootPath: null,
        lyricsInfo: null,
        allowLyricsPlaceholder: false,
        songRootPath: null,
      );

      expect(missingSong.errorCode, LyricsSavePlanErrorCode.missingSongPath);
      expect(
        missingMirrorRoot.errorCode,
        LyricsSavePlanErrorCode.missingSaveRoot,
      );
      expect(
        missingFolderRoot.errorCode,
        LyricsSavePlanErrorCode.missingSaveRoot,
      );
    });

    test('CUE sourceBasename 缺少歌词信息时按占位策略处理', () {
      const SongInfo cueSong = SongInfo(
        source: Source.local,
        path: 'music/disc.flac',
        title: 'Cue Track',
        fromCue: true,
      );
      LyricsSavePlan plan({required bool allowPlaceholder}) {
        return LyricsSavePlanner.planLocalMatch(
          directoryMode: LyricsSaveDirectoryMode.songDirectory,
          fileNameMode: LyricsSaveFileNameMode.sourceBasename,
          localInfo: cueSong,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          fileNameFormat: 'track-placeholder',
          lyricLangs: const <String>['orig'],
          saveRootPath: null,
          lyricsInfo: null,
          allowLyricsPlaceholder: allowPlaceholder,
          songRootPath: null,
        );
      }

      expect(
        plan(allowPlaceholder: false).errorCode,
        LyricsSavePlanErrorCode.missingLyricsInfo,
      );
      expect(plan(allowPlaceholder: true).fileName, 'track-placeholder.lrc');
    });

    test('templateByLyrics 使用远端信息，缺失时可选择占位或报错', () {
      const SongInfo local = SongInfo(
        source: Source.local,
        path: 'music/local.mp3',
        title: 'Local',
      );
      const SongInfo remote = SongInfo(source: Source.qm, title: 'Remote');
      LyricsSavePlan plan({SongInfo? lyricsInfo, required bool placeholder}) {
        return LyricsSavePlanner.planLocalMatch(
          directoryMode: LyricsSaveDirectoryMode.songDirectory,
          fileNameMode: LyricsSaveFileNameMode.templateByLyrics,
          localInfo: local,
          lyricsFormat: LyricsFormat.lineByLineLrc,
          fileNameFormat: '%<title>',
          lyricLangs: const <String>['orig'],
          saveRootPath: null,
          lyricsInfo: lyricsInfo,
          allowLyricsPlaceholder: placeholder,
          songRootPath: null,
        );
      }

      expect(
        plan(placeholder: false).errorCode,
        LyricsSavePlanErrorCode.missingLyricsInfo,
      );
      expect(plan(placeholder: true).fileName, '%<title>.lrc');
      final LyricsSavePlan remotePlan = plan(
        lyricsInfo: remote,
        placeholder: false,
      );
      expect(remotePlan.fileName, 'Remote.lrc');
      expect(identical(remotePlan.request!.songInfo, remote), isTrue);
    });

    test('templateBySong 在普通歌曲缺少标题时回退源文件名', () {
      final LyricsSavePlan plan = LyricsSavePlanner.planLocalMatch(
        directoryMode: LyricsSaveDirectoryMode.songDirectory,
        fileNameMode: LyricsSaveFileNameMode.templateBySong,
        localInfo: const SongInfo(
          source: Source.local,
          path: 'music/fallback-name.mp3',
        ),
        lyricsFormat: LyricsFormat.srt,
        fileNameFormat: '%<title>',
        lyricLangs: const <String>['orig'],
        saveRootPath: null,
        lyricsInfo: null,
        allowLyricsPlaceholder: false,
        songRootPath: null,
      );

      expect(plan.fileName, 'fallback-name.srt');
    });

    test('BatchConvert 输出路径复用保存规划', () {
      final LyricsSavePlan plan = LyricsSavePlanner.planBatchConvert(
        sourcePath: p.join('input', 'demo.ass'),
        targetFormat: LyricsFormat.srt,
        saveRootPath: p.join('out'),
      );

      expect(plan.isSuccess, isTrue);
      expect(plan.displayPath, p.join('out', 'demo.srt'));
      expect(plan.fileName, 'demo.srt');
    });

    test('BatchConvert 空源路径返回明确错误', () {
      final LyricsSavePlan plan = LyricsSavePlanner.planBatchConvert(
        sourcePath: '   ',
        targetFormat: LyricsFormat.srt,
      );

      expect(plan.isSuccess, isFalse);
      expect(plan.errorCode, LyricsSavePlanErrorCode.missingSongPath);
    });

    test('LocalMatch mirror 拒绝将根目录外歌曲写出保存根目录', () {
      final LyricsSavePlan plan = LyricsSavePlanner.planLocalMatch(
        directoryMode: LyricsSaveDirectoryMode.mirrorSourceRoot,
        fileNameMode: LyricsSaveFileNameMode.sourceBasename,
        localInfo: SongInfo(
          source: Source.local,
          path: p.join('outside', 'demo.mp3'),
        ),
        lyricsFormat: LyricsFormat.lineByLineLrc,
        fileNameFormat: '%<title>',
        lyricLangs: const <String>['orig'],
        saveRootPath: p.join('lyrics'),
        lyricsInfo: null,
        allowLyricsPlaceholder: false,
        songRootPath: p.join('music'),
      );

      expect(plan.isSuccess, isFalse);
      expect(plan.errorCode, LyricsSavePlanErrorCode.songOutsideRoot);
    });

    test('保存请求持有歌词语言快照', () {
      final List<String> langs = <String>['orig', 'ts'];
      final LyricsSavePlan plan = LyricsSavePlanner.planSearch(
        folder: 'lyrics',
        fileNameFormat: '%<title>',
        songInfo: const SongInfo(source: Source.qm, title: 'Song'),
        lyricLangs: langs,
        lyricsFormat: LyricsFormat.lineByLineLrc,
      );

      langs.clear();

      expect(plan.request!.lyricLangs, <String>['orig', 'ts']);
      expect(
        () => plan.request!.lyricLangs.add('roma'),
        throwsUnsupportedError,
      );
    });
  });
}
