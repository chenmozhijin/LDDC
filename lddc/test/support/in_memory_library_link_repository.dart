import 'package:lddc/src/core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 仅供不需要 SQLite 的 Provider/widget 测试使用的关联库内存替身。
///
/// 该实现不创建 StreamController、文件或数据库句柄，因此测试容器销毁时不会
/// 留下异步资源；数据量只由单个测试显式写入的记录决定，不参与生产装配。
final class InMemoryLibraryLinkRepository implements LibraryLinkRepository {
  final Map<int, LibraryLinkItem> _items = <int, LibraryLinkItem>{};
  int _nextId = 1;
  bool _disposed = false;

  @override
  Future<void> initialize() async => _ensureOpen();

  @override
  Future<LibraryLinkItem> setSong({
    required SongInfo song,
    String? lyricsPath,
    Map<String, Object?> configSnapshot = const <String, Object?>{},
  }) async {
    _ensureOpen();
    final LibraryLinkKey key = LibraryLinkKey.fromSong(song);
    final LibraryLinkItem? existing = await query(song);
    final LibraryLinkItem item = LibraryLinkItem(
      id: existing?.id ?? _nextId++,
      song: song,
      key: key,
      lyricsPath: lyricsPath,
      configSnapshot: configSnapshot,
    );
    _items[item.id] = item;
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
    _ensureOpen();
    _items.clear();
    _nextId = 1;
    await setSongs(items);
  }

  @override
  Future<void> rewriteItems(Iterable<LibraryLinkRewriteItem> items) async {
    _ensureOpen();
    for (final LibraryLinkRewriteItem item in items) {
      _items.remove(item.originalId);
      await setSong(
        song: item.upsert.song,
        lyricsPath: item.upsert.lyricsPath,
        configSnapshot: item.upsert.configSnapshot,
      );
    }
  }

  @override
  Future<LibraryLinkItem?> query(SongInfo song) async {
    _ensureOpen();
    final LibraryLinkKey key = LibraryLinkKey.fromSong(song);
    for (final LibraryLinkItem item in _items.values) {
      if (item.key == key) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<LibraryLinkItem?> getItem(int id) async {
    _ensureOpen();
    return _items[id];
  }

  @override
  Future<int> countItems({String searchText = ''}) async {
    _ensureOpen();
    return _filteredItems(searchText).length;
  }

  @override
  Future<List<LibraryLinkItem>> getPage({
    required int offset,
    required int limit,
    String searchText = '',
  }) async {
    _ensureOpen();
    return (_filteredItems(searchText)..sort(
          (LibraryLinkItem left, LibraryLinkItem right) =>
              left.id.compareTo(right.id),
        ))
        .skip(offset)
        .take(limit)
        .toList(growable: false);
  }

  List<LibraryLinkItem> _filteredItems(String searchText) {
    final String query = searchText.trim().toLowerCase();
    final Iterable<LibraryLinkItem> values = _items.values;
    if (query.isEmpty) {
      return values.toList(growable: false);
    }
    return values
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
  Future<void> delItem(int id) async {
    _ensureOpen();
    _items.remove(id);
  }

  @override
  Future<void> delItems(Iterable<int> ids) async {
    _ensureOpen();
    for (final int id in ids) {
      _items.remove(id);
    }
  }

  @override
  Future<void> delAll() async {
    _ensureOpen();
    _items.clear();
  }

  @override
  Stream<void> watchChanges({bool emitCurrent = false}) async* {
    _ensureOpen();
    if (emitCurrent) {
      yield null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _items.clear();
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('InMemoryLibraryLinkRepository 已释放');
    }
  }
}
