import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart' hide Digest;

import 'qm_device.dart';

const String qimeiAppId = 'qimei_qq_android';
const String qimeiSignSecret = 'pzAuCmaFAaFaHrdakPjLIEqKrGnSOOvH';
const String qimeiService = 'trpc.tme_datasvr.qimeiproxy.QimeiProxy';
const String qimeiMethod = 'GetQimeiV2';
const String defaultQimeiUserAgent = 'QQMusic 14100508(android 14)';
const String defaultQimei36 = 'b925092ce71e51774071587c100013f14a01';

final Uint8List _packedKey = _hexToBytes('ff802003f67f55be8b535a97b01b459d');
final Uint8List _packedIv = _hexToBytes('b8221969c27a8019d533b139ade71bcc');
final Uint8List _pmsHeader = _hexToBytes('0300000001');
final Uint8List _field57Const20 = Uint8List.fromList(
  ascii.encode('plzdontcrackme856c91'),
);
final Uint8List _field18Key = Uint8List.fromList(
  ascii.encode('ebaecfe4fe48c925'),
);
final Uint8List _field18Iv = Uint8List.fromList(
  ascii.encode('bbf35926e3321062'),
);

const String _rsaPublicKeyBase64 =
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApLEpcsiHA/PE4MKl7WS7r11RijhytmEQH8jaY3nKhvq/'
    'KC29yEpJVAu+/asRp9mpoxCAiaTxJynVZMw5amwe24ff0Eau/MLCcfG9jFq8fp0LJwXmKtJuwha2hVr6zhW1+'
    'Q1h8f3T9hu+QMZTRxqQnIY1mjqDY1/ARAK2hMzS+uoB+COosppWgFxOcQhzkjcM7Oa0RO+rSaatWsgBrKspVEXF'
    'MYfHS+awD8qGXZyyOVaiDNvXgLfPecJerKCOFdujwR3isgtEEe8yyRryUm1FZgdIi8e+t23Lp0XDDB6LCox7DWL'
    'KmRjQ5K/5R7+HmSwNLANkw6yTUuLtYcoMY2nOUwIDAQAB';
final RegExp _base64CharactersPattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');
final RegExp _whitespacePattern = RegExp(r'\s');
final RSAPublicKey _defaultRsaPublicKey = _parseQimeiRsaPublicKey(
  _rsaPublicKeyBase64,
);

final Uint8List _chachaConstant = Uint8List.fromList(
  ascii.encode('expand 32-byte k'),
);
// JavaScript 的 int 只能精确表示 53 位整数。协议常量按 ChaCha 状态实际消费的
// 高低 32 位保存，既保持原始 64 位字节语义，也避免 Web fallback 在编译期拒绝字面量。
const int _snConstantLow32 = 0xEF44A2A3;
const int _snConstantHigh32 = 0x65A4E57F;
final Uint8List _snFixed16 = _hexToBytes('6db579083ffb211c7c8d917494fc4561');
final Uint8List _snPrefix = _hexToBytes('4c438510');
final Uint8List _snZeroTail = Uint8List(8);
const int _mask32 = 0xFFFFFFFF;

const List<int> _sha256K = <int>[
  0x428A2F98,
  0x71374491,
  0xB5C0FBCF,
  0xE9B5DBA5,
  0x3956C25B,
  0x59F111F1,
  0x923F82A4,
  0xAB1C5ED5,
  0xD807AA98,
  0x12835B01,
  0x243185BE,
  0x550C7DC3,
  0x72BE5D74,
  0x80DEB1FE,
  0x9BDC06A7,
  0xC19BF174,
  0xE49B69C1,
  0xEFBE4786,
  0x0FC19DC6,
  0x240CA1CC,
  0x2DE92C6F,
  0x4A7484AA,
  0x5CB0A9DC,
  0x76F988DA,
  0x983E5152,
  0xA831C66D,
  0xB00327C8,
  0xBF597FC7,
  0xC6E00BF3,
  0xD5A79147,
  0x06CA6351,
  0x14292967,
  0x27B70A85,
  0x2E1B2138,
  0x4D2C6DFC,
  0x53380D13,
  0x650A7354,
  0x766A0ABB,
  0x81C2C92E,
  0x92722C85,
  0xA2BFE8A1,
  0xA81A664B,
  0xC24B8B70,
  0xC76C51A3,
  0xD192E819,
  0xD6990624,
  0xF40E3585,
  0x106AA070,
  0x19A4C116,
  0x1E376C08,
  0x2748774C,
  0x34B0BCB5,
  0x391C0CB3,
  0x4ED8AA4A,
  0x5B9CCA4F,
  0x682E6FF3,
  0x748F82EE,
  0x78A5636F,
  0x84C87814,
  0x8CC70208,
  0x90BEFFFA,
  0xA4506CEB,
  0xBEF9A3F7,
  0xC67178F2,
];

const List<int> _customIv = <int>[
  0x6A09A669,
  0xBA67AE87,
  0x7B6BF372,
  0xA56CF53A,
  0x511E527F,
  0x5B25688C,
  0x1F73C9AB,
  0x3BD0BD19,
];

