import 'dart:collection';
import 'dart:typed_data';

import 'ruby_char_utils.dart';
import 'ruby_dictionary.dart';
import 'ruby_models.dart';
import 'ruby_romaji_converter.dart';
import 'ruby_rules.dart';

const String _rubyPlaceholder = '█';

const double _dictMatchReward = -1000;
const double _exactMatchCost = 0;
const double _annotationMatchCost = -1000;
const double _fuzzyBaseCost = 5;
const double _editDistanceCost = 150;
const double _kanjiRatioTarget = 2;
const double _kanaRatioTarget = 1;
const double _otherRatioTarget = 2;
const double _genericKanjiBaseCost = 10;
const double _genericKanaBaseCost = 2000;
const double _ratioPenaltyWeight = 8;
const double _sokuonEndPenalty = 100;
const double _skipTokenCost = 500;
const double _skipSymbolCost = 0;
const double _skipLatinCost = 0.1;
const double _skipHiraganaCost = 200;
const double _skipParenthesizedContentCost = 10;
const int _maxRubyDpCells = 60000;

/// DP 动作类型（顺序需与Python版一致）。
enum ActionType {
  start,
  skipToken,
  skipHira,
  matchExact,
  matchFuzzy,
  matchDict,
  matchAnnot,
  consumeGeneric,
}

/// OTHER 细分类型。
enum OtherType { latin, number, symbol }

final class TokenProps {
  const TokenProps({
    required this.skipCost,
    required this.isKana,
    required this.baseHira,
    required this.annotInfo,
    required this.dictInfo,
    required this.fuzzyVariants,
  });

  final double skipCost;
  final bool isKana;
  final String? baseHira;
  final (String, int)? annotInfo;
  final (List<String>, int)? dictInfo;
  final List<(String, double)>? fuzzyVariants;
}

// Ruby 对齐会反复比较相近假名片段、构造分隔用正则。这里使用有上限的
// LinkedHashMap 做小型 FIFO 缓存：命中时避免重复分配 DP 行和 RegExp，
// 超过上限时丢弃最早插入项，防止批量处理歌词时缓存无限增长。
final LinkedHashMap<(String, String), int> _levenshteinCache =
    LinkedHashMap<(String, String), int>();
final LinkedHashMap<String, RegExp> _symbolSplitPatternCache =
    LinkedHashMap<String, RegExp>();
final LinkedHashMap<String, RegExp> _latinSplitPatternCache =
    LinkedHashMap<String, RegExp>();

OtherType _classifyOtherToken(String text) {
  bool containsDigit = false;
  for (final int rune in text.runes) {
    if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
      return OtherType.latin;
    }
    if (rune >= 0x30 && rune <= 0x39) {
      containsDigit = true;
    }
  }
  return containsDigit ? OtherType.number : OtherType.symbol;
}

int _levenshtein(String s1, String s2) {
  if (s1.length < s2.length) {
    return _levenshtein(s2, s1);
  }
  if (s2.isEmpty) {
    return s1.length;
  }

  final (String, String) key = (s1, s2);
  final int? cached = _levenshteinCache[key];
  if (cached != null) {
    return cached;
  }

  Uint32List previousRow = Uint32List(s2.length + 1);
  Uint32List currentRow = Uint32List(s2.length + 1);
  for (int index = 0; index <= s2.length; index += 1) {
    previousRow[index] = index;
  }
  for (int i = 0; i < s1.length; i += 1) {
    currentRow[0] = i + 1;
    for (int j = 0; j < s2.length; j += 1) {
      final int insertions = previousRow[j + 1] + 1;
      final int deletions = currentRow[j] + 1;
      final int substitutions = previousRow[j] + (s1[i] != s2[j] ? 1 : 0);
      currentRow[j + 1] = _min3(insertions, deletions, substitutions);
    }
    final Uint32List completedRow = previousRow;
    previousRow = currentRow;
    currentRow = completedRow;
  }

  final int result = previousRow.last;
  _cachePutWithLimit(_levenshteinCache, key, result, 4096);
  return result;
}

