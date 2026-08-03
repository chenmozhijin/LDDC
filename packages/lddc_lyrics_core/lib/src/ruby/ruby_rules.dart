import 'ruby_char_utils.dart';
import 'ruby_models.dart';

/// 假名到元音的映射表。
const Map<String, String> _vowelMap = <String, String>{
  'あ': 'あ',
  'か': 'あ',
  'さ': 'あ',
  'た': 'あ',
  'な': 'あ',
  'は': 'あ',
  'ま': 'あ',
  'や': 'あ',
  'ら': 'あ',
  'わ': 'あ',
  'が': 'あ',
  'ざ': 'あ',
  'だ': 'あ',
  'ば': 'あ',
  'ぱ': 'あ',
  'ゃ': 'あ',
  'ぁ': 'あ',
  'ゎ': 'あ',
  'い': 'い',
  'き': 'い',
  'し': 'い',
  'ち': 'い',
  'に': 'い',
  'ひ': 'い',
  'み': 'い',
  'り': 'い',
  'ぎ': 'い',
  'じ': 'い',
  'ぢ': 'い',
  'び': 'い',
  'ぴ': 'い',
  'ぃ': 'い',
  'う': 'う',
  'く': 'う',
  'す': 'う',
  'つ': 'う',
  'ぬ': 'う',
  'ふ': 'う',
  'む': 'う',
  'ゆ': 'う',
  'る': 'う',
  'ぐ': 'う',
  'ず': 'う',
  'づ': 'う',
  'ぶ': 'う',
  'ぷ': 'う',
  'ゅ': 'う',
  'ぅ': 'う',
  'え': 'え',
  'け': 'え',
  'せ': 'え',
  'て': 'え',
  'ね': 'え',
  'へ': 'え',
  'め': 'え',
  'れ': 'え',
  'げ': 'え',
  'ぜ': 'え',
  'で': 'え',
  'べ': 'え',
  'ぺ': 'え',
  'ぇ': 'え',
  'お': 'お',
  'こ': 'お',
  'そ': 'お',
  'と': 'お',
  'の': 'お',
  'ほ': 'お',
  'も': 'お',
  'よ': 'お',
  'ろ': 'お',
  'を': 'お',
  'ご': 'お',
  'ぞ': 'お',
  'ど': 'お',
  'ぼ': 'お',
  'ぽ': 'お',
  'ょ': 'お',
  'ぉ': 'お',
};

const int _costEquivalent = 0;
const int _costCommonVariant = 1;
const int _costRareVariant = 2;

String _handleLongVowel(
  String anchor,
  List<RubyToken> tokens,
  int currentTokenIndex,
) {
  if (!anchor.contains('ー')) {
    return anchor;
  }

  final StringBuffer out = StringBuffer();
  for (int i = 0; i < anchor.length; i += 1) {
    final String char = anchor[i];
    if (char != 'ー') {
      out.write(char);
      continue;
    }

    String prevChar = '';
    if (i > 0) {
      prevChar = anchor[i - 1];
    } else if (currentTokenIndex > 0) {
      final String prevTokenText = tokens[currentTokenIndex - 1].text;
      if (prevTokenText.isNotEmpty) {
        prevChar = katakanaToHiragana(
          String.fromCharCode(prevTokenText.runes.last),
        );
      }
    }

    final String? vowel = _vowelMap[prevChar];
    if (vowel != null) {
      out.write(vowel);
    } else {
      out.write('ー');
    }
  }

  return out.toString();
}

List<SubstitutionRule> _createSubstitutionRules({
  required List<(String, String)> pairs,
  required int costAToB,
  int? costBToA,
}) {
  final int reverseCost = costBToA ?? costAToB;
  final List<SubstitutionRule> rules = <SubstitutionRule>[];
  for (final (String from, String to) in pairs) {
    rules.add(SubstitutionRule(cost: costAToB, from: from, to: to));
    rules.add(SubstitutionRule(cost: reverseCost, from: to, to: from));
  }
  return rules;
}

