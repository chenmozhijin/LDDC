import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' hide Digest;

const String _deviceIdXorKey = '3go8&\$8*3*3h0k(2)2';
const String _delimiterText = '-36cd479b6b5-';
final Uint8List _delimiter = Uint8List.fromList(ascii.encode(_delimiterText));
final Uint8List _nobody = Uint8List.fromList(ascii.encode('nobody'));
final Uint8List _use = Uint8List.fromList(ascii.encode('use'));
final Uint8List _md5ForEncrypt = Uint8List.fromList(
  ascii.encode('md5forencrypt'),
);
final Uint8List _eapiAesKey = Uint8List.fromList(
  ascii.encode('e82ckenh8dichen8'),
);
final Uint8List _cacheAesKey = Uint8List.fromList(
  ascii.encode(')(13daqP@ssw0rd~'),
);

/// 迁移自Python版 `eapi.py::eapi_params_encrypt`。
String eapiParamsEncrypt({
  required Uint8List path,
  required Map<String, Object?> params,
}) {
  final Uint8List paramsBytes = Uint8List.fromList(
    utf8.encode(jsonEncode(params)),
  );
  final Uint8List signSrc =
      (BytesBuilder(copy: false)
            ..add(_nobody)
            ..add(path)
            ..add(_use)
            ..add(paramsBytes)
            ..add(_md5ForEncrypt))
          .takeBytes();
  final String sign = md5.convert(signSrc).toString();
  final Uint8List aesSrc =
      (BytesBuilder(copy: false)
            ..add(path)
            ..add(_delimiter)
            ..add(paramsBytes)
            ..add(_delimiter)
            ..add(ascii.encode(sign)))
          .takeBytes();
  final Uint8List encryptedData = _aesEncrypt(aesSrc, _eapiAesKey);
  return 'params=${_encodeHex(encryptedData).toUpperCase()}';
}

/// 迁移自Python版 `eapi.py::eapi_params_decrypt`。
Map<String, Object?> eapiParamsDecrypt(String encryptedText) {
  final Uint8List encryptedBytes = _decodeHex(encryptedText);
  final Uint8List decryptedData = _aesDecrypt(encryptedBytes, _eapiAesKey);
  final String decryptedText = utf8.decode(decryptedData);
  final int firstDelimiter = decryptedText.indexOf(_delimiterText);
  final int lastDelimiter = decryptedText.lastIndexOf(_delimiterText);
  if (firstDelimiter < 0 || lastDelimiter <= firstDelimiter) {
    throw const FormatException('eapi_params_decrypt 数据格式非法');
  }

  final Uint8List path = Uint8List.fromList(
    utf8.encode(decryptedText.substring(0, firstDelimiter)),
  );
  final String paramsText = decryptedText.substring(
    firstDelimiter + _delimiterText.length,
    lastDelimiter,
  );
  final dynamic rawParams = jsonDecode(paramsText);
  if (rawParams is! Map) {
    throw const FormatException('eapi_params_decrypt params 不是对象');
  }
  final Map<String, Object?> params = rawParams.cast<String, Object?>();

  // 对齐Python版：重算 sign 但不做校验，仅保持等效执行路径。
  final Uint8List signSrc =
      (BytesBuilder(copy: false)
            ..add(_nobody)
            ..add(path)
            ..add(_use)
            ..add(utf8.encode(jsonEncode(params)))
            ..add(_md5ForEncrypt))
          .takeBytes();
  md5.convert(signSrc);
  return params;
}

/// 迁移自Python版 `eapi.py::get_cache_key`。
String eapiGetCacheKey(Uint8List data) {
  return base64Encode(_aesEncrypt(data, _cacheAesKey));
}

/// 迁移自Python版 `eapi.py::cache_key_decrypt`。
String eapiCacheKeyDecrypt(String data) {
  final Uint8List decrypted = _aesDecrypt(base64Decode(data), _cacheAesKey);
  return utf8.decode(decrypted);
}

