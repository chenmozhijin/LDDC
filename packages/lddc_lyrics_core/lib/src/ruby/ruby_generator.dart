import 'package:characters/characters.dart';

import 'ruby_char_utils.dart';
import 'ruby_dictionary.dart';
import 'ruby_index_mapper.dart';
import 'ruby_logic.dart';
import 'ruby_models.dart';
import 'ruby_unicode.dart';
import '../models/models.dart';

final RegExp _origSegmentSeparator = RegExp(r' +');
final RegExp _romaSegmentSeparator = RegExp(r' {2,}');

/// 判断文本是否包含汉字。
bool _containsKanji(String text) {
  for (final int rune in text.runes) {
    if (rune >= 0x4E00 && rune <= 0x9FFF) {
      return true;
    }
  }
  return false;
}

List<RubyToken> _tokenizeOrigLine(String text) {
  if (text.isEmpty) {
    return <RubyToken>[];
  }

  final List<RubyToken> tokens = <RubyToken>[];
  int i = 0;
  final List<String> chars = text.characters.toList(growable: false);
  final List<CharType> charTypes = chars
      .map<CharType>(getCharType)
      .toList(growable: false);
  final int n = chars.length;
  int groupIdCounter = 0;

  while (i < n) {
    final int matchLength = findLongestVocabPrefixLength(chars, i);

    if (matchLength > 0) {
      groupIdCounter += 1;
      final int decomposedStart = i;
      int subI = 0;
      while (subI < matchLength) {
        final CharType currentCharType = charTypes[i + subI];
        int subJ = subI + 1;
        while (subJ < matchLength && charTypes[i + subJ] == currentCharType) {
          subJ += 1;
        }

        final String segment = chars.getRange(i + subI, i + subJ).join();
        tokens.add(
          RubyToken(
            text: segment,
            charType: currentCharType,
            start: decomposedStart + subI,
            end: decomposedStart + subJ,
            groupId: groupIdCounter,
          ),
        );

        subI = subJ;
      }

      i += matchLength;
    } else {
      final CharType charType = charTypes[i];
      int j = i + 1;
      while (j < n && charTypes[j] == charType) {
        j += 1;
      }
      final String segment = chars.getRange(i, j).join();
      tokens.add(
        RubyToken(
          text: segment,
          charType: charType,
          start: i,
          end: j,
          groupId: null,
        ),
      );
      i = j;
    }
  }

  if (tokens.isEmpty) {
    return <RubyToken>[];
  }

  final List<RubyToken> mergedTokens = <RubyToken>[tokens.first];
  for (int idx = 1; idx < tokens.length; idx += 1) {
    final RubyToken prevToken = mergedTokens.last;
    final RubyToken currToken = tokens[idx];
    if (prevToken.charType == CharType.other &&
        currToken.charType == CharType.other &&
        prevToken.groupId == null &&
        currToken.groupId == null) {
      final String mergedText = prevToken.text + currToken.text;
      mergedTokens[mergedTokens.length - 1] = RubyToken(
        text: mergedText,
        charType: CharType.other,
        start: prevToken.start,
        end: currToken.end,
        groupId: null,
      );
    } else {
      mergedTokens.add(currToken);
    }
  }

  return mergedTokens;
}

/// 生成日文歌词平假名注音。
List<RubySpan> generateRuby(LyricsLine origLine, LyricsLine romaLine) {
  final String origTextRaw = origLine.words
      .map((LyricsWord word) => word.text)
      .join();
  final String romaTextRaw = romaLine.words
      .map((LyricsWord word) => word.text)
      .join();

  final IndexMapper mapper = IndexMapper(origTextRaw);
  final String origText = mapper.normalizedText;
  final String romaText = normalizeRubyNfkc(romaTextRaw);

  if (!_containsKanji(origText)) {
    return <RubySpan>[];
  }
  if (romaText.trim().isEmpty) {
    return <RubySpan>[];
  }

  final List<String> origSegments = origText.split(_origSegmentSeparator);
  final List<String> romaSegments = romaText.split(_romaSegmentSeparator);

  if (origSegments.length > 1 && origSegments.length == romaSegments.length) {
    final List<RubySpan> allResults = <RubySpan>[];
    int normOffset = 0;
    final List<RegExpMatch> origSeps = _origSegmentSeparator
        .allMatches(origText)
        .toList(growable: false);

    for (int i = 0; i < origSegments.length; i += 1) {
      final String origSeg = origSegments[i];
      final String romaSeg = romaSegments[i];

      final List<RubyToken> tokens = _tokenizeOrigLine(origSeg);
      final List<RubySpan> segmentResults = processLine(romaSeg, tokens);
      for (final RubySpan span in segmentResults) {
        final int normStart = span.start + normOffset;
        final int normEnd = span.end + normOffset;
        final (int, int) originalRange = mapper.toOriginalIndices(
          normStart,
          normEnd,
        );
        allResults.add(
          RubySpan(
            start: originalRange.$1,
            end: originalRange.$2,
            ruby: span.ruby,
          ),
        );
      }

      normOffset += origSeg.characters.length;
      if (i < origSeps.length) {
        normOffset += origSeps[i].end - origSeps[i].start;
      }
    }
    return allResults;
  }

  final List<RubyToken> tokens = _tokenizeOrigLine(origText);
  final List<RubySpan> normResults = processLine(romaText, tokens);
  return normResults
      .map((RubySpan span) {
        final (int, int) originalRange = mapper.toOriginalIndices(
          span.start,
          span.end,
        );
        return RubySpan(
          start: originalRange.$1,
          end: originalRange.$2,
          ruby: span.ruby,
        );
      })
      .toList(growable: false);
}
