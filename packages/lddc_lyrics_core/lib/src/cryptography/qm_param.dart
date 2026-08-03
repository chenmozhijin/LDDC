import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'qm_device.dart';

const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const List<int> _hk = <int>[57, 70, 70, 49, 54, 57, 68, 54, 52, 54, 65, 51];
const int _delta = 0x9E3779B9;
const int _mask32 = 0xFFFFFFFF;

/// `qm_param.calc_sign` 的返回结果。
final class QmParamSignResult {
  const QmParamSignResult({required this.p1, required this.p2});

  final String p1;
  final String p2;
}

/// `qm_param` 随机源接口，便于向量测试注入固定随机序列。
abstract interface class QmParamRandomSource {
  int nextIndex(int maxExclusive);

  int nextByte();
}

/// 默认随机源（运行时使用）。
final class DefaultQmParamRandomSource implements QmParamRandomSource {
  DefaultQmParamRandomSource([Random? random])
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  int nextIndex(int maxExclusive) => _random.nextInt(maxExclusive);

  @override
  int nextByte() => _random.nextInt(256);
}

/// 回放随机源（向量测试使用）。
final class ReplayQmParamRandomSource implements QmParamRandomSource {
  ReplayQmParamRandomSource({
    List<int> indexValues = const <int>[],
    List<int> byteValues = const <int>[],
  }) : _indexValues = List<int>.from(indexValues),
       _byteValues = List<int>.from(byteValues);

  final List<int> _indexValues;
  final List<int> _byteValues;
  int _indexCursor = 0;
  int _byteCursor = 0;

  @override
  int nextIndex(int maxExclusive) {
    if (_indexCursor >= _indexValues.length) {
      throw StateError('ReplayQmParamRandomSource 索引随机值不足');
    }
    final int value = _indexValues[_indexCursor++];
    if (value < 0 || value >= maxExclusive) {
      throw RangeError('索引随机值越界: value=$value, maxExclusive=$maxExclusive');
    }
    return value;
  }

  @override
  int nextByte() {
    if (_byteCursor >= _byteValues.length) {
      throw StateError('ReplayQmParamRandomSource 字节随机值不足');
    }
    final int value = _byteValues[_byteCursor++];
    if (value < 0 || value > 0xFF) {
      throw RangeError('字节随机值越界: value=$value');
    }
    return value;
  }
}

/// 迁移自Python版 `qm_param.py::calc_sign`。
QmParamSignResult calcQmParamSign({
  required Uint8List body,
  required String headers,
  QmParamRandomSource? randomSource,
}) {
  final QmParamRandomSource random =
      randomSource ?? DefaultQmParamRandomSource();

  final Uint8List nB = Uint8List(12);
  for (int index = 0; index < nB.length; index += 1) {
    nB[index] = _alphabet.codeUnitAt(random.nextIndex(_alphabet.length));
  }

  final List<int> base64BodyBytes = ascii.encode(base64Encode(body));
  final List<int> reversedBase64Body = base64BodyBytes.reversed.toList(
    growable: false,
  );
  final Hmac hmac = Hmac(sha1, _hk);
  final List<int> digest = hmac.convert(reversedBase64Body).bytes;
  final String p1 = base64Encode(<int>[...nB, ...digest]);

  final String keyInput = '${p1.substring(0, 8)}${p1.substring(p1.length - 8)}';
  final Uint8List keyBytes = Uint8List.fromList(ascii.encode(keyInput));
  final int k0 = _readUint32BE(keyBytes, 0);
  final int k1 = _readUint32BE(keyBytes, 4);
  final int k2 = _readUint32BE(keyBytes, 8);
  final int k3 = _readUint32BE(keyBytes, 12);

  final Uint8List v = Uint8List.fromList(utf8.encode(headers));
  final int vl = v.length;
  final int fn = (8 - (vl + 2)) % 8 + 2;
  final int tl = 1 + fn + vl + 7;

  final Uint8List buf = Uint8List(tl);
  buf[0] = (random.nextByte() & 0xF8) | (fn - 2);
  for (int i = 1; i <= fn; i++) {
    buf[i] = random.nextByte() & 0xFF;
  }
  buf.setRange(fn, fn + vl, v);

  final Uint8List res = Uint8List(tl);
  int trY = 0;
  int trZ = 0;
  int toY = 0;
  int toZ = 0;

  for (int i = 0; i < tl; i += 8) {
    final int py = _readUint32BE(buf, i);
    final int pz = _readUint32BE(buf, i + 4);
    final int oy = _toUint32(py ^ trY);
    final int oz = _toUint32(pz ^ trZ);
    int y = oy;
    int z = oz;
    int s = 0;

    for (int round = 0; round < 16; round++) {
      s = _toUint32(s + _delta);
      y = _toUint32(y + ((((z << 4) + k0) ^ (z + s) ^ ((z >> 5) + k1))));
      z = _toUint32(z + ((((y << 4) + k2) ^ (y + s) ^ ((y >> 5) + k3))));
    }

    trY = _toUint32(y ^ toY);
    trZ = _toUint32(z ^ toZ);
    _writeUint32BE(res, i, trY);
    _writeUint32BE(res, i + 4, trZ);
    toY = oy;
    toZ = oz;
  }

  return QmParamSignResult(p1: p1, p2: base64Encode(res));
}