/// 迁移自Python版 `eapi.py::eapi_response_decrypt`。
Uint8List eapiResponseDecrypt(Uint8List cipherBuffer) {
  return _aesDecrypt(cipherBuffer, _eapiAesKey);
}

/// 迁移自Python版 `eapi.py::get_anonimous_username`。
String eapiGetAnonymousUsername(String deviceId) {
  final StringBuffer xored = StringBuffer();
  final int keyLength = _deviceIdXorKey.length;
  for (int i = 0; i < deviceId.length; i++) {
    final int xorCode =
        deviceId.codeUnitAt(i) ^ _deviceIdXorKey.codeUnitAt(i % keyLength);
    xored.writeCharCode(xorCode);
  }
  final Digest md5Digest = md5.convert(utf8.encode(xored.toString()));
  final String combined = '$deviceId ${base64Encode(md5Digest.bytes)}';
  return base64Encode(utf8.encode(combined));
}

Uint8List _pkcs7Pad(Uint8List data, {int blockSize = 16}) {
  final int padLen = blockSize - (data.length % blockSize);
  return Uint8List(data.length + padLen)
    ..setRange(0, data.length, data)
    ..fillRange(data.length, data.length + padLen, padLen);
}

Uint8List _pkcs7Unpad(Uint8List data) {
  if (data.isEmpty) {
    throw const FormatException('PKCS#7 padding 数据为空');
  }
  if (data.length % 16 != 0) {
    throw FormatException('PKCS#7 padding 数据长度不是 16 的倍数: ${data.length}');
  }
  final int padLen = data[data.length - 1];
  if (padLen < 1 || padLen > 16) {
    throw const FormatException('Invalid padding encountered.');
  }
  if (padLen > data.length) {
    throw FormatException('PKCS#7 padding 长度超出数据长度: $padLen');
  }
  for (int index = data.length - padLen; index < data.length; index += 1) {
    if (data[index] != padLen) {
      throw FormatException(
        'PKCS#7 padding 字节不一致: index=$index expected=$padLen actual=${data[index]}',
      );
    }
  }
  return Uint8List.sublistView(data, 0, data.length - padLen);
}

Uint8List _aesEncrypt(Uint8List data, Uint8List key) {
  final Uint8List padded = _pkcs7Pad(data);
  return _aesEcbCrypt(padded, key, encrypt: true);
}

Uint8List _aesDecrypt(Uint8List cipherBuffer, Uint8List key) {
  final Uint8List decrypted = _aesEcbCrypt(cipherBuffer, key, encrypt: false);
  return _pkcs7Unpad(decrypted);
}

Uint8List _aesEcbCrypt(Uint8List data, Uint8List key, {required bool encrypt}) {
  if (data.length % 16 != 0) {
    throw ArgumentError.value(
      data.length,
      'data.length',
      'AES ECB 输入必须是 16 的倍数',
    );
  }
  final BlockCipher cipher = ECBBlockCipher(AESEngine())
    ..init(encrypt, KeyParameter(key));
  final Uint8List output = Uint8List(data.length);
  for (int i = 0; i < data.length; i += 16) {
    cipher.processBlock(data, i, output, i);
  }
  return output;
}

String _encodeHex(Uint8List data) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in data) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List _decodeHex(String hex) {
  final String normalized = hex.trim();
  if (normalized.length.isOdd) {
    throw FormatException('非法十六进制字符串长度: ${normalized.length}');
  }
  final Uint8List bytes = Uint8List(normalized.length ~/ 2);
  for (int i = 0; i < bytes.length; i++) {
    final int start = i * 2;
    final int? value = int.tryParse(
      normalized.substring(start, start + 2),
      radix: 16,
    );
    if (value == null) {
      throw FormatException(
        '非法十六进制内容: ${normalized.substring(start, start + 2)}',
      );
    }
    bytes[i] = value;
  }
  return bytes;
}
