import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  group('LocalLyricsInputNormalizer', () {
    test('file URI 正确解码，且请求与解析结果各自持有字节快照', () async {
      final Uint8List source = Uint8List.fromList(<int>[1, 2, 3]);
      final LocalLyricsRequest request = LocalLyricsRequest(
        path: '  file:///C:/My%20Lyrics/demo.lrc  ',
        data: source,
      );
      source[0] = 9;

      final ResolvedLocalLyricsInput resolved =
          await LocalLyricsInputNormalizer().resolve(request);
      request.data![1] = 8;

      expect(
        resolved.path,
        Uri.parse('file:///C:/My%20Lyrics/demo.lrc').toFilePath(),
      );
      expect(resolved.data, <int>[1, 2, 3]);
    });

    test('只有路径时读取规范化路径，并复制 reader 返回的缓冲区', () async {
      final Uint8List fileBytes = Uint8List.fromList(<int>[4, 5, 6]);
      String? readPath;
      final LocalLyricsInputNormalizer normalizer = LocalLyricsInputNormalizer(
        fileReader: (String path) async {
          readPath = path;
          return fileBytes;
        },
      );

      final ResolvedLocalLyricsInput resolved = await normalizer.resolve(
        LocalLyricsRequest(path: '  demo.lrc  '),
      );
      fileBytes[0] = 0;

      expect(readPath, 'demo.lrc');
      expect(resolved.data, <int>[4, 5, 6]);
    });

    test('空路径和空字节均给出明确参数异常', () async {
      final LocalLyricsInputNormalizer normalizer = LocalLyricsInputNormalizer(
        fileReader: (String path) async => Uint8List(0),
      );

      await expectLater(
        () => normalizer.resolve(LocalLyricsRequest(path: '   ')),
        throwsA(isA<LddcApiParamsException>()),
      );
      await expectLater(
        () => normalizer.resolve(LocalLyricsRequest(path: 'empty.lrc')),
        throwsA(isA<LddcApiParamsException>()),
      );
    });

    test('明文 QRC 和 KRC 可进入展示与后续解析链路', () {
      final LocalLyricsInputNormalizer normalizer =
          LocalLyricsInputNormalizer();
      const Map<String, String> samples = <String, String>{
        'demo.QRC':
            '<Lyric_1 LyricType="1" LyricContent="[0,1000]歌词(0,1000)"/>',
        'demo.krc': '[0,1000]<0,1000,0>歌词',
      };

      for (final MapEntry<String, String> sample in samples.entries) {
        expect(
          normalizer.decodeDisplayText(
            data: Uint8List.fromList(utf8.encode(sample.value)),
            path: sample.key,
          ),
          sample.value,
        );
      }
    });

    test('未知扩展名仍会在展示阶段明确拒绝', () {
      expect(
        () => LocalLyricsInputNormalizer().decodeDisplayText(
          data: Uint8List.fromList(utf8.encode('plain text')),
          path: 'demo.unknown',
        ),
        throwsUnsupportedError,
      );
    });
  });
}
