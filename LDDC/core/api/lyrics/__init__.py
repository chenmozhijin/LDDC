# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
"""LDDC的歌词提供api

模块中的函数都是被缓存的,而lyrics_api中的函数则不是
"""

from collections.abc import Callable
from dataclasses import replace
from pathlib import Path
from threading import Lock
from typing import TYPE_CHECKING, Literal, NoReturn, overload

from LDDC.common.data.cache import cached_call_with_status
from LDDC.common.exceptions import LDDCError, LyricsNotFoundError
from LDDC.common.logger import logger
from LDDC.common.models import APIResultList, LyricInfo, Lyrics, P, SearchType, SongInfo, SongListInfo, Source, T

if TYPE_CHECKING:
    from .models import BaseAPI, CloudAPI


class LyricsAPI:
    def __init__(self) -> None:
        self.init_lock = Lock()
        self.inited = False

    def init(self) -> None:
        with self.init_lock:
            if self.inited:
                return
            from .kg import KGAPI
            from .local import LocalAPI
            from .lrclib import LrclibAPI
            from .ne import NEAPI
            from .qm import QMAPI

            self.cloud_apis: dict[Source, CloudAPI] = {
                KGAPI.source: KGAPI(),
                NEAPI.source: NEAPI(),
                QMAPI.source: QMAPI(),
                LrclibAPI.source: LrclibAPI(),  # 添加LrclibAPI到cloud_apis字典中
            }
            self.apis: dict[Source, BaseAPI] = {**self.cloud_apis, LocalAPI.source: LocalAPI()}
            self.inited = True

    def timeout_retry(self, func: Callable[P, T], *args: P.args, **kwargs: P.kwargs) -> T:
        from httpx import TimeoutException  # 加快启动速度

        for i in range(3):
            try:
                return func(*args, **kwargs)
            except TimeoutException:  # noqa: PERF203
                if i == 2:
                    raise
                continue
            except Exception:
                logger.exception("请求歌词Api时遇到错误")
                raise

        msg = "Unknown error"
        raise LDDCError(msg)

    @overload
    def search(self, source: Source, keyword: str, search_type: Literal[SearchType.SONG], page: int = 1) -> APIResultList[SongInfo]: ...

    @overload
    def search(
        self,
        source: Source,
        keyword: str,
        search_type: Literal[SearchType.SONGLIST, SearchType.ALBUM],
        page: int = 1,
    ) -> APIResultList[SongListInfo]: ...

    @overload
    def search(
        self,
        source: Source,
        keyword: str,
        search_type: Literal[SearchType.SONG, SearchType.SONGLIST, SearchType.ALBUM],
        page: int = 1,
    ) -> APIResultList[SongInfo] | APIResultList[SongListInfo]: ...

    @overload
    def search(
        self,
        source: Source,
        keyword: str,
        search_type: SearchType,
        page: int = 1,
    ) -> APIResultList[SongInfo] | APIResultList[SongListInfo]: ...

    @overload
    def search(
        self,
        source: Source,
        keyword: str,
        search_type: Literal[SearchType.ARTIST, SearchType.LYRICS],
        page: int = 1,
    ) -> NoReturn: ...

    def search(self, source: Source, keyword: str, search_type: SearchType, page: int = 1) -> APIResultList[SongInfo] | APIResultList[SongListInfo]:
        """从指定歌词源搜索歌曲/专辑/歌单

        Args:
            source (Source): 歌词源
            keyword (str): 搜索关键词
            search_type (SearchType): 搜索类型
            page (int, optional): 页码. Defaults to 1.

        Returns:
            list[SongInfo] | list[SongListInfo]: 搜索结果

        """
        if not self.inited:
            self.init()
        if source not in self.cloud_apis:
            msg = f"Unsupported source: {source}"
            raise ValueError(msg)
        if search_type not in self.cloud_apis[source].supported_search_types:
            msg = f"Unsupported search type: {search_type}"
            raise ValueError(msg)
        return self.timeout_retry(self.cloud_apis[source].search, keyword, search_type, page)

    def get_songlist(self, songlist_info: SongListInfo) -> APIResultList[SongInfo]:
        """获取歌单内容

        Args:
            songlist_info (SongListInfo): 歌单信息

        Returns:
            list[SongInfo]: 歌单内容

        """
        if not self.inited:
            self.init()
        return self.timeout_retry(self.cloud_apis[songlist_info.source].get_songlist, songlist_info)

    def get_lyricslist(self, song_info: SongInfo) -> APIResultList[LyricInfo]:
        """获取歌曲歌词信息

        Args:
            song_info (SongInfo): 歌曲信息

        Returns:
            list[LyricInfo]: 歌曲歌词

        """
        if not self.inited:
            self.init()
        return self.timeout_retry(self.cloud_apis[song_info.source].get_lyricslist, song_info)

    def get_lyrics(self, info: SongInfo | LyricInfo | None = None, path: Path | None = None, data: str | bytearray | bytes | None = None) -> Lyrics:
        """获取歌词

        Args:
            info (SongInfo | LyricInfo): 歌曲信息或歌词信息
            path (Path): 歌词文件路径
            data (str | bytearray | bytes): 歌词文件内容

        Returns:
            Lyrics: 歌词

        """
        if not self.inited:
            self.init()
        if not info or info.source == Source.Local:
            if not info and not path and not data:
                msg = "info, path, and data cannot be None at the same time"
                raise ValueError(msg)
            if not info:
                info = LyricInfo(
                    Source.Local,
                    SongInfo(Source.Local),
                    path=path,
                    data=bytes(data.encode("utf-8") if isinstance(data, str) else data) if data else None,
                )
            lyrics = self.apis[Source.Local].get_lyrics(info)
        else:
            lyrics = self.timeout_retry(self.apis[info.source].get_lyrics, info)
        if not lyrics:
            msg = "没有找到歌词"
            raise LyricsNotFoundError(msg, info)
        return lyrics