List<(String, double)> _generateFuzzyVariants(
  String baseChar,
  List<RubyToken> tokens,
  int currTokenIndex,
) {
  // 模糊变体用于吸收罗马音、促音、长音等输入差异。搜索深度固定为 3，
  // processedHashes 负责去重，避免规则之间互相转换时形成指数级爆炸。
  final Map<String, double> results = <String, double>{baseChar: 0.0};
  List<(String, double)> queue = <(String, double)>[(baseChar, 0.0)];
  const int maxDepth = 3;

  final Set<String> processedHashes = <String>{baseChar};

  for (int depth = 0; depth < maxDepth; depth += 1) {
    if (queue.isEmpty) {
      break;
    }
    final List<(String, double)> nextQueue = <(String, double)>[];

    for (final (String text, double cost) in queue) {
      for (final MatchRule rule in allRules) {
        String newText = text;
        double ruleCost = 0.0;

        if (rule is SubstitutionRule) {
          if (text.contains(rule.from)) {
            newText = text.replaceAll(rule.from, rule.to);
            ruleCost = rule.cost * _fuzzyBaseCost;
          }
        } else if (rule is FunctionRule) {
          newText = rule.handler(text, tokens, currTokenIndex);
          if (newText != text) {
            ruleCost = rule.cost * _fuzzyBaseCost;
          }
        }

        if (newText == text) {
          continue;
        }

        final double newTotalCost = cost + ruleCost;
        final double? oldCost = results[newText];
        if (oldCost == null || newTotalCost < oldCost) {
          results[newText] = newTotalCost;
          if (!processedHashes.contains(newText)) {
            nextQueue.add((newText, newTotalCost));
            processedHashes.add(newText);
          }
        }
      }
    }

    queue = nextQueue;
  }

  return results.entries
      .map<(String, double)>(
        (MapEntry<String, double> entry) => (entry.key, entry.value),
      )
      .toList(growable: false);
}

double _calculateGenericCost(
  String tokenText,
  String consumedText,
  CharType charType,
) {
  final int tokenLength = tokenText.length;
  final int rubyLength = consumedText.length;
  if (tokenLength == 0) {
    return double.infinity;
  }

  double baseCost = 0.0;
  double targetRatio = 2.0;

  if (charType == CharType.kanji) {
    baseCost = _genericKanjiBaseCost;
    targetRatio = _kanjiRatioTarget;
    if (tokenLength > 1 && rubyLength == 1) {
      return 5000.0;
    }
  } else if (charType == CharType.hiragana || charType == CharType.katakana) {
    baseCost = _genericKanaBaseCost;
    targetRatio = _kanaRatioTarget;
  } else if (charType == CharType.symbol) {
    return double.infinity;
  } else if (charType == CharType.other) {
    final OtherType otherType = _classifyOtherToken(tokenText);
    if (otherType == OtherType.number) {
      baseCost = _genericKanjiBaseCost;
      targetRatio = _otherRatioTarget;
    } else {
      return double.infinity;
    }
  }

  final double ratio = rubyLength / tokenLength;
  if (charType == CharType.kanji && (ratio > 5.0 || ratio < 0.4)) {
    return 2000.0;
  }

  double sokuonPenalty = 0.0;
  if (consumedText.endsWith('っ')) {
    sokuonPenalty = _sokuonEndPenalty;
  }

  final double diff = (ratio - targetRatio).abs();
  final double ratioPenalty = diff * diff * _ratioPenaltyWeight;
  return baseCost + ratioPenalty + sokuonPenalty;
}

(String, int)? _getAnnotationInfo(List<RubyToken> tokens, int idx) {
  if (idx + 3 >= tokens.length) {
    return null;
  }

  final RubyToken t1 = tokens[idx + 1];
  if (t1.text != '(') {
    return null;
  }

  final RubyToken t0 = tokens[idx];
  if (t0.charType != CharType.kanji) {
    return null;
  }

  final RubyToken t2 = tokens[idx + 2];
  if (t2.charType != CharType.hiragana && t2.charType != CharType.katakana) {
    return null;
  }

  final RubyToken t3 = tokens[idx + 3];
  if (t3.text != ')') {
    return null;
  }

  final String hintHira = katakanaToHiragana(t2.text);
  return (hintHira, 4);
}

(List<String>, int)? _getDictGroupInfo(List<RubyToken> tokens, int idx) {
  final RubyToken current = tokens[idx];

  if (current.groupId != null) {
    if (idx > 0 && tokens[idx - 1].groupId == current.groupId) {
      return null;
    }

    int endIdx = idx + 1;
    while (endIdx < tokens.length &&
        tokens[endIdx].groupId == current.groupId) {
      endIdx += 1;
    }

    final StringBuffer groupText = StringBuffer();
    for (int tokenIndex = idx; tokenIndex < endIdx; tokenIndex += 1) {
      groupText.write(tokens[tokenIndex].text);
    }
    final List<String>? readings = findVocabWord(groupText.toString());
    if (readings != null) {
      return (readings, endIdx - idx);
    }
  } else {
    final List<String>? readings = findVocabWord(current.text);
    if (readings != null) {
      return (readings, 1);
    }
  }

  return null;
}

