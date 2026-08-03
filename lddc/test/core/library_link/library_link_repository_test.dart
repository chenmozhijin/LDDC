import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  group('SqliteLibraryLinkRepository', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lddc-library-link-repo-',
      );
      dbFile = File(p.join(tempDir.path, 'local_song_lyrics.db'));
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    SqliteLibraryLinkRepository createRepository() {
      return SqliteLibraryLinkRepository(executor: NativeDatabase(dbFile));
    }

    test('initialize 会创建Python版 songs schema', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      await repository.initialize();
      await repository.dispose();

      final sqlite3.Database rawDb = sqlite3.sqlite3.open(dbFile.path);
      final sqlite3.ResultSet columns = rawDb.select(
        'PRAGMA table_info(songs)',
      );
      final List<String> columnNames = columns
          .map((sqlite3.Row row) => row['name'] as String)
          .toList(growable: false);
      rawDb.close();

      expect(columnNames, <String>[
        'id',
        'title',
        'artist',
        'album',
        'duration',
        'song_path',
        'track_number',
        'lyrics_path',
        'config',
      ]);
    });

    test('并发 initialize 只创建一个 executor', () async {
      final Completer<void> factoryStarted = Completer<void>();
      final Completer<void> releaseFactory = Completer<void>();
      int factoryCalls = 0;
      final SqliteLibraryLinkRepository repository =
          SqliteLibraryLinkRepository(
            executorFactory: () async {
              factoryCalls += 1;
              factoryStarted.complete();
              await releaseFactory.future;
              return NativeDatabase.memory();
            },
          );

      final Future<void> first = repository.initialize();
      final Future<void> second = repository.initialize();
      await factoryStarted.future;
      expect(factoryCalls, 1);
      releaseFactory.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(factoryCalls, 1);
      await repository.dispose();
    });

    test('初始化失败后允许重试且不会污染操作队列', () async {
      int factoryCalls = 0;
      final SqliteLibraryLinkRepository repository =
          SqliteLibraryLinkRepository(
            executorFactory: () async {
              factoryCalls += 1;
              if (factoryCalls == 1) {
                throw StateError('模拟 executor 创建失败');
              }
              return NativeDatabase.memory();
            },
          );

      await expectLater(repository.initialize(), throwsStateError);
      await repository.initialize();

      expect(factoryCalls, 2);
      expect(await repository.countItems(), 0);
      await repository.dispose();
    });

    test('dispose 等待已接收操作并永久拒绝后续调用', () async {
      final Completer<void> factoryStarted = Completer<void>();
      final Completer<void> releaseFactory = Completer<void>();
      final SqliteLibraryLinkRepository repository =
          SqliteLibraryLinkRepository(
            executorFactory: () async {
              factoryStarted.complete();
              await releaseFactory.future;
              return NativeDatabase.memory();
            },
          );
      final SongInfo song = SongInfo(
        source: Source.local,
        title: '关闭竞态',
        artist: SongArtist(<String>['测试']),
      );

      final Future<LibraryLinkItem> write = repository.setSong(song: song);
      await factoryStarted.future;
      final Future<void> closing = repository.dispose();
      await expectLater(repository.countItems(), throwsStateError);
      releaseFactory.complete();

      expect((await write).song.title, '关闭竞态');
      await closing;
      await repository.dispose();
    });

    test('批量调用会冻结输入列表和嵌套 config 快照', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final Map<String, Object?> config = <String, Object?>{
        'nested': <Object?>[1],
      };
      final SongInfo firstSong = SongInfo(
        source: Source.local,
        title: '快照一',
        artist: SongArtist(<String>['测试']),
        id: '1',
      );
      final List<LibraryLinkUpsertItem> items = <LibraryLinkUpsertItem>[
        LibraryLinkUpsertItem(song: firstSong, configSnapshot: config),
      ];

      final Future<void> write = repository.setSongs(items);
      items.add(
        LibraryLinkUpsertItem(
          song: firstSong.copyWith(title: '快照二', id: '2'),
        ),
      );
      (config['nested']! as List<Object?>).add(2);
      await write;

      expect(await repository.countItems(), 1);
      final LibraryLinkItem saved = (await repository.query(firstSong))!;
      expect(saved.configSnapshot['nested'], <Object?>[1]);
      expect(
        () => (saved.configSnapshot['nested']! as List<Object?>).add(3),
        throwsUnsupportedError,
      );
      await repository.dispose();
    });

    test('循环 config 会返回参数错误且仓储仍可继续使用', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final Map<String, Object?> cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      final SongInfo song = SongInfo(
        source: Source.local,
        title: '循环配置',
        artist: SongArtist(<String>['测试']),
      );

      await expectLater(
        repository.setSong(song: song, configSnapshot: cyclic),
        throwsArgumentError,
      );
      await repository.setSong(song: song);

      expect(await repository.countItems(), 1);
      await repository.dispose();
    });

    test('setSong + query 语义对齐Python版唯一键规则', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo song = SongInfo(
        source: Source.local,
        title: '夜曲',
        artist: SongArtist(<String>['周杰伦']),
        album: '十一月的萧邦',
        durationMs: 236000,
        path: r'D:\music\yequ.mp3',
        id: '1',
      );

      final LibraryLinkItem saved = await repository.setSong(
        song: song,
        lyricsPath: r'D:\lyrics\yequ.lrc',
        configSnapshot: <String, Object?>{
          'offset': 120,
          'langs': <String>['orig', 'ts'],
        },
      );

      final LibraryLinkItem? queried = await repository.query(song);

      expect(saved.id, greaterThan(0));
      expect(queried, isNotNull);
      expect(queried!.lyricsPath, r'D:\lyrics\yequ.lrc');
      expect(queried.key.songPath, 'file://${song.path}');
      expect(queried.key.trackNumber, '1');
      expect(queried.configSnapshot['offset'], 120);

      await repository.dispose();
    });

    test('播放器传入 file URL 时命中原生路径关联且不会新增记录', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo nativeSong = SongInfo(
        source: Source.local,
        title: '路径规范化',
        artist: SongArtist(<String>['测试歌手']),
        album: '测试专辑',
        durationMs: 180000,
        path: r'D:\music\normalized.flac',
        id: '3',
      );
      await repository.setSong(
        song: nativeSong,
        lyricsPath: r'D:\lyrics\original.lrc',
      );

      final SongInfo prefixedSong = nativeSong.copyWith(
        path: r'file://D:\music\normalized.flac',
      );
      final LibraryLinkItem? queried = await repository.query(prefixedSong);

      expect(queried, isNotNull);
      expect(queried!.lyricsPath, r'D:\lyrics\original.lrc');
      expect(queried.key.songPath, r'file://D:\music\normalized.flac');

      await repository.setSong(
        song: nativeSong.copyWith(
          path: r'file://file://D:\music\normalized.flac',
        ),
        lyricsPath: r'D:\lyrics\updated.lrc',
      );

      expect(await repository.countItems(), 1);
      expect(
        (await repository.query(nativeSong))!.lyricsPath,
        r'D:\lyrics\updated.lrc',
      );
      await repository.dispose();
    });

    test('重复 setSong 会更新同一条记录而非新增', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo song = SongInfo(
        source: Source.local,
        title: '稻香',
        artist: SongArtist(<String>['周杰伦']),
        album: '魔杰座',
        durationMs: 223000,
        path: r'D:\music\daoxiang.mp3',
        id: '1',
      );

      await repository.setSong(
        song: song,
        lyricsPath: r'D:\lyrics\old.lrc',
        configSnapshot: <String, Object?>{'offset': 10},
      );
      await repository.setSong(
        song: song,
        lyricsPath: r'D:\lyrics\new.lrc',
        configSnapshot: <String, Object?>{'offset': 20},
      );

      final List<LibraryLinkItem> all = await _readAll(repository);
      expect(all.length, 1);
      expect(all.first.lyricsPath, r'D:\lyrics\new.lrc');
      expect(all.first.configSnapshot['offset'], 20);

      await repository.dispose();
    });

    test('setSongs/getItem/delItem/delItems/delAll 主流程可用', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo song1 = SongInfo(
        source: Source.local,
        title: '晴天',
        artist: SongArtist(<String>['周杰伦']),
        durationMs: 269000,
        path: r'D:\music\qt.mp3',
        id: '1',
      );
      final SongInfo song2 = SongInfo(
        source: Source.local,
        title: '反方向的钟',
        artist: SongArtist(<String>['周杰伦']),
        durationMs: 281000,
        path: r'D:\music\fxdz.mp3',
        id: '2',
      );
      final SongInfo song3 = SongInfo(
        source: Source.local,
        title: '听妈妈的话',
        artist: SongArtist(<String>['周杰伦']),
        durationMs: 268000,
        path: r'D:\music\tmmdh.mp3',
        id: '3',
      );

      await repository.setSongs(<LibraryLinkUpsertItem>[
        LibraryLinkUpsertItem(song: song1, lyricsPath: r'D:\lyrics\qt.lrc'),
        LibraryLinkUpsertItem(song: song2, lyricsPath: r'D:\lyrics\fxdz.lrc'),
        LibraryLinkUpsertItem(song: song3, lyricsPath: r'D:\lyrics\tmmdh.lrc'),
      ]);
      final List<LibraryLinkItem> all = await _readAll(repository);
      expect(all.length, 3);

      final LibraryLinkItem? item = await repository.getItem(all[0].id);
      expect(item, isNotNull);
      expect(item!.song.title, all[0].song.title);

      await repository.delItem(all[0].id);
      final List<LibraryLinkItem> afterDelOne = await _readAll(repository);
      expect(afterDelOne.length, 2);

      await repository.delItems(<int>[afterDelOne[0].id, afterDelOne[1].id]);
      final List<LibraryLinkItem> afterDelBatch = await _readAll(repository);
      expect(afterDelBatch, isEmpty);

      await repository.setSong(song: song1, lyricsPath: r'D:\lyrics\qt.lrc');
      await repository.delAll();
      expect(await _readAll(repository), isEmpty);

      await repository.dispose();
    });

    test('countItems/getPage 支持分页读取', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      await repository.setSongs(<LibraryLinkUpsertItem>[
        for (int index = 0; index < 5; index += 1)
          LibraryLinkUpsertItem(
            song: SongInfo(
              source: Source.local,
              title: '歌曲$index',
              artist: SongArtist(<String>['歌手$index']),
              durationMs: 180000 + index,
              path: r'D:\music\song.mp3',
              id: '$index',
            ),
            lyricsPath: r'D:\lyrics\song.lrc',
          ),
      ]);

      expect(await repository.countItems(), 5);

      final List<LibraryLinkItem> page = await repository.getPage(
        offset: 2,
        limit: 2,
      );
      expect(page, hasLength(2));
      expect(page.first.song.title, '歌曲2');
      expect(page.last.song.title, '歌曲3');

      await repository.dispose();
    });

    test('countItems/getPage 在数据库层按元数据和路径字面搜索', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      await repository.setSongs(<LibraryLinkUpsertItem>[
        LibraryLinkUpsertItem(
          song: SongInfo(
            source: Source.local,
            title: 'Morning Star',
            artist: SongArtist(<String>['The Band']),
            album: 'First Album',
            durationMs: 180000,
            path: r'D:\music\morning_star.mp3',
            id: '1',
          ),
          lyricsPath: r'D:\lyrics\morning_star.lrc',
        ),
        LibraryLinkUpsertItem(
          song: SongInfo(
            source: Source.local,
            title: 'Night Drive',
            artist: SongArtist(<String>['Other Artist']),
            album: 'Second Album',
            durationMs: 181000,
            path: r'D:\music\night_drive.mp3',
            id: '2',
          ),
          lyricsPath: r'D:\lyrics\special_%_file.lrc',
        ),
        LibraryLinkUpsertItem(
          song: SongInfo(
            source: Source.local,
            title: 'Quiet Room',
            artist: SongArtist(<String>['Third Artist']),
            album: 'Live Set',
            durationMs: 182000,
            path: r'D:\archive\quiet_room.mp3',
            id: '3',
          ),
          lyricsPath: r'D:\lyrics\quiet_room.lrc',
        ),
      ]);

      expect(await repository.countItems(searchText: 'MORNING'), 1);
      expect(await repository.countItems(searchText: 'artist'), 2);
      expect(await repository.countItems(searchText: r'%'), 1);
      final List<LibraryLinkItem> page = await repository.getPage(
        offset: 0,
        limit: 2,
        searchText: 'album',
      );
      expect(
        page.map((LibraryLinkItem item) => item.song.title).toList(),
        <String>['Morning Star', 'Night Drive'],
      );
      expect(
        await repository.getPage(offset: 0, limit: 10, searchText: 'missing'),
        isEmpty,
      );

      await repository.dispose();
    });

    test('getPage 对非法分页参数抛出参数错误', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      await repository.initialize();

      await expectLater(
        repository.getPage(offset: -1, limit: 10),
        throwsArgumentError,
      );
      await expectLater(
        repository.getPage(offset: 0, limit: 0),
        throwsArgumentError,
      );

      await repository.dispose();
    });

    test('空批次和非法分页不会启动数据库 executor', () async {
      int factoryCalls = 0;
      final SqliteLibraryLinkRepository repository =
          SqliteLibraryLinkRepository(
            executorFactory: () async {
              factoryCalls += 1;
              return NativeDatabase.memory();
            },
          );

      await repository.setSongs(const <LibraryLinkUpsertItem>[]);
      await repository.delItems(const <int>[]);
      await expectLater(
        repository.getPage(offset: -1, limit: 10),
        throwsArgumentError,
      );

      expect(factoryCalls, 0);
      await repository.dispose();
    });

    test('setSongs 拒绝同一批次内的重复唯一键', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo song = SongInfo(
        source: Source.local,
        title: '重复歌曲',
        artist: SongArtist(<String>['歌手']),
        durationMs: 180000,
        path: r'D:\music\dup.mp3',
        id: '1',
      );

      await expectLater(
        repository.setSongs(<LibraryLinkUpsertItem>[
          LibraryLinkUpsertItem(song: song, lyricsPath: r'D:\lyrics\a.lrc'),
          LibraryLinkUpsertItem(song: song, lyricsPath: r'D:\lyrics\b.lrc'),
        ]),
        throwsArgumentError,
      );
      expect(await _readAll(repository), isEmpty);

      await repository.dispose();
    });

    test('replaceAll 使用事务替换并在校验失败时保留旧数据', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo oldSong = SongInfo(
        source: Source.local,
        title: '旧歌曲',
        artist: SongArtist(<String>['歌手']),
        durationMs: 180000,
        path: r'D:\music\old.mp3',
        id: '1',
      );
      final SongInfo newSong = SongInfo(
        source: Source.local,
        title: '新歌曲',
        artist: SongArtist(<String>['歌手']),
        durationMs: 190000,
        path: r'D:\music\new.mp3',
        id: '2',
      );

      await repository.setSong(song: oldSong, lyricsPath: r'D:\lyrics\old.lrc');
      await repository.replaceAll(<LibraryLinkUpsertItem>[
        LibraryLinkUpsertItem(song: newSong, lyricsPath: r'D:\lyrics\new.lrc'),
      ]);

      List<LibraryLinkItem> all = await _readAll(repository);
      expect(all, hasLength(1));
      expect(all.single.song.title, '新歌曲');

      await expectLater(
        repository.replaceAll(<LibraryLinkUpsertItem>[
          LibraryLinkUpsertItem(song: newSong, lyricsPath: r'D:\lyrics\a.lrc'),
          LibraryLinkUpsertItem(song: newSong, lyricsPath: r'D:\lyrics\b.lrc'),
        ]),
        throwsArgumentError,
      );
      all = await _readAll(repository);
      expect(all, hasLength(1));
      expect(all.single.song.title, '新歌曲');

      await repository.dispose();
    });

    test('rewriteItems 在同一事务中删除旧记录并写入迁移后记录', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo oldSong = SongInfo(
        source: Source.local,
        title: '迁移歌曲',
        artist: SongArtist(<String>['歌手']),
        durationMs: 180000,
        path: r'D:\old\song.mp3',
        id: '1',
      );
      final SongInfo otherSong = SongInfo(
        source: Source.local,
        title: '保留歌曲',
        artist: SongArtist(<String>['歌手']),
        durationMs: 190000,
        path: r'D:\old\other.mp3',
        id: '2',
      );
      await repository.setSongs(<LibraryLinkUpsertItem>[
        LibraryLinkUpsertItem(song: oldSong, lyricsPath: r'D:\old\song.lrc'),
        LibraryLinkUpsertItem(song: otherSong, lyricsPath: r'D:\old\other.lrc'),
      ]);
      final LibraryLinkItem oldItem = (await repository.query(oldSong))!;
      final SongInfo migratedSong = oldSong.copyWith(path: r'E:\new\song.mp3');

      await repository.rewriteItems(<LibraryLinkRewriteItem>[
        LibraryLinkRewriteItem(
          originalId: oldItem.id,
          upsert: LibraryLinkUpsertItem(
            song: migratedSong,
            lyricsPath: r'E:\new\song.lrc',
            configSnapshot: const <String, Object?>{'offset': 42},
          ),
        ),
      ]);

      final List<LibraryLinkItem> all = await _readAll(repository);
      expect(all, hasLength(2));
      expect(await repository.query(oldSong), isNull);
      final LibraryLinkItem? migrated = await repository.query(migratedSong);
      expect(migrated, isNotNull);
      expect(migrated!.lyricsPath, r'E:\new\song.lrc');
      expect(migrated.configSnapshot['offset'], 42);
      expect(await repository.query(otherSong), isNotNull);

      await expectLater(
        repository.rewriteItems(<LibraryLinkRewriteItem>[
          LibraryLinkRewriteItem(
            originalId: migrated.id,
            upsert: LibraryLinkUpsertItem(
              song: migratedSong.copyWith(path: r'E:\dup\a.mp3'),
            ),
          ),
          LibraryLinkRewriteItem(
            originalId: migrated.id,
            upsert: LibraryLinkUpsertItem(
              song: migratedSong.copyWith(path: r'E:\dup\b.mp3'),
            ),
          ),
        ]),
        throwsArgumentError,
      );
      expect(await repository.query(migratedSong), isNotNull);

      await repository.dispose();
    });

    test('损坏 config JSON 时回退空对象', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo song = SongInfo(
        source: Source.local,
        title: '龙卷风',
        artist: SongArtist(<String>['周杰伦']),
        durationMs: 250000,
        path: r'D:\music\ljf.mp3',
        id: '1',
      );

      await repository.setSong(
        song: song,
        configSnapshot: <String, Object?>{'offset': 66},
      );
      final LibraryLinkItem? saved = await repository.query(song);
      expect(saved, isNotNull);
      await repository.dispose();

      final sqlite3.Database rawDb = sqlite3.sqlite3.open(dbFile.path);
      rawDb.execute('UPDATE songs SET config = ?1 WHERE id = ?2', <Object>[
        '{broken',
        saved!.id,
      ]);
      rawDb.close();

      final SqliteLibraryLinkRepository repository2 = createRepository();
      final LibraryLinkItem? queried = await repository2.query(song);
      expect(queried, isNotNull);
      expect(queried!.configSnapshot, isEmpty);
      await repository2.dispose();
    });

    test('空值哨兵会按Python版规则落库', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo song = SongInfo(
        source: Source.local,
        artist: SongArtist(<String>[]),
      );

      await repository.setSong(song: song, lyricsPath: null);
      await repository.dispose();

      final sqlite3.Database rawDb = sqlite3.sqlite3.open(dbFile.path);
      final sqlite3.Row row = rawDb.select('''
SELECT title, artist, album, duration, song_path, track_number, lyrics_path, config
FROM songs
LIMIT 1
''').first;
      rawDb.close();

      expect(row['title'], '');
      expect(row['artist'], '');
      expect(row['album'], '');
      expect(row['duration'], -1);
      expect(row['song_path'], '');
      expect(row['track_number'], '');
      expect(row['lyrics_path'], '');
      expect(jsonDecode(row['config'] as String), <String, Object?>{});
    });

    test('watchChanges 能收到变更事件', () async {
      final SqliteLibraryLinkRepository repository = createRepository();
      final SongInfo song = SongInfo(
        source: Source.local,
        title: '彩虹',
        artist: SongArtist(<String>['周杰伦']),
        durationMs: 260000,
        path: r'D:\music\ch.mp3',
        id: '1',
      );

      final Future<List<void>> eventsFuture = repository
          .watchChanges()
          .take(2)
          .toList();
      await Future<void>.delayed(Duration.zero);

      await repository.setSong(
        song: song,
        configSnapshot: <String, Object?>{'offset': 0},
      );
      await repository.delAll();

      final List<void> events = await eventsFuture;
      expect(events.length, 2);

      await repository.dispose();
    });
  });
}

Future<List<LibraryLinkItem>> _readAll(LibraryLinkRepository repository) async {
  final int count = await repository.countItems();
  if (count == 0) {
    return const <LibraryLinkItem>[];
  }
  return repository.getPage(offset: 0, limit: count);
}
