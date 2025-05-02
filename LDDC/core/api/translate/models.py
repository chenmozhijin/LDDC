# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from abc import ABC, abstractmethod

from LDDC.common.models import Lyrics, LyricsData, LyricsLine, LyricsWord


class BaseTranslator(ABC):
    @abstractmethod
    def translate_lyrics(self, lyrics: Lyrics) -> LyricsData: ...

    def is_available(self) -> bool:
        return True

    def get_orig_lines(self, lyrics: Lyrics) -> list[str]:
        return ["".join(word.text for word in line.words) for line in lyrics["orig"]]

    def texts2data(self, texts: list[str], lyrics: Lyrics) -> LyricsData:
        orig_data = lyrics["orig"]
        if len(texts) != len(orig_data):
            msg = "The number of translated texts does not match the number of original lines."
            raise ValueError(msg)
        ts_data = LyricsData([])
        for orig_line, text in zip(orig_data, texts, strict=True):
            ts_data.append(
                LyricsLine(
                    start=orig_line.start,
                    end=orig_line.end,
                    words=[LyricsWord(start=orig_line.start, end=orig_line.end, text=text)],
                ),
            )
        return ts_data
