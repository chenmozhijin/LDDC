import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/library_link_manager/application/library_link_manager_usecase.dart';

void main() {
  group('LibraryLinkManagerUseCase', () {
    test('restoreFromJsonBytes 在坏 JSON 或非数组备份时不替换仓储', () async {
      final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
        <LibraryLinkItem>[_buildItem(1)],
      );
      final LibraryLinkManagerUseCase useCase = LibraryLinkManagerUseCase(
        repository: repository,
        fileExists: (_) async => true,
      );

      await expectLater(
        useCase.restoreFromJsonBytes(
          utf8.encode('{broken'),
          invalidBackupFormatMessage: '备份格式错误',
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        useCase.restoreFromJsonBytes(
          utf8.encode('{"items":[]}'),
          invalidBackupFormatMessage: '备份格式错误',
        ),
        throwsA(isA<FormatException>()),
      );

      expect(repository.replaceAllCalls, 0);
      expect(repository.items, hasLength(1));
    });

    test('restoreFromJsonBytes 先完整解析再事务替换', () async {
      final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
        <LibraryLinkItem>[_buildItem(1)],
      );
      final LibraryLinkManagerUseCase useCase = LibraryLinkManagerUseCase(
        repository: repository,
        fileExists: (_) async => true,
      );

      final int restored = await useCase.restoreFromJsonBytes(
        utf8.encode('''
[
  {
    "title": "新歌",
    "artist": "歌手",
    "album": "专辑",
    "duration": 120000,
    "song_path": "D:/music/new.mp3",
    "track_number": "7",
    "lyrics_path": "D:/lyrics/new.lrc",
    "config": {"offset": 100}
  }
]
'''),
        invalidBackupFormatMessage: '备份格式错误',
      );

      expect(restored, 1);
      expect(repository.replaceAllCalls, 1);
      expect(repository.items.single.song.title, '新歌');
      expect(repository.items.single.configSnapshot['offset'], 100);
    });

    test('clearInvalid 分页读取并删除不存在路径', () async {
      final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
        List<LibraryLinkItem>.generate(
          205,
          (int index) => _buildItem(
            index,
            songPath: 'song://$index',
            lyricsPath: index.isEven
                ? 'missing://$index.lrc'
                : 'lyrics://$index',
          ),
        ),
      );
      final LibraryLinkManagerUseCase useCase = LibraryLinkManagerUseCase(
        repository: repository,
        fileExists: (String path) async => !path.startsWith('missing://'),
        batchSize: 200,
      );

      final LibraryLinkClearInvalidResult result = await useCase.clearInvalid();

      expect(repository.pageOffsets, <int>[0, 200]);
      expect(result.count, 103);
      expect(repository.deletedIds, result.deletedIds);
    });

    test('rewriteDirectory 使用仓储 rewriteItems 保持删除写入事务边界', () async {
      final _FakeLibraryLinkRepository repository =
          _FakeLibraryLinkRepository(<LibraryLinkItem>[
            _buildItem(
              1,
              songPath: r'D:\old\album\song.mp3',
              lyricsPath: r'D:\old\lyrics\song.lrc',
            ),
            _buildItem(
              2,
              songPath: r'D:\other\song.mp3',
              lyricsPath: r'D:\other\song.lrc',
            ),
          ]);
      final LibraryLinkManagerUseCase useCase = LibraryLinkManagerUseCase(
        repository: repository,
        fileExists: (String path) async => path.startsWith(r'E:\new'),
      );

      final LibraryLinkRewriteDirectoryResult result = await useCase
          .rewriteDirectory(oldDir: r'D:\old', newDir: r'E:\new');

      expect(result.originalIds, <int>{1});
      expect(repository.rewriteItemsCalls, 1);
      expect(repository.setSongsCalls, 0);
      expect(repository.deletedIds, isEmpty);
      expect(repository.items.map((LibraryLinkItem item) => item.song.path), [
        r'D:\other\song.mp3',
        r'E:\new\album\song.mp3',
      ]);
      expect(repository.items.last.lyricsPath, r'E:\new\lyrics\song.lrc');
    });

    test('buildBackupJson 流式分页生成可恢复数组', () async {
      final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
        <LibraryLinkItem>[
          _buildItem(1, configSnapshot: const <String, Object?>{'offset': 20}),
          _buildItem(2, lyricsPath: null),
        ],
      );
      final LibraryLinkManagerUseCase useCase = LibraryLinkManagerUseCase(
        repository: repository,
        fileExists: (_) async => true,
        batchSize: 1,
      );

      final Object? decoded = jsonDecode(await useCase.buildBackupJson());

      expect(repository.pageOffsets, <int>[0, 1]);
      expect(decoded, isA<List<Object?>>());
      final List<Object?> rows = decoded! as List<Object?>;
      expect(rows, hasLength(2));
      expect((rows.first! as Map<String, Object?>)['config'], <String, Object?>{
        'offset': 20,
      });
      expect((rows.last! as Map<String, Object?>)['lyrics_path'], isNull);
    });
  });
}

