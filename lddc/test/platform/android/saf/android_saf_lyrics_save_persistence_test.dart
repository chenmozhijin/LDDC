import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/android/saf/android_saf_lyrics_save_persistence.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
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

  LyricsSaveRequest requestFor(String songPath) {
    return LyricsSaveRequest(
      songInfo: SongInfo(
        source: Source.local,
        path: songPath,
        title: 'Demo',
        artist: SongArtist(<String>['Singer']),
      ),
      lyricLangs: const <String>['orig'],
      lyricsFormat: LyricsFormat.lineByLineLrc,
      fileNameFormat: '%<title>',
    );
  }

  Uint8List bytes() => Uint8List.fromList(<int>[1, 2, 3]);

  group('保存模式决定写入目标', () {
    test('song 模式写到歌曲所在目录', () async {
      final _FakeTreePort treePort = _FakeTreePort();
      final AndroidSafLyricsSavePersistence persistence =
          AndroidSafLyricsSavePersistence(
            treePort: treePort,
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.song,
          );

      final String uri = await persistence.saveBytes(
        request: requestFor(nestedSongUri),
        bytes: bytes(),
      );

      expect(treePort.writes.single.treeUri, songTree);
      expect(treePort.writes.single.directorySegments, <String>['Album']);
      expect(treePort.writes.single.displayName, 'Demo.lrc');
      expect(uri, contains('Album'));
    });

    test('song 模式下树根的歌曲写树根', () async {
      final _FakeTreePort treePort = _FakeTreePort();
      final AndroidSafLyricsSavePersistence persistence =
          AndroidSafLyricsSavePersistence(
            treePort: treePort,
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.song,
          );

      await persistence.saveBytes(
        request: requestFor(rootLevelSongUri),
        bytes: bytes(),
      );

      expect(treePort.writes.single.directorySegments, isEmpty);
      expect(treePort.writes.single.treeUri, songTree);
    });

    test('mirror 模式写到保存根并保留歌曲相对层级', () async {
      final _FakeTreePort treePort = _FakeTreePort();
      final AndroidSafLyricsSavePersistence persistence =
          AndroidSafLyricsSavePersistence(
            treePort: treePort,
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.mirror,
            saveTreeUri: saveTree,
          );

      await persistence.saveBytes(
        request: requestFor(nestedSongUri),
        bytes: bytes(),
      );

      expect(treePort.writes.single.treeUri, saveTree);
      expect(treePort.writes.single.directorySegments, <String>['Album']);
    });

    test('specify 模式扁平写到保存根，不再隐式写歌曲树', () async {
      final _FakeTreePort treePort = _FakeTreePort();
      final AndroidSafLyricsSavePersistence persistence =
          AndroidSafLyricsSavePersistence(
            treePort: treePort,
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.specify,
            saveTreeUri: saveTree,
          );

      await persistence.saveBytes(
        request: requestFor(nestedSongUri),
        bytes: bytes(),
      );

      expect(treePort.writes.single.treeUri, saveTree);
      expect(treePort.writes.single.directorySegments, isEmpty);
    });

    test('搜索页用法（specify + 保存根=所选树）仍写所选树根', () async {
      final _FakeTreePort treePort = _FakeTreePort();
      final AndroidSafLyricsSavePersistence persistence =
          AndroidSafLyricsSavePersistence(
            treePort: treePort,
            treeUri: saveTree,
            saveMode: LocalMatchSaveMode.specify,
            saveTreeUri: saveTree,
          );

      await persistence.saveBytes(
        request: requestFor(nestedSongUri),
        bytes: bytes(),
      );

      expect(treePort.writes.single.treeUri, saveTree);
      expect(treePort.writes.single.directorySegments, isEmpty);
    });

    test('缺失保存根树时抛出可分类的异常而不是静默写错地方', () async {
      final AndroidSafLyricsSavePersistence persistence =
          AndroidSafLyricsSavePersistence(
            treePort: _FakeTreePort(),
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.mirror,
          );

      await expectLater(
        persistence.saveBytes(
          request: requestFor(nestedSongUri),
          bytes: bytes(),
        ),
        throwsA(
          isA<AndroidSafSaveTargetException>().having(
            (AndroidSafSaveTargetException error) => error.failure,
            'failure',
            AndroidSafSaveTargetFailure.missingSaveTree,
          ),
        ),
      );
    });
  });

  group('exists 按目标目录判断', () {
    test('同名文件只对同一目标目录生效', () async {
      final _FakeTreePort treePort = _FakeTreePort();
      final AndroidSafLyricsSavePersistence songMode =
          AndroidSafLyricsSavePersistence(
            treePort: treePort,
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.song,
          );
      final AndroidSafLyricsSavePersistence flatMode =
          AndroidSafLyricsSavePersistence(
            treePort: treePort,
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.specify,
            saveTreeUri: saveTree,
          );

      await songMode.saveBytes(
        request: requestFor(nestedSongUri),
        bytes: bytes(),
      );

      expect(await songMode.exists(request: requestFor(nestedSongUri)), isTrue);
      // 保存根是另一棵树：同一个文件名不应被判成"已存在"，否则会静默跳过写入。
      expect(
        await flatMode.exists(request: requestFor(nestedSongUri)),
        isFalse,
      );
    });

    test('目标目录尚不存在时按"没有同名歌词"处理', () async {
      final AndroidSafLyricsSavePersistence persistence =
          AndroidSafLyricsSavePersistence(
            treePort: _FakeTreePort(),
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.song,
          );

      expect(
        await persistence.exists(request: requestFor(nestedSongUri)),
        isFalse,
      );
    });

    test('目标不可推导时不误判为已存在', () async {
      final AndroidSafLyricsSavePersistence persistence =
          AndroidSafLyricsSavePersistence(
            treePort: _FakeTreePort(),
            treeUri: songTree,
            saveMode: LocalMatchSaveMode.specify,
          );

      expect(
        await persistence.exists(request: requestFor(nestedSongUri)),
        isFalse,
      );
    });
  });
}

