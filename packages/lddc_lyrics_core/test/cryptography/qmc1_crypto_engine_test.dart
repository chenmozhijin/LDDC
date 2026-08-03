import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('LyricsCryptoEngine.qmc1Decrypt', () {
    test('基础固定答案', () {
      final LyricsCryptoEngine engine = LyricsCryptoEngine();
      final Uint8List output = engine.qmc1Decrypt(
        Uint8List.fromList(<int>[0x05, 0x97]),
      );
      expect(output, Uint8List.fromList(<int>[0xc6, 0xdd]));
    });

    test('0x7FFF 后索引分支符合 QMC1 协议', () {
      final LyricsCryptoEngine engine = LyricsCryptoEngine();
      final Uint8List input = Uint8List(0x8002);
      final Uint8List output = engine.qmc1Decrypt(input);

      // i=0x7FFF 走 i<=0x7FFF 分支，索引为 127，对应 0x4A。
      expect(output[0x7fff], 0x4a);
      // i=0x8001 走 i>0x7FFF 分支，索引应为 2，对应 0xD6。
      expect(output[0x8001], 0xd6);
    });

    test('32767/32768/32769 边界使用摘要代替大型十六进制向量', () {
      const Map<int, String> expectedSha256 = <int, String>{
        32767:
            'e80a3c630c8d4c60781467966c577f173fbc9218ff48c2b8dea21199c14f082b',
        32768:
            '294cc263290e33d5690e5b67955e0549454f2cc9133f3dcf6cf73754b5f945bc',
        32769:
            '57085692ea1b81b6e44d53042f06c9841c37818bf0f7b9088c6050217f08bea2',
      };
      final LyricsCryptoEngine engine = LyricsCryptoEngine();

      for (final MapEntry<int, String> item in expectedSha256.entries) {
        final Uint8List input = Uint8List.fromList(
          List<int>.generate(
            item.key,
            (int index) => (index * 31 + 7) & 0xff,
            growable: false,
          ),
        );
        final Uint8List output = engine.qmc1Decrypt(input);

        expect(output, hasLength(item.key));
        expect(sha256.convert(output).toString(), item.value);
      }
    });
  });

  group('LyricsCryptoEngine 边界校验', () {
    test('3DES key 和 block 长度错误会抛出 ArgumentError', () {
      final LyricsCryptoEngine engine = LyricsCryptoEngine();
      expect(
        () => engine.tripledesKeySetup(
          key: Uint8List(23),
          mode: TripleDesMode.decrypt,
        ),
        throwsArgumentError,
      );

      final TripleDesSchedule schedule = engine.tripledesKeySetup(
        key: Uint8List(24),
        mode: TripleDesMode.decrypt,
      );
      expect(
        () => engine.tripledesCrypt(data: Uint8List(7), schedule: schedule),
        throwsArgumentError,
      );
    });

    test('EAPI 解密拒绝空数据、非块长度和坏 padding', () {
      expect(() => eapiResponseDecrypt(Uint8List(0)), throwsFormatException);
      expect(() => eapiResponseDecrypt(Uint8List(15)), throwsArgumentError);
      final Uint8List badPadding = Uint8List.fromList(<int>[
        0x49,
        0xd8,
        0x2f,
        0xe8,
        0x52,
        0xc4,
        0x9a,
        0x19,
        0x3c,
        0x41,
        0x7a,
        0x69,
        0xbc,
        0x88,
        0x85,
        0x71,
      ]);
      expect(() => eapiResponseDecrypt(badPadding), throwsFormatException);
    });

    test('EAPI 参数包含协议分隔符时仍可完整往返', () {
      final String encrypted = eapiParamsEncrypt(
        path: Uint8List.fromList('/api/test'.codeUnits),
        params: const <String, Object?>{'value': 'left-36cd479b6b5-right'},
      );
      final Map<String, Object?> decrypted = eapiParamsDecrypt(
        encrypted.substring('params='.length),
      );

      expect(decrypted['value'], 'left-36cd479b6b5-right');
    });
  });
}
