import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/library_link_manager/application/library_link_manager_usecase.dart';
import 'package:lddc/src/features/library_link_manager/application/library_link_manager_page_controller.dart';
import 'package:lddc/src/features/library_link_manager/presentation/library_link_manager_dependencies.dart';
import 'package:lddc/src/features/library_link_manager/presentation/library_link_manager_page.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/platform/files/app_file_picker.dart';

void main() {
  testWidgets('关联库管理页使用扁平卡片、语义配置与路径 Tooltip', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    const String songPath =
        r'C:\library\very_long_artist_name\very_long_album_name\disc_01\track_01_song.mp3';
    const String lyricsPath =
        r'C:\lyrics\archive\2026\matched\very_long_artist_name\track_01_song.lrc';
    final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
      <LibraryLinkItem>[
        _buildItem(
          0,
          songPath: songPath,
          lyricsPath: lyricsPath,
          configSnapshot: const <String, Object?>{
            'offset': 250,
            'langs': <String>['orig', 'ts'],
            'disable_auto_search': true,
            'custom_mode': 'manual',
          },
        ),
      ],
    );
    addTearDown(repository.dispose);

    await _pumpPage(tester, repository);

    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.textContaining('无显式分页'), findsNothing);
    expect(find.textContaining('窗口缓存'), findsNothing);
    expect(find.text('已关联歌词'), findsNothing);
    expect(find.text('歌曲路径'), findsOneWidget);
    expect(find.text('歌词路径'), findsOneWidget);
    expect(find.text('轨道 1'), findsOneWidget);
    expect(find.text('偏移 +250ms'), findsOneWidget);
    expect(find.text('语言 原文/译文'), findsOneWidget);
    expect(find.text('禁用自动搜索'), findsOneWidget);
    expect(find.text('其他配置 1 项'), findsOneWidget);
    expect(
      find
          .byType(Row)
          .evaluate()
          .any(
            (Element element) => _subtreeContainsTexts(element, <String>[
              'Song 0',
              '轨道 1',
              '偏移 +250ms',
              '语言 原文/译文',
            ]),
          ),
      isTrue,
    );
    expect(find.text(songPath), findsOneWidget);
    expect(find.textContaining('very_long_album_name'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is Tooltip && widget.message == songPath,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is Tooltip && widget.message == lyricsPath,
      ),
      findsOneWidget,
    );
  });

  testWidgets('未关联歌词时在歌词路径位置提示并显示默认配置', (WidgetTester tester) async {
    final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
      <LibraryLinkItem>[_buildItem(3, lyricsPath: null)],
    );
    addTearDown(repository.dispose);

    await _pumpPage(tester, repository);

    expect(find.text('未关联歌词'), findsOneWidget);
    expect(find.text('默认配置'), findsOneWidget);
  });

  testWidgets('语义 Chip 与路径标签支持英文本地化', (WidgetTester tester) async {
    final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
      <LibraryLinkItem>[
        _buildItem(
          1,
          lyricsPath: null,
          configSnapshot: const <String, Object?>{
            'langs': <String>['orig', 'ts'],
          },
        ),
      ],
    );
    addTearDown(repository.dispose);

    await _pumpPage(tester, repository, locale: const Locale('en'));

    expect(find.text('Lyrics Path'), findsOneWidget);
    expect(find.text('Song Path'), findsOneWidget);
    expect(find.text('Track 2'), findsOneWidget);
    expect(find.text('Languages Original/Translation'), findsOneWidget);
    expect(find.text('No lyrics linked'), findsOneWidget);
  });

  testWidgets('窄屏英文与大字号下关联库条目不被固定高度裁切', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final _FakeLibraryLinkRepository
    repository = _FakeLibraryLinkRepository(<LibraryLinkItem>[
      _buildItem(
        7,
        songPath:
            r'C:\library\very_long_artist_name\very_long_album_name\disc_01\track_08_song.mp3',
        lyricsPath:
            r'C:\lyrics\archive\2026\matched\very_long_artist_name\track_08_song.lrc',
        configSnapshot: const <String, Object?>{
          'offset': 1200,
          'langs': <String>['orig', 'ts', 'roma'],
          'disable_auto_search': true,
          'custom_mode': 'manual',
          'prefer_source': 'kg',
          'save_policy': 'overwrite',
        },
      ),
    ]);
    addTearDown(repository.dispose);

    await _pumpPage(
      tester,
      repository,
      locale: const Locale('en'),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Other Config 3'), findsOneWidget);
  });

  testWidgets('关联库使用紧凑固定行高且桌面滚动条可直接拖动', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
      <LibraryLinkItem>[
        for (int index = 0; index < 300; index += 1) _buildItem(index),
      ],
    );
    addTearDown(repository.dispose);

    await _pumpPage(tester, repository);

    final ListView listView = tester.widget<ListView>(find.byType(ListView));
    final Scrollbar scrollbar = tester.widget<Scrollbar>(
      find.byType(Scrollbar),
    );
    expect(listView.itemExtent, 148);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.trackVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.controller, same(listView.controller));

    final Finder scrollbarFinder = find.byType(Scrollbar);
    final Offset topRight = tester.getTopRight(scrollbarFinder);
    final double height = tester.getSize(scrollbarFinder).height;
    final TestGesture gesture = await tester.startGesture(
      topRight + const Offset(-6, 10),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(Offset(0, height * 0.55));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(listView.controller!.offset, greaterThan(0));
  });

  testWidgets('搜索防抖只提交最终关键词并在筛选变化时清空选择', (WidgetTester tester) async {
    final _FakeLibraryLinkRepository repository =
        _FakeLibraryLinkRepository(<LibraryLinkItem>[
          _buildItem(0),
          _buildItem(1),
          _buildItem(2, songPath: r'C:\target\matched_song.mp3'),
        ]);
    addTearDown(repository.dispose);
    await _pumpPage(tester, repository);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.textContaining('已选择 1 条记录'), findsOneWidget);

    final Finder searchField = find.byType(TextField);
    await tester.enterText(searchField, 'not-final');
    await tester.pump(const Duration(milliseconds: 120));
    await tester.enterText(searchField, 'target');
    await tester.pump(const Duration(milliseconds: 249));
    expect(repository.countSearchTexts, isNot(contains('not-final')));
    expect(repository.countSearchTexts, isNot(contains('target')));

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(repository.countSearchTexts, contains('target'));
    expect(find.text('Song 2'), findsOneWidget);
    expect(find.text('Song 0'), findsNothing);
    expect(find.textContaining('已选择 0 条记录'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('Song 0'), findsOneWidget);
    expect(find.textContaining('共 3 条记录'), findsOneWidget);
  });

  testWidgets('较慢的旧搜索结果不会覆盖后提交的新搜索', (WidgetTester tester) async {
    final _FakeLibraryLinkRepository repository =
        _FakeLibraryLinkRepository(<LibraryLinkItem>[
          _buildItem(0, songPath: r'C:\slow\song.mp3'),
          _buildItem(1, songPath: r'C:\fast\song.mp3'),
        ]);
    addTearDown(repository.dispose);
    await _pumpPage(tester, repository);

    final Completer<void> slowCount = Completer<void>();
    repository.countBlockers['slow'] = slowCount;
    await tester.enterText(find.byType(TextField), 'slow');
    await tester.pump(LibraryLinkManagerPageController.searchDebounceDuration);
    expect(repository.countSearchTexts, contains('slow'));

    await tester.enterText(find.byType(TextField), 'fast');
    await tester.pump(LibraryLinkManagerPageController.searchDebounceDuration);
    await tester.pump();
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Song 0'), findsNothing);

    slowCount.complete();
    await tester.pumpAndSettle();
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Song 0'), findsNothing);
  });

  testWidgets('失败 chunk 不会由占位重建循环请求且刷新可以重试', (WidgetTester tester) async {
    final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
      <LibraryLinkItem>[
        for (int index = 0; index < 450; index += 1) _buildItem(index),
      ],
    );
    repository.failPageOffsets.add(200);
    addTearDown(repository.dispose);
    await _pumpPage(tester, repository);

    int failedCalls() =>
        repository.pageOffsets.where((int offset) => offset == 200).length;
    expect(failedCalls(), 1);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryLinkManagerPage)),
    );
    container
        .read(libraryLinkManagerPageControllerProvider.notifier)
        .handleRequiredIndexes(<int>[250]);
    await tester.pumpAndSettle();
    expect(failedCalls(), 1);

    repository.failPageOffsets.clear();
    await container
        .read(libraryLinkManagerPageControllerProvider.notifier)
        .refresh();
    await tester.pumpAndSettle();
    expect(failedCalls(), 2);
  });

  testWidgets('2800 条记录快速跳到末尾后加载目标 chunk 且缓存保持有界', (WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final _FakeLibraryLinkRepository repository = _FakeLibraryLinkRepository(
      <LibraryLinkItem>[
        for (int index = 0; index < 2800; index += 1)
          _buildItem(
            index,
            configSnapshot: index.isEven
                ? const <String, Object?>{}
                : const <String, Object?>{
                    'offset': 120,
                    'langs': <String>['orig', 'ts'],
                    'disable_auto_search': true,
                  },
          ),
      ],
    );
    addTearDown(repository.dispose);
    await _pumpPage(tester, repository);

    final ScrollController scrollController = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    for (int attempt = 0; attempt < 4; attempt += 1) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(find.text('Song 2799'), findsOneWidget);
    expect(repository.pageOffsets, contains(2600));
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryLinkManagerPage)),
    );
    expect(
      container
          .read(libraryLinkManagerPageControllerProvider)
          .loadedChunks
          .length,
      lessThanOrEqualTo(LibraryLinkManagerPageController.maxRetainedChunkCount),
    );
    expect(tester.takeException(), isNull);
  });
}