const List<int> _dataLocalLongSelector = <int>[
  0x00,
  0x01,
  0x70,
  0x73,
  0x71,
  0x72,
  0x74,
  0x75,
  0x79,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0A,
  0x0B,
  0x0C,
  0x0D,
  0x0E,
  0x0F,
  0x10,
  0x11,
  0x12,
  0x13,
  0x6C,
  0x6D,
  0x6E,
  0x6F,
  0x14,
  0x15,
  0x16,
  0x17,
  0x18,
  0x19,
  0x1A,
  0x1B,
  0x1C,
  0x1D,
  0x1E,
  0x1F,
  0x20,
  0x22,
  0x24,
  0x25,
  0x28,
  0x2A,
  0x2C,
  0x2E,
  0x32,
  0x35,
  0x36,
  0x3A,
  0x3E,
  0x40,
  0x41,
  0x42,
  0x46,
  0x48,
  0x4A,
  0x4C,
  0x4E,
  0x52,
  0x54,
  0x56,
  0x5A,
  0x5E,
  0x61,
  0x62,
  0x65,
  0x68,
  0x78,
];

/// QIMEI 协议格式或校验错误。
final class QimeiProtocolException implements Exception {
  const QimeiProtocolException(this.message);

  final String message;

  @override
  String toString() => 'QimeiProtocolException: $message';
}

enum QimeiCommand {
  register(1);

  const QimeiCommand(this.value);
  final int value;
}

final class QimeiProtoField {
  QimeiProtoField({
    required this.field,
    required this.wire,
    required Object value,
    this.offset = 0,
    this.end = 0,
  }) : value = value is Uint8List
           ? Uint8List.fromList(value).asUnmodifiableView()
           : value;

  final int field;
  final int wire;
  final Object value;
  final int offset;
  final int end;
}

final class QimeiPayloadState {
  const QimeiPayloadState({
    this.cacheQ16 = '',
    this.cacheQ36 = '',
    this.headDeviceToken,
    this.registerCounter = 0,
    this.dataLocalSnapshot,
    this.dataLocalField5,
    this.dataLocalTimestampSeconds,
    this.preauditEnabled = true,
    this.preauditTimestampSeconds,
  });

  final String cacheQ16;
  final String cacheQ36;
  final String? headDeviceToken;
  final int registerCounter;
  final Map<String, Object?>? dataLocalSnapshot;
  final String? dataLocalField5;
  final int? dataLocalTimestampSeconds;
  final bool preauditEnabled;
  final int? preauditTimestampSeconds;

  QimeiPayloadState copyWith({int? registerCounter}) => QimeiPayloadState(
    cacheQ16: cacheQ16,
    cacheQ36: cacheQ36,
    headDeviceToken: headDeviceToken,
    registerCounter: registerCounter ?? this.registerCounter,
    dataLocalSnapshot: dataLocalSnapshot,
    dataLocalField5: dataLocalField5,
    dataLocalTimestampSeconds: dataLocalTimestampSeconds,
    preauditEnabled: preauditEnabled,
    preauditTimestampSeconds: preauditTimestampSeconds,
  );
}

final class QimeiRequestArtifacts {
  QimeiRequestArtifacts({
    required this.command,
    required this.cpt,
    required Map<String, String> headers,
    required Map<String, Object?> requestBody,
    required Map<String, String> reqData,
    required Uint8List packedPayload,
    required Uint8List pmsPlain,
    required Uint8List pmsCipher,
    required Uint8List requestKey,
    required Uint8List requestIv,
    required this.ky,
    required Uint8List snInput,
    required this.sn,
  }) : headers = Map<String, String>.unmodifiable(headers),
       requestBody = Map<String, Object?>.unmodifiable(requestBody),
       reqData = Map<String, String>.unmodifiable(reqData),
       packedPayload = Uint8List.fromList(packedPayload).asUnmodifiableView(),
       pmsPlain = Uint8List.fromList(pmsPlain).asUnmodifiableView(),
       pmsCipher = Uint8List.fromList(pmsCipher).asUnmodifiableView(),
       requestKey = Uint8List.fromList(requestKey).asUnmodifiableView(),
       requestIv = Uint8List.fromList(requestIv).asUnmodifiableView(),
       snInput = Uint8List.fromList(snInput).asUnmodifiableView();

  final QimeiCommand command;
  final String cpt;
  final Map<String, String> headers;
  final Map<String, Object?> requestBody;
  final Map<String, String> reqData;
  final Uint8List packedPayload;
  final Uint8List pmsPlain;
  final Uint8List pmsCipher;
  final Uint8List requestKey;
  final Uint8List requestIv;
  final String ky;
  final Uint8List snInput;
  final String sn;

  String get pms => reqData['pms']!;
}

abstract interface class QimeiRandomSource {
  Uint8List nextBytes(int count);
}

final class SecureQimeiRandomSource implements QimeiRandomSource {
  SecureQimeiRandomSource([Random? random])
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  Uint8List nextBytes(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', '不能为负数');
    }
    final Uint8List result = Uint8List(count);
    for (int index = 0; index < count; index += 1) {
      result[index] = _random.nextInt(256);
    }
    return result;
  }
}

final class ReplayQimeiRandomSource implements QimeiRandomSource {
  ReplayQimeiRandomSource(Iterable<int> bytes)
    : _bytes = List<int>.from(bytes) {
    for (int index = 0; index < _bytes.length; index += 1) {
      final int value = _bytes[index];
      if (value < 0 || value > 0xff) {
        throw RangeError('随机字节越界: index=$index value=$value');
      }
    }
  }

  final List<int> _bytes;
  int _cursor = 0;

  @override
  Uint8List nextBytes(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', '不能为负数');
    }
    if (_cursor + count > _bytes.length) {
      throw StateError('ReplayQimeiRandomSource 随机字节不足');
    }
    final Uint8List result = Uint8List.fromList(
      _bytes.sublist(_cursor, _cursor + count),
    );
    _cursor += count;
    return result;
  }
}

