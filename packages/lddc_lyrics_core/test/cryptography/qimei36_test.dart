import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('QIMEI36 虚构设备协议', () {
    test('SN、AES 与 RSA 公钥保持协议固定值', () {
      expect(
        buildQimeiSn(Uint8List.fromList(ascii.encode('abc')), 0x12345678),
        '4C4385103CEB1234567885AEE7BE95D20CBC59C8ADE7F77404B40000000000000000',
      );
      expect(
        _bytesToHex(
          qimeiAesEncryptCbc(
            Uint8List.fromList(ascii.encode('hello qimei')),
            Uint8List.fromList(List<int>.generate(16, (int index) => index)),
            Uint8List.fromList(
              List<int>.generate(16, (int index) => index + 16),
            ),
          ),
        ),
        '5230f6dfbe72e1105348df485e57555e',
      );
      expect(qimeiRsaPublicKey().modulus!.bitLength, 2048);
      expect(identical(qimeiRsaPublicKey(), qimeiRsaPublicKey()), isTrue);
    });

    test('REGISTER 头、field#5 和 field#7 保持 native 形状', () {
      const QmDeviceProfile profile = QmDeviceProfile(model: '22041211AC');
      const QimeiPayloadState state = QimeiPayloadState(
        headDeviceToken: '0011223344556677',
        registerCounter: 7,
        dataLocalTimestampSeconds: 1783352230,
        preauditEnabled: false,
      );
      final Uint8List payload = buildQimeiRegisterPayload(
        profile: profile,
        state: state,
      );
      final Map<int, Object> outer = parseQimeiProtoLike(payload);
      final Map<int, Object> head = parseQimeiProtoLike(outer[1]! as Uint8List);
      final Map<int, Object> body = parseQimeiProtoLike(outer[2]! as Uint8List);
      expect(head[11], orderedEquals(ascii.encode('com.tencent.qqmusic')));
      expect(head[12], orderedEquals(ascii.encode('wifi')));
      expect(head[13], 7);
      final String field5 = utf8.decode(body[5]! as Uint8List);
      expect(field5.split(';').last, 'k10:1');
      expect(body[7], isA<Uint8List>());
      expect((body[7]! as Uint8List).length, 64);
    });

    test('data-local selector 保持协议字段顺序', () {
      const QmDeviceProfile profile = QmDeviceProfile();
      final QmDeviceIdentity identity = generateQmDeviceIdentity(
        profile,
        generation: 0,
        random: Random(1),
        currentTimeMs: 1783352230057,
      );
      final List<String> records =
          (identity.dataLocalSnapshot['records']! as List).cast<String>();
      final List<String> pairs = buildQimeiDataLocalField5(
        profile,
        snapshot: identity.dataLocalSnapshot,
      ).split(';');
      expect(pairs.length, 75);
      expect(pairs.take(10), <String>[
        'k1:${records[0]}',
        'k2:${records[1]}',
        'k3:${records[112]}',
        'k4:${records[115]}',
        'k5:${records[113]}',
        'k6:${records[114]}',
        'k7:${records[116]}',
        'k8:${records[117]}',
        'k9:${records[121]}',
        'k11:${records[2]}',
      ]);
      expect(pairs[pairs.length - 2], 'k75:${records[120]}');
      expect(pairs.last, 'k10:1');
    });

    test('默认 REGISTER 包含可解密的 field#18', () {
      final Uint8List payload = buildQimeiRegisterPayload(
        state: const QimeiPayloadState(
          headDeviceToken: '0011223344556677',
          dataLocalTimestampSeconds: 1783352230,
          preauditTimestampSeconds: 1783352230,
        ),
      );
      final Map<int, QimeiProtoField> outer = qimeiFieldsByNumber(
        parseQimeiProtoMessage(payload),
      );
      final Map<int, QimeiProtoField> body = qimeiFieldsByNumber(
        parseQimeiProtoMessage(requireQimeiBytes(outer[2], 'outer body')),
      );
      final String capsule = ascii.decode(
        requireQimeiBytes(body[18], 'preaudit'),
      );
      final Uint8List plaintext = qimeiAesDecryptCbc(
        base64Decode(capsule),
        Uint8List.fromList(ascii.encode('ebaecfe4fe48c925')),
        Uint8List.fromList(ascii.encode('bbf35926e3321062')),
      );
      final Map<String, Object?> decoded =
          jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
      expect(decoded['0'], 1783352230);
      expect(decoded['22'], 'arm64-v8a');
    });

    test('响应解密并接受 16 位 q16', () {
      const String q16 = '0123456789abcdef';
      const String q36 = defaultQimei36;
      final Uint8List key = Uint8List.fromList(
        List<int>.generate(16, (int index) => index),
      );
      final Uint8List iv = Uint8List.fromList(
        List<int>.generate(16, (int index) => index + 16),
      );
      final Uint8List plaintext = serializeQimeiProtoMessage(<QimeiProtoField>[
        QimeiProtoField(
          field: 1,
          wire: 2,
          value: Uint8List.fromList(ascii.encode(q16)),
        ),
        QimeiProtoField(
          field: 2,
          wire: 2,
          value: Uint8List.fromList(ascii.encode(q36)),
        ),
      ]);
      final ({String qimei16, String qimei36}) result = parseQimeiResponse(
        <String, Object?>{
          'code': 0,
          'data': <String, Object?>{
            'code': 0,
            'data': base64Encode(qimeiAesEncryptCbc(plaintext, key, iv)),
          },
        },
        key,
        iv,
      );
      expect(result.qimei16, q16);
      expect(result.qimei36, q36);
    });

    test('非法 protobuf、padding、Base64 与 QIMEI 长度被拒绝', () {
      expect(
        () => parseQimeiProtoMessage(Uint8List.fromList(<int>[0x0B])),
        throwsA(isA<QimeiProtocolException>()),
      );
      expect(
        () => qimeiAesDecryptCbc(Uint8List(16), Uint8List(16), Uint8List(16)),
        throwsA(isA<QimeiProtocolException>()),
      );
      expect(
        () => parseQimeiResponse(
          <String, Object?>{
            'code': 0,
            'data': <String, Object?>{'code': 0, 'data': '***'},
          },
          Uint8List(16),
          Uint8List(16),
        ),
        throwsA(isA<QimeiProtocolException>()),
      );
      expect(
        () => validateQimeiIdentity('short', defaultQimei36),
        throwsA(isA<QimeiProtocolException>()),
      );
      expect(
        () => serializeQimeiProtoMessage(<QimeiProtoField>[
          QimeiProtoField(field: 1, wire: 3, value: 0),
        ]),
        throwsA(isA<QimeiProtocolException>()),
      );
    });

    test('设备身份与请求 artifacts 暴露不可变快照', () {
      final List<String> records = List<String>.filled(122, 'record');
      final Map<String, Object?> snapshot = <String, Object?>{
        'version': qmDataLocalSnapshotVersion,
        'records': records,
      };
      final QmDeviceIdentity identity = QmDeviceIdentity(
        generation: 0,
        androidId: '0123456789abcdef',
        openUdid2: '0123456789abcdef0123456789abcdef',
        dataLocalSnapshot: snapshot,
      );
      records[0] = 'mutated';
      snapshot['version'] = -1;
      final QmDeviceIdentity copied = identity.copyWith(qimei16: 'q16');

      expect(identity.dataLocalSnapshot['version'], qmDataLocalSnapshotVersion);
      expect(
        (identity.dataLocalSnapshot['records']! as List<Object?>).first,
        'record',
      );
      expect(
        identical(copied.dataLocalSnapshot, identity.dataLocalSnapshot),
        isTrue,
      );

      final QimeiRequestArtifacts artifacts = buildGetQimei36Request(
        buildQimeiRegisterPayload(
          state: const QimeiPayloadState(
            headDeviceToken: '0011223344556677',
            dataLocalTimestampSeconds: 1783352230,
            preauditEnabled: false,
          ),
        ),
      );
      expect(() => artifacts.headers['x'] = 'y', throwsUnsupportedError);
      expect(() => artifacts.requestKey[0] = 1, throwsUnsupportedError);
    });
  });
}

String _bytesToHex(Uint8List bytes) =>
    bytes.map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
