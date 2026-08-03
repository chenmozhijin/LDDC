/// 罗马音到平假名映射表（按Python版语义迁移）。
const Map<String, String> _romaHiraMap = <String, String>{
  // 3 字母
  'cha': 'ちゃ',
  'chu': 'ちゅ',
  'cho': 'ちょ',
  'sha': 'しゃ',
  'shu': 'しゅ',
  'sho': 'しょ',
  'hya': 'ひゃ',
  'hyu': 'ひゅ',
  'hyo': 'ひょ',
  'kya': 'きゃ',
  'kyu': 'きゅ',
  'kyo': 'きょ',
  'gya': 'ぎゃ',
  'gyu': 'ぎゅ',
  'gyo': 'ぎょ',
  'nya': 'にゃ',
  'nyu': 'にゅ',
  'nyo': 'にょ',
  'rya': 'りゃ',
  'ryu': 'りゅ',
  'ryo': 'りょ',
  'pya': 'ぴゃ',
  'pyu': 'ぴゅ',
  'pyo': 'ぴょ',
  'bya': 'びゃ',
  'byu': 'びゅ',
  'byo': 'びょ',
  'mya': 'みゃ',
  'myu': 'みゅ',
  'myo': 'みょ',
  'ja': 'じゃ',
  'ju': 'じゅ',
  'jo': 'じょ',
  'ssu': 'っす',
  'tsa': 'つぁ',
  'tsi': 'つぃ',
  'tse': 'つぇ',
  'tso': 'つぉ',
  'thi': 'てぃ',
  'dhi': 'でぃ',
  'she': 'しぇ',
  'che': 'ちぇ',

  // 2 字母
  'fa': 'ふぁ',
  'fi': 'ふぃ',
  'fe': 'ふぇ',
  'fo': 'ふぉ',
  'wi': 'うぃ',
  'we': 'うぇ',
  'va': 'ゔぁ',
  'vi': 'ゔぃ',
  've': 'ゔぇ',
  'vo': 'ゔぉ',
  'je': 'じぇ',
  'shi': 'し',
  'tsu': 'つ',
  'chi': 'ち',
  'za': 'ざ',
  'ze': 'ぜ',
  'zo': 'ぞ',
  'da': 'だ',
  'de': 'で',
  'do': 'ど',
  'ba': 'ば',
  'bi': 'び',
  'bu': 'ぶ',
  'be': 'べ',
  'bo': 'ぼ',
  'pa': 'ぱ',
  'pi': 'ぴ',
  'pu': 'ぷ',
  'pe': 'ぺ',
  'po': 'ぽ',
  'ga': 'が',
  'gi': 'ぎ',
  'gu': 'ぐ',
  'ge': 'げ',
  'go': 'ご',
  'ka': 'か',
  'ki': 'き',
  'ku': 'く',
  'ke': 'け',
  'ko': 'こ',
  'sa': 'さ',
  'su': 'す',
  'se': 'せ',
  'so': 'そ',
  'ta': 'た',
  'te': 'て',
  'to': 'と',
  'na': 'な',
  'ni': 'に',
  'nu': 'ぬ',
  'ne': 'ね',
  'no': 'の',
  'ha': 'は',
  'hi': 'ひ',
  'fu': 'ふ',
  'he': 'へ',
  'ho': 'ほ',
  'ma': 'ま',
  'mi': 'み',
  'mu': 'む',
  'me': 'め',
  'mo': 'も',
  'ya': 'や',
  'yu': 'ゆ',
  'yo': 'よ',
  'ra': 'ら',
  'ri': 'り',
  'ru': 'る',
  're': 'れ',
  'ro': 'ろ',
  'wa': 'わ',
  'wo': 'を',
  'ji': 'じ',
  'zu': 'ず',
  'di': 'ぢ',
  'du': 'づ',

  // 长音
  'aa': 'ああ',
  'ii': 'いい',
  'uu': 'うう',
  'ee': 'ええ',
  'oo': 'おお',
  'ou': 'おう',

  // 非标准兼容
  'si': 'し',
  'ti': 'ち',
  'tu': 'つ',
  'hu': 'ふ',
  'la': 'ら',
  'li': 'り',
  'lu': 'る',
  'le': 'れ',
  'lo': 'ろ',
  'xi': 'し',
  'qi': 'ち',
  'cu': 'つ',
  'jya': 'じゃ',
  'jyu': 'じゅ',
  'jyo': 'じょ',

  // 1 字母
  'a': 'あ',
  'i': 'い',
  'u': 'う',
  'e': 'え',
  'o': 'お',
  'n': 'ん',
};

const String _vowels = 'aiueo';
const String _consonants = 'bcdfghjklmnpqrstvwxyz';
final RegExp _longVowelPattern = RegExp(r'([a-z])-');
final RegExp _utaPattern = RegExp(r'\buta\b');

/// 预处理罗马音文本。
String _preprocessRomaji(String romaji) {
  String text = romaji.toLowerCase().trim();
  if (text.endsWith('\'')) {
    text = text.substring(0, text.length - 1).trim();
  }

  // 将 `ko-hi-` 这类长音符写法转换为重复元音。
  text = text.replaceAllMapped(_longVowelPattern, (Match match) {
    final String prev = match.group(1)!;
    if (_vowels.contains(prev)) {
      return '$prev$prev';
    }
    return match.group(0)!;
  });

  // 修正常见误拼。
  text = text.replaceAll(_utaPattern, 'futa');
  return text;
}

/// 罗马音转平假名，对齐Python版 `roma_to_hiragana`。
String romaToHiragana(String romaji) {
  final String normalized = _preprocessRomaji(romaji);
  final StringBuffer hiragana = StringBuffer();
  int i = 0;

  while (i < normalized.length) {
    final String current = normalized[i];

    // 0. 保留空白
    if (current.trim().isEmpty) {
      hiragana.write(current);
      i += 1;
      continue;
    }

    // 1. 优先匹配 3/2/1 长度音节。
    bool matched = false;
    for (int length = 3; length > 0; length -= 1) {
      if (i + length > normalized.length) {
        continue;
      }
      final String sub = normalized.substring(i, i + length);
      final String? hira = _romaHiraMap[sub];
      if (hira != null) {
        hiragana.write(hira);
        i += length;
        matched = true;
        break;
      }
    }
    if (matched) {
      continue;
    }

    // 2. 促音：重复辅音。
    if (i + 1 < normalized.length &&
        _consonants.contains(normalized[i]) &&
        normalized[i] == normalized[i + 1]) {
      hiragana.write('っ');
      i += 1;
      continue;
    }

    // 3. n/m -> ん
    final bool isN = normalized[i] == 'n';
    final bool isMAsN =
        normalized[i] == 'm' &&
        i + 1 < normalized.length &&
        !_vowels.contains(normalized[i + 1]) &&
        !'y\' '.contains(normalized[i + 1]);
    if (isN || isMAsN) {
      if (i + 1 < normalized.length &&
          '${_vowels}y\''.contains(normalized[i + 1])) {
        // 保持与Python版一致：让其进入后续分支处理。
      } else {
        hiragana.write('ん');
        i += 1;
        continue;
      }
    }

    // 4. 撇号处理。
    if (normalized[i] == '\'') {
      if (!(i > 0 && normalized[i - 1] == 'n')) {
        hiragana.write('っ');
      }
      i += 1;
      continue;
    }

    // 5. 未知字符按原样保留。
    hiragana.write(normalized[i]);
    i += 1;
  }

  return hiragana.toString();
}