Uint8List qimeiAesEncryptCbc(Uint8List plaintext, Uint8List key, Uint8List iv) {
  _validateAesParameters(key, iv);
  final int paddingLength = 16 - (plaintext.length % 16);
  final Uint8List padded = Uint8List(plaintext.length + paddingLength)
    ..setRange(0, plaintext.length, plaintext)
    ..fillRange(
      plaintext.length,
      plaintext.length + paddingLength,
      paddingLength,
    );
  final BlockCipher cipher = CBCBlockCipher(AESEngine())
    ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));
  final Uint8List output = Uint8List(padded.length);
  for (int offset = 0; offset < padded.length; offset += 16) {
    cipher.processBlock(padded, offset, output, offset);
  }
  return output;
}

Uint8List qimeiAesDecryptCbc(
  Uint8List ciphertext,
  Uint8List key,
  Uint8List iv,
) {
  _validateAesParameters(key, iv);
  if (ciphertext.isEmpty || ciphertext.length % 16 != 0) {
    throw QimeiProtocolException(
      'AES-CBC 密文长度未按 16 字节对齐: ${ciphertext.length}',
    );
  }
  final BlockCipher cipher = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));
  final Uint8List output = Uint8List(ciphertext.length);
  for (int offset = 0; offset < ciphertext.length; offset += 16) {
    cipher.processBlock(ciphertext, offset, output, offset);
  }
  final int paddingLength = output.last;
  if (paddingLength < 1 || paddingLength > 16) {
    throw const QimeiProtocolException('AES-CBC 响应的 PKCS#7 填充长度无效');
  }
  for (
    int index = output.length - paddingLength;
    index < output.length;
    index += 1
  ) {
    if (output[index] != paddingLength) {
      throw const QimeiProtocolException('AES-CBC 响应的 PKCS#7 填充内容无效');
    }
  }
  return Uint8List.sublistView(output, 0, output.length - paddingLength);
}

RSAPublicKey qimeiRsaPublicKey([String publicKeyBase64 = _rsaPublicKeyBase64]) {
  if (publicKeyBase64 == _rsaPublicKeyBase64) {
    return _defaultRsaPublicKey;
  }
  return _parseQimeiRsaPublicKey(publicKeyBase64);
}

RSAPublicKey _parseQimeiRsaPublicKey(String publicKeyBase64) {
  try {
    final Uint8List der = _decodeStrictBase64(publicKeyBase64);
    final ASN1Sequence outer = ASN1Parser(der).nextObject() as ASN1Sequence;
    final ASN1BitString bitString = outer.elements![1] as ASN1BitString;
    final ASN1Sequence keySequence =
        ASN1Parser(Uint8List.fromList(bitString.stringValues!)).nextObject()
            as ASN1Sequence;
    final BigInt modulus = (keySequence.elements![0] as ASN1Integer).integer!;
    final BigInt exponent = (keySequence.elements![1] as ASN1Integer).integer!;
    return RSAPublicKey(modulus, exponent);
  } catch (error) {
    if (error is QimeiProtocolException) {
      rethrow;
    }
    throw const QimeiProtocolException('QIMEI RSA 公钥格式无效');
  }
}

Uint8List qimeiRsaEncryptPkcs1(
  Uint8List plaintext, {
  String publicKeyBase64 = _rsaPublicKeyBase64,
  QimeiRandomSource? randomSource,
}) {
  final QimeiRandomSource source = randomSource ?? SecureQimeiRandomSource();
  final AsymmetricBlockCipher cipher = PKCS1Encoding(RSAEngine())
    ..init(
      true,
      ParametersWithRandom<PublicKeyParameter<RSAPublicKey>>(
        PublicKeyParameter<RSAPublicKey>(qimeiRsaPublicKey(publicKeyBase64)),
        _QimeiSecureRandom(source),
      ),
    );
  return cipher.process(plaintext);
}

int _rol32(int value, int shift) {
  final int normalized = value & _mask32;
  return ((normalized << shift) & _mask32) | (normalized >> (32 - shift));
}

void _chachaQuarterRound(List<int> state, int a, int b, int c, int d) {
  state[a] = (state[a] + state[b]) & _mask32;
  state[d] = _rol32(state[d] ^ state[a], 16);
  state[c] = (state[c] + state[d]) & _mask32;
  state[b] = _rol32(state[b] ^ state[c], 12);
  state[a] = (state[a] + state[b]) & _mask32;
  state[d] = _rol32(state[d] ^ state[a], 8);
  state[c] = (state[c] + state[d]) & _mask32;
  state[b] = _rol32(state[b] ^ state[c], 7);
}

Uint8List qimeiChacha20Xor(
  Uint8List keyMaterial,
  int constantLow32,
  int constantHigh32,
  Uint8List data,
) {
  final Uint8List key = Uint8List(32);
  key.setRange(0, min(32, keyMaterial.length), keyMaterial);
  final List<int> constWords = _readWordsLe(_chachaConstant);
  final List<int> keyWords = _readWordsLe(key);
  final Uint8List output = Uint8List(data.length);
  for (
    int blockIndex = 0;
    blockIndex < (data.length + 63) ~/ 64;
    blockIndex += 1
  ) {
    final List<int> baseState = <int>[
      ...constWords,
      ...keyWords,
      blockIndex & _mask32,
      (blockIndex >> 32) & _mask32,
      constantLow32 & _mask32,
      constantHigh32 & _mask32,
    ];
    final List<int> work = List<int>.from(baseState);
    for (int round = 0; round < 10; round += 1) {
      _chachaQuarterRound(work, 0, 4, 8, 12);
      _chachaQuarterRound(work, 1, 5, 9, 13);
      _chachaQuarterRound(work, 2, 6, 10, 14);
      _chachaQuarterRound(work, 3, 7, 11, 15);
      _chachaQuarterRound(work, 0, 5, 10, 15);
      _chachaQuarterRound(work, 1, 6, 11, 12);
      _chachaQuarterRound(work, 2, 7, 8, 13);
      _chachaQuarterRound(work, 3, 4, 9, 14);
    }
    final Uint8List stream = Uint8List(64);
    for (int index = 0; index < 16; index += 1) {
      _writeUint32Le(
        stream,
        index * 4,
        (work[index] + baseState[index]) & _mask32,
      );
    }
    final int start = blockIndex * 64;
    final int end = min(start + 64, data.length);
    for (int index = start; index < end; index += 1) {
      output[index] = data[index] ^ stream[index - start];
    }
  }
  return output;
}

