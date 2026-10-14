import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:test/test.dart';

const String _treeUri = 'content://provider/tree/primary%3AMusic';

void main() {
  group('SafBatchConvertFileIo', () {
    late _FakeTreePort treePort;
    late _FakeContentPort contentPort;
    late _FakeLocalFileIo localFileIo;
    late SafBatchConvertFileIo io;

    setUp(() {
      treePort = _FakeTreePort();
      contentPort = _FakeContentPort();
      localFileIo = _FakeLocalFileIo();
      io = SafBatchConvertFileIo(
        treePort: treePort,
        contentPort: contentPort,
        localFileIo: localFileIo,
      );
    });

    test('本地源与本地目标一律委托给本地实现', () async {
      final Uint8List bytes = await io.readBytes(
        const LocalFileSource('a.lrc'),
      );
      expect(bytes, localFileIo.bytes);

      await io.writeText(
        source: const LocalFileSource('a.lrc'),
        target: const LocalFileTarget('a.srt'),
        text: 'x',
        allowOverwrite: false,
      );
      expect(localFileIo.writeTargets, <String>['a.srt']);
    });

    test('SAF 源经内容端口读取', () async {
      final Uint8List bytes = await io.readBytes(
        const SafDocumentSource(
          documentUri: 'content://provider/tree/t/document/d',
          treeUri: _treeUri,
          treeLabel: '内部存储',
          displayPath: '内部存储 / a.lrc',
        ),
      );

      expect(utf8.decode(bytes), '[00:00.00]saf');
      expect(contentPort.readUris, <String>[
        'content://provider/tree/t/document/d',
      ]);
    });

    test('写 SAF 目标时逐级目录、文件名与 MIME 一并下传', () async {
      await io.writeText(
        source: const LocalFileSource('/cache/a.ass'),
        target: SafDocumentTarget(
          target: const AndroidSafSaveTarget(
            treeUri: _treeUri,
            directorySegments: <String>['Album'],
            treeLabel: '内部存储',
          ),
          fileName: 'a.srt',
        ),
        text: '1\n00:00:00,000 --> 00:00:01,000\nx',
        allowOverwrite: false,
      );

      expect(treePort.writes, hasLength(1));
      expect(treePort.writes.single.treeUri, _treeUri);
      expect(treePort.writes.single.segments, <String>['Album']);
      expect(treePort.writes.single.displayName, 'a.srt');
      expect(treePort.writes.single.mimeType, 'application/x-subrip');
    });

    test('同名文件已存在且未确认覆盖时拒绝写入', () async {
      treePort.children = <AndroidSafTreeEntry>[_fileEntry('a.srt')];

      expect(
        () => io.writeText(
          source: const LocalFileSource('/cache/a.ass'),
          target: _safTarget('a.srt'),
          text: 'x',
          allowOverwrite: false,
        ),
        throwsA(isA<LddcApiParamsException>()),
      );
      expect(treePort.writes, isEmpty);
    });

    test('同名目录同样视为冲突（否则原生按文件定位会失败）', () async {
      treePort.children = <AndroidSafTreeEntry>[_directoryEntry('a.srt')];

      expect(await io.targetExists(_safTarget('a.srt')), isTrue);
    });

    test('确认覆盖后直接写入，不再枚举', () async {
      treePort.children = <AndroidSafTreeEntry>[_fileEntry('a.srt')];

      await io.writeText(
        source: const LocalFileSource('/cache/a.ass'),
        target: _safTarget('a.srt'),
        text: 'x',
        allowOverwrite: true,
      );

      expect(treePort.writes, hasLength(1));
      expect(treePort.listCalls, 0);
    });

    test('枚举失败时返回 null（无法确认），未确认覆盖则拒绝写入', () async {
      treePort.throwOnList = true;

      expect(await io.targetExists(_safTarget('a.srt')), isNull);
      expect(
        () => io.writeText(
          source: const LocalFileSource('/cache/a.ass'),
          target: _safTarget('a.srt'),
          text: 'x',
          allowOverwrite: false,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('目录里没有同名项时返回 false', () async {
      treePort.children = <AndroidSafTreeEntry>[_fileEntry('other.srt')];

      expect(await io.targetExists(_safTarget('a.srt')), isFalse);
    });
  });
}

SafDocumentTarget _safTarget(String fileName) {
  return SafDocumentTarget(
    target: const AndroidSafSaveTarget(
      treeUri: _treeUri,
      directorySegments: <String>[],
      treeLabel: '内部存储',
    ),
    fileName: fileName,
  );
}

AndroidSafTreeEntry _fileEntry(String name) {
  return AndroidSafTreeEntry(
    uri: 'content://provider/document/$name',
    displayName: name,
    mimeType: 'text/plain',
    isDirectory: false,
    isFile: true,
  );
}

AndroidSafTreeEntry _directoryEntry(String name) {
  return AndroidSafTreeEntry(
    uri: 'content://provider/document/$name',
    displayName: name,
    mimeType: 'vnd.android.document/directory',
    isDirectory: true,
    isFile: false,
  );
}

class _FakeLocalFileIo implements BatchConvertFileIo {
  final Uint8List bytes = Uint8List.fromList(utf8.encode('[00:00.00]local'));
  final List<String> writeTargets = <String>[];

  @override
  Future<Uint8List> readBytes(BatchConvertSource source) async => bytes;

  @override
  Future<void> writeText({
    required BatchConvertSource source,
    required BatchConvertTarget target,
    required String text,
    required bool allowOverwrite,
  }) async {
    writeTargets.add(target.fileName);
  }

  @override
  Future<bool?> targetExists(BatchConvertTarget target) async => false;
}

class _FakeContentPort implements AndroidSafContentPort {
  final List<String> readUris = <String>[];

  @override
  Future<Uint8List> readBytes(String uri, {int? maxBytes}) async {
    readUris.add(uri);
    return Uint8List.fromList(utf8.encode('[00:00.00]saf'));
  }
}

class _FakeTreePort implements AndroidSafTreePort {
  List<AndroidSafTreeEntry> children = <AndroidSafTreeEntry>[];
  bool throwOnList = false;
  int listCalls = 0;
  final List<
    ({
      String treeUri,
      List<String> segments,
      String displayName,
      String mimeType,
    })
  >
  writes =
      <
        ({
          String treeUri,
          List<String> segments,
          String displayName,
          String mimeType,
        })
      >[];

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    listCalls += 1;
    if (throwOnList) {
      throw StateError('permission denied');
    }
    final List<AndroidSafTreeEntry> page = offset == 0
        ? children
        : const <AndroidSafTreeEntry>[];
    return AndroidSafTreePage(entries: page, nextOffset: null);
  }

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
      segments: directorySegments,
      displayName: displayName,
      mimeType: mimeType,
    ));
    return AndroidSafWriteDocumentResult(
      uri: 'content://provider/document/$displayName',
      displayName: displayName,
    );
  }

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) {
    throw UnimplementedError();
  }

  @override
  Future<void> persistTreePermission(String uri) {
    throw UnimplementedError();
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() {
    throw UnimplementedError();
  }
}