bool _isSkippableContext(List<RubyToken> tokens, int idx) {
  bool hasOpen = false;
  final int startBound = idx - 15 < -1 ? -1 : idx - 15;
  for (int i = idx - 1; i > startBound; i -= 1) {
    final String text = tokens[i].text;
    if (text == '(' || text == '（' || text == '《') {
      hasOpen = true;
      break;
    }
    if (text == ')' || text == '）' || text == '》') {
      break;
    }
  }

  if (!hasOpen) {
    return false;
  }

  bool hasClose = false;
  final int endBound = idx + 15 > tokens.length ? tokens.length : idx + 15;
  for (int i = idx + 1; i < endBound; i += 1) {
    final String text = tokens[i].text;
    if (text == ')' || text == '）' || text == '》') {
      hasClose = true;
      break;
    }
    if (text == '(' || text == '（' || text == '《') {
      break;
    }
  }
  return hasClose;
}

TokenProps _prepareTokenProps(List<RubyToken> tokens, int idx, int nTokens) {
  final RubyToken currentToken = tokens[idx];
  final CharType charType = currentToken.charType;
  final String tokenText = currentToken.text;

  double skipCostBase = _skipTokenCost;
  if (charType == CharType.symbol || tokenText.trim().isEmpty) {
    skipCostBase = _skipSymbolCost;
  } else if (charType == CharType.other) {
    final OtherType otherType = _classifyOtherToken(tokenText);
    if (otherType == OtherType.latin) {
      skipCostBase = _skipLatinCost;
    } else if (otherType == OtherType.symbol) {
      skipCostBase = _skipSymbolCost;
    }
  }

  if (idx > 0 &&
      idx + 1 < nTokens &&
      tokens[idx - 1].text == '(' &&
      tokens[idx + 1].text == ')') {
    skipCostBase = 0.0;
  } else if (_isSkippableContext(tokens, idx)) {
    skipCostBase = skipCostBase < _skipParenthesizedContentCost
        ? skipCostBase
        : _skipParenthesizedContentCost;
  }

  bool tokenIsKana = false;
  String? tokenBaseHira;
  if (charType == CharType.hiragana ||
      charType == CharType.katakana ||
      charType == CharType.symbol ||
      charType == CharType.other) {
    tokenBaseHira = katakanaToHiragana(tokenText);
    if (charType == CharType.hiragana || charType == CharType.katakana) {
      tokenIsKana = true;
    }
  }

  final (String, int)? annotInfo = _getAnnotationInfo(tokens, idx);
  final (List<String>, int)? dictInfo = _getDictGroupInfo(tokens, idx);
  List<(String, double)>? fuzzyVariants;
  if (tokenBaseHira != null) {
    fuzzyVariants = _generateFuzzyVariants(tokenBaseHira, tokens, idx);
  }

  return TokenProps(
    skipCost: skipCostBase,
    isKana: tokenIsKana,
    baseHira: tokenBaseHira,
    annotInfo: annotInfo,
    dictInfo: dictInfo,
    fuzzyVariants: fuzzyVariants,
  );
}

final class _PathStep {
  const _PathStep({
    required this.iEnd,
    required this.jEnd,
    required this.action,
    required this.iStart,
    required this.ruby,
  });

  final int iEnd;
  final int jEnd;
  final ActionType action;
  final int iStart;
  final String? ruby;
}

