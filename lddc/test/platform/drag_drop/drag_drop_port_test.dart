import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/drag_drop/drag_drop_port.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  group('DragDropPortImpl private mime parser', () {
    test('parseAimpDropData 解析 path 和 index', () {
      final Uint8List payload = _buildAimpPayload(<String>[
        r'C:\music\foo.mp3:3',
        r'D:\albums\bar.flac:12',
      ]);

      final List<DragDropItemDescriptor> items =
          DragDropPortImpl.parseAimpDropData(payload);

      expect(items, hasLength(2));
      expect(items.first.kind, DragDropItemKind.songInfoLike);
      expect(items.first.song?.path, r'C:\music\foo.mp3');
      expect(items.first.song?.index, '3');
      expect(items.last.song?.path, r'D:\albums\bar.flac');
      expect(items.last.song?.index, '12');
    });

    test('parseFoobarDropData 解析 path 和 track', () {
      final Uint8List payload = _buildFoobarPayload(<String>[
        'file:///C:/music/foo.mp3',
        'file:///D:/albums/bar.flac',
      ]);
      const String plainText =
          'Artist A - [Album A #03] Song A\r\nArtist B - [Album B #12] Song B';

      final List<DragDropItemDescriptor> items =
          DragDropPortImpl.parseFoobarDropData(payload, plainText);

      expect(items, hasLength(2));
      expect(items.first.song?.path, 'C:/music/foo.mp3');
      expect(items.first.song?.track, '03');
      expect(items.last.song?.path, 'D:/albums/bar.flac');
      expect(items.last.song?.track, '12');
    });

    test('parseFoobarDropData 遇到非法百分号编码时仍能保留路径', () {
      final Uint8List payload = _buildFoobarPayload(<String>[
        'file:///F:/music/100% Hits/foo.mp3',
      ]);

      final List<DragDropItemDescriptor> items =
          DragDropPortImpl.parseFoobarDropData(
            payload,
            'Artist - [Album #01] Song',
          );

      expect(items, hasLength(1));
      expect(items.single.song?.path, 'F:/music/100% Hits/foo.mp3');
      expect(items.single.song?.track, '01');
    });

    test('parseAimpDropData 在 payload 无效时抛出明确异常', () {
      expect(
        () => DragDropPortImpl.parseAimpDropData(Uint8List(16)),
        throwsA(isA<Exception>()),
      );
    });

    test('parsePayload 不会把私有格式解析异常写入业务失败结果', () {
      final List<String> logs = <String>[];
      final DragDropPortImpl port = DragDropPortImpl(
        enableDiagnostics: true,
        debugLogger: logs.add,
      );

      final DragDropParseResult result = port.parsePayload(
        DesktopDragDropPayload(
          platform: 'windows',
          x: 0,
          y: 0,
          coordinateSpace: 'logical',
          formats: const <String>{kAimpDropFormat},
          files: const <String>[],
          privateData: <String, Uint8List>{kAimpDropFormat: Uint8List(25)},
        ),
      );

      expect(result.items, isEmpty);
      expect(result.failure, DragDropFailure.unreadablePrivateMime);
      expect(logs, hasLength(2));
      expect(logs.first, contains('AIMP 拖拽正文不是完整的 UTF-16LE 数据'));
      expect(logs.last, contains('failure=unreadablePrivateMime'));
    });

    test('启用诊断时会输出可读摘要', () {
      final List<String> logs = <String>[];
      final DragDropPortImpl port = DragDropPortImpl(
        enableDiagnostics: true,
        debugLogger: logs.add,
      );

      final List<DragDropItemDescriptor> items =
          DragDropPortImpl.parseFoobarDropData(
            _buildFoobarPayload(<String>['file:///C:/music/foo.mp3']),
            'Artist - [Album #01] Song',
          );

      expect(items, hasLength(1));
      expect(logs, isEmpty, reason: '静态解析器本身不输出日志，诊断仅在 parseDrop 链中开启');
      expect(port.enableDiagnostics, isTrue);
    });
  });

  group('DragDrop shared models', () {
    test('解析结果冻结输入集合，调用方后续修改不会污染已发布快照', () {
      final List<DragDropItemDescriptor> items = <DragDropItemDescriptor>[
        DragDropItemDescriptor.file(r'C:\music\song.flac'),
      ];
      final Set<String> formats = <String>{'CF_HDROP'};
      final DragDropParseResult result = DragDropParseResult(
        items: items,
        platformFormats: formats,
      );

      items.clear();
      formats.clear();

      expect(result.items, hasLength(1));
      expect(result.platformFormats, <String>{'CF_HDROP'});
      expect(
        () => result.items.add(
          DragDropItemDescriptor.file(r'D:\music\other.mp3'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => result.platformFormats.add('text/plain'),
        throwsUnsupportedError,
      );
    });

    test('描述符拒绝空路径，缺省查找不能再伪造合法条目', () {
      expect(() => DragDropItemDescriptor.file(''), throwsArgumentError);
      expect(() => DragDropItemDescriptor.directory('  '), throwsArgumentError);
      expect(() => DragDropSongDescriptor(path: '\t'), throwsArgumentError);
    });
  });
}

Uint8List _buildAimpPayload(List<String> entries) {
  final BytesBuilder builder = BytesBuilder();
  builder.add(Uint8List(20));
  final String content = '${entries.join('\u0000')}\u0000';
  final ByteData byteData = ByteData(content.length * 2);
  for (int index = 0; index < content.length; index += 1) {
    byteData.setUint16(index * 2, content.codeUnitAt(index), Endian.little);
  }
  builder.add(byteData.buffer.asUint8List());
  builder.add(Uint8List(4));
  return builder.toBytes();
}

Uint8List _buildFoobarPayload(List<String> entries) {
  final BytesBuilder builder = BytesBuilder();
  for (final String entry in entries) {
    final Uint8List encoded = Uint8List.fromList(utf8.encode(entry));
    final ByteData header = ByteData(8)
      ..setUint32(0, 0, Endian.little)
      ..setUint32(4, encoded.length, Endian.little);
    builder.add(header.buffer.asUint8List());
    builder.add(encoded);
  }
  return builder.toBytes();
}