String buildQimeiSn(Uint8List mainInput, int timeWord) {
  final Uint8List md5First = Uint8List.fromList(md5.convert(mainInput).bytes);
  final Uint8List key = Uint8List(4);
  _writeUint32Le(key, 0, timeWord & _mask32);
  final Uint8List chacha = qimeiChacha20Xor(
    key,
    _snConstantLow32,
    _snConstantHigh32,
    md5First,
  );
  final Uint8List template = Uint8List.fromList(<int>[
    0x28,
    chacha[5],
    0x47,
    0x2B,
    md5First[4],
    0x2C,
    0x4C,
    0x4B,
  ]);
  final Uint8List md5Second = Uint8List.fromList(
    md5.convert(Uint8List.fromList(<int>[..._snFixed16, ...template])).bytes,
  );
  final Uint8List scratch = Uint8List(16)
    ..setRange(0, 4, md5First)
    ..[4] = (timeWord >> 24) & 0xFF
    ..setRange(8, 12, chacha, 1)
    ..setRange(12, 16, _uint32LeBytes(0x12345678));
  final Uint8List tail = Uint8List(16);
  for (int index = 0; index < 16; index += 1) {
    tail[index] = scratch[index] ^ template[index & 7] ^ md5Second[index];
  }
  final Uint8List structure = Uint8List.fromList(<int>[
    ..._snPrefix,
    md5First[4],
    chacha[5],
    ..._uint32BeBytes(timeWord & _mask32),
    ...tail,
    ..._snZeroTail,
  ]);
  return _bytesToHex(structure).toUpperCase();
}

Uint8List encodeQimeiVarint(int value) {
  if (value < 0) {
    throw QimeiProtocolException('negative varint: $value');
  }
  final BytesBuilder output = BytesBuilder(copy: false);
  int cursor = value;
  while (cursor >= 0x80) {
    output.addByte((cursor & 0x7F) | 0x80);
    cursor >>= 7;
  }
  output.addByte(cursor);
  return output.toBytes();
}

({int value, int offset}) readQimeiVarint(Uint8List data, int offset) {
  int value = 0;
  int shift = 0;
  final int start = offset;
  int cursor = offset;
  while (cursor < data.length && cursor - start < 10) {
    final int byte = data[cursor++];
    value |= (byte & 0x7F) << shift;
    if ((byte & 0x80) == 0) {
      return (value: value, offset: cursor);
    }
    shift += 7;
  }
  throw QimeiProtocolException('bad protobuf-like varint at offset $start');
}

List<QimeiProtoField> parseQimeiProtoMessage(Uint8List data) {
  final List<QimeiProtoField> fields = <QimeiProtoField>[];
  int offset = 0;
  while (offset < data.length) {
    final int start = offset;
    final ({int value, int offset}) keyResult = readQimeiVarint(data, offset);
    final int key = keyResult.value;
    offset = keyResult.offset;
    final int field = key >> 3;
    final int wire = key & 7;
    if (field <= 0) {
      throw QimeiProtocolException(
        'invalid field number $field at offset $start',
      );
    }
    late Object value;
    if (wire == 0) {
      final ({int value, int offset}) result = readQimeiVarint(data, offset);
      value = result.value;
      offset = result.offset;
    } else if (wire == 1) {
      final int end = offset + 8;
      if (end > data.length) {
        throw QimeiProtocolException(
          'truncated fixed64 field#$field at offset $offset',
        );
      }
      value = Uint8List.sublistView(data, offset, end);
      offset = end;
    } else if (wire == 2) {
      final ({int value, int offset}) sizeResult = readQimeiVarint(
        data,
        offset,
      );
      offset = sizeResult.offset;
      final int end = offset + sizeResult.value;
      if (end > data.length) {
        throw QimeiProtocolException(
          'truncated length-delimited field#$field: need ${sizeResult.value}, have ${data.length - offset}',
        );
      }
      value = Uint8List.sublistView(data, offset, end);
      offset = end;
    } else if (wire == 5) {
      final int end = offset + 4;
      if (end > data.length) {
        throw QimeiProtocolException(
          'truncated fixed32 field#$field at offset $offset',
        );
      }
      value = Uint8List.sublistView(data, offset, end);
      offset = end;
    } else {
      throw QimeiProtocolException(
        'unsupported protobuf-like wire type $wire at offset $start',
      );
    }
    fields.add(
      QimeiProtoField(
        field: field,
        wire: wire,
        value: value,
        offset: start,
        end: offset,
      ),
    );
  }
  return fields;
}