List<RubySpan> _dpAlign(List<RubyToken> tokens, String hiraStream) {
  final int nTokens = tokens.length;
  final int mHira = hiraStream.length;
  final int tokenTextLength = tokens.fold<int>(
    0,
    (int sum, RubyToken token) => sum + token.text.length,
  );
  final int estimatedCells =
      (nTokens + 1) * (mHira + 1) + tokenTextLength * (mHira + 1);
  if (estimatedCells > _maxRubyDpCells) {
    // Python 版没有安全阈值，会为超长行预分配多张矩阵。Flutter 版运行在
    // UI/桌面服务同步重建链路里，宁可跳过异常长段，也不能制造内存峰值。
    return <RubySpan>[];
  }

  // 这是本文件最核心的动态规划：横轴是罗马音转出的平假名位置，纵轴是原文 token。
  // 数值矩阵使用 typed data，避免每个代价、动作和父节点都成为独立 Dart 对象。
  // 父节点把二维坐标编码成单个整数；activeMin/Max 只扫描每一行真正到达的列。
  final int columns = mHira + 1;
  final List<Float64List> costs = List<Float64List>.generate(
    nTokens + 1,
    (_) => Float64List(columns)..fillRange(0, columns, double.infinity),
  );
  final List<Uint8List> actions = List<Uint8List>.generate(
    nTokens + 1,
    (_) => Uint8List(columns),
  );
  final List<Int32List> parents = List<Int32List>.generate(
    nTokens + 1,
    (_) => Int32List(columns)..fillRange(0, columns, -1),
  );
  final List<List<String?>> rubies = List<List<String?>>.generate(
    nTokens + 1,
    (_) => List<String?>.filled(columns, null),
  );

  final Int32List activeMin = Int32List(nTokens + 1)
    ..fillRange(0, nTokens + 1, mHira + 1);
  final Int32List activeMax = Int32List(nTokens + 1)
    ..fillRange(0, nTokens + 1, -1);
  costs[0][0] = 0.0;
  activeMin[0] = 0;
  activeMax[0] = 0;

  const double costImpossible = double.infinity;
  const double costSkipHira = _skipHiraganaCost;
  const double costAnnotMatch = _annotationMatchCost;
  const double costDictReward = _dictMatchReward;
  const double costExactMatch = _exactMatchCost;
  const double costEditDist = _editDistanceCost;

  for (int i = 0; i <= nTokens; i += 1) {
    final int currentMinJ = activeMin[i];
    int currentMaxJ = activeMax[i];
    if (currentMinJ > currentMaxJ) {
      continue;
    }

    RubyToken? currToken;
    TokenProps? props;
    if (i < nTokens) {
      currToken = tokens[i];
      props = _prepareTokenProps(tokens, i, nTokens);
    }

    int j = currentMinJ;
    while (j <= currentMaxJ) {
      if (j > mHira) {
        break;
      }

      final double currentCost = costs[i][j];
      if (currentCost >= costImpossible) {
        j += 1;
        continue;
      }

      if (j < mHira) {
        final int nextJ = j + 1;
        final double newCost = currentCost + costSkipHira;
        if (newCost < costs[i][nextJ]) {
          costs[i][nextJ] = newCost;
          actions[i][nextJ] = ActionType.skipHira.index;
          parents[i][nextJ] = i * columns + j;
          rubies[i][nextJ] = hiraStream[j];
          currentMaxJ = currentMaxJ > nextJ ? currentMaxJ : nextJ;
        }
      }

      if (currToken == null || props == null) {
        j += 1;
        continue;
      }

      final int niSkip = i + 1;
      final int njSkip = j;
      final double skipTokenCost = currentCost + props.skipCost;
      if (skipTokenCost < costs[niSkip][njSkip]) {
        costs[niSkip][njSkip] = skipTokenCost;
        actions[niSkip][njSkip] = ActionType.skipToken.index;
        parents[niSkip][njSkip] = i * columns + j;
        rubies[niSkip][njSkip] = '';
        _updateActiveBounds(activeMin, activeMax, niSkip, njSkip);
      }

      if (props.annotInfo case (String hintHira, int consumedTokens)) {
        final int hintLength = hintHira.length;
        if (j + hintLength <= mHira &&
            hiraStream.substring(j, j + hintLength) == hintHira) {
          final double newCost = currentCost + costAnnotMatch;
          final int ni = i + consumedTokens;
          final int nj = j + hintLength;
          if (ni <= nTokens && newCost < costs[ni][nj]) {
            costs[ni][nj] = newCost;
            actions[ni][nj] = ActionType.matchAnnot.index;
            parents[ni][nj] = i * columns + j;
            rubies[ni][nj] = hintHira;
            _updateActiveBounds(activeMin, activeMax, ni, nj);
          }
        }
      }

      if (props.dictInfo case (List<String> readings, int consumedTokens)) {
        for (final String reading in readings) {
          final int readingLength = reading.length;
          if (j + readingLength > mHira || hiraStream[j] != reading[0]) {
            continue;
          }
          if (!hiraStream.startsWith(reading, j)) {
            continue;
          }

          final double newCost = currentCost + costDictReward;
          int absorbedExtra = 0;
          final int nextTokenIndex = i + consumedTokens;
          if (nextTokenIndex < nTokens) {
            final RubyToken nextToken = tokens[nextTokenIndex];
            if (nextToken.charType == CharType.hiragana ||
                nextToken.charType == CharType.katakana) {
              final String hiraNext = katakanaToHiragana(nextToken.text);
              if (reading.endsWith(hiraNext)) {
                absorbedExtra = 1;
              }
            }
          }

          final int finalConsumed = consumedTokens + absorbedExtra;
          final int ni = i + finalConsumed;
          final int nj = j + readingLength;
          if (ni <= nTokens && newCost < costs[ni][nj]) {
            costs[ni][nj] = newCost;
            actions[ni][nj] = ActionType.matchDict.index;
            parents[ni][nj] = i * columns + j;
            rubies[ni][nj] = reading;
            _updateActiveBounds(activeMin, activeMax, ni, nj);
          }
        }
      }

      if (props.baseHira != null) {
        final List<(String, double)>? fuzzyVariants = props.fuzzyVariants;
        if (fuzzyVariants != null) {
          for (final (String varText, double ruleCost) in fuzzyVariants) {
            final int varLength = varText.length;
            if (varLength == 0) {
              final double newCost = currentCost + ruleCost;
              final int ni = i + 1;
              final int nj = j;
              if (newCost < costs[ni][nj]) {
                costs[ni][nj] = newCost;
                actions[ni][nj] = ActionType.matchFuzzy.index;
                parents[ni][nj] = i * columns + j;
                rubies[ni][nj] = '';
                _updateActiveBounds(activeMin, activeMax, ni, nj);
              }
            } else if (j + varLength <= mHira) {
              bool isMatch = false;
              if (hiraStream.startsWith(varText, j)) {
                isMatch = true;
              } else if (currToken.charType == CharType.other) {
                final String targetSub = hiraStream.substring(j, j + varLength);
                isMatch = targetSub == varText.toLowerCase();
              }

              if (isMatch) {
                final double newCost = currentCost + costExactMatch + ruleCost;
                final ActionType actionType = ruleCost > 0
                    ? ActionType.matchFuzzy
                    : ActionType.matchExact;
                final int ni = i + 1;
                final int nj = j + varLength;
                if (newCost < costs[ni][nj]) {
                  costs[ni][nj] = newCost;
                  actions[ni][nj] = actionType.index;
                  parents[ni][nj] = i * columns + j;
                  rubies[ni][nj] = hiraStream.substring(j, j + varLength);
                  _updateActiveBounds(activeMin, activeMax, ni, nj);
                }
              }
            }
          }
        }

        if (props.isKana && props.baseHira!.length > 1) {
          final int lowerBound = (props.baseHira!.length - 1) > 1
              ? props.baseHira!.length - 1
              : 1;
          final int upperBound0 = props.baseHira!.length + 2;
          final int upperBound1 = mHira - j;
          final int upperBound = upperBound0 < upperBound1
              ? upperBound0
              : upperBound1;

          for (int length = lowerBound; length <= upperBound; length += 1) {
            final String targetSub = hiraStream.substring(j, j + length);
            final int dist = _levenshtein(props.baseHira!, targetSub);
            if (dist <= 0 || dist > props.baseHira!.length / 2.5 + 1) {
              continue;
            }

            final double newCost = currentCost + dist * costEditDist;
            final int ni = i + 1;
            final int nj = j + length;
            if (newCost < costs[ni][nj]) {
              costs[ni][nj] = newCost;
              actions[ni][nj] = ActionType.matchFuzzy.index;
              parents[ni][nj] = i * columns + j;
              rubies[ni][nj] = targetSub;
              _updateActiveBounds(activeMin, activeMax, ni, nj);
            }
          }
        }
      }

      int maxK = 12;
      final int remain = mHira - j;
      if (remain < maxK) {
        maxK = remain;
      }
      if (maxK > 0 && currToken.text.isNotEmpty) {
        for (int k = 1; k <= maxK; k += 1) {
          final String consumedHira = hiraStream.substring(j, j + k);
          final double costValue = _calculateGenericCost(
            currToken.text,
            consumedHira,
            currToken.charType,
          );
          if (costValue >= costImpossible) {
            continue;
          }

          final double newCost = currentCost + costValue;
          final int ni = i + 1;
          final int nj = j + k;
          if (newCost < costs[ni][nj]) {
            costs[ni][nj] = newCost;
            actions[ni][nj] = ActionType.consumeGeneric.index;
            parents[ni][nj] = i * columns + j;
            rubies[ni][nj] = consumedHira;
            _updateActiveBounds(activeMin, activeMax, ni, nj);
          }
        }
      }

      j += 1;
    }
  }

  final double finalCost = costs[nTokens][mHira];
  int currI = nTokens;
  int currJ = mHira;

  if (finalCost >= costImpossible) {
    (int, int) bestCoord = (0, 0);
    double minHeuristic = double.infinity;
    for (int r = 0; r <= nTokens; r += 1) {
      final int startC = activeMin[r];
      final int endC = activeMax[r];
      if (startC > endC) {
        continue;
      }
      for (int c = startC; c <= endC; c += 1) {
        final double cst = costs[r][c];
        if (cst >= costImpossible) {
          continue;
        }
        final double penalty = (nTokens - r) * 5000.0 + (mHira - c) * 5000.0;
        final double totalScore = cst + penalty;
        if (totalScore < minHeuristic) {
          minHeuristic = totalScore;
          bestCoord = (r, c);
        }
      }
    }
    currI = bestCoord.$1;
    currJ = bestCoord.$2;
  }

  final List<_PathStep> reconstructedPath = <_PathStep>[];
  int skippedMeaningfulTokens = 0;
  int totalMeaningfulTokens = 0;

  while (currI > 0 || currJ > 0) {
    final int parent = parents[currI][currJ];
    if (parent == -1) {
      break;
    }
    final int prevI = parent ~/ columns;
    final int prevJ = parent % columns;

    final ActionType action = ActionType.values[actions[currI][currJ]];
    final String? ruby = rubies[currI][currJ];

    if (prevI >= 0 && prevI < nTokens && action != ActionType.skipHira) {
      final RubyToken token = tokens[prevI];
      if (token.charType == CharType.hiragana ||
          token.charType == CharType.katakana ||
          token.charType == CharType.other ||
          token.charType == CharType.kanji) {
        final OtherType? otherType = token.charType == CharType.other
            ? _classifyOtherToken(token.text)
            : null;
        final bool isSymbolLike =
            token.charType == CharType.symbol || otherType == OtherType.symbol;
        if (!isSymbolLike) {
          totalMeaningfulTokens += 1;
          if (action == ActionType.skipToken) {
            skippedMeaningfulTokens += 1;
          }
        }
      }
    }

    reconstructedPath.add(
      _PathStep(
        iEnd: currI,
        jEnd: currJ,
        action: action,
        iStart: prevI,
        ruby: ruby,
      ),
    );
    currI = prevI;
    currJ = prevJ;
  }
  if (totalMeaningfulTokens > 0 &&
      (skippedMeaningfulTokens / totalMeaningfulTokens) > 0.6) {
    return <RubySpan>[];
  }

  final List<RubySpan> finalResults = <RubySpan>[];
  final List<RubySpan> genericBuffer = <RubySpan>[];

  void flushGenericBuffer() {
    if (genericBuffer.isEmpty) {
      return;
    }

    final StringBuffer ruby = StringBuffer();
    for (final RubySpan span in genericBuffer) {
      ruby.write(span.ruby);
    }

    finalResults.add(
      RubySpan(
        start: genericBuffer.first.start,
        end: genericBuffer.last.end,
        ruby: ruby.toString(),
      ),
    );
    genericBuffer.clear();
  }

  for (final _PathStep step in reconstructedPath.reversed) {
    if (step.iStart < 0 ||
        step.iEnd > tokens.length ||
        step.iStart >= step.iEnd) {
      continue;
    }
    final String safeRuby = step.ruby ?? '';

    if (step.action == ActionType.consumeGeneric) {
      final RubyToken token = tokens[step.iStart];
      if (token.charType == CharType.kanji ||
          token.charType == CharType.other) {
        genericBuffer.add(
          RubySpan(start: token.start, end: token.end, ruby: safeRuby),
        );
      } else {
        flushGenericBuffer();
      }
      continue;
    }

    if (step.action == ActionType.matchExact ||
        step.action == ActionType.matchFuzzy ||
        step.action == ActionType.matchDict ||
        step.action == ActionType.matchAnnot) {
      flushGenericBuffer();
    }

    if (step.action == ActionType.matchDict) {
      finalResults.addAll(
        _alignAndGenerateRubyForWord(tokens, step.iStart, step.iEnd, safeRuby),
      );
    } else if (step.action == ActionType.matchAnnot) {
      final RubyToken token = tokens[step.iStart];
      finalResults.add(
        RubySpan(start: token.start, end: token.end, ruby: safeRuby),
      );
    } else if (step.action == ActionType.matchExact ||
        step.action == ActionType.matchFuzzy) {
      final RubyToken token = tokens[step.iStart];
      final bool isSelfMatch =
          token.text == safeRuby ||
          token.text.toLowerCase() == safeRuby.toLowerCase();
      if (!isSelfMatch &&
          (token.charType == CharType.kanji ||
              token.charType == CharType.other)) {
        finalResults.add(
          RubySpan(start: token.start, end: token.end, ruby: safeRuby),
        );
      }
    }
  }

  flushGenericBuffer();
  return finalResults;
}

