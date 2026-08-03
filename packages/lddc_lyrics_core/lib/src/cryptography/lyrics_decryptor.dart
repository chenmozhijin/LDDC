import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../error/error.dart';
import 'lyrics_crypto_engine.dart';
import 'lyrics_crypto_port.dart';
import 'tripledes.dart';

/// QRC 解密类型，对齐Python版 `QrcType`。
enum QrcDecryptType { cloud, local }

final RegExp _hexWhitespacePattern = RegExp(r'\s+');

/// 歌词解密器：封装 QRC/KRC 解密流程。
final class LyricsDecryptor {
  LyricsDecryptor({LyricsCryptoPort? crypto})
    : _crypto = crypto ?? const LyricsCryptoEngine();

  // 对齐Python版 `core/cryptography/__init__.py::QRC_KEY`。
  static const List<int> _qrcKey = <int>[
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

  // 对齐Python版 `core/cryptography/__init__.py::KRC_KEY`。
  static const List<int> _krcKey = <int>[
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

  final LyricsCryptoPort _crypto;
  TripleDesSchedule? _qrcDecryptSchedule;

  /// 解密 QRC（云端 hex 文本或本地二进制）。
  String decryptQrc(
    Object encryptedQrc, {
    QrcDecryptType type = QrcDecryptType.cloud,
  }) {
    final Uint8List encrypted = _normalizeQrcInput(encryptedQrc, type: type);
    if (encrypted.isEmpty) {
      throw const LddcLyricsDecryptException('没有可解密的数据');
    }

    try {
      Uint8List data = encrypted;
      if (type == QrcDecryptType.local) {
        final Uint8List qmc1Decoded = _crypto.qmc1Decrypt(data);
        if (qmc1Decoded.length <= 11) {
          throw const LddcLyricsDecryptException('QRC解密失败');
        }
        data = Uint8List.sublistView(qmc1Decoded, 11);
      }

      if (data.length % 8 != 0) {
        throw const LddcLyricsDecryptException('QRC解密失败');
      }

      final TripleDesSchedule schedule = _qrcDecryptSchedule ??= _crypto
          .tripledesKeySetup(
            key: Uint8List.fromList(_qrcKey),
            mode: TripleDesMode.decrypt,
          );
      final BytesBuilder decrypted = BytesBuilder(copy: false);
      for (int offset = 0; offset < data.length; offset += 8) {
        final Uint8List block = Uint8List.sublistView(data, offset, offset + 8);
        decrypted.add(_crypto.tripledesCrypt(data: block, schedule: schedule));
      }
      return _inflateQrcPayload(decrypted.takeBytes());
    } catch (error, stackTrace) {
      if (error is LddcLyricsDecryptException) {
        rethrow;
      }
      throw LddcLyricsDecryptException(
        'QRC解密失败',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 解密 KRC（本地二进制）。
  String decryptKrc(Object encryptedLyrics) {
    final Uint8List encrypted = _normalizeBytes(encryptedLyrics);
    if (encrypted.length <= 4) {
      throw const LddcLyricsDecryptException('没有可解密的数据');
    }

    try {
      final Uint8List encryptedData = Uint8List.sublistView(encrypted, 4);
      final Uint8List xored = Uint8List(encryptedData.length);
      for (int index = 0; index < encryptedData.length; index += 1) {
        xored[index] = encryptedData[index] ^ _krcKey[index % _krcKey.length];
      }
      final List<int> uncompressed = const ZLibDecoder().decodeBytes(xored);
      return utf8.decode(uncompressed);
    } catch (error, stackTrace) {
      throw LddcLyricsDecryptException(
        'KRC解密失败',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Uint8List _normalizeQrcInput(Object input, {required QrcDecryptType type}) {
    if (input is String) {
      final String text = input.trim();
      if (text.isEmpty) {
        throw const LddcLyricsDecryptException('没有可解密的数据');
      }
      if (type == QrcDecryptType.cloud) {
        return _decodeHex(text);
      }
      return Uint8List.fromList(utf8.encode(text));
    }
    return _normalizeBytes(input);
  }

  Uint8List _normalizeBytes(Object value) {
    if (value is Uint8List) {
      return Uint8List.fromList(value);
    }
    if (value is List) {
      // 解密入口是格式边界，不能把 null/字符串这类坏 payload 静默变成 0。
      // 提前指出第一个非法元素，调用方才能定位是 JSON、平台通道还是测试数据污染。
      final Uint8List bytes = Uint8List(value.length);
      for (int index = 0; index < value.length; index += 1) {
        final Object? item = value[index];
        if (item is! int) {
          throw LddcLyricsDecryptException(
            '无效的加密数据类型',
            detail: '字节列表第 $index 项不是整数: ${item.runtimeType}',
            context: <String, Object?>{
              'index': index,
              'type': item.runtimeType.toString(),
            },
          );
        }
        if (item < 0 || item > 0xff) {
          throw LddcLyricsDecryptException(
            '无效的加密数据类型',
            detail: '字节列表第 $index 项超出 0..255: $item',
            context: <String, Object?>{'index': index, 'value': item},
          );
        }
        bytes[index] = item;
      }
      return bytes;
    }
    throw const LddcLyricsDecryptException('无效的加密数据类型');
  }

  Uint8List _decodeHex(String text) {
    final String normalized = text.replaceAll(_hexWhitespacePattern, '');
    if (normalized.isEmpty || normalized.length.isOdd) {
      throw const LddcLyricsDecryptException('无效的加密数据类型');
    }
    final Uint8List result = Uint8List(normalized.length ~/ 2);
    for (int index = 0; index < normalized.length; index += 2) {
      final int? parsed = int.tryParse(
        normalized.substring(index, index + 2),
        radix: 16,
      );
      if (parsed == null) {
        throw const LddcLyricsDecryptException('无效的加密数据类型');
      }
      result[index ~/ 2] = parsed;
    }
    return result;
  }

  String _inflateQrcPayload(Uint8List payload) {
    final ZLibDecoder decoder = ZLibDecoder();
    Object? lastError;
    StackTrace? lastStackTrace;

    // Python `zlib.decompress` 可容忍尾部冗余字节；Dart 这里做等效兜底。
    for (int trim = 0; trim <= 7; trim += 1) {
      final int end = payload.length - trim;
      if (end <= 0) {
        break;
      }
      try {
        final List<int> uncompressed = decoder.decodeBytes(
          Uint8List.sublistView(payload, 0, end),
        );
        return utf8.decode(uncompressed);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        // 继续尝试更短的尾部截断。
      }
    }
    throw LddcLyricsDecryptException(
      'QRC解密失败',
      cause: lastError,
      stackTrace: lastStackTrace,
    );
  }
}