Uint8List serializeQimeiProtoMessage(List<QimeiProtoField> fields) {
  final BytesBuilder output = BytesBuilder(copy: false);
  for (final QimeiProtoField item in fields) {
    if (item.field <= 0) {
      throw QimeiProtocolException('invalid field number ${item.field}');
    }
    output.add(encodeQimeiVarint((item.field << 3) | item.wire));
    if (item.wire == 0) {
      if (item.value is! int) {
        throw QimeiProtocolException(
          'field#${item.field} wire=0 needs int value',
        );
      }
      output.add(encodeQimeiVarint(item.value as int));
    } else if (item.wire == 1) {
      if (item.value is! Uint8List || (item.value as Uint8List).length != 8) {
        throw QimeiProtocolException(
          'field#${item.field} wire=1 needs 8 bytes',
        );
      }
      output.add(item.value as Uint8List);
    } else if (item.wire == 2) {
      if (item.value is! Uint8List) {
        throw QimeiProtocolException('field#${item.field} wire=2 needs bytes');
      }
      final Uint8List bytes = item.value as Uint8List;
      output.add(encodeQimeiVarint(bytes.length));
      output.add(bytes);
    } else if (item.wire == 5) {
      if (item.value is! Uint8List || (item.value as Uint8List).length != 4) {
        throw QimeiProtocolException(
          'field#${item.field} wire=5 needs 4 bytes',
        );
      }
      output.add(item.value as Uint8List);
    } else {
      throw QimeiProtocolException(
        'field#${item.field} uses unsupported wire type ${item.wire}',
      );
    }
  }
  return output.toBytes();
}

Map<int, QimeiProtoField> qimeiFieldsByNumber(List<QimeiProtoField> fields) {
  final Map<int, QimeiProtoField> result = <int, QimeiProtoField>{};
  for (final QimeiProtoField item in fields) {
    if (result.containsKey(item.field)) {
      throw QimeiProtocolException(
        'duplicate protobuf-like field#${item.field}',
      );
    }
    result[item.field] = item;
  }
  return result;
}

Map<int, Object> parseQimeiProtoLike(Uint8List data) => <int, Object>{
  for (final MapEntry<int, QimeiProtoField> entry in qimeiFieldsByNumber(
    parseQimeiProtoMessage(data),
  ).entries)
    entry.key: entry.value.value,
};

Uint8List requireQimeiBytes(QimeiProtoField? item, String label) {
  if (item == null || item.wire != 2 || item.value is! Uint8List) {
    throw QimeiProtocolException(
      '$label must be a length-delimited bytes field',
    );
  }
  return item.value as Uint8List;
}

int requireQimeiInt(QimeiProtoField? item, String label) {
  if (item == null || item.wire != 0 || item.value is! int) {
    throw QimeiProtocolException('$label must be a varint field');
  }
  return item.value as int;
}

Uint8List qimeiCustomIvSha256(Uint8List data) {
  final int bitLength = data.length * 8;
  final BytesBuilder paddedBuilder = BytesBuilder(copy: false)
    ..add(data)
    ..addByte(0x80);
  int currentLength = data.length + 1;
  while (currentLength % 64 != 56) {
    paddedBuilder.addByte(0);
    currentLength += 1;
  }
  final Uint8List bitLengthBytes = Uint8List(8);
  BigInt cursor = BigInt.from(bitLength);
  for (int index = 7; index >= 0; index -= 1) {
    bitLengthBytes[index] = (cursor & BigInt.from(0xFF)).toInt();
    cursor >>= 8;
  }
  paddedBuilder.add(bitLengthBytes);
  final Uint8List padded = paddedBuilder.toBytes();
  List<int> state = List<int>.from(_customIv);
  for (int offset = 0; offset < padded.length; offset += 64) {
    final List<int> words = List<int>.filled(64, 0);
    for (int index = 0; index < 16; index += 1) {
      words[index] = _readUint32Be(padded, offset + (index * 4));
    }
    for (int index = 16; index < 64; index += 1) {
      final int sigma0 =
          _rotr32(words[index - 15], 7) ^
          _rotr32(words[index - 15], 18) ^
          (words[index - 15] >> 3);
      final int sigma1 =
          _rotr32(words[index - 2], 17) ^
          _rotr32(words[index - 2], 19) ^
          (words[index - 2] >> 10);
      words[index] =
          (words[index - 16] + sigma0 + words[index - 7] + sigma1) & _mask32;
    }
    int a = state[0];
    int b = state[1];
    int c = state[2];
    int d = state[3];
    int e = state[4];
    int f = state[5];
    int g = state[6];
    int h = state[7];
    for (int index = 0; index < 64; index += 1) {
      final int sum1 = _rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25);
      final int choose = (e & f) ^ ((~e) & g);
      final int temp1 =
          (h + sum1 + choose + _sha256K[index] + words[index]) & _mask32;
      final int sum0 = _rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22);
      final int majority = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = (sum0 + majority) & _mask32;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & _mask32;
    }
    final List<int> updated = <int>[a, b, c, d, e, f, g, h];
    state = List<int>.generate(
      8,
      (int index) => (state[index] + updated[index]) & _mask32,
    );
  }
  final Uint8List output = Uint8List(32);
  for (int index = 0; index < state.length; index += 1) {
    _writeUint32Be(output, index * 4, state[index]);
  }
  return output;
}

({Uint8List left, Uint8List right}) qimeiAsymmetricSplit(Uint8List material) {
  final int totalLength = material.length + _field57Const20.length;
  final Uint8List left = Uint8List((totalLength + 1) ~/ 2);
  final Uint8List right = Uint8List(totalLength ~/ 2);
  for (int index = 0; index < totalLength; index += 1) {
    if ((index & 1) == 0) {
      left[index ~/ 2] = index < _field57Const20.length
          ? _field57Const20[index]
          : material[index - _field57Const20.length];
    } else {
      right[index ~/ 2] = index < material.length
          ? material[index]
          : _field57Const20[index - material.length];
    }
  }
  return (left: left, right: right);
}