List<RubySpan> _alignAndGenerateRubyForWord(
  List<RubyToken> tokens,
  int start,
  int end,
  String reading,
) {
  final List<RubySpan> results = <RubySpan>[];

  if (end - start == 1) {
    final RubyToken token = tokens[start];
    if ((token.charType == CharType.kanji ||
            token.charType == CharType.other) &&
        reading.isNotEmpty) {
      results.add(RubySpan(start: token.start, end: token.end, ruby: reading));
    }
    return results;
  }

  final String wordTextHira = katakanaToHiragana(
    tokens.getRange(start, end).map((RubyToken token) => token.text).join(),
  );
  if (wordTextHira == reading) {
    return <RubySpan>[];
  }

  int readingCursor = 0;
  final List<RubyToken> currentKanjiBlock = <RubyToken>[];
  int tokenIdx = start;

  while (tokenIdx < end) {
    final RubyToken token = tokens[tokenIdx];
    if (token.charType == CharType.kanji || token.charType == CharType.other) {
      currentKanjiBlock.add(token);
    } else if (token.charType == CharType.hiragana ||
        token.charType == CharType.katakana ||
        token.charType == CharType.symbol) {
      if (token.text.trim().isEmpty) {
        tokenIdx += 1;
        continue;
      }

      final String hiraAnchor = katakanaToHiragana(token.text);
      if (currentKanjiBlock.isNotEmpty) {
        final int anchorPos = reading.indexOf(hiraAnchor, readingCursor);
        if (anchorPos != -1) {
          final String rubyText = reading.substring(readingCursor, anchorPos);
          if (rubyText.isNotEmpty) {
            results.add(
              RubySpan(
                start: currentKanjiBlock.first.start,
                end: currentKanjiBlock.last.end,
                ruby: rubyText,
              ),
            );
          }
          readingCursor = anchorPos;
        } else {
          final String remaining = reading.substring(readingCursor);
          if (remaining.isNotEmpty) {
            results.add(
              RubySpan(
                start: currentKanjiBlock.first.start,
                end: currentKanjiBlock.last.end,
                ruby: remaining,
              ),
            );
          }
          return results;
        }
      }

      if (reading.startsWith(hiraAnchor, readingCursor)) {
        readingCursor += hiraAnchor.length;
      }
      currentKanjiBlock.clear();
    }
    tokenIdx += 1;
  }

  if (currentKanjiBlock.isNotEmpty) {
    final String rubyText = reading.substring(readingCursor);
    if (rubyText.isNotEmpty) {
      results.add(
        RubySpan(
          start: currentKanjiBlock.first.start,
          end: currentKanjiBlock.last.end,
          ruby: rubyText,
        ),
      );
    }
  }

  return results;
}

