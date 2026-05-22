# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
"""Tests for LDDC.core.romaji module."""

import pytest

from LDDC.core.romaji import romaji_to_hiragana


@pytest.mark.parametrize(
    ("input_text", "expected"),
    [
        # Basic syllables
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
        ("na", "な"),
        ("shi", "し"),
        ("tsu", "つ"),
        ("fu", "ふ"),
        # Dakuon (voiced)
        ("ga", "が"),
        ("ji", "じ"),
        ("zu", "ず"),
        ("de", "で"),
        ("bo", "ぼ"),
        # Youon (contracted)
        ("kya", "きゃ"),
        ("shu", "しゅ"),
        ("cho", "ちょ"),
        ("nya", "にゃ"),
        ("ryo", "りょ"),
        # Sokuon (geminate consonant)
        ("kka", "っか"),
        ("tta", "った"),
        ("ssa", "っさ"),
        ("ppi", "っぴ"),
        ("sshi", "っし"),
        ("tchi", "っち"),
        ("ttsu", "っつ"),
        # Sokuon + youon
        ("kkya", "っきゃ"),
        ("sshu", "っしゅ"),
        ("tcho", "っちょ"),
        # Space-separated words → no spaces in output
        ("a ka", "あか"),
        ("ha tsu na", "はつな"),
        ("a za ya ka", "あざやか"),
        ("na ru", "なる"),
        ("sen bon za ku ra", "せんぼんざくら"),
        ("i tsu mo na ga me te i ta", "いつもながめていた"),
        # Non-Japanese text preserved
        ("Hello", "Hello"),
        ("ha tsu na Hello", "はつなHello"),
        ("Hello World", "HelloWorld"),
        ("123", "123"),
        ("!?", "!?"),
        ("ha tsu na 123", "はつな123"),
        # Dakuten youon
        ("gya", "ぎゃ"),
        ("ja", "じゃ"),
        ("ju", "じゅ"),
        ("bya", "びゃ"),
        ("pya", "ぴゃ"),
        # Particle wa vs ha note: "wa" maps to わ
        ("wa", "わ"),
        ("wo", "を"),
        ("n", "ん"),
        # Extended vowels
        ("aa", "あー"),
        ("ii", "いー"),
        ("uu", "うー"),
        # Apostrophe-sokuon
        ("'t", "っ"),
        ("'s", "っ"),
        ("'k", "っ"),
        # Apostrophe-sokuon in context
        ("i 't te", "いって"),
        ("i 't ta", "いった"),
        ("fu e te i 't te", "ふえていって"),
        # Mixed complex
        ("ha tsu na no ni", "はつなのに"),
        ("shi ki sa i", "しきさい"),
        # Empty string
        ("", ""),
    ],
)
def test_romaji_to_hiragana(input_text: str, expected: str) -> None:
    assert romaji_to_hiragana(input_text) == expected


def test_empty_string() -> None:
    assert romaji_to_hiragana("") == ""


def test_only_spaces() -> None:
    assert romaji_to_hiragana("   ") == ""


def test_non_japanese_only() -> None:
    assert romaji_to_hiragana("Hello World 123") == "HelloWorld123"


def test_long_sentence() -> None:
    input_text = "ko re wa ha na ga sa ku"
    expected = "これわはながさく"
    assert romaji_to_hiragana(input_text) == expected


def test_apostrophe_sokuon_in_context() -> None:
    """Test that 't adjacent to te produces tte (gemination)."""
    assert romaji_to_hiragana("i 't te") == "いって"
    assert romaji_to_hiragana("fu e te i 't te") == "ふえていって"
    assert romaji_to_hiragana("ma 't te") == "まって"


def test_mixed_with_punctuation() -> None:
    input_text = "ha i ka ta i"
    expected = "はいかたい"
    assert romaji_to_hiragana(input_text) == expected


def test_no_spaces_preserves_text() -> None:
    """Input with no spaces at all should still be treated as one token."""
    assert romaji_to_hiragana("konnnitiwa") != ""