String buildQimeiField7Token(
  String field5,
  QmDeviceProfile profile,
  QimeiPayloadState state,
) {
  final Uint8List material = Uint8List.fromList(
    utf8.encode(
      '$field5${state.cacheQ16}${state.cacheQ36}${profile.osVersion}${profile.model}'
      '${profile.platformDeviceId}${profile.sdkVersion}${profile.appVersion}',
    ),
  );
  final ({Uint8List left, Uint8List right}) split = qimeiAsymmetricSplit(
    material,
  );
  final Uint8List first = qimeiCustomIvSha256(split.left);
  final Uint8List second = qimeiCustomIvSha256(split.right);
  final Uint8List selected = Uint8List.fromList(
    first.map((int byte) => second[byte & 0x1F]).toList(growable: false),
  );
  return _bytesToHex(selected).toUpperCase();
}

String buildQimeiDataLocalField5(
  QmDeviceProfile profile, {
  Map<String, Object?>? snapshot,
  int? timestampSeconds,
}) {
  final Map<String, Object?> effective =
      snapshot ??
      generateQmDataLocalSnapshot(
        profile,
        currentTimeMs: timestampSeconds == null
            ? null
            : timestampSeconds * 1000,
      );
  final Object? rawRecords = effective['records'];
  if (rawRecords is! List ||
      rawRecords.length != 122 ||
      rawRecords.any((Object? item) => item is! String)) {
    throw const QimeiProtocolException(
      'data_local snapshot records must be 122 strings',
    );
  }
  final List<String> records = rawRecords.cast<String>();
  final List<String> pairs = <String>[];
  for (int index = 0; index < _dataLocalLongSelector.length; index += 1) {
    final int keyIndex = index < 9 ? index + 1 : index + 2;
    pairs.add('k$keyIndex:${records[_dataLocalLongSelector[index]]}');
  }
  pairs.add('k10:1');
  return pairs.join(';');
}

String buildQimeiField18Capsule(
  QmDeviceProfile profile, {
  int? timestampSeconds,
}) {
  final Map<String, Object?> data = <String, Object?>{
    '0': timestampSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    '2': profile.suspiciousModules,
    '10': profile.virtioBitmask,
    '11': profile.riskBitmask,
    '16': profile.sourceDirStatus,
    '17': profile.signingBlockStatus,
    '21': 2,
    '22': profile.abi,
    '23': profile.artMethodEntries,
    '25': profile.mountinfoZygisk ? 1 : 0,
  };
  if (profile.networkBitmask != null) {
    data['19'] = profile.networkBitmask;
  }
  final Map<String, String> hooks = <String, String>{};
  if (profile.instrumentationClass.isNotEmpty) {
    hooks['1'] = profile.instrumentationClass;
  }
  if (profile.callbackClass.isNotEmpty) {
    hooks['2'] = profile.callbackClass;
  }
  if (hooks.isNotEmpty) {
    data['24'] = hooks;
  }
  final String json = encodePythonJson(
    data,
    asciiOnly: false,
    sortKeys: false,
  ).replaceAll('/', r'\/');
  return base64Encode(
    qimeiAesEncryptCbc(
      Uint8List.fromList(utf8.encode(json)),
      _field18Key,
      _field18Iv,
    ),
  );
}

Uint8List buildQimeiRegisterPayload({
  QmDeviceProfile profile = const QmDeviceProfile(),
  QimeiPayloadState state = const QimeiPayloadState(),
  QimeiRandomSource? randomSource,
}) {
  final QimeiRandomSource random = randomSource ?? SecureQimeiRandomSource();
  final String headToken =
      state.headDeviceToken ?? _bytesToHex(random.nextBytes(8)).toUpperCase();
  if (utf8.encode(headToken).length != 16) {
    throw const QimeiProtocolException(
      'REGISTER head field#2 token must be exactly 16 UTF-8 bytes',
    );
  }
  final Uint8List head = serializeQimeiProtoMessage(<QimeiProtoField>[
    QimeiProtoField(field: 1, wire: 0, value: QimeiCommand.register.value),
    QimeiProtoField(
      field: 2,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(headToken)),
    ),
    QimeiProtoField(field: 3, wire: 0, value: 0),
    QimeiProtoField(
      field: 4,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(profile.platformDeviceId)),
    ),
    QimeiProtoField(
      field: 5,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(profile.sdkVersion)),
    ),
    QimeiProtoField(
      field: 6,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(profile.appVersion)),
    ),
    QimeiProtoField(
      field: 7,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(profile.osVersion)),
    ),
    QimeiProtoField(
      field: 8,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(profile.model)),
    ),
    QimeiProtoField(
      field: 9,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(state.cacheQ36)),
    ),
    QimeiProtoField(
      field: 10,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(state.cacheQ16)),
    ),
    QimeiProtoField(
      field: 11,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(profile.processName)),
    ),
    QimeiProtoField(
      field: 12,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(profile.networkType)),
    ),
    QimeiProtoField(field: 13, wire: 0, value: state.registerCounter),
  ]);
  final String field5 =
      state.dataLocalField5 ??
      buildQimeiDataLocalField5(
        profile,
        snapshot: state.dataLocalSnapshot,
        timestampSeconds: state.dataLocalTimestampSeconds,
      );
  final List<QimeiProtoField> bodyFields = <QimeiProtoField>[
    QimeiProtoField(
      field: 5,
      wire: 2,
      value: Uint8List.fromList(utf8.encode(field5)),
    ),
    QimeiProtoField(
      field: 7,
      wire: 2,
      value: Uint8List.fromList(
        ascii.encode(buildQimeiField7Token(field5, profile, state)),
      ),
    ),
  ];
  if (state.preauditEnabled) {
    bodyFields.add(
      QimeiProtoField(
        field: 18,
        wire: 2,
        value: Uint8List.fromList(
          ascii.encode(
            buildQimeiField18Capsule(
              profile,
              timestampSeconds: state.preauditTimestampSeconds,
            ),
          ),
        ),
      ),
    );
  }
  return serializeQimeiProtoMessage(<QimeiProtoField>[
    QimeiProtoField(field: 1, wire: 2, value: head),
    QimeiProtoField(
      field: 2,
      wire: 2,
      value: serializeQimeiProtoMessage(bodyFields),
    ),
  ]);
}

