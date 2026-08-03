import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:test/test.dart';

const String _qrcTextBase64 =
    'PEx5cmljXzEgTHlyaWNUeXBlPSIxIiBMeXJpY0NvbnRlbnQ9IlsxMDAwLDkwMF1hbCgxMDAwLDQwMClwaGEoMTQwMCw1MDApCiIvPg==';
const String _qrcCloudCipherHex =
    'c90db2e3f6940a43538b45865eb6753863c981f936a71a093b450246d48b65f03f3563cd2daf4951992461c1ff11dafba7f86ae9df09caa02530b2d19734bc0d385c152b36c85703';
const String _qrcLocalCipherHex =
    '9825b0ace3028368e8fc6cab92e9eaf65754d670145697206ee707df593a8d38645d7d06d5a879855391e1bbaabd58306c8f584cbb9ba706c92a0c0768cb3f2cca397684a0122667ec456bc2c3c022f00b4a96';
const String _krcTextBase64 =
    'WzEwMDAsOTAwXTwwLDQwMCwwPuWQiDw0MDAsNTAwLDA+5oiQ';
const String _krcCipherHex =
    '6b72633138dbea416a024497e00201a57be3be5841756c9bc07c9cf750877dec72b5737a40e2a57d75';

void main() {
  group('LyricsDecryptor 固定协议样本', () {
    final LyricsDecryptor decryptor = LyricsDecryptor();
    final String qrcText = utf8.decode(base64Decode(_qrcTextBase64));
    final String krcText = utf8.decode(base64Decode(_krcTextBase64));

    test('decryptKrc 解开独立生成的合成密文', () {
      expect(decryptor.decryptKrc(_hex(_krcCipherHex)), krcText);
    });

    test('decryptQrc(cloud) 解开独立生成的合成密文', () {
      expect(
        decryptor.decryptQrc(_qrcCloudCipherHex, type: QrcDecryptType.cloud),
        qrcText,
      );
    });

    test('decryptQrc(local) 解开带 QMC1 外层的合成密文', () {
      expect(
        decryptor.decryptQrc(
          _hex(_qrcLocalCipherHex),
          type: QrcDecryptType.local,
        ),
        qrcText,
      );
    });

    test('同一解密器只展开一次固定 QRC 轮密钥', () {
      final _CountingLyricsCrypto crypto = _CountingLyricsCrypto();
      final LyricsDecryptor cachedDecryptor = LyricsDecryptor(crypto: crypto);

      expect(cachedDecryptor.decryptQrc(_qrcCloudCipherHex), qrcText);
      expect(cachedDecryptor.decryptQrc(_qrcCloudCipherHex), qrcText);
      expect(crypto.keySetupCalls, 1);
    });

    test('非法输入会抛出歌词解密异常', () {
      expect(
        () => decryptor.decryptQrc('xx', type: QrcDecryptType.cloud),
        throwsA(isA<LddcLyricsDecryptException>()),
      );
      expect(
        () => decryptor.decryptKrc(Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(isA<LddcLyricsDecryptException>()),
      );
    });

    test('字节列表不能把非法元素静默转换为 0', () {
      expect(
        () => decryptor.decryptKrc(<Object?>[0x6b, 0x72, null, 0x31, 0]),
        throwsA(
          isA<LddcLyricsDecryptException>().having(
            (LddcLyricsDecryptException error) => error.detail,
            'detail',
            contains('第 2 项不是整数'),
          ),
        ),
      );
      expect(
        () => decryptor.decryptKrc(<int>[0x6b, 0x72, 0x63, 0x31, -1]),
        throwsA(
          isA<LddcLyricsDecryptException>().having(
            (LddcLyricsDecryptException error) => error.detail,
            'detail',
            contains('超出 0..255'),
          ),
        ),
      );
      expect(
        () => decryptor.decryptKrc(<int>[0x6b, 0x72, 0x63, 0x31, 256]),
        throwsA(isA<LddcLyricsDecryptException>()),
      );
    });

    test('底层解压失败时保留诊断 cause', () {
      expect(
        () => decryptor.decryptKrc(
          Uint8List.fromList(<int>[0x6b, 0x72, 0x63, 0x31, 0xbf, 0xb8]),
        ),
        throwsA(
          isA<LddcLyricsDecryptException>().having(
            (LddcLyricsDecryptException error) => error.cause,
            'cause',
            isNotNull,
          ),
        ),
      );
    });
  });
}

final class _CountingLyricsCrypto implements LyricsCryptoPort {
  final LyricsCryptoEngine _delegate = LyricsCryptoEngine();
  int keySetupCalls = 0;

  @override
  Uint8List qmc1Decrypt(Uint8List data) => _delegate.qmc1Decrypt(data);

  @override
  TripleDesSchedule tripledesKeySetup({
    required Uint8List key,
    required TripleDesMode mode,
  }) {
    keySetupCalls += 1;
    return _delegate.tripledesKeySetup(key: key, mode: mode);
  }

  @override
  Uint8List tripledesCrypt({
    required Uint8List data,
    required TripleDesSchedule schedule,
  }) => _delegate.tripledesCrypt(data: data, schedule: schedule);
}

Uint8List _hex(String value) {
  final Uint8List result = Uint8List(value.length ~/ 2);
  for (int index = 0; index < result.length; index += 1) {
    result[index] = int.parse(
      value.substring(index * 2, index * 2 + 2),
      radix: 16,
    );
  }
  return result;
}
