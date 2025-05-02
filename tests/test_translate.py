# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
"""Tests for LDDC.core.api.translate module."""

import pytest

from LDDC.common.models import Lyrics, LyricsData, LyricsLine, LyricsWord
from LDDC.core.api.translate.bing import BingTranslator
from LDDC.core.api.translate.google import GoogleTranslator
from LDDC.core.api.translate.models import BaseTranslator


@pytest.fixture
def mock_lyrics() -> Lyrics:
    """Fixture for test lyrics data."""
    lyrics = Lyrics(None)  # type: ignore[arg-type]
    lyrics["orig"] = LyricsData(
        [LyricsLine(None, None, [LyricsWord(None, None, "Hello world")]), LyricsLine(None, None, [LyricsWord(None, None, "Test line")])],
    )
    return lyrics


@pytest.mark.parametrize("translator_class", [BingTranslator, GoogleTranslator])
class TestTranslators:
    """Test cases for translator classes."""

    def test_translate_lyrics(self, translator_class: type[BaseTranslator], mock_lyrics: Lyrics, monkeypatch: pytest.MonkeyPatch) -> None:
        """Test translate_lyrics method."""
        translator = translator_class()

        # Setup mocks
        orig_calls: list[Lyrics] = []
        translate_calls: list[tuple[list[str], str]] = []
        texts2data_calls: list[tuple[list[str], Lyrics]] = []

        def mock_get_orig(lyrics: Lyrics) -> list[str]:
            orig_calls.append(lyrics)
            return ["Hello world", "Test line"]

        def mock_translate(texts: list[str], target_lang: str) -> list[str]:
            translate_calls.append((texts, target_lang))
            return ["你好世界", "测试行"]

        def mock_texts2data(texts: list[str], lyrics: Lyrics) -> LyricsData:
            texts2data_calls.append((texts, lyrics))
            return LyricsData([LyricsLine(None, None, [LyricsWord(None, None, "你好世界")]), LyricsLine(None, None, [LyricsWord(None, None, "测试行")])])

        monkeypatch.setattr(translator, "get_orig_lines", mock_get_orig)
        monkeypatch.setattr(translator, "translate_texts", mock_translate)
        monkeypatch.setattr(translator, "texts2data", mock_texts2data)

        result = translator.translate_lyrics(mock_lyrics)

        # Verify calls
        assert orig_calls[0] == mock_lyrics
        if translator_class == BingTranslator:
            assert translate_calls[0] == (["Hello world", "Test line"], "zh-Hans")
        else:
            assert translate_calls[0] == (["Hello world", "Test line"], "zh-CN")
        assert texts2data_calls[0] == (["你好世界", "测试行"], mock_lyrics)
        assert len(result) == 2
        assert result[0].words[0].text == "你好世界"
        assert result[1].words[0].text == "测试行"


@pytest.mark.parametrize("translator_class", [BingTranslator, GoogleTranslator])
def test_real_translation(translator_class: type[BaseTranslator], mock_lyrics: Lyrics) -> None:
    """Test real API translation (requires internet)."""
    translator = translator_class()
    result = translator.translate_lyrics(mock_lyrics)

    assert len(result) == 2
    # More lenient assertion for real API results
    assert any(word.text for line in result for word in line.words)