QimeiRequestArtifacts buildGetQimei36Request(
  Uint8List packedPayload, {
  Uint8List? requestKey,
  Uint8List? requestIv,
  int? timestampMs,
  String? nonceHex,
  int? headerTimestampSeconds,
  String userAgent = defaultQimeiUserAgent,
  QimeiRandomSource? randomSource,
}) {
  final Map<int, QimeiProtoField> outer = qimeiFieldsByNumber(
    parseQimeiProtoMessage(packedPayload),
  );
  final Map<int, QimeiProtoField> head = qimeiFieldsByNumber(
    parseQimeiProtoMessage(requireQimeiBytes(outer[1], 'packed outer field#1')),
  );
  if (requireQimeiInt(head[1], 'packed inner field#1') !=
      QimeiCommand.register.value) {
    throw const QimeiProtocolException('REGISTER 载荷中的命令不正确');
  }
  final QimeiRandomSource random = randomSource ?? SecureQimeiRandomSource();
  final Uint8List key = requestKey ?? random.nextBytes(16);
  final Uint8List iv = requestIv ?? random.nextBytes(16);
  _validateAesParameters(key, iv);
  final Uint8List packedCipher = qimeiAesEncryptCbc(
    packedPayload,
    _packedKey,
    _packedIv,
  );
  final Uint8List pmsPlain = Uint8List.fromList(<int>[
    ..._pmsHeader,
    ...packedCipher,
  ]);
  final Uint8List pmsCipher = qimeiAesEncryptCbc(pmsPlain, key, iv);
  final String pms = base64Encode(pmsCipher);
  final String tm = (timestampMs ?? DateTime.now().millisecondsSinceEpoch)
      .toString();
  final String nonce =
      nonceHex ?? _bytesToHex(random.nextBytes(8)).toUpperCase();
  if (nonce.length != 16 || !_isHex(nonce)) {
    throw const QimeiProtocolException('QIMEI nonce 必须是 16 个十六进制字符');
  }
  final String ky = base64Encode(
    qimeiRsaEncryptPkcs1(
      Uint8List.fromList(<int>[...key, ...iv]),
      randomSource: random,
    ),
  );
  final Uint8List snInput = Uint8List.fromList(
    ascii.encode('1$ky$pms$tm$nonce'),
  );
  final int timeWord = int.parse(tm) & _mask32;
  final String sn = buildQimeiSn(snInput, timeWord);
  final Map<String, String> reqData = <String, String>{
    'cpt': '1',
    'ky': ky,
    'pms': pms,
    'tm': tm,
    'nn': nonce,
    'sn': sn,
    'ext': '',
  };
  final int timestamp =
      headerTimestampSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final String sign = md5
      .convert(utf8.encode('$qimeiAppId$qimeiSignSecret$timestamp'))
      .toString();
  return QimeiRequestArtifacts(
    command: QimeiCommand.register,
    cpt: '1',
    headers: <String, String>{
      'Content-Type': 'application/json',
      'appid': qimeiAppId,
      'timestamp': timestamp.toString(),
      'sign': sign,
      'service': qimeiService,
      'method': qimeiMethod,
      'user-agent': userAgent,
    },
    requestBody: <String, Object?>{
      'app': 0,
      'os': 1,
      'reqData': encodePythonJson(reqData, asciiOnly: false, sortKeys: false),
    },
    reqData: reqData,
    packedPayload: packedPayload,
    pmsPlain: pmsPlain,
    pmsCipher: pmsCipher,
    requestKey: key,
    requestIv: iv,
    ky: ky,
    snInput: snInput,
    sn: sn,
  );
}

({String qimei16, String qimei36}) validateQimeiIdentity(
  String qimei16,
  String qimei36,
) {
  if ((qimei16.length != 16 && qimei16.length != 36) ||
      !_isAsciiAlphanumeric(qimei16)) {
    throw const QimeiProtocolException('QIMEI16 必须是 16 或 36 位 ASCII 字母数字');
  }
  if (qimei36.length != 36 || !_isAsciiAlphanumeric(qimei36)) {
    throw const QimeiProtocolException('QIMEI36 必须是 36 位 ASCII 字母数字');
  }
  return (qimei16: qimei16, qimei36: qimei36);
}

