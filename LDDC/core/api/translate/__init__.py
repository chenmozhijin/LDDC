# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from threading import Lock
from typing import TYPE_CHECKING

from LDDC.common.data.config import cfg
from LDDC.common.models import Lyrics, LyricsData, TranslateSource

if TYPE_CHECKING:
    from .models import BaseTranslator


class TranslateAPI:
    def __init__(self) -> None:
        self.init_lock = Lock()
        self.inited = False

    def init(self) -> None:
        with self.init_lock:
            if self.inited:
                return

            from .bing import BingTranslator
            from .google import GoogleTranslator
            from .openai import OpenAITranslator

            self.apis: dict[TranslateSource, BaseTranslator] = {
                TranslateSource.BING: BingTranslator(),
                TranslateSource.GOOGLE: GoogleTranslator(),
                TranslateSource.OPENAI: OpenAITranslator(),
            }
            self.inited = True


    def translate_lyrics(self, lyrics: Lyrics) -> LyricsData:
        if not self.inited:
            self.init()
        return self.apis[TranslateSource[cfg["translate_source"]]].translate_lyrics(lyrics)


translate_api = TranslateAPI()


def translate_lyrics(lyrics: Lyrics) -> LyricsData:
    return translate_api.translate_lyrics(lyrics)
