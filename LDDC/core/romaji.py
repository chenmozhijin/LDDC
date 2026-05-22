# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
"""Romaji to hiragana conversion module.

Port of the Rust romaji-to-hiragana mapping from UtaBuild.

Splits input by whitespace, maps each word to hiragana using the
longest-match-first strategy, and joins all results without spaces.
Unmappable tokens (non-Japanese text, numbers, punctuation) pass through
unchanged.
"""
def _build_romaji_map() -> dict[str, str]:
    pairs: list[tuple[str, str]] = [
        ("a", "あ"),
        ("i", "い"),
        ("u", "う"),
        ("e", "え"),
        ("o", "お"),
        ("ka", "か"),
        ("ki", "き"),
        ("ku", "く"),
        ("ke", "け"),
        ("ko", "こ"),
        ("sa", "さ"),
        ("shi", "し"),
        ("su", "す"),
        ("se", "せ"),
        ("so", "そ"),
        ("ta", "た"),
        ("chi", "ち"),
        ("tsu", "つ"),
        ("te", "て"),
        ("to", "と"),
        ("na", "な"),
        ("ni", "に"),
        ("nu", "ぬ"),
        ("ne", "ね"),
        ("no", "の"),
        ("ha", "は"),
        ("hi", "ひ"),
        ("fu", "ふ"),
        ("fa", "ふぁ"),
        ("fi", "ふぃ"),
        ("fe", "ふぇ"),
        ("fo", "ふぉ"),
        ("fya", "ふゃ"),
        ("fyu", "ふゅ"),
        ("fyo", "ふょ"),
        ("he", "へ"),
        ("ho", "ほ"),
        ("ma", "ま"),
        ("mi", "み"),
        ("mu", "む"),
        ("me", "め"),
        ("mo", "も"),
        ("ya", "や"),
        ("yu", "ゆ"),
        ("yo", "よ"),
        ("ra", "ら"),
        ("ri", "り"),
        ("ru", "る"),
        ("re", "れ"),
        ("ro", "ろ"),
        ("wa", "わ"),
        ("wo", "を"),
        ("n", "ん"),
        ("ga", "が"),
        ("gi", "ぎ"),
        ("gu", "ぐ"),
        ("ge", "げ"),
        ("go", "ご"),
        ("za", "ざ"),
        ("ji", "じ"),
        ("zu", "ず"),
        ("ze", "ぜ"),
        ("zo", "ぞ"),
        ("da", "だ"),
        ("di", "ぢ"),
        ("du", "づ"),
        ("de", "で"),
        ("do", "ど"),
        ("ba", "ば"),
        ("bi", "び"),
        ("bu", "ぶ"),
        ("be", "べ"),
        ("bo", "ぼ"),
        ("pa", "ぱ"),
        ("pi", "ぴ"),
        ("pu", "ぷ"),
        ("pe", "ぺ"),
        ("po", "ぽ"),
        ("kya", "きゃ"),
        ("kyu", "きゅ"),
        ("kyo", "きょ"),
        ("sha", "しゃ"),
        ("shu", "しゅ"),
        ("sho", "しょ"),
        ("cha", "ちゃ"),
        ("chu", "ちゅ"),
        ("cho", "ちょ"),
        ("nya", "にゃ"),
        ("nyu", "にゅ"),
        ("nyo", "にょ"),
        ("hya", "ひゃ"),
        ("hyu", "ひゅ"),
        ("hyo", "ひょ"),
        ("mya", "みゃ"),
        ("myu", "みゅ"),
        ("myo", "みょ"),
        ("rya", "りゃ"),
        ("ryu", "りゅ"),
        ("ryo", "りょ"),
        ("gya", "ぎゃ"),
        ("gyu", "ぎゅ"),
        ("gyo", "ぎょ"),
        ("ja", "じゃ"),
        ("ju", "じゅ"),
        ("jo", "じょ"),
        ("bya", "びゃ"),
        ("byu", "びゅ"),
        ("byo", "びょ"),
        ("pya", "ぴゃ"),
        ("pyu", "ぴゅ"),
        ("pyo", "ぴょ"),
        ("kka", "っか"),
        ("kki", "っき"),
        ("kku", "っく"),
        ("kke", "っけ"),
        ("kko", "っこ"),
        ("ssa", "っさ"),
        ("sshi", "っし"),
        ("ssu", "っす"),
        ("sse", "っせ"),
        ("sso", "っそ"),
        ("tta", "った"),
        ("tchi", "っち"),
        ("ttsu", "っつ"),
        ("tte", "って"),
        ("tto", "っと"),
        ("ppa", "っぱ"),
        ("ppi", "っぴ"),
        ("ppu", "っぷ"),
        ("ppe", "っぺ"),
        ("ppo", "っぽ"),
        ("dda", "っだ"),
        ("ddi", "っぢ"),
        ("ddu", "っづ"),
        ("dde", "っで"),
        ("ddo", "っど"),
        ("gga", "っが"),
        ("ggi", "っぎ"),
        ("ggu", "っぐ"),
        ("gge", "っげ"),
        ("ggo", "っご"),
        ("bba", "っば"),
        ("bbi", "っび"),
        ("bbu", "っぶ"),
        ("bbe", "っべ"),
        ("bbo", "っぼ"),
        ("ffa", "っふぁ"),
        ("ffi", "っふぃ"),
        ("ffe", "っふぇ"),
        ("ffo", "っふぉ"),
        ("ffya", "っふゃ"),
        ("ffyu", "っふゅ"),
        ("ffyo", "っふょ"),
        ("aa", "あー"),
        ("ii", "いー"),
        ("uu", "うー"),
        ("ee", "えー"),
        ("oo", "おー"),
        ("kkya", "っきゃ"),
        ("kkyu", "っきゅ"),
        ("kkyo", "っきょ"),
        ("ssha", "っしゃ"),
        ("sshu", "っしゅ"),
        ("ssho", "っしょ"),
        ("tcha", "っちゃ"),
        ("tchu", "っちゅ"),
        ("tcho", "っちょ"),
        ("ppya", "っぴゃ"),
        ("ppyu", "っぴゅ"),
        ("ppyo", "っぴょ"),
        ("bbya", "っびゃ"),
        ("bbyu", "っびゅ"),
        ("bbyo", "っびょ"),
        ("ggya", "っぎゃ"),
        ("ggyu", "っぎゅ"),
        ("ggyo", "っぎょ"),
        ("jja", "っじゃ"),
        ("jju", "っじゅ"),
        ("jjo", "っじょ"),
        # Apostrophe-sokuon: 't, 's, 'k, etc. mark gemination in some romaji notations
        ("'t", "っ"),
        ("'s", "っ"),
        ("'k", "っ"),
        ("'p", "っ"),
        ("'b", "っ"),
        ("'d", "っ"),
        ("'g", "っ"),
        ("'j", "っ"),
        ("'c", "っ"),
    ]
    return dict(pairs)