LibraryLinkItem _buildItem(
  int index, {
  String? songPath,
  String? lyricsPath = r'D:\lyrics\song.lrc',
  Map<String, Object?> configSnapshot = const <String, Object?>{},
}) {
  final SongInfo song = SongInfo(
    source: Source.local,
    id: '$index',
    title: 'Song $index',
    artist: SongArtist(<String>['Artist $index']),
    album: 'Album $index',
    durationMs: 120000 + index,
    path: songPath ?? 'D:\\music\\song_$index.mp3',
  );
  return LibraryLinkItem(
    id: index,
    song: song,
    key: LibraryLinkKey.fromSong(song),
    lyricsPath: lyricsPath,
    configSnapshot: configSnapshot,
  );
}

class _FakeLibraryLinkRepository implements LibraryLinkRepository {
  _FakeLibraryLinkRepository(List<LibraryLinkItem> items)
    : items = List<LibraryLinkItem>.from(items);

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<LibraryLinkItem> items;
  final List<int> pageOffsets = <int>[];
  final Set<int> deletedIds = <int>{};
  int replaceAllCalls = 0;
  int rewriteItemsCalls = 0;
  int setSongsCalls = 0;

  @override
  Future<int> countItems({String searchText = ''}) async => items.length;

  @override
  Future<void> delAll() async {
    items.clear();
    _changes.add(null);
  }

  @override
  Future<void> delItem(int id) async {
    items.removeWhere((LibraryLinkItem item) => item.id == id);
    deletedIds.add(id);
    _changes.add(null);
  }

  @override
  Future<void> delItems(Iterable<int> ids) async {
    final Set<int> idSet = ids.toSet();
    items.removeWhere((LibraryLinkItem item) => idSet.contains(item.id));
    deletedIds.addAll(idSet);
    _changes.add(null);
  }

  @override
  Future<void> dispose() async {
    await _changes.close();
  }

  @override
  Future<LibraryLinkItem?> getItem(int id) async {
    return items.where((LibraryLinkItem item) => item.id == id).firstOrNull;
  }

  @override
  Future<List<LibraryLinkItem>> getPage({
    required int offset,
    required int limit,
    String searchText = '',
  }) async {
    pageOffsets.add(offset);
    if (offset >= items.length) {
      return const <LibraryLinkItem>[];
    }
    final int end = (offset + limit) > items.length
        ? items.length
        : offset + limit;
    return List<LibraryLinkItem>.from(items.sublist(offset, end));
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<LibraryLinkItem?> query(SongInfo song) async {
    return items
        .where(
          (LibraryLinkItem item) => item.key == LibraryLinkKey.fromSong(song),
        )
        .firstOrNull;
  }

  @override
  Future<void> replaceAll(Iterable<LibraryLinkUpsertItem> upserts) async {
    replaceAllCalls += 1;
    items.clear();
    await setSongs(upserts);
  }

  @override
  Future<void> rewriteItems(Iterable<LibraryLinkRewriteItem> rewrites) async {
    rewriteItemsCalls += 1;
    final List<LibraryLinkRewriteItem> rewriteList = rewrites.toList(
      growable: false,
    );
    final Set<int> ids = rewriteList
        .map((LibraryLinkRewriteItem item) => item.originalId)
        .toSet();
    items.removeWhere((LibraryLinkItem item) => ids.contains(item.id));
    for (final LibraryLinkRewriteItem rewrite in rewriteList) {
      await setSong(
        song: rewrite.upsert.song,
        lyricsPath: rewrite.upsert.lyricsPath,
        configSnapshot: rewrite.upsert.configSnapshot,
      );
    }
  }

  @override
  Future<LibraryLinkItem> setSong({
    required SongInfo song,
    String? lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) async {
    final LibraryLinkItem item = LibraryLinkItem(
      id: items.isEmpty
          ? 1
          : items
                    .map((LibraryLinkItem item) => item.id)
                    .reduce((int a, int b) => a > b ? a : b) +
                1,
      song: song,
      key: LibraryLinkKey.fromSong(song),
      lyricsPath: lyricsPath,
      configSnapshot: configSnapshot,
    );
    items.add(item);
    _changes.add(null);
    return item;
  }

  @override
  Future<void> setSongs(Iterable<LibraryLinkUpsertItem> upserts) async {
    setSongsCalls += 1;
    for (final LibraryLinkUpsertItem upsert in upserts) {
      await setSong(
        song: upsert.song,
        lyricsPath: upsert.lyricsPath,
        configSnapshot: upsert.configSnapshot,
      );
    }
  }

  @override
  Stream<void> watchChanges({bool emitCurrent = false}) async* {
    if (emitCurrent) {
      yield null;
    }
    yield* _changes.stream;
  }
}
