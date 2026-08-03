import 'ruby_models.dart';

/// 按Python版规则判断单个字符类型。
CharType getCharType(String char) {
  final Iterator<int> iterator = char.runes.iterator;
  if (!iterator.moveNext()) {
    return CharType.other;
  }
  final int rune = iterator.current;
  if (iterator.moveNext()) {
    return CharType.other;
  }

  // 日文汉字范围。
  if (rune >= 0x4E00 && rune <= 0x9FFF) {
    return CharType.kanji;
  }

  // 迭代符号 々 常按汉字处理。
  if (char == '々') {
    return CharType.kanji;
  }

  // 常见中日文标点与英文标点。
  if ('「」『』【】、。，．・〜？！（）(),.?!\'"：:'.contains(char)) {
    return CharType.symbol;
  }

  // 平假名范围。
  if (rune >= 0x3040 && rune <= 0x309F) {
    return CharType.hiragana;
  }

  // 片假名范围。
  if (rune >= 0x30A0 && rune <= 0x30FF) {
    return CharType.katakana;
  }

  return CharType.other;
}

/// 将字符串中的片假名转换为平假名。
String katakanaToHiragana(String text) {
  if (text.isEmpty) {
    return text;
  }

  final StringBuffer buffer = StringBuffer();
  for (final int rune in text.runes) {
    if (rune == 0x30F5 || rune == 0x30F6) {
      // Python 词典把小写 ヵ/ヶ 都折叠为普通的“か”。这两个码点也位于
      // 通用片假名区间内，因此必须在范围转换前处理，避免得到 ゕ/ゖ。
      buffer.write('か');
      continue;
    }
    if (rune >= 0x30A1 && rune < 0x30F7) {
      buffer.writeCharCode(rune - 0x60);
      continue;
    }

    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}