RegExp _getSymbolSplitPattern(String text) {
  final RegExp? cached = _symbolSplitPatternCache[text];
  if (cached != null) {
    return cached;
  }

  final String pattern = text.runes
      .map((int rune) => RegExp.escape(String.fromCharCode(rune)))
      .join(r'\s*');
  final RegExp regex = RegExp(pattern, caseSensitive: false);
  _cachePutWithLimit(_symbolSplitPatternCache, text, regex, 128);
  return regex;
}

RegExp _getLatinSplitPattern(String text) {
  final RegExp? cached = _latinSplitPatternCache[text];
  if (cached != null) {
    return cached;
  }

  final String compact = text.replaceAll(' ', '');
  final String pattern = compact.runes
      .map((int rune) => RegExp.escape(String.fromCharCode(rune)))
      .join(r'\s*');
  final RegExp regex = RegExp(pattern, caseSensitive: false);
  _cachePutWithLimit(_latinSplitPatternCache, text, regex, 128);
  return regex;
}

List<RubySpan> processLine(String romaText, List<RubyToken> tokens) {
  String processedRoma = romaText;
  final Set<int> dividingTokenIndices = <int>{};

  // 先用原文中的符号、较长拉丁词把罗马音流切块，再分别做 DP。
  // 这样可以把常见的括号、英文歌名片段当作锚点，减少跨片段误配；
  // 如果切块数量对不上，会回退到整行 DP，优先保证结果完整而不是硬套锚点。
  for (final RubyToken token in tokens) {
    if (token.charType == CharType.symbol && token.text.trim().isNotEmpty) {
      final RegExp regex = _getSymbolSplitPattern(token.text);
      final (String replaced, bool matched) = _replaceFirst(
        regex,
        processedRoma,
        _rubyPlaceholder,
      );
      if (matched) {
        processedRoma = replaced;
        dividingTokenIndices.add(token.start);
      }
    } else if (token.charType == CharType.other &&
        token.text.trim().isNotEmpty) {
      final OtherType otherType = _classifyOtherToken(token.text);
      if (otherType == OtherType.latin && token.text.length > 1) {
        final RegExp regex = _getLatinSplitPattern(token.text);
        final (String replaced, bool matched) = _replaceFirst(
          regex,
          processedRoma,
          _rubyPlaceholder,
        );
        if (matched) {
          processedRoma = replaced;
          dividingTokenIndices.add(token.start);
        }
      }
    }
  }

  final String hiraFromRomaRaw = romaToHiragana(processedRoma);
  final List<String> hiraChunks = hiraFromRomaRaw
      .split(_rubyPlaceholder)
      .where((String chunk) => chunk.trim().isNotEmpty)
      .toList(growable: false);

  final List<List<RubyToken>> tokenChunks = <List<RubyToken>>[];
  List<RubyToken> currentChunk = <RubyToken>[];
  for (final RubyToken token in tokens) {
    if (dividingTokenIndices.contains(token.start)) {
      if (currentChunk.isNotEmpty) {
        tokenChunks.add(currentChunk);
      }
      currentChunk = <RubyToken>[];
    } else {
      currentChunk.add(token);
    }
  }
  if (currentChunk.isNotEmpty) {
    tokenChunks.add(currentChunk);
  }

  if (hiraChunks.length != tokenChunks.length) {
    final String fullHira = _keepHiragana(romaToHiragana(romaText));
    return _dpAlign(tokens, fullHira);
  }

  final List<RubySpan> allResults = <RubySpan>[];
  for (int i = 0; i < tokenChunks.length; i += 1) {
    final List<RubyToken> tokenChunk = tokenChunks[i];
    final String hiraChunkRaw = hiraChunks[i];
    final String hiraForMatch = _keepHiragana(hiraChunkRaw);

    if (tokenChunk.isEmpty) {
      continue;
    }

    if (hiraForMatch.isEmpty &&
        tokenChunk.every(
          (RubyToken token) =>
              (token.charType == CharType.symbol ||
                  token.charType == CharType.other) &&
              _classifyOtherToken(token.text) != OtherType.number,
        )) {
      continue;
    }

    allResults.addAll(_dpAlign(tokenChunk, hiraForMatch));
  }

  return allResults;
}