/// 迁移自Python版 `qm_param.py::QMTea`。
final class QmTea {
  QmTea({required Uint8List key, QmParamRandomSource? randomSource})
    : _key = Uint8List.fromList(key),
      _randomSource = randomSource ?? DefaultQmParamRandomSource() {
    if (_key.length != 16) {
      throw ArgumentError.value(
        _key.length,
        'key.length',
        'QMTea key 必须为 16 字节',
      );
    }
  }

  final Uint8List _key;
  final QmParamRandomSource _randomSource;

  Uint8List encrypt(Uint8List plainText) {
    final int inputLen = plainText.length;

    int padLen = (inputLen + 10) % 8;
    if (padLen != 0) {
      padLen = 8 - padLen;
    }

    final Uint8List prePlain = Uint8List(8);
    final Uint8List plain = Uint8List(8);
    final Uint8List preCrypt = Uint8List(8);
    final BytesBuilder output = BytesBuilder(copy: false);

    int pos = 0;
    bool header = true;

    plain[0] = (_randomSource.nextByte() & 0xF8) | padLen;
    pos += 1;

    for (int i = 0; i < padLen; i++) {
      plain[pos] = _randomSource.nextByte() & 0xFF;
      pos += 1;
    }

    for (int i = 0; i < 2; i++) {
      plain[pos] = _randomSource.nextByte() & 0xFF;
      pos += 1;
      if (pos == 8) {
        _encryptBlock(
          plain: plain,
          prePlain: prePlain,
          preCrypt: preCrypt,
          header: header,
          output: output,
        );
        header = false;
        pos = 0;
      }
    }

    for (int i = 0; i < inputLen; i++) {
      plain[pos] = plainText[i];
      pos += 1;
      if (pos == 8) {
        _encryptBlock(
          plain: plain,
          prePlain: prePlain,
          preCrypt: preCrypt,
          header: header,
          output: output,
        );
        header = false;
        pos = 0;
      }
    }

    for (int i = 0; i < 7; i++) {
      plain[pos] = 0;
      pos += 1;
      if (pos == 8) {
        _encryptBlock(
          plain: plain,
          prePlain: prePlain,
          preCrypt: preCrypt,
          header: header,
          output: output,
        );
        header = false;
        pos = 0;
      }
    }

    return output.toBytes();
  }

  void _encryptBlock({
    required Uint8List plain,
    required Uint8List prePlain,
    required Uint8List preCrypt,
    required bool header,
    required BytesBuilder output,
  }) {
    for (int i = 0; i < 8; i++) {
      if (header) {
        plain[i] = plain[i] ^ prePlain[i];
      } else {
        plain[i] = plain[i] ^ preCrypt[i];
      }
    }

    final Uint8List encryptedBlock = _encipher(plain);
    for (int i = 0; i < 8; i++) {
      final int outByte = encryptedBlock[i] ^ prePlain[i];
      output.addByte(outByte);
      preCrypt[i] = outByte;
      prePlain[i] = plain[i];
    }
  }

  Uint8List _encipher(Uint8List v) {
    int y = _readUint32BE(v, 0);
    int z = _readUint32BE(v, 4);
    int sum = 0;
    final int k0 = _readUint32BE(_key, 0);
    final int k1 = _readUint32BE(_key, 4);
    final int k2 = _readUint32BE(_key, 8);
    final int k3 = _readUint32BE(_key, 12);

    for (int round = 0; round < 16; round++) {
      sum = _toUint32(sum + _delta);
      final int yMix =
          (((z << 4) & _mask32) + k0) ^ (z + sum) ^ (((z >> 5) & _mask32) + k1);
      y = _toUint32(y + yMix);
      final int zMix =
          (((y << 4) & _mask32) + k2) ^ (y + sum) ^ (((y >> 5) & _mask32) + k3);
      z = _toUint32(z + zMix);
    }

    final Uint8List out = Uint8List(8);
    _writeUint32BE(out, 0, y);
    _writeUint32BE(out, 4, z);
    return out;
  }
}