lyrics_api = LyricsAPI()


@overload
def search(source: Source, keyword: str, search_type: Literal[SearchType.SONG], page: int = 1) -> APIResultList[SongInfo]: ...


@overload
def search(
    source: Source,
    keyword: str,
    search_type: Literal[SearchType.SONGLIST, SearchType.ALBUM],
    page: int = 1,
) -> APIResultList[SongListInfo]: ...


@overload
def search(
    source: Source,
    keyword: str,
    search_type: Literal[SearchType.SONG, SearchType.SONGLIST, SearchType.ALBUM],
    page: int = 1,
) -> APIResultList[SongInfo] | APIResultList[SongListInfo]: ...


@overload
def search(
    source: Source,
    keyword: str,
    search_type: SearchType,
    page: int = 1,
) -> APIResultList[SongInfo] | APIResultList[SongListInfo]: ...


@overload
def search(
    source: Source,
    keyword: str,
    search_type: Literal[SearchType.ARTIST, SearchType.LYRICS],
    page: int = 1,
) -> NoReturn: ...


def search(source: Source, keyword: str, search_type: SearchType, page: int = 1) -> APIResultList[SongInfo] | APIResultList[SongListInfo]:
    """从指定歌词源搜索歌曲/专辑/歌单

    Args:
        source (Source): 歌词源
        keyword (str): 搜索关键词
        search_type (SearchType): 搜索类型
        page (int, optional): 页码. Defaults to 1.

    Returns:
        list[SongInfo] | list[SongListInfo]: 搜索结果

    """
    result, cached = cached_call_with_status(lyrics_api.search, {"expire": 14400}, source, keyword, search_type, page)
    result.cached = cached
    return result


def get_songlist(songlist_info: SongListInfo) -> APIResultList[SongInfo]:
    """获取歌单内容

    Args:
        songlist_info (SongListInfo): 歌单信息

    Returns:
        list[SongInfo]: 歌单内容

    """
    result, cached = cached_call_with_status(lyrics_api.get_songlist, {"expire": 14400}, songlist_info)
    result.cached = cached
    return result


def get_lyricslist(song_info: SongInfo) -> APIResultList[LyricInfo]:
    """获取歌曲歌词信息

    Args:
        song_info (SongInfo): 歌曲信息

    Returns:
        list[LyricInfo]: 歌曲歌词

    """
    result, cached = cached_call_with_status(lyrics_api.get_lyricslist, {"expire": 14400}, song_info)
    result.cached = cached
    return result


def get_lyrics(info: SongInfo | LyricInfo | None = None, path: Path | None = None, data: str | bytearray | bytes | None = None) -> Lyrics:
    """获取歌词

    Args:
        info (SongInfo | LyricInfo): 歌曲信息或歌词信息
        path (Path): 歌词文件路径
        data (str | bytearray | bytes): 歌词文件内容

    Returns:
        Lyrics: 歌词

    """
    if not info or info.source == Source.Local:
        return lyrics_api.get_lyrics(info, path, data)
    result, cached = cached_call_with_status(lyrics_api.get_lyrics, {"expire": 14400}, info)
    result.info = replace(result.info, cached=cached)
    return result
