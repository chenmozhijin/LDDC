import '../error/error.dart';
import 'krc_parser.dart' as krc;
import 'lyrics_parser_port.dart';
import 'parser_format.dart';
import 'parser_utils.dart';
import 'qrc_parser.dart' as qrc;

/// 统一分派入口：先魔数，再扩展名，最后执行无扩展名回退链路。
class LyricsParserDispatcher {
  const LyricsParserDispatcher(this._parser);

  final LyricsParserPort _parser;

  ParsedLyricsPayload parse(LyricsParserRequest request) {
    final List<LyricsParserFormat> candidates = _resolveCandidates(request);
    final List<String> errors = <String>[];
    final Set<LyricsParserFormat> supportedFormats = _parser.supportedFormats;

    for (final LyricsParserFormat format in candidates) {
      if (!supportedFormats.contains(format)) {
        errors.add('${format.value}: 未注册实现');
        continue;
      }

      try {
        return _parser.parse(format: format, request: request);
      } on LddcLyricsFormatException catch (error) {
        // 与Python版“按候选顺序尝试解析”的语义一致，格式不匹配时继续后续候选。
        errors.add('${format.value}: ${error.message}');
      }
    }

    final String detail = errors.isEmpty ? '无可用解析实现' : errors.join('; ');
    final String candidateChain = candidates
        .map((LyricsParserFormat format) => format.value)
        .join(' -> ');
    throw LddcLyricsFormatException(
      '歌词解析失败: ${request.path ?? '<memory>'}，候选=$candidateChain，原因=$detail',
    );
  }

  List<LyricsParserFormat> _resolveCandidates(LyricsParserRequest request) {
    final List<LyricsParserFormat> candidates = <LyricsParserFormat>[];
    final List<int> data = request.data;

    if (hasBytePrefix(data, qrc.qrcMagicHeader)) {
      return const <LyricsParserFormat>[LyricsParserFormat.qrc];
    }
    if (hasBytePrefix(data, krc.krcMagicHeader)) {
      return const <LyricsParserFormat>[LyricsParserFormat.krc];
    }

    if (_looksLikeJsonObject(data)) {
      candidates.add(LyricsParserFormat.jsonLrc);
    }

    final String? extension = request.normalizedExtension;
    switch (extension) {
      case '.qrc':
        _addCandidate(candidates, LyricsParserFormat.qrc);
      case '.krc':
        _addCandidate(candidates, LyricsParserFormat.krc);
      case '.yrc':
        _addCandidate(candidates, LyricsParserFormat.yrc);
      case '.json':
        _addCandidate(candidates, LyricsParserFormat.jsonLrc);
      case '.lrc':
        _addCandidate(candidates, LyricsParserFormat.lrc);
      case '.ass':
      case '.ssa':
        _addCandidate(candidates, LyricsParserFormat.ass);
      case '.srt':
        _addCandidate(candidates, LyricsParserFormat.srt);
      case null:
        // 对齐Python版 LocalAPI 的无扩展名回退链路：LRC -> ASS -> SRT。
        _addFallbackCandidates(candidates);
      default:
        if (candidates.isEmpty) {
          _addFallbackCandidates(candidates);
        }
    }

    return candidates;
  }

  static bool _looksLikeJsonObject(List<int> data) {
    int index = 0;
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      index = 3;
    }
    while (index < data.length && _isAsciiWhitespace(data[index])) {
      index += 1;
    }
    return index < data.length && data[index] == 0x7B; // '{'
  }

  static bool _isAsciiWhitespace(int value) {
    return value == 0x20 || value == 0x09 || value == 0x0A || value == 0x0D;
  }

  static void _addCandidate(
    List<LyricsParserFormat> candidates,
    LyricsParserFormat format,
  ) {
    if (!candidates.contains(format)) {
      candidates.add(format);
    }
  }

  static void _addFallbackCandidates(List<LyricsParserFormat> candidates) {
    for (final LyricsParserFormat format in textLyricsFallbackFormats) {
      _addCandidate(candidates, format);
    }
  }
}
