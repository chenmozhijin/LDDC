import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  group('BackgroundFileIo', () {
    test('小文本直接写入并自动创建父目录', () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'lddc-background-io-text-',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      final String path = '${root.path}/nested/lyrics.lrc';

      final String savedPath = await BackgroundFileIo.writeText(
        path: path,
        text: '[00:00.000]歌词',
      );

      expect(savedPath, path);
      expect(await File(path).readAsString(), '[00:00.000]歌词');
    });

    test('大字节写入保持内容完整', () async {
      final Directory root = await Directory.systemTemp.createTemp(
        'lddc-background-io-bytes-',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      final String path = '${root.path}/nested/blob.bin';
      final Uint8List bytes = Uint8List.fromList(
        List<int>.generate(80 * 1024, (int index) => index % 251),
      );

      final String savedPath = await BackgroundFileIo.writeBytes(
        path: path,
        bytes: bytes,
      );

      expect(savedPath, path);
      expect(await File(path).readAsBytes(), bytes);
    });
  });
}
