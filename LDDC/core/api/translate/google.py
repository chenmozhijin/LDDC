# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

import httpx

from LDDC.common.data.cache import cache
from LDDC.common.data.config import cfg
from LDDC.common.logger import logger
from LDDC.common.models import Lyrics, LyricsData, TranslateTargetLanguage
from LDDC.common.version import __version__

from .models import BaseTranslator

lang_map = {
    TranslateTargetLanguage.SIMPLIFIED_CHINESE: "zh-CN",
    TranslateTargetLanguage.TRADITIONAL_CHINESE: "zh-TW",
    TranslateTargetLanguage.ENGLISH: "en",
    TranslateTargetLanguage.JAPANESE: "ja",
    TranslateTargetLanguage.KOREAN: "ko",
    TranslateTargetLanguage.SPANISH: "es",
    TranslateTargetLanguage.FRENCH: "fr",
    TranslateTargetLanguage.GERMAN: "de",
    TranslateTargetLanguage.PORTUGUESE: "pt",
    TranslateTargetLanguage.RUSSIAN: "ru",
}


class GoogleTranslator(BaseTranslator):
    def __init__(self, client: httpx.Client | None = None) -> None:
        self.client = client or httpx.Client(
            http2=True,
            headers={
                "sec-ch-ua": '"Not.A/Brand";v="8", "Chromium";v="114", "Google Chrome";v="114"',
                "content-type": "application/json+protobuf",
                "sec-ch-ua-mobile": "?0",
                "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36",
                "sec-ch-ua-platform": '"Windows"',
                "accept": "*/*",
                "accept-encoding": "gzip, deflate, br",
                "accept-language": "en,zh-CN;q=0.9,zh;q=0.8,ja;q=0.7,en-US;q=0.6",
            },
        )
        self.auth_key = "AIzaSyATBXajvzQLTDHEQbcpq0Ihe0vWDHmO520"
        self._update_auth()

    def _update_auth(self) -> None:
        try:
            resp = self.client.get(
                "https://translate.googleapis.com/_/translate_http/_/js/k=translate_http.tr.zh_CN.xQDQL-zBfUc.O/am=ACA/d=1/exm=el_conf/ed=1/rs=AN8SPfq926FSxeFN_C5CEBNv9zTcTCAKGA/m=el_main",
            )
            if match := re.search(r'"X-goog-api-key"\s*:\s*"(\w{39})"', resp.text):  # "X-goog-api-key":"AIzaSyATBXajvzQLTDHEQbcpq0Ihe0vWDHmO520"
                self._AUTH_KEY = match.group(1)
        except Exception:
            logger.exception("Failed to update Google Translate API key")

    def translate_texts(self, texts: list[str], target_lang: str, source_lang: str = "auto") -> list[str]:
        cache_key = (__version__, "bing", source_lang, target_lang, tuple(texts).__hash__())
        if cache_key in cache:
            return cache[cache_key]  # type: ignore[reportReturnType]
        payload = [[texts, source_lang, target_lang], "te"]

        resp = self.client.post(
            "https://translate-pa.googleapis.com/v1/translateHtml",
            json=payload,
            headers={
                "sec-ch-ua": '"Not.A/Brand";v="8", "Chromium";v="114", "Google Chrome";v="114"',
                "content-type": "application/json+protobuf",
                "X-goog-api-key": self._AUTH_KEY,
                "sec-ch-ua-mobile": "?0",
                "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36",
                "sec-ch-ua-platform": '"Windows"',
                "accept": "*/*",
                "accept-encoding": "gzip, deflate, br",
                "accept-language": "en,zh-CN;q=0.9,zh;q=0.8,ja;q=0.7,en-US;q=0.6",
            },
        )
        resp.raise_for_status()

        result = list(resp.json()[0])
        cache.set(cache_key, result, expire=14400)
        return result

    def translate_lyrics(self, lyrics: Lyrics) -> LyricsData:
        return self.texts2data(self.translate_texts(self.get_orig_lines(lyrics), lang_map[TranslateTargetLanguage[cfg["translate_target_lang"]]]), lyrics)
