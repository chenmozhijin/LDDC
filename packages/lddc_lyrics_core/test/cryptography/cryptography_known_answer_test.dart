import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:test/test.dart';

void main() {
  group('QM QRC 自定义 DES-EDE 固定答案', () {
    test('自定义轮密钥、S-box 与分组顺序保持协议结果', () {
      final LyricsCryptoEngine engine = LyricsCryptoEngine();
      final Uint8List key = _hex(
        '21402329282a24253132335a5843214021402329284e484c',
      );
      final Uint8List cipher = _hex('8e4c9b7f0d3a21c5');
      final Uint8List plain = _hex('6342502352276f2d');

      expect(
        engine.tripledesCrypt(
          data: cipher,
          schedule: engine.tripledesKeySetup(
            key: key,
            mode: TripleDesMode.decrypt,
          ),
        ),
        plain,
      );
    });
  });

  group('QM 参数协议固定答案', () {
    test('calcQmParamSign 对固定正文、请求头和随机源产生稳定签名', () {
      final QmParamSignResult result = calcQmParamSign(
        body: _hex('7b22726571223a2264656d6f222c2276223a317d'),
        headers:
            '11&14100508&123456&null&1710000000000&abcdef0123456789&android',
        randomSource: ReplayQmParamRandomSource(
          indexValues: const <int>[11, 13, 11, 6, 5, 5, 4, 20, 17, 4, 23, 19],
          byteValues: const <int>[202, 76, 112],
        ),
      );

      expect(result.p1, 'TE5MR0ZGRVVSRVhUwYcB0AHiVby/37gQYpcV93HhZq8=');
      expect(
        result.p2,
        'cBda7AxCHwUcOW2GwaIMKJf1gIaSOljINMbGUpIMADR+J7ujNU6iZD/CeecQbmNPzv9wGAYSjtjLvC5eIaI2JQz/HvSySidW',
      );
    });

    test('QMTea 空正文仍生成完整协议 padding 块', () {
      final QmTea tea = QmTea(
        key: _hex('ffeeddccbbaa99887766554433221100'),
        randomSource: ReplayQmParamRandomSource(
          byteValues: const <int>[40, 169, 31, 211, 27, 132, 222, 33, 255],
        ),
      );

      expect(
        tea.encrypt(Uint8List(0)),
        _hex('caf541b3fd8fe1984b5cb8f4a8535bd6'),
      );
    });
  });

  group('EAPI 协议固定答案', () {
    test('参数加密使用固定路径、JSON 顺序、摘要和 AES 封装', () {
      final String encrypted = eapiParamsEncrypt(
        path: Uint8List.fromList(ascii.encode('/api/song/lyric/v1')),
        params: const <String, Object?>{
          'id': '123456',
          'cp': false,
          'tv': 0,
          'lv': 0,
        },
      );

      expect(
        encrypted,
        'params=04AE33D34A93FE3EC22DA8FA305D290AB337D0FE5F36D211DE0D338CC6AA89D054089EE65735DE9BEFF66F93F6FB8FDAD461DFF90077763EC1AEFEEA70B344C4BC3E5B2DB77C551C322FCDC1F2233A40687614514B3BB0544BF0CC461B6999A4BDAA1D93533B034BC08B33EDB7E9EF20BBBA81AC7D882B650013D49CC68BDA08',
      );
    });

    test('缓存键、响应解密和匿名用户名分别命中固定答案', () {
      expect(
        eapiGetCacheKey(Uint8List.fromList(utf8.encode('cache_key_demo_text'))),
        'S9gSYrCU6eDxnXun02Z4Zj+WtPNwxXcG4JpIL/WuQTE=',
      );
      expect(
        utf8.decode(
          eapiResponseDecrypt(
            _hex(
              '2d2756c4eadf578033119ce08b87d5aacada043fbef5a49a38c987394944b975303f711456e09f6fc3dd81df7fc6bf55',
            ),
          ),
        ),
        '{"code":200,"lyric":"[00:00.00]demo"}',
      );
      expect(
        eapiGetAnonymousUsername('0123456789abcdef'),
        'MDEyMzQ1Njc4OWFiY2RlZiBGZEd0TGNER0VRL2JBUyttdVhYMDVBPT0=',
      );
    });
  });
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
