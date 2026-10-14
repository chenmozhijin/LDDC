import 'dart:typed_data';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('AndroidSafLyricsScanUseCase', () {
    test('递归扫描：嵌套目录按相对层级拼出可读落点，并过滤非歌词文件', () async {
      const String rootUri = 'content://tree/root';
      const String albumUri = 'content://doc/album';
      const String discUri = 'content://doc/disc';
      const String topLyricsUri = 'content://doc/top.lrc';
      const String albumLyricsUri = 'content://doc/album-song.srt';
      const String discLyricsUri = 'content://doc/disc-song.ass';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            _entry(albumUri, 'Album', isDirectory: true),
            _entry(topLyricsUri, 'top.lrc'),
          ],
          albumUri: <AndroidSafTreeEntry>[
            _entry(albumLyricsUri, 'album.srt'),
            _entry(discUri, 'Disc 1', isDirectory: true),
            // 非歌词扩展名必须被过滤掉。
            _entry('content://doc/cover.jpg', 'cover.jpg'),
            _entry('content://doc/no-extension', 'no-extension'),
          ],
          discUri: <AndroidSafTreeEntry>[_entry(discLyricsUri, 'disc.ass')],
        },
      );
      final List<List<SafDocumentSource>> chunks = <List<SafDocumentSource>>[];
      final List<AndroidSafLyricsScanProgress> progress =
          <AndroidSafLyricsScanProgress>[];

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(
              uri: rootUri,
              displayName: '音乐',
            ),
            recursive: true,
            onChunk: chunks.add,
            onProgress: progress.add,
          );

      final List<SafDocumentSource> sources = chunks
          .expand((List<SafDocumentSource> chunk) => chunk)
          .toList(growable: false);
      expect(result.cancelled, isFalse);
      expect(result.errors, isEmpty);
      expect(result.foundCount, 3);
      expect(sources, hasLength(3));
      // BFS 顺序：先枚举根目录，再进子目录。
      expect(
        sources.map((SafDocumentSource source) => source.documentUri),
        <String>[topLyricsUri, albumLyricsUri, discLyricsUri],
      );
      // 每个源都要带齐 documentUri / 源树 URI / 源树显示名 / 可读落点：缺任一项，
      // 批量转换的"镜像源目录层级"就无法推导。
      expect(
        sources.map((SafDocumentSource source) => source.treeUri).toSet(),
        <String>{rootUri},
      );
      expect(
        sources.map((SafDocumentSource source) => source.treeLabel).toSet(),
        <String>{'音乐'},
      );
      expect(
        sources.map((SafDocumentSource source) => source.displayPath),
        <String>[
          '音乐 / top.lrc',
          '音乐 / Album/album.srt',
          '音乐 / Album/Disc 1/disc.ass',
        ],
      );
      // 可读落点里只有"树显示名"和"树内相对路径"之间用 ` / ` 连接，取文件名才能
      // 直接按 `/` 切最后一段。
      expect(
        sources.map((SafDocumentSource source) => source.displayName),
        <String>['top.lrc', 'album.srt', 'disc.ass'],
      );

      // 进度里能看到正在枚举的目录（根目录用树显示名）。
      expect(
        progress
            .map(
              (AndroidSafLyricsScanProgress item) => item.currentDirectoryLabel,
            )
            .toList(growable: false),
        <String>['音乐', 'Album', 'Album/Disc 1'],
      );
      expect(progress.last.scannedDirectoryCount, 3);
    });

    test('分页枚举跟随 nextOffset 续页，并按 chunkSize 分批交付', () async {
      const String rootUri = 'content://tree/root';
      const int totalCount = 5;
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        pageSize: 2,
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            for (int index = 0; index < totalCount; index += 1)
              _entry('content://doc/song-$index.lrc', 'song-$index.lrc'),
          ],
        },
      );
      final List<List<SafDocumentSource>> chunks = <List<SafDocumentSource>>[];

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(uri: rootUri),
            recursive: true,
            onChunk: chunks.add,
          );

      expect(result.foundCount, totalCount);
      // 每页 2 条 → 至少 3 次分页请求，说明真的跟着 nextOffset 续页。
      expect(treePort.listChildrenPageCalls, greaterThanOrEqualTo(3));
      expect(
        chunks.expand((List<SafDocumentSource> chunk) => chunk),
        hasLength(totalCount),
      );
    });

    test('非递归模式只扫描所选树的直接子项', () async {
      const String rootUri = 'content://tree/root';
      const String albumUri = 'content://doc/album';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            _entry('content://doc/top.lrc', 'top.lrc'),
            _entry(albumUri, 'Album', isDirectory: true),
          ],
          albumUri: <AndroidSafTreeEntry>[
            _entry('content://doc/nested.lrc', 'nested.lrc'),
          ],
        },
      );
      final List<SafDocumentSource> sources = <SafDocumentSource>[];

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(
              uri: rootUri,
              displayName: '音乐',
            ),
            recursive: false,
            onChunk: sources.addAll,
          );

      expect(result.foundCount, 1);
      expect(
        sources.map((SafDocumentSource source) => source.displayPath),
        <String>['音乐 / top.lrc'],
      );
      // 子目录根本不会被枚举。
      expect(treePort.requestedUris, <String>[rootUri]);
    });

    test('取消后立即结束，且不再交付或请求后续内容', () async {
      const String rootUri = 'content://tree/root';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            _entry('content://doc/first.lrc', 'first.lrc'),
            _entry('content://doc/second.lrc', 'second.lrc'),
          ],
        },
      );
      final List<SafDocumentSource> sources = <SafDocumentSource>[];
      // 第一次检查（进入根目录前）放行，第二次检查（处理第一条目之前）即取消。
      int cancelChecks = 0;
      bool shouldCancel() {
        cancelChecks += 1;
        return cancelChecks > 1;
      }

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(uri: rootUri),
            recursive: true,
            onChunk: sources.addAll,
            shouldCancel: shouldCancel,
          );

      expect(result.cancelled, isTrue);
      expect(sources, isEmpty);
      expect(result.foundCount, 0);
      // 取消在第一页内生效：不会再请求后续分页。
      expect(treePort.requestedUris, <String>[rootUri]);
    });

    test('单个目录枚举失败只记录错误，不影响其余目录', () async {
      const String rootUri = 'content://tree/root';
      const String brokenUri = 'content://doc/broken';
      const String albumUri = 'content://doc/album';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            _entry(brokenUri, 'Broken', isDirectory: true),
            _entry(albumUri, 'Album', isDirectory: true),
          ],
          albumUri: <AndroidSafTreeEntry>[
            _entry('content://doc/ok.lrc', 'ok.lrc'),
          ],
        },
        failingUris: <String>{brokenUri},
      );
      final List<SafDocumentSource> sources = <SafDocumentSource>[];

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(
              uri: rootUri,
              displayName: '音乐',
            ),
            recursive: true,
            onChunk: sources.addAll,
          );

      expect(result.cancelled, isFalse);
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains(brokenUri));
      expect(result.foundCount, 1);
      expect(sources.single.displayPath, '音乐 / Album/ok.lrc');
    });

    test('目录项既不是文件也不是目录时留下错误而不是静默跳过', () async {
      const String rootUri = 'content://tree/root';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            const AndroidSafTreeEntry(
              uri: 'content://doc/weird',
              displayName: 'weird.lrc',
              mimeType: null,
              isDirectory: false,
              isFile: false,
            ),
          ],
        },
      );

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(uri: rootUri),
            recursive: true,
            onChunk: (List<SafDocumentSource> _) {},
          );

      expect(result.foundCount, 0);
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('weird.lrc'));
    });

    test('分页偏移不前进时记录错误并停止，不会原地死循环', () async {
      const String rootUri = 'content://tree/root';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        // 固定返回 nextOffset=0：非法实现会让"跟随 nextOffset"的循环永远取同一页。
        stuckNextOffset: 0,
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            _entry('content://doc/a.lrc', 'a.lrc'),
          ],
        },
      );

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(uri: rootUri),
            recursive: true,
            onChunk: (List<SafDocumentSource> _) {},
          );

      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('分页偏移未前进'));
      // 首页仍然正常枚举：错误只影响续页。
      expect(result.foundCount, 1);
      expect(treePort.listChildrenPageCalls, 1);
    });

    test('扩展名大小写不敏感，并与本地歌词输入白名单一致', () async {
      const String rootUri = 'content://tree/root';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            _entry('content://doc/upper.LRC', 'upper.LRC'),
            _entry('content://doc/mixed.Qrc', 'mixed.Qrc'),
            _entry('content://doc/ignored.mp3', 'ignored.mp3'),
          ],
        },
      );
      final List<SafDocumentSource> sources = <SafDocumentSource>[];

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(uri: rootUri),
            recursive: true,
            onChunk: sources.addAll,
          );

      expect(result.foundCount, 2);
      expect(
        sources.map((SafDocumentSource source) => source.displayName),
        <String>['upper.LRC', 'mixed.Qrc'],
      );
      // 白名单必须来自运行时统一常量，而不是本用例另立一份。
      expect(localLyricsInputSupportedExtensions, contains('lrc'));
    });

    test('树显示名为空时只保留树内相对路径', () async {
      const String rootUri = 'content://tree/root';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            _entry('content://doc/a.lrc', 'a.lrc'),
          ],
        },
      );
      final List<SafDocumentSource> sources = <SafDocumentSource>[];

      await AndroidSafLyricsScanUseCase(treePort: treePort).run(
        rootTree: const AndroidSafTreeToken(uri: rootUri),
        recursive: true,
        onChunk: sources.addAll,
      );

      expect(sources.single.treeLabel, '');
      expect(sources.single.displayPath, 'a.lrc');
    });

    test('同一文档被多个目录返回时只交付一次', () async {
      const String rootUri = 'content://tree/root';
      const String albumUri = 'content://doc/album';
      const String lyricsUri = 'content://doc/shared.lrc';
      final _FakeSafTreePort treePort = _FakeSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          rootUri: <AndroidSafTreeEntry>[
            _entry(lyricsUri, 'shared.lrc'),
            _entry(albumUri, 'Album', isDirectory: true),
          ],
          albumUri: <AndroidSafTreeEntry>[_entry(lyricsUri, 'shared.lrc')],
        },
      );
      final List<SafDocumentSource> sources = <SafDocumentSource>[];

      final AndroidSafLyricsScanResult result =
          await AndroidSafLyricsScanUseCase(treePort: treePort).run(
            rootTree: const AndroidSafTreeToken(uri: rootUri),
            recursive: true,
            onChunk: sources.addAll,
          );

      expect(result.foundCount, 1);
      expect(sources, hasLength(1));
      expect(sources.single.displayPath, 'shared.lrc');
    });
  });
}

