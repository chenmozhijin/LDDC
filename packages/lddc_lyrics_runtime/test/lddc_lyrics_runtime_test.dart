import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('便利 runtime 使用内置本地来源并幂等释放全部自有资源', () async {
    final _MemoryCacheStore store = _MemoryCacheStore();
    final LddcLyricsRuntime runtime = await LddcLyricsRuntime.create(
      cacheStore: store,
      translationOptionsResolver: _translationOptions,
      memoryCacheCapacity: 8,
    );
    expect(runtime.lyrics, isA<LyricsClient>());
    expect(runtime.translation, isA<TranslationClient>());

    final Lyrics lyrics = await runtime.lyrics.getLyrics(
      data: Uint8List.fromList(utf8.encode('[00:01.00]Runtime line\n')),
    );
    expect(lyrics['orig']?.single.text, 'Runtime line');

    final Future<void> firstClose = runtime.close();
    final Future<void> secondClose = runtime.close();
    expect(identical(firstClose, secondClose), isTrue);
    await firstClose;
    expect(runtime.isClosed, isTrue);
    expect(store.disposed, isTrue);
  });
}

TranslationOptions _translationOptions() {
  return const TranslationOptions(
    source: TranslateSource.bing,
    targetLang: TranslateTargetLang.simplifiedChinese,
    openAi: OpenAiConfig(
      profile: OpenAiProfile.custom,
      baseUrl: '',
      apiKey: '',
      model: '',
    ),
  );
}

final class _MemoryCacheStore extends CacheStore {
  final Map<String, CacheStoreEntry> _entries = <String, CacheStoreEntry>{};
  final StreamController<CacheStats> _stats =
      StreamController<CacheStats>.broadcast();
  bool disposed = false;

  String _key(String namespace, String key) => '$namespace::$key';

  @override
  Future<void> initialize() async {
    if (disposed) {
      throw StateError('测试缓存已释放');
    }
  }

  @override
  Future<void> ensureNamespaceVersion(
    String namespace,
    int cacheVersion,
  ) async {}

  @override
  Future<CacheStoreEntry?> getEntry(String namespace, String key) async {
    return _entries[_key(namespace, key)];
  }

  @override
  Future<void> set(
    String namespace,
    String key,
    Object? value, {
    Duration? ttl,
  }) async {
    _entries[_key(namespace, key)] = CacheStoreEntry(value: value);
  }

  @override
  Future<Object?> updateAtomically(
    String namespace,
    String key,
    Object? Function(Object? current) update, {
    Duration? ttl,
  }) async {
    final String compositeKey = _key(namespace, key);
    final Object? value = update(_entries[compositeKey]?.value);
    _entries[compositeKey] = CacheStoreEntry(value: value);
    return value;
  }

  @override
  Future<void> remove(String namespace, String key) async {
    _entries.remove(_key(namespace, key));
  }

  @override
  Future<void> clearNamespace(String namespace) async {
    _entries.removeWhere((String key, _) => key.startsWith('$namespace::'));
  }

  @override
  Future<void> clearAll() async {
    _entries.clear();
  }

  @override
  Future<CacheStats> stats({String? namespace}) async {
    return CacheStats.empty;
  }

  @override
  Stream<CacheStats> watchStats({
    String? namespace,
    bool emitCurrent = true,
  }) async* {
    if (emitCurrent) {
      yield CacheStats.empty;
    }
    yield* _stats.stream;
  }

  @override
  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    _entries.clear();
    await _stats.close();
  }
}
