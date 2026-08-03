import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('LocalLyricsProvider', () {
    late LocalLyricsProvider provider;

    setUp(() {
      provider = LocalLyricsProvider();
    });

    test('无 path/data 时抛参数异常', () async {
      await expectLater(
        () => provider.getLyrics(LocalLyricsRequest()),
        throwsA(isA<LddcApiParamsException>()),
      );
    });

    test('可按 data 直接解析无扩展名 LRC', () async {
      final Lyrics lyrics = await provider.getLyrics(
        LocalLyricsRequest(
          data: Uint8List.fromList(utf8.encode('[00:01.00]你好')),
        ),
      );
      expect(lyrics.source, Source.local);
      expect(lyrics.data['orig'], isNotNull);
      expect(lyrics.data['orig']!.single.words.single.text, '你好');
    });

    test('path 存在且未提供 data 时会读取文件', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-provider-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final File file = File('${dir.path}/demo.lrc');
      await file.writeAsString('[00:01.00]来自文件', encoding: utf8);

      final Lyrics lyrics = await provider.getLyrics(
        LocalLyricsRequest(path: file.path),
      );
      expect(lyrics.path, file.path);
      expect(lyrics.data['orig']!.single.words.single.text, '来自文件');
    });

    test('QRC 本地分支支持 companion 联读（orig + roma）', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-local-qrc-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final ({String text, Uint8List encrypted}) orig = _buildEncryptedQrcLocal(
        '<Lyric_1 LyricType="1" LyricContent="[ar:测试]\n[1000,500]你(1000,200)好(1200,300)\n"/>',
      );
      final ({String text, Uint8List encrypted}) roma = _buildEncryptedQrcLocal(
        '<Lyric_1 LyricType="1" LyricContent="[1000,500]ni(1000,200)hao(1200,300)\n"/>',
      );
      expect(orig.text, contains('Lyric_1'));
      expect(roma.text, contains('Lyric_1'));

      final File origFile = File('${dir.path}/track_qm.qrc');
      final File romaFile = File('${dir.path}/track_qmRoma.qrc');
      await origFile.writeAsBytes(orig.encrypted);
      await romaFile.writeAsBytes(roma.encrypted);

      final Lyrics lyrics = await provider.getLyrics(
        LocalLyricsRequest(path: origFile.path),
      );
      expect(lyrics.data.keys, containsAll(<String>['orig', 'roma']));
      expect(lyrics.tags['ar'], '测试');
      expect(lyrics.data['orig']!.single.words.first.text, '你');
      expect(lyrics.data['roma']!.single.words.first.text, 'ni');
    });

    test('KRC 本地分支可解密并解析', () async {
      final Uint8List encrypted = _buildEncryptedKrc(
        '[1000,500]<0,200,0>你<200,300,0>好',
      );
      final Lyrics lyrics = await provider.getLyrics(
        LocalLyricsRequest(data: encrypted, path: 'demo.krc'),
      );

      expect(lyrics.data['orig'], isNotNull);
      expect(lyrics.data['orig']!.single.words.length, 2);
      expect(lyrics.data['orig']!.single.words.first.text, '你');
      expect(lyrics.data['orig']!.single.words.last.text, '好');
    });
  });
}

Uint8List _buildEncryptedKrc(String text) {
  const List<int> krcKey = <int>[
    0x40,
    0x47,
    0x61,
    0x77,
    0x5E,
    0x32,
    0x74,
    0x47,
    0x51,
    0x36,
    0x31,
    0x2D,
    0xCE,
    0xD2,
    0x6E,
    0x69,
  ];

  final Uint8List compressed = Uint8List.fromList(
    ZLibEncoder().convert(utf8.encode(text)),
  );
  final Uint8List encrypted = Uint8List(4 + compressed.length);
  encrypted[0] = 0x6B;
  encrypted[1] = 0x72;
  encrypted[2] = 0x63;
  encrypted[3] = 0x31;
  for (int index = 0; index < compressed.length; index += 1) {
    encrypted[index + 4] = compressed[index] ^ krcKey[index % krcKey.length];
  }
  expect(encrypted.sublist(0, 5), krcMagicHeader);
  return encrypted;
}

({String text, Uint8List encrypted}) _buildEncryptedQrcLocal(String qrcText) {
  final LyricsCryptoEngine crypto = LyricsCryptoEngine();
  final ({String text, Uint8List encrypted}) cloud = _buildEncryptedQrcCloud(
    qrcText,
  );
  final Uint8List qmc1InputPrefix = crypto.qmc1Decrypt(
    Uint8List.fromList(qrcMagicHeader),
  );
  final Uint8List qmc1Input = Uint8List(
    qmc1InputPrefix.length + cloud.encrypted.length,
  );
  qmc1Input.setRange(0, qmc1InputPrefix.length, qmc1InputPrefix);
  qmc1Input.setRange(qmc1InputPrefix.length, qmc1Input.length, cloud.encrypted);
  final Uint8List encrypted = crypto.qmc1Decrypt(qmc1Input);
  expect(encrypted.sublist(0, qrcMagicHeader.length), qrcMagicHeader);
  return (text: cloud.text, encrypted: encrypted);
}

({String text, Uint8List encrypted}) _buildEncryptedQrcCloud(String qrcText) {
  final LyricsCryptoEngine crypto = LyricsCryptoEngine();
  final ({String text, Uint8List compressed}) prepared = _prepareQrcPayload(
    qrcText,
  );
  const List<int> qrcKey = <int>[
    0x21,
    0x40,
    0x23,
    0x29,
    0x28,
    0x2A,
    0x24,
    0x25,
    0x31,
    0x32,
    0x33,
    0x5A,
    0x58,
    0x43,
    0x21,
    0x40,
    0x21,
    0x40,
    0x23,
    0x29,
    0x28,
    0x4E,
    0x48,
    0x4C,
  ];

  final TripleDesSchedule schedule = crypto.tripledesKeySetup(
    key: Uint8List.fromList(qrcKey),
    mode: TripleDesMode.encrypt,
  );
  final BytesBuilder bytes = BytesBuilder(copy: false);
  for (int offset = 0; offset < prepared.compressed.length; offset += 8) {
    final Uint8List block = Uint8List.sublistView(
      prepared.compressed,
      offset,
      offset + 8,
    );
    bytes.add(crypto.tripledesCrypt(data: block, schedule: schedule));
  }
  return (
    text: prepared.text,
    encrypted: Uint8List.fromList(bytes.takeBytes()),
  );
}

({String text, Uint8List compressed}) _prepareQrcPayload(String qrcText) {
  final Uint8List compressed = Uint8List.fromList(
    ZLibEncoder().convert(utf8.encode(qrcText)),
  );
  final int remainder = compressed.length % 8;
  if (remainder == 0) {
    return (text: qrcText, compressed: compressed);
  }
  final Uint8List padded = Uint8List(compressed.length + (8 - remainder));
  padded.setRange(0, compressed.length, compressed);
  return (text: qrcText, compressed: padded);
}