AndroidSafTreeEntry _entry(
  String uri,
  String displayName, {
  bool isDirectory = false,
}) {
  return AndroidSafTreeEntry(
    uri: uri,
    displayName: displayName,
    mimeType: isDirectory
        ? 'vnd.android.document/directory'
        : 'application/octet-stream',
    isDirectory: isDirectory,
    isFile: !isDirectory,
  );
}

/// 内存 SAF 目录树：按 `listChildrenPage` 契约分页返回，并支持注入枚举失败。
class _FakeSafTreePort implements AndroidSafTreePort {
  _FakeSafTreePort({
    required this.childrenByUri,
    this.pageSize = 128,
    this.stuckNextOffset,
    Set<String>? failingUris,
  }) : failingUris = failingUris ?? const <String>{};

  final Map<String, List<AndroidSafTreeEntry>> childrenByUri;

  /// 每次分页最多返回几条：用来强制走 `nextOffset` 续页分支。
  ///
  /// 真实端口对同一 limit 每次返回相同页大小，因此这里固定 pageSize，不按 limit
  /// 收缩——否则后续页会一次性返回剩余条目，就验证不到"跟随 nextOffset"。
  final int pageSize;

  /// 非空时固定返回该 nextOffset（用于验证非法端口不会让扫描原地死循环）。
  final int? stuckNextOffset;

  /// 这些 URI 的枚举请求会抛 [Exception]，用于验证"错误收集但不中断"。
  final Set<String> failingUris;

  final List<String> requestedUris = <String>[];
  int listChildrenPageCalls = 0;

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    listChildrenPageCalls += 1;
    requestedUris.add(uri);
    if (failingUris.contains(uri)) {
      throw Exception('枚举失败：$uri');
    }
    final List<AndroidSafTreeEntry> entries =
        childrenByUri[uri] ?? const <AndroidSafTreeEntry>[];
    final int? stuck = stuckNextOffset;
    if (stuck != null) {
      return AndroidSafTreePage(entries: entries, nextOffset: stuck);
    }
    if (offset >= entries.length) {
      return AndroidSafTreePage(
        entries: const <AndroidSafTreeEntry>[],
        nextOffset: null,
      );
    }
    final int end = offset + pageSize < entries.length
        ? offset + pageSize
        : entries.length;
    return AndroidSafTreePage(
      entries: entries.sublist(offset, end),
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

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required List<String> directorySegments,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) {
    throw UnimplementedError();
  }
}
