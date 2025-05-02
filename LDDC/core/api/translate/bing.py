# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only


import httpx

from LDDC.common.data.cache import cache
from LDDC.common.data.config import cfg
from LDDC.common.models import Lyrics, LyricsData, TranslateTargetLanguage
from LDDC.common.version import __version__

from .models import BaseTranslator

lang_map = {
    TranslateTargetLanguage.SIMPLIFIED_CHINESE: "zh-Hans",
    TranslateTargetLanguage.TRADITIONAL_CHINESE: "zh-Hant",
    TranslateTargetLanguage.ENGLISH: "en",
    TranslateTargetLanguage.JAPANESE: "ja",
    TranslateTargetLanguage.KOREAN: "ko",
    TranslateTargetLanguage.SPANISH: "es",
    TranslateTargetLanguage.FRENCH: "fr",
    TranslateTargetLanguage.GERMAN: "de",
    TranslateTargetLanguage.PORTUGUESE: "pt",
    TranslateTargetLanguage.RUSSIAN: "ru",
}


class BingTranslator(BaseTranslator):
    def __init__(self) -> None:
        self.client = httpx.Client(
            http2=True,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0",
                "Connection": "keep-alive",
                "Accept": "*/*",
                "Accept-Encoding": "gzip, deflate, br, zstd",
                "Content-Type": "application/json",
                "sec-ch-ua-platform": '"Windows"',
                "sec-ch-ua": '"Microsoft Edge";v="135", "Not-A.Brand";v="8", "Chromium";v="135"',
                "sec-ch-ua-mobile": "?0",
                "sec-mesh-client-edge-version": "135.0.3179.98",
                "sec-mesh-client-edge-channel": "stable",
                "sec-mesh-client-os": "Windows",
                "sec-mesh-client-os-version": "10.0.26100",
                "sec-mesh-client-arch": "x86_64",
                "sec-mesh-client-webview": "0",
            },
        )

    def translate_texts(self, texts: list[str], target_lang: str, source_lang: str = "auto") -> list[str]:
        cache_key = (__version__, "bing", source_lang, target_lang, tuple(texts).__hash__())
        if cache_key in cache:
            return cache[cache_key]  # type: ignore[reportReturnType]

        params = {"to": target_lang}
        if source_lang != "auto":
            params["from"] = source_lang

        resp = self.client.post(
            "https://edge.microsoft.com/translate/translatetext",
            params=params,
            json=texts,
        )
        resp.raise_for_status()

        result = [item["translations"][0]["text"] for item in resp.json()]
        cache.set(cache_key, result, expire=14400)
        return result

    def translate_lyrics(self, lyrics: Lyrics) -> LyricsData:
        return self.texts2data(self.translate_texts(self.get_orig_lines(lyrics), lang_map[TranslateTargetLanguage[cfg["translate_target_lang"]]]), lyrics)