/// 迁移自Python版 `qm_param.py::QMParamGenerator`。
final class QmParamGenerator {
  QmParamGenerator({
    required QmDeviceProfile profile,
    required QmDeviceIdentity identity,
    QmParamRandomSource Function()? teaRandomSourceFactory,
  }) : androidId = identity.androidId,
       imei = profile.imei,
       simSerial = profile.simSerial,
       mcc = profile.mcc,
       mnc = profile.mnc,
       openUdid2 = identity.openUdid2,
       _teaRandomSourceFactory =
           teaRandomSourceFactory ?? (() => DefaultQmParamRandomSource()) {
    did = _generateDid();
    openUdid = _generateOpenUdid();
    aid = _generateAid();
    mValue = _generateMValue();
  }

  final String androidId;
  final String imei;
  final String simSerial;
  final String mcc;
  final String mnc;

  late final String did;
  late final String openUdid;
  final String openUdid2;
  late final String aid;
  late final String mValue;

  final QmParamRandomSource Function() _teaRandomSourceFactory;

  int _hashCode(String input) => qmJavaHashCode(input);

  String _generateDid() {
    if (imei.isEmpty) {
      return '';
    }
    return base64Encode(utf8.encode(imei));
  }

  String _generateOpenUdid() {
    final int hAndroidId = _hashCode(androidId);
    final int hImei = _hashCode(imei);
    final int hSim = _hashCode(simSerial);

    final int mostSigBits = hAndroidId;
    final int leastSigBits = (hImei << 32) | (hSim & _mask32);
    final Uint8List uuidBytes = Uint8List.fromList(<int>[
      ..._packInt64Signed(mostSigBits),
      ..._packInt64Signed(leastSigBits),
    ]);
    return _bytesToHex(uuidBytes);
  }

  String _generateAid() {
    // qm CommonParamPacker 直接读取 Settings.Secure.android_id。
    return androidId;
  }

  String _generateMValue() {
    final String jsonText = jsonEncode(<String, String>{
      'did': did,
      'mcc': mcc,
      'mnc': mnc,
    });
    final Uint8List jsonBytes = Uint8List.fromList(utf8.encode(jsonText));
    final Uint8List rawKey = Uint8List.fromList(utf8.encode(androidId));
    final Uint8List key = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      key[i] = i < rawKey.length ? rawKey[i] : 0;
    }
    final QmTea tea = QmTea(key: key, randomSource: _teaRandomSourceFactory());
    final Uint8List encrypted = tea.encrypt(jsonBytes);
    return base64Encode(encrypted);
  }
}

int _toUint32(int value) => value & _mask32;

int _readUint32BE(Uint8List data, int offset) {
  return ((data[offset] << 24) |
          (data[offset + 1] << 16) |
          (data[offset + 2] << 8) |
          data[offset + 3]) &
      _mask32;
}

void _writeUint32BE(Uint8List data, int offset, int value) {
  final int v = value & _mask32;
  data[offset] = (v >> 24) & 0xFF;
  data[offset + 1] = (v >> 16) & 0xFF;
  data[offset + 2] = (v >> 8) & 0xFF;
  data[offset + 3] = v & 0xFF;
}

Uint8List _packInt64Signed(int value) {
  final BigInt raw = BigInt.from(value);
  final BigInt min = -(BigInt.one << 63);
  final BigInt max = (BigInt.one << 63) - BigInt.one;
  if (raw < min || raw > max) {
    throw RangeError('int64 signed 越界: $value');
  }
  BigInt encoded = raw;
  if (encoded.isNegative) {
    encoded += BigInt.one << 64;
  }
  return _packBigInt64(encoded);
}

Uint8List _packBigInt64(BigInt value) {
  final Uint8List out = Uint8List(8);
  BigInt cursor = value;
  for (int i = 7; i >= 0; i--) {
    out[i] = (cursor & BigInt.from(0xFF)).toInt();
    cursor = cursor >> 8;
  }
  return out;
}

String _bytesToHex(Uint8List bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