/// 记录写入请求的最小 tree port；目录内容按目录 URI 存放，供 exists 分页枚举。
class _FakeTreePort implements AndroidSafTreePort {
  final List<
    ({String treeUri, List<String> directorySegments, String displayName})
  >
  writes =
      <
        ({String treeUri, List<String> directorySegments, String displayName})
      >[];
  final Map<String, List<AndroidSafTreeEntry>> childrenByUri =
      <String, List<AndroidSafTreeEntry>>{};

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required List<String> directorySegments,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    writes.add((
      treeUri: treeUri,
      directorySegments: List<String>.unmodifiable(directorySegments),
      displayName: displayName,
    ));
    final String directoryUri =
        safDirectoryUri(
          treeUri: treeUri,
          directorySegments: directorySegments,
        ) ??
        treeUri;
    AndroidSafTreeEntry createdEntry() => AndroidSafTreeEntry(
      uri: '$directoryUri/$displayName',
      displayName: displayName,
      mimeType: mimeType,
      isDirectory: false,
      isFile: true,
    );
    childrenByUri.update(
      directoryUri,
      (List<AndroidSafTreeEntry> current) => <AndroidSafTreeEntry>[
        ...current,
        createdEntry(),
      ],
      ifAbsent: () => <AndroidSafTreeEntry>[createdEntry()],
    );
    return AndroidSafWriteDocumentResult(
      uri: '$directoryUri/$displayName',
      displayName: displayName,
    );
  }

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    final List<AndroidSafTreeEntry> entries =
        childrenByUri[uri] ?? const <AndroidSafTreeEntry>[];
    final int end = offset + limit < entries.length
        ? offset + limit
        : entries.length;
    return AndroidSafTreePage(
      entries: offset >= entries.length
          ? const <AndroidSafTreeEntry>[]
          : entries.sublist(offset, end),
      nextOffset: end < entries.length ? end : null,
    );
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() async {
    return const <AndroidSafPersistedTree>[];
  }

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) {
    throw UnimplementedError();
  }

  @override
  Future<void> persistTreePermission(String uri) async {}
}