bool _subtreeContainsTexts(Element element, List<String> texts) {
  final Set<String> remaining = texts.toSet();

  void visit(Element child) {
    if (remaining.isEmpty) {
      return;
    }
    final Widget widget = child.widget;
    if (widget is Text && widget.data != null) {
      remaining.remove(widget.data);
    }
    child.visitChildren(visit);
  }

  visit(element);
  return remaining.isEmpty;
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeLibraryLinkRepository repository, {
  Locale locale = const Locale('zh'),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryLinkRepositoryProvider.overrideWithValue(repository),
        libraryLinkManagerDependenciesProvider.overrideWithValue(
          LibraryLinkManagerDependencies(
            repository: repository,
            filePicker: _FakeAppFilePicker(),
            useCase: LibraryLinkManagerUseCase(
              repository: repository,
              fileExists: (String path) async => !path.startsWith('missing://'),
            ),
            returnToSettings: () async {},
          ),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: const Scaffold(body: LibraryLinkManagerPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

LibraryLinkItem _buildItem(
  int index, {
  String? songPath,
  String? lyricsPath = r'C:\lyrics\song.lrc',
  Map<String, Object?> configSnapshot = const <String, Object?>{},
}) {
  final SongInfo song = SongInfo(
    source: Source.local,
    id: '${index + 1}',
    title: 'Song $index',
    artist: SongArtist(<String>['Artist $index']),
    album: 'Album $index',
    path: songPath ?? 'C:\\library\\album_$index\\song_$index.mp3',
  );
  return LibraryLinkItem(
    id: index + 1,
    song: song,
    key: LibraryLinkKey.fromSong(song),
    lyricsPath: lyricsPath,
    configSnapshot: configSnapshot,
  );
}

class _FakeLibraryLinkRepository implements LibraryLinkRepository {
  _FakeLibraryLinkRepository(List<LibraryLinkItem> items)
    : _items = List<LibraryLinkItem>.from(items);

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<LibraryLinkItem> _items;
  final List<int> pageOffsets = <int>[];
  final List<String> countSearchTexts = <String>[];
  final Map<String, Completer<void>> countBlockers =
      <String, Completer<void>>{};
  final Set<int> failPageOffsets = <int>{};
  final Set<int> deletedIds = <int>{};

  @override
  Future<int> countItems({String searchText = ''}) async {
    countSearchTexts.add(searchText);
    await countBlockers[searchText]?.future;
    return _filteredItems(searchText).length;
  }

  @override
  Future<void> delAll() async {
    _items.clear();
    _changes.add(null);
  }

  @override
  Future<void> delItem(int id) async {
    _items.removeWhere((LibraryLinkItem item) => item.id == id);
    deletedIds.add(id);
    _changes.add(null);
  }

  @override
  Future<void> delItems(Iterable<int> ids) async {
    final Set<int> idSet = ids.toSet();
    _items.removeWhere((LibraryLinkItem item) => idSet.contains(item.id));
    deletedIds.addAll(idSet);
    _changes.add(null);
  }

  @override
  Future<void> dispose() async {
    await _changes.close();
  }

  @override
  Future<LibraryLinkItem?> getItem(int id) async {
    for (final LibraryLinkItem item in _items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<List<LibraryLinkItem>> getPage({
    required int offset,
    required int limit,
    String searchText = '',
  }) async {
    pageOffsets.add(offset);
    if (failPageOffsets.contains(offset)) {
      throw StateError('模拟 chunk 加载失败: $offset');
    }
    final List<LibraryLinkItem> filtered = _filteredItems(searchText);
    if (offset >= filtered.length || limit <= 0) {
      return const <LibraryLinkItem>[];
    }
    final int end = (offset + limit) > filtered.length
        ? filtered.length
        : (offset + limit);
    return filtered.sublist(offset, end);
  }

  List<LibraryLinkItem> _filteredItems(String searchText) {
    final String query = searchText.trim().toLowerCase();
    if (query.isEmpty) {
      return _items;
    }
    return _items
        .where((LibraryLinkItem item) {
          return <String>[
            item.song.title ?? '',
            item.song.artistText,
            item.song.album ?? '',
            item.song.path ?? '',
            item.lyricsPath ?? '',
          ].any((String value) => value.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<LibraryLinkItem?> query(SongInfo song) async => null;

  @override
  Future<LibraryLinkItem> setSong({
    required SongInfo song,
    String? lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) async {
    final LibraryLinkItem item = LibraryLinkItem(
      id: _items.isEmpty ? 1 : (_items.last.id + 1),
      song: song,
      key: LibraryLinkKey.fromSong(song),
      lyricsPath: lyricsPath,
      configSnapshot: configSnapshot,
    );
    _items.add(item);
    _changes.add(null);
    return item;
  }

  @override
  Future<void> setSongs(Iterable<LibraryLinkUpsertItem> items) async {
    for (final LibraryLinkUpsertItem item in items) {
      await setSong(
        song: item.song,
        lyricsPath: item.lyricsPath,
        configSnapshot: item.configSnapshot,
      );
    }
  }

  @override
  Future<void> replaceAll(Iterable<LibraryLinkUpsertItem> items) async {
    _items.clear();
    await setSongs(items);
  }

  @override
  Future<void> rewriteItems(Iterable<LibraryLinkRewriteItem> items) async {
    final List<LibraryLinkRewriteItem> rewrites = items.toList(growable: false);
    final Set<int> ids = rewrites
        .map((LibraryLinkRewriteItem item) => item.originalId)
        .toSet();
    _items.removeWhere((LibraryLinkItem item) => ids.contains(item.id));
    await setSongs(rewrites.map((LibraryLinkRewriteItem item) => item.upsert));
  }

  @override
  Stream<void> watchChanges({bool emitCurrent = false}) async* {
    if (emitCurrent) {
      yield null;
    }
    yield* _changes.stream;
  }
}

class _FakeAppFilePicker implements AppFilePicker {
  @override
  Future<String?> pickDirectory({String? initialDirectory}) async => null;

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({String? initialDirectory}) {
    return Future<PickedAudioFileHandle?>.value();
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) async => file;

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    return null;
  }

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    return const <PickedFileHandle>[];
  }

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) async {}

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    return null;
  }
}