_ROMANJI_MAP: dict[str, str] = _build_romaji_map()

# Precompute length-based lookup keys for longest-match-first strategy
_MAX_KEY_LEN: int = max(len(k) for k in _ROMANJI_MAP)


def romaji_to_hiragana(text: str) -> str:
    """Convert space-separated romaji text to hiragana (no spaces).

    Each whitespace-delimited token is matched against the romaji mapping
    table. Unmappable tokens pass through unchanged. Results are joined
    without any separator.

    Args:
        text: Space-separated romaji string.

    Returns:
        Hiragana string without spaces.

    """
    if not text or not text.strip():
        return ""

    result_parts: list[str] = []

    for word in text.split():
        if not word:
            continue
        result_parts.append(_convert_word(word))

    return "".join(result_parts)


def _convert_word(word: str) -> str:
    """Convert a single romaji word token to hiragana.

    Returns the hiragana conversion if the entire word can be fully
    consumed by the romaji mapping.  If any character cannot be mapped,
    the original word is returned unchanged (e.g. "Hello" → "Hello").
    """
    i = 0
    result: list[str] = []
    while i < len(word):
        matched = False
        # Try longest match first (from max key length down to 1)
        for length in range(min(_MAX_KEY_LEN, len(word) - i), 0, -1):
            chunk = word[i:i + length]
            if hiragana := _ROMANJI_MAP.get(chunk):
                result.append(hiragana)
                i += length
                matched = True
                break
        if not matched:
            # This word contains an unmappable character — pass through
            # the whole token unchanged.
            return word

    return "".join(result)