List<(String, String)> _buildLongVowelPairs() {
  final String oDan = _vowelMap.entries
      .where((MapEntry<String, String> entry) => entry.value == 'お')
      .map((MapEntry<String, String> entry) => entry.key)
      .join();
  final String eDan = _vowelMap.entries
      .where((MapEntry<String, String> entry) => entry.value == 'え')
      .map((MapEntry<String, String> entry) => entry.key)
      .join();

  final List<(String, String)> pairs = <(String, String)>[];
  for (final int rune in oDan.runes) {
    final String char = String.fromCharCode(rune);
    pairs.add(('$charう', '$charお'));
  }
  for (final int rune in eDan.runes) {
    final String char = String.fromCharCode(rune);
    pairs.add(('$charい', '$charえ'));
  }
  return pairs;
}

/// 全量规则集合，对齐Python版 `ALL_RULES`。
final List<MatchRule> allRules = List<MatchRule>.unmodifiable(<MatchRule>[
  // 等价规则
  const SubstitutionRule(cost: _costEquivalent, from: 'は', to: 'わ'),
  const SubstitutionRule(cost: _costEquivalent, from: 'へ', to: 'え'),
  const SubstitutionRule(cost: _costEquivalent, from: 'を', to: 'お'),
  ..._createSubstitutionRules(
    pairs: <(String, String)>[('づ', 'ず'), ('ぢ', 'じ')],
    costAToB: _costEquivalent,
  ),
  ..._createSubstitutionRules(
    pairs: _buildLongVowelPairs(),
    costAToB: _costEquivalent,
  ),
  ..._createSubstitutionRules(
    pairs: <(String, String)>[('でぃ', 'ぢ'), ('でゅ', 'づ')],
    costAToB: _costEquivalent,
  ),
  const FunctionRule(cost: _costEquivalent, handler: _handleLongVowel),

  // 模糊规则
  const SubstitutionRule(cost: _costCommonVariant, from: 'っ', to: ''),
  const SubstitutionRule(cost: _costCommonVariant, from: 'っ', to: 'つ'),
  const SubstitutionRule(cost: _costCommonVariant, from: 'ん', to: ''),
  ..._createSubstitutionRules(
    pairs: <(String, String)>[
      ('ぁ', 'あ'),
      ('ぃ', 'い'),
      ('ぅ', 'う'),
      ('ぇ', 'え'),
      ('ぉ', 'お'),
      ('ゃ', 'や'),
      ('ゅ', 'ゆ'),
      ('ょ', 'よ'),
      ('っ', 'つ'),
      ('ゎ', 'わ'),
    ],
    costAToB: _costCommonVariant,
    costBToA: _costRareVariant,
  ),
  const SubstitutionRule(cost: _costRareVariant, from: 'ー', to: ''),
  ..._createSubstitutionRules(
    pairs: <(String, String)>[
      ('か', 'が'),
      ('き', 'ぎ'),
      ('く', 'ぐ'),
      ('け', 'げ'),
      ('こ', 'ご'),
      ('さ', 'ざ'),
      ('し', 'じ'),
      ('す', 'ず'),
      ('せ', 'ぜ'),
      ('そ', 'ぞ'),
      ('た', 'だ'),
      ('ち', 'ぢ'),
      ('つ', 'づ'),
      ('て', 'で'),
      ('と', 'ど'),
      ('は', 'ば'),
      ('ひ', 'び'),
      ('ふ', 'ぶ'),
      ('へ', 'べ'),
      ('ほ', 'ぼ'),
      ('は', 'ぱ'),
      ('ひ', 'ぴ'),
      ('ふ', 'ぷ'),
      ('へ', 'ぺ'),
      ('ほ', 'ぽ'),
      ('ば', 'ぱ'),
      ('び', 'ぴ'),
      ('ぶ', 'ぷ'),
      ('べ', 'ぺ'),
      ('ぼ', 'ぽ'),
    ],
    costAToB: _costRareVariant,
  ),
]);
