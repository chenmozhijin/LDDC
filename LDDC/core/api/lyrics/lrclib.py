# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import json

import httpx

from LDDC.common.exceptions import APIParamsError, APIRequestError
from LDDC.common.models import APIResultList, Artist, Language, LyricInfo, Lyrics, SearchInfo, SearchType, SongInfo, SongListInfo, Source
from LDDC.common.version import __version__
from LDDC.core.parser.lrc import lrc2data
from LDDC.core.parser.utils import judge_lyrics_type, plaintext2data

from .models import CloudAPI


class LrclibAPI(CloudAPI):
    source = Source.LRCLIB
    supported_search_types = (SearchType.SONG,)

    def __init__(self) -> None:
        self.client = httpx.Client(
            headers={
                "User-Agent": f"LDDC/{__version__}",
                "Accept": "application/json",
            },
            timeout=30,
        )

    def _make_request(self, endpoint: str, params: dict | None = None) -> dict:
        """发送API请求"""
        url = f"https://lrclib.net/api{endpoint}"
        response = self.client.get(url, params=params)
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            msg = f"lrclib API请求失败: {response.status_code}"
            raise APIRequestError(msg) from e

        try:
            return response.json()
        except json.JSONDecodeError as e:
            msg = "lrclib API响应解析失败"
            raise APIRequestError(msg) from e

    def _parse_song_info(self, data: dict) -> SongInfo:
        """解析歌曲信息"""
        return SongInfo(
            source=self.source,
            title=data["trackName"],
            artist=Artist(data["artistName"]),
            album=data["albumName"],
            duration=int(data["duration"] * 1000),  # API返回秒数，转换为毫秒
            id=str(data["id"]),
            language=Language.INSTRUMENTAL if data["instrumental"] else Language.OTHER,
        )

    def get_lyrics(self, info: SongInfo) -> Lyrics:
        """获取歌词"""
        if not info.title or not info.artist or not info.album or not info.duration:
            msg = "缺少必要参数"
            raise APIParamsError(msg)

        params = {"track_name": info.title, "artist_name": info.artist.str(), "album_name": info.album, "duration": info.duration / 1000}
        data = self._make_request("/get", params)

        if "error" in data:
            msg = f"lrclib API错误: {data['error']}"
            raise APIRequestError(msg)

        lyrics = Lyrics(info)
        lyrics.tags = {
            "ti": data["trackName"],
            "ar": data["artistName"],
            "al": data["albumName"],
        }

        # 处理同步歌词
        if data.get("syncedLyrics"):
            tags, lyrics["orig"] = lrc2data(data["syncedLyrics"])
            lyrics.types["orig"] = judge_lyrics_type(lyrics["orig"])
            lyrics.tags.update(tags)

        # 处理纯文本歌词
        elif data.get("plainLyrics"):
            lyrics["orig"] = plaintext2data(data["plainLyrics"])
            lyrics.types["orig"] = judge_lyrics_type(lyrics["orig"])

        return lyrics

    def search(self, keyword: str, search_type: SearchType, page: int = 1) -> APIResultList[SongInfo]:
        """搜索歌曲"""
        if search_type not in self.supported_search_types:
            msg = f"不支持的搜索类型: {search_type}"
            raise NotImplementedError(msg)

        params = {"q": keyword}
        response = self._make_request("/search", params)

        if "error" in response:
            msg = f"lrclib API错误: {response['error']}"
            raise APIRequestError(msg)

        items = [self._parse_song_info(item) for item in response]
        items = items[(page - 1) * 20 : page * 20]  # 分页处理

        return APIResultList(items, SearchInfo(source=self.source, keyword=keyword, search_type=search_type, page=page), (0, len(items) - 1, len(items)))

    def get_songlist(self, songlist_info: SongListInfo) -> APIResultList[SongInfo]:
        msg = "lrclib API不支持获取歌单"
        raise NotImplementedError(msg)

    def get_lyricslist(self, song_info: SongInfo) -> APIResultList[LyricInfo]:
        msg = "lrclib API不支持获取歌词列表"
        raise NotImplementedError(msg)
