import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/core/library_link/library_link.dart';
import 'package:lddc/src/features/library_link_manager/application/library_link_manager_page_controller.dart';
import 'package:lddc/src/features/library_link_manager/application/library_link_manager_usecase.dart';
import 'package:lddc/src/features/library_link_manager/presentation/library_link_manager_dependencies.dart';
import 'package:lddc/src/features/library_link_manager/presentation/library_link_manager_page.dart';
import 'package:lddc/src/platform/files/app_file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  testWidgets('关联管理器 2800 条记录快速往返保持帧和缓存有界', (WidgetTester tester) async {
    final _PerformanceLibraryLinkRepository repository =
        _PerformanceLibraryLinkRepository(<LibraryLinkItem>[
          for (int index = 0; index < 2800; index += 1) _buildItem(index),
        ]);
    addTearDown(repository.dispose);

    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryLinkManagerDependenciesProvider.overrideWithValue(
            LibraryLinkManagerDependencies(
              repository: repository,
              filePicker: const AppFilePickerImpl(),
              useCase: LibraryLinkManagerUseCase(
                repository: repository,
                fileExists: (String path) async => true,
              ),
              returnToSettings: () async {},
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibraryLinkManagerPage()),
        ),
      ),
    );
    await _pumpForAsyncWork(tester);

    final ScrollController scrollController = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    // 先完成两轮预热，让首屏 chunk 和渲染缓存不计入往返样本。
    for (int attempt = 0; attempt < 2; attempt += 1) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await _pumpForAsyncWork(tester);
      scrollController.jumpTo(0);
      await _pumpForAsyncWork(tester);
    }

    final List<FrameTiming> timings = <FrameTiming>[];
    void collectTimings(List<FrameTiming> values) {
      timings.addAll(values);
    }

    WidgetsBinding.instance.addTimingsCallback(collectTimings);
    final int rssBefore = ProcessInfo.currentRss;
    for (int attempt = 0; attempt < 20; attempt += 1) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await _pumpForAsyncWork(tester);
      scrollController.jumpTo(0);
      await _pumpForAsyncWork(tester);
    }
    final int rssAfter = ProcessInfo.currentRss;
    WidgetsBinding.instance.removeTimingsCallback(collectTimings);

    final int longFrameCount = timings
        .where(
          (FrameTiming timing) =>
              timing.totalSpan > const Duration(milliseconds: 100),
        )
        .length;
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryLinkManagerPage)),
    );
    final int cachedChunkCount = container
        .read(libraryLinkManagerPageControllerProvider)
        .loadedChunks
        .length;
    final Map<String, Object> report = <String, Object>{
      'frameCount': timings.length,
      'longFrameCountOver100ms': longFrameCount,
      'rssBefore': rssBefore,
      'rssAfter': rssAfter,
      'rssDelta': rssAfter - rssBefore,
      'cachedChunkCount': cachedChunkCount,
    };
    // 该输出会被 profile 验收脚本采集到报告中，便于比较不同实现的趋势。
    // 断言只关注长帧、无界缓存和异常大的单轮 RSS 增长，避免机器基线差异造成误报。
    debugPrint('LIBRARY_LINK_PERFORMANCE ${jsonEncode(report)}');
    expect(longFrameCount, 0);
    expect(cachedChunkCount, lessThanOrEqualTo(4));
    expect(rssAfter - rssBefore, lessThan(64 * 1024 * 1024));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpForAsyncWork(WidgetTester tester) async {
  // profile engine 里的 Scrollbar 和 Material 状态可能持续安排动画帧，
  // 因此使用有界帧窗口等待 chunk 查询，而不是依赖“完全无计划帧”。
  for (int frame = 0; frame < 6; frame += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

LibraryLinkItem _buildItem(int index) {
  final SongInfo song = SongInfo(
    source: Source.local,
    title: 'Performance Song $index',
    artist: SongArtist(<String>['Artist $index']),
    album: 'Album $index',
    durationMs: 180000 + index,
    path: 'C:\\performance\\song_$index.mp3',
    id: '$index',
  );
  return LibraryLinkItem(
    id: index + 1,
    song: song,
    key: LibraryLinkKey.fromSong(song),
    lyricsPath: 'C:\\performance\\lyrics_$index.lrc',
  );
}

final class _PerformanceLibraryLinkRepository implements LibraryLinkRepository {
  _PerformanceLibraryLinkRepository(this._items);

  final List<LibraryLinkItem> _items;

  @override
  Future<void> initialize() async {}

  @override
  Future<int> countItems({String searchText = ''}) async =>
      _filter(searchText).length;

  @override
  Future<List<LibraryLinkItem>> getPage({
    required int offset,
    required int limit,
    String searchText = '',
  }) async => _filter(searchText).skip(offset).take(limit).toList();

  List<LibraryLinkItem> _filter(String searchText) {
    final String query = searchText.trim().toLowerCase();
    if (query.isEmpty) {
      return _items;
    }
    return _items
        .where(
          (LibraryLinkItem item) => <String>[
            item.song.title ?? '',
            item.song.artistText,
            item.song.album ?? '',
            item.song.path ?? '',
            item.lyricsPath ?? '',
          ].any((String value) => value.toLowerCase().contains(query)),
        )
        .toList(growable: false);
  }

  @override
  Stream<void> watchChanges({bool emitCurrent = false}) async* {
    if (emitCurrent) {
      yield null;
    }
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<LibraryLinkItem?> getItem(int id) async =>
      id > 0 && id <= _items.length ? _items[id - 1] : null;

  @override
  Future<LibraryLinkItem?> query(SongInfo song) async => null;

  @override
  Future<void> delAll() => throw UnsupportedError('性能 smoke 不执行写操作');

  @override
  Future<void> delItem(int id) => throw UnsupportedError('性能 smoke 不执行写操作');

  @override
  Future<void> delItems(Iterable<int> ids) =>
      throw UnsupportedError('性能 smoke 不执行写操作');

  @override
  Future<void> replaceAll(Iterable<LibraryLinkUpsertItem> items) =>
      throw UnsupportedError('性能 smoke 不执行写操作');

  @override
  Future<void> rewriteItems(Iterable<LibraryLinkRewriteItem> items) =>
      throw UnsupportedError('性能 smoke 不执行写操作');

  @override
  Future<LibraryLinkItem> setSong({
    required SongInfo song,
    String? lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) => throw UnsupportedError('性能 smoke 不执行写操作');

  @override
  Future<void> setSongs(Iterable<LibraryLinkUpsertItem> items) =>
      throw UnsupportedError('性能 smoke 不执行写操作');
}
