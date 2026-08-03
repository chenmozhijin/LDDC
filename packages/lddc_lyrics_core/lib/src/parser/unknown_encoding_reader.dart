import 'dart:typed_data';

import 'package:charset_codec/charset_codec.dart';
import 'package:charset_normalizer_dart/charset_normalizer_dart.dart'
    as charset_normalizer;

import '../error/error.dart';

/// 中文环境优先编码别名表，对齐Python版 `read_unknown_encoding_file`。
const List<String> _zhPreferredEncodingAliases = <String>[
  'gb18030',
  'chinese',
  'csiso58gb231280',
  'euc-cn',
  'euccn',
  'eucgb2312-cn',
  'gb2312-1980',
  'gb2312-80',
  'iso-ir-58',
  '936',
  'cp936',
  'ms936',
];
final List<String> _normalizedDefaultPreferredEncodings =
    _normalizePreferredEncodings(<String>[
      'utf_8',
      'ascii',
      ..._zhPreferredEncodingAliases,
    ]);
final RegExp _lyricsTimestampPattern = RegExp(
  r'(\[\d{1,2}:\d{2}(?:\.\d{1,3})?\]|<\d{1,2}:\d{2}(?:\.\d{1,3})?>)',
);

/// 从字节解码未知编码文本。
///
/// 文件系统读取属于 runtime 边界；纯 Dart 核心只接受调用方提供的字节。
String readUnknownEncoding({
  required Uint8List data,
  Iterable<String>? signWords,
  List<String>? preferredEncodings,
}) {
  return _decodeUnknownEncodingBytes(
    bytes: data,
    signWords: signWords,
    preferredEncodings: preferredEncodings,
  );
}

String _decodeUnknownEncodingBytes({
  required Uint8List bytes,
  Iterable<String>? signWords,
  List<String>? preferredEncodings,
}) {
  if (bytes.isEmpty) {
    return '';
  }

  final Set<String> requiredSigns = signWords == null
      ? const <String>{}
      : signWords.where((String value) => value.isNotEmpty).toSet();
  final List<String> normalizedPreferred = preferredEncodings == null
      ? _defaultPreferredEncodings()
      : _normalizePreferredEncodings(preferredEncodings);

  final String? utf8StrictText = _tryDecodeUtf8Strict(bytes);
  final String? preferredDecoded = _decodeByPreferredEncodings(
    bytes: bytes,
    preferredEncodings: normalizedPreferred,
    signWords: requiredSigns,
    utf8StrictText: utf8StrictText,
  );
  if (preferredDecoded != null) {
    return preferredDecoded;
  }

  final charset_normalizer.CharsetMatches matches = charset_normalizer
      .fromBytes(bytes);
  final _ScoredDecoded? best = _selectBestCandidate(
    matches: matches,
    preferredEncodings: normalizedPreferred,
    signWords: requiredSigns,
    utf8StrictText: utf8StrictText,
  );
  if (best != null) {
    return best.text;
  }

  throw const LddcDecodingException('无法解码文件');
}

/// 仅对字节执行未知编码解码。
String decodeUnknownEncoding(
  Uint8List data, {
  Iterable<String>? signWords,
  List<String>? preferredEncodings,
}) {
  return readUnknownEncoding(
    data: data,
    signWords: signWords,
    preferredEncodings: preferredEncodings,
  );
}

List<String> _defaultPreferredEncodings() {
  return _normalizedDefaultPreferredEncodings;
}

List<String> _normalizePreferredEncodings(List<String> encodings) {
  final Set<String> deduplicated = <String>{};
  for (final String encoding in encodings) {
    final String trimmed = encoding.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    try {
      deduplicated.add(
        charset_normalizer.ianaName(trimmed, strict: false).toLowerCase(),
      );
    } catch (_) {
      deduplicated.add(trimmed.toLowerCase().replaceAll('-', '_'));
    }
  }
  return deduplicated.toList(growable: false);
}

String? _decodeByPreferredEncodings({
  required Uint8List bytes,
  required List<String> preferredEncodings,
  required Set<String> signWords,
  required String? utf8StrictText,
}) {
  for (final String encoding in preferredEncodings) {
    final String decoded = _decodeWithCharsetCodec(bytes, encoding);
    if (decoded.isEmpty && bytes.isNotEmpty) {
      continue;
    }
    if (_shouldRejectPreferredDecoded(
      decoded: decoded,
      encoding: encoding,
      utf8StrictText: utf8StrictText,
    )) {
      continue;
    }
    if (!_containsAllSigns(decoded, signWords)) {
      continue;
    }
    return decoded;
  }
  return null;
}

String _decodeWithCharsetCodec(Uint8List bytes, String encoding) {
  try {
    return decodeBytes(
      bytes,
      encoding: encoding,
      errors: CodecErrorMode.strict,
    );
  } catch (_) {
    return '';
  }
}

String? _tryDecodeUtf8Strict(Uint8List bytes) {
  return tryDecodeBytes(
    bytes,
    encoding: 'utf_8',
    errors: CodecErrorMode.strict,
  );
}

bool _shouldRejectPreferredDecoded({
  required String decoded,
  required String encoding,
  required String? utf8StrictText,
}) {
  if (encoding == 'gb18030' && decoded.contains('锘縍EM')) {
    return true;
  }

  if (encoding != 'utf_8') {
    // 同一批字节只需做一次 UTF-8 严格探测，避免在多个候选编码循环中重复解码。
    if (utf8StrictText != null) {
      return true;
    }
  }
  return false;
}

_ScoredDecoded? _selectBestCandidate({
  required charset_normalizer.CharsetMatches matches,
  required List<String> preferredEncodings,
  required Set<String> signWords,
  required String? utf8StrictText,
}) {
  _ScoredDecoded? best;
  for (final charset_normalizer.CharsetMatch match in matches) {
    final String decoded;
    try {
      decoded = match.toString();
    } catch (_) {
      continue;
    }
    if (!_containsAllSigns(decoded, signWords)) {
      continue;
    }

    final String encoding = match.encoding.toLowerCase();
    double score = 1.0 - match.chaos;
    final int preferredIndex = preferredEncodings.indexOf(encoding);
    if (preferredIndex >= 0) {
      score += 0.35 - (preferredIndex * 0.02);
    }
    if (match.bom) {
      score += 0.08;
    }
    if (_looksLikeLyricsText(decoded)) {
      score += 0.05;
    }
    if (decoded.contains('\uFFFD')) {
      score -= 0.5;
    }
    if (encoding == 'gb18030' && decoded.contains('锘縍EM')) {
      score -= 0.6;
    }
    if (_shouldRejectPreferredDecoded(
      decoded: decoded,
      encoding: encoding,
      utf8StrictText: utf8StrictText,
    )) {
      score -= 0.25;
    }

    if (best == null || score > best.score) {
      best = _ScoredDecoded(text: decoded, score: score);
    }
  }
  return best;
}

bool _containsAllSigns(String text, Set<String> signWords) {
  if (signWords.isEmpty) {
    return true;
  }
  for (final String sign in signWords) {
    if (!text.contains(sign)) {
      return false;
    }
  }
  return true;
}

bool _looksLikeLyricsText(String text) {
  return _lyricsTimestampPattern.hasMatch(text);
}

final class _ScoredDecoded {
  const _ScoredDecoded({required this.text, required this.score});

  final String text;
  final double score;
}
