# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from abc import ABC, abstractmethod
from typing import Literal, NoReturn, overload

from LDDC.common.models import APIResultList, LyricInfo, Lyrics, SearchType, SongInfo, SongListInfo, Source


class BaseAPI(ABC):
    source: Source

    @abstractmethod
    def get_lyrics(self, info: SongInfo | LyricInfo) -> Lyrics: ...


class CloudAPI(BaseAPI):
    supported_search_types: tuple[Literal[SearchType.SONG, SearchType.SONGLIST, SearchType.ALBUM], ...]

    @overload
    def search(self, keyword: str, search_type: Literal[SearchType.SONG], page: int = 1) -> APIResultList[SongInfo]: ...

    @overload
    def search(
        self,
        keyword: str,
        search_type: Literal[SearchType.SONGLIST, SearchType.ALBUM],
        page: int = 1,
    ) -> APIResultList[SongListInfo]: ...

    @overload
    def search(
        self,
        keyword: str,
        search_type: Literal[SearchType.SONG, SearchType.SONGLIST, SearchType.ALBUM],
        page: int = 1,
    ) -> APIResultList[SongInfo] | APIResultList[SongListInfo]:...


    @overload
    def search(
        self,
        keyword: str,
        search_type: Literal[SearchType.ARTIST, SearchType.LYRICS],
        page: int = 1,
    ) -> NoReturn: ...

    @overload
    def search(
        self,
        keyword: str,
        search_type: Literal[SearchType.ARTIST, SearchType.LYRICS],
        page: int = 1,
    ) -> NoReturn: ...

    @abstractmethod
    def search(
        self,
        keyword: str,
        search_type: SearchType,
        page: int = 1,
    ) -> APIResultList[SongInfo] | APIResultList[SongListInfo]:...

    @abstractmethod
    def get_songlist(self, songlist_info: SongListInfo) -> APIResultList[SongInfo]: ...

    @abstractmethod
    def get_lyricslist(self, song_info: SongInfo) -> APIResultList[LyricInfo]: ...