({String qimei16, String qimei36}) parseQimeiResponse(
  Map<String, Object?> response,
  Uint8List requestKey,
  Uint8List requestIv,
) {
  if (response['code'] != 0) {
    throw QimeiProtocolException('QIMEI TRPC 外层错误: code=${response['code']}');
  }
  final Object? rawInner = response['data'];
  late Map<String, Object?> inner;
  if (rawInner is String) {
    try {
      final Object? decoded = jsonDecode(rawInner);
      if (decoded is! Map) {
        throw const FormatException('inner data is not an object');
      }
      inner = <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in decoded.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      };
    } catch (_) {
      throw const QimeiProtocolException('QIMEI 内层 data 不是有效 JSON');
    }
  } else if (rawInner is Map) {
    inner = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in rawInner.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
  } else {
    throw const QimeiProtocolException('QIMEI 响应缺少内层 data');
  }
  if (inner['code'] != 0) {
    throw QimeiProtocolException('QIMEI 业务错误: code=${inner['code']}');
  }
  final Object? encoded = inner['data'];
  if (encoded is! String || encoded.isEmpty) {
    throw const QimeiProtocolException('QIMEI 响应缺少加密 data');
  }
  final Uint8List plaintext = qimeiAesDecryptCbc(
    _decodeStrictBase64(encoded),
    requestKey,
    requestIv,
  );
  final Map<int, QimeiProtoField> fields = qimeiFieldsByNumber(
    parseQimeiProtoMessage(plaintext),
  );
  late final String q16;
  late final String q36;
  try {
    q16 = ascii.decode(requireQimeiBytes(fields[1], 'QIMEI response field#1'));
    q36 = ascii.decode(requireQimeiBytes(fields[2], 'QIMEI response field#2'));
  } on FormatException {
    throw const QimeiProtocolException('QIMEI 标识必须是 ASCII 字符串');
  }
  return validateQimeiIdentity(q16, q36);
}

final class _QimeiSecureRandom implements SecureRandom {
  _QimeiSecureRandom(this._source);

  final QimeiRandomSource _source;

  @override
  String get algorithmName => 'QIMEI-RANDOM';

  @override
  void seed(CipherParameters params) {}

  @override
  int nextUint8() => _source.nextBytes(1).single;

  @override
  int nextUint16() => nextUint8() | (nextUint8() << 8);

  @override
  int nextUint32() =>
      nextUint8() |
      (nextUint8() << 8) |
      (nextUint8() << 16) |
      (nextUint8() << 24);

  @override
  Uint8List nextBytes(int count) => _source.nextBytes(count);

  @override
  BigInt nextBigInteger(int bitLength) {
    if (bitLength < 0) {
      throw ArgumentError.value(bitLength, 'bitLength', '不能为负数');
    }
    final int byteCount = (bitLength + 7) ~/ 8;
    final Uint8List bytes = nextBytes(byteCount);
    if (bytes.isNotEmpty) {
      final int excessBits = (byteCount * 8) - bitLength;
      bytes[0] &= (1 << (8 - excessBits)) - 1;
    }
    BigInt result = BigInt.zero;
    for (final int byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}

void _validateAesParameters(Uint8List key, Uint8List iv) {
  if (key.length != 16 || iv.length != 16) {
    throw const QimeiProtocolException('AES-128-CBC 的 key 和 IV 必须都是 16 字节');
  }
}

Uint8List _decodeStrictBase64(String value) {
  if (value.isEmpty ||
      value.contains(_whitespacePattern) ||
      !_base64CharactersPattern.hasMatch(value)) {
    throw const QimeiProtocolException('QIMEI 响应 data 不是有效 Base64');
  }
  try {
    final Uint8List decoded = base64Decode(value);
    if (base64Encode(decoded).replaceAll('=', '') !=
        value.replaceAll('=', '')) {
      throw const FormatException('non canonical base64');
    }
    return decoded;
  } catch (_) {
    throw const QimeiProtocolException('QIMEI 响应 data 不是有效 Base64');
  }
}

int _rotr32(int value, int bits) =>
    ((value >> bits) | (value << (32 - bits))) & _mask32;

List<int> _readWordsLe(Uint8List bytes) => List<int>.generate(
  bytes.length ~/ 4,
  (int index) => _readUint32Le(bytes, index * 4),
  growable: false,
);

int _readUint32Le(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

int _readUint32Be(Uint8List bytes, int offset) =>
    ((bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3]) &
    _mask32;

void _writeUint32Le(Uint8List bytes, int offset, int value) {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}

void _writeUint32Be(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xFF;
  bytes[offset + 1] = (value >> 16) & 0xFF;
  bytes[offset + 2] = (value >> 8) & 0xFF;
  bytes[offset + 3] = value & 0xFF;
}

Uint8List _uint32LeBytes(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
Uint8List _uint32BeBytes(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);

bool _isAsciiAlphanumeric(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (final int unit in value.codeUnits) {
    final bool digit = unit >= 0x30 && unit <= 0x39;
    final bool upper = unit >= 0x41 && unit <= 0x5A;
    final bool lower = unit >= 0x61 && unit <= 0x7A;
    if (!digit && !upper && !lower) {
      return false;
    }
  }
  return true;
}

bool _isHex(String value) {
  for (final int unit in value.codeUnits) {
    final bool digit = unit >= 0x30 && unit <= 0x39;
    final bool upper = unit >= 0x41 && unit <= 0x46;
    final bool lower = unit >= 0x61 && unit <= 0x66;
    if (!digit && !upper && !lower) {
      return false;
    }
  }
  return true;
}

Uint8List _hexToBytes(String hex) {
  final Uint8List result = Uint8List(hex.length ~/ 2);
  for (int index = 0; index < hex.length; index += 2) {
    result[index ~/ 2] = int.parse(hex.substring(index, index + 2), radix: 16);
  }
  return result;
}

String _bytesToHex(Uint8List bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
