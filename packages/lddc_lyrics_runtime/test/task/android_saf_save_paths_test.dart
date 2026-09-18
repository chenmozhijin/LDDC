import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  const String songTree =
      'content://com.android.externalstorage.documents/tree/primary%3AMusic';
  const String saveTree =
      'content://com.android.externalstorage.documents/tree/primary%3ALyrics';
  const String nestedSongUri =
      'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2FAlbum%2Fa.mp3';
  const String rootLevelSongUri =
      'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2Fb.mp3';
  const String outsideTreeSongUri =
      'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AOther%2Fc.mp3';

  group('safDocumentIdOf', () {
    test('文档 URI 取第 4 段并与平台 getDocumentId 一致', () {
      expect(safDocumentIdOf(nestedSongUri), 'primary:Music/Album/a.mp3');
    });

    test('树根 URI 取第 2 段', () {
      expect(safDocumentIdOf(songTree), 'primary:Music');
    });

    test('非 SAF 路径与空值返回 null', () {
      expect(safDocumentIdOf(null), isNull);
      expect(safDocumentIdOf('  '), isNull);
      expect(safDocumentIdOf(r'D:\music\a.mp3'), isNull);
    });
  });

  group('safDirectoryUri', () {
    test('空层级返回树根 URI', () {
      expect(
        safDirectoryUri(treeUri: songTree, directorySegments: const <String>[]),
        songTree,
      );
    });

    test('相对层级拼成树内文档 URI，含 / 的文档 id 保持单一段', () {
      final String? directoryUri = safDirectoryUri(
        treeUri: songTree,
        directorySegments: const <String>['Album', 'Disc 1'],
      );

      // 关键不变量：构造出的目录 URI 能被同一套解析逻辑还原回原文档 id（原生侧同样解析），
      // 因此含 '/' 的文档 id 必须保持为单个路径段。
      expect(safDocumentIdOf(directoryUri), 'primary:Music/Album/Disc 1');
      expect(directoryUri, contains('%2FAlbum%2FDisc%201'));
      expect(
        directoryUri,
        startsWith('content://com.android.externalstorage.documents/tree/'),
      );
    });

    test('非 content URI 无法构造', () {
      expect(
        safDirectoryUri(
          treeUri: r'D:\music',
          directorySegments: const <String>['Album'],
        ),
        isNull,
      );
    });
  });

  group('resolveAndroidSafSaveTarget', () {
    test('song 模式写到歌曲所在目录', () {
      final AndroidSafSaveTargetResult result = resolveAndroidSafSaveTarget(
        saveMode: LocalMatchSaveMode.song,
        songPath: nestedSongUri,
        songTreeUri: songTree,
        saveTreeUri: null,
        songTreeLabel: 'Music',
      );

      expect(result.failure, isNull);
      expect(result.target!.treeUri, songTree);
      expect(result.target!.directorySegments, <String>['Album']);
      expect(result.target!.directoryLabel, 'Music / Album');
    });

    test('song 模式下位于树根的歌曲写树根', () {
      final AndroidSafSaveTargetResult result = resolveAndroidSafSaveTarget(
        saveMode: LocalMatchSaveMode.song,
        songPath: rootLevelSongUri,
        songTreeUri: songTree,
        saveTreeUri: null,
        songTreeLabel: 'Music',
      );

      expect(result.target!.directorySegments, isEmpty);
      expect(result.target!.directoryLabel, 'Music');
    });

    test('mirror 模式写到保存根并保留歌曲相对层级', () {
      final AndroidSafSaveTargetResult result = resolveAndroidSafSaveTarget(
        saveMode: LocalMatchSaveMode.mirror,
        songPath: nestedSongUri,
        songTreeUri: songTree,
        saveTreeUri: saveTree,
        saveTreeLabel: 'Lyrics',
      );

      expect(result.target!.treeUri, saveTree);
      expect(result.target!.directorySegments, <String>['Album']);
      expect(result.target!.directoryLabel, 'Lyrics / Album');
    });

    test('mirror 保存根就是歌曲树时与 song 等价', () {
      final AndroidSafSaveTargetResult result = resolveAndroidSafSaveTarget(
        saveMode: LocalMatchSaveMode.mirror,
        songPath: nestedSongUri,
        songTreeUri: songTree,
        saveTreeUri: songTree,
        songTreeLabel: 'Music',
      );

      expect(result.target!.treeUri, songTree);
      expect(result.target!.directorySegments, <String>['Album']);
    });

    test('specify 模式扁平写到保存根', () {
      final AndroidSafSaveTargetResult result = resolveAndroidSafSaveTarget(
        saveMode: LocalMatchSaveMode.specify,
        songPath: nestedSongUri,
        songTreeUri: songTree,
        saveTreeUri: saveTree,
        saveTreeLabel: 'Lyrics',
      );

      expect(result.target!.treeUri, saveTree);
      expect(result.target!.directorySegments, isEmpty);
      expect(result.target!.directoryLabel, 'Lyrics');
    });

    test('mirror/specify 缺保存根时报 missingSaveTree', () {
      for (final LocalMatchSaveMode mode in <LocalMatchSaveMode>[
        LocalMatchSaveMode.mirror,
        LocalMatchSaveMode.specify,
      ]) {
        final AndroidSafSaveTargetResult result = resolveAndroidSafSaveTarget(
          saveMode: mode,
          songPath: nestedSongUri,
          songTreeUri: songTree,
          saveTreeUri: null,
        );
        expect(result.target, isNull);
        expect(result.failure, AndroidSafSaveTargetFailure.missingSaveTree);
      }
    });

    test('歌曲不在授权树内时报 songOutsideTree', () {
      final AndroidSafSaveTargetResult result = resolveAndroidSafSaveTarget(
        saveMode: LocalMatchSaveMode.song,
        songPath: outsideTreeSongUri,
        songTreeUri: songTree,
        saveTreeUri: null,
      );

      expect(result.target, isNull);
      expect(result.failure, AndroidSafSaveTargetFailure.songOutsideTree);
    });

    test('本地路径报 unknownSongPath', () {
      final AndroidSafSaveTargetResult result = resolveAndroidSafSaveTarget(
        saveMode: LocalMatchSaveMode.song,
        songPath: r'D:\music\a.mp3',
        songTreeUri: songTree,
        saveTreeUri: null,
      );

      expect(result.target, isNull);
      expect(result.failure, AndroidSafSaveTargetFailure.unknownSongPath);
    });
  });
}