String _keepHiragana(String text) {
  final StringBuffer out = StringBuffer();
  for (final int rune in text.runes) {
    if (rune >= 0x3040 && rune <= 0x309F) {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

void _updateActiveBounds(
  Int32List activeMin,
  Int32List activeMax,
  int row,
  int col,
) {
  if (activeMin[row] > col) {
    activeMin[row] = col;
  }
  if (activeMax[row] < col) {
    activeMax[row] = col;
  }
}

(String, bool) _replaceFirst(RegExp regex, String input, String replacement) {
  final RegExpMatch? match = regex.firstMatch(input);
  if (match == null) {
    return (input, false);
  }
  final String replaced =
      input.substring(0, match.start) +
      replacement +
      input.substring(match.end);
  return (replaced, true);
}

int _min3(int a, int b, int c) {
  if (a <= b && a <= c) {
    return a;
  }
  if (b <= a && b <= c) {
    return b;
  }
  return c;
}

void _cachePutWithLimit<K, V>(
  LinkedHashMap<K, V> cache,
  K key,
  V value,
  int maxSize,
) {
  // LinkedHashMap 保留插入顺序，因此 keys.first 就是当前最早写入的缓存项。
  // 这里不做 LRU 提升，目的是让成本保持 O(1) 级别且行为可预测。
  if (cache.length >= maxSize && !cache.containsKey(key)) {
    cache.remove(cache.keys.first);
  }
  cache[key] = value;
}
