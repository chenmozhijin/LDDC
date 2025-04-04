# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import datetime
from collections import OrderedDict, defaultdict
from collections.abc import Iterable, Iterator, Mapping, Sequence
from dataclasses import asdict, dataclass
from itertools import zip_longest
from pathlib import Path
from types import MappingProxyType
from typing import Self, TypeVar

from ._enums import Language, SearchType, SongListType, Source, get_enum

__all__ = ["InfoBase", "LyricInfo", "SearchInfo", "SongInfo", "SongListInfo"]


class Artist(tuple[str]):
    __slots__ = ()

    def __new__(cls, artist: str | Iterable[str]) -> Self:
        unique_ordered = OrderedDict.fromkeys([artist] if isinstance(artist, str) else artist)
        return super().__new__(cls, unique_ordered)

    def __str__(self) -> str:
        return self.str()

    def str(self, sep: str = "/") -> str:
        return sep.join(self)

    def __bool__(self) -> bool:
        return bool(self.str())


@dataclass(frozen=True, slots=True)
class InfoBase:
    source: Source


@dataclass(frozen=True, slots=True)
class SongInfo(InfoBase):
    title: str | None = None
    subtitle: str | None = None
    artist: Artist | None = None
    album: str | None = None
    duration: int | None = None  # 单位毫秒

    id: str | None = None  # 对于从云端获取的数据id为该平台的歌曲id,对于来自本地cue的数据id为音轨号
    mid: str | None = None
    hash: str | None = None

    path: Path | None = None
    from_cue: bool = False

    language: Language | None = None

    @property
    def full_title(self) -> str:
        return (f"{self.title}({self.subtitle})" if self.subtitle else self.title) if self.title else ""

    @property
    def str_artist(self) -> str:
        return str(self.artist) if self.artist else ""

    @property
    def url(self) -> str | None:
        return "file://" + str(self.path.resolve()) if self.path else None

    def artist_title(self, full: bool = False, replace: bool = False) -> str:
        """歌曲歌手和标题组成的字符串

        Args:
            full (bool, optional): 是否显示副标题. Defaults to False.
            replace (bool, optional): 是否不存在的信息为?. Defaults to False.

        """
        title = (self.full_title if full else self.title) or ("?" if replace else "")
        artist = self.str_artist or ("?" if replace else "")
        if artist and title:
            return f"{artist} - {title}"
        return artist + title

    @property
    def format_duration(self) -> str:
        return f"{self.duration // 1000 // 60:02}:{self.duration // 1000 % 60:02}" if self.duration else ""

    def to_dict(self) -> dict[str, str | int | frozenset[str] | Language]:
        return {k: v for k, v in asdict(self).items() if v is not None}

    @classmethod
    def from_dict(cls, info: dict[str, str | int | Iterable[str] | Language | Source | None]) -> "SongInfo":
        if isinstance(info["source"], Source):
            Source(info["source"])
        return cls(
            source=get_enum(Source, info["source"]),
            title=info["title"] if "title" in info and isinstance(info["title"], str) else None,
            subtitle=info["subtitle"] if "subtitle" in info and isinstance(info["subtitle"], str) else None,
            artist=Artist(info["artist"]) if "artist" in info and isinstance(info["artist"], (str, Iterable)) else None,
            album=info["album"] if "album" in info and isinstance(info["album"], str) else None,
            duration=info["duration"] if "duration" in info and isinstance(info["duration"], int) else None,
            id=info["id"] if "id" in info and isinstance(info["id"], str) else None,
            mid=info["mid"] if "mid" in info and isinstance(info["mid"], str) else None,
            hash=info["hash"] if "hash" in info and isinstance(info["hash"], str) else None,
            path=(info["path"] if isinstance(info["path"], Path) else Path(info["path"].removeprefix("file://")))
            if "path" in info and isinstance(info["path"], str | Path)
            else None,
            from_cue=info["from_cue"] if "from_cue" in info and isinstance(info["from_cue"], bool) else False,
            language=get_enum(Language, info["language"]) if "language" in info and isinstance(info["language"], str) else None,
        )


@dataclass(frozen=True, slots=True)
class SongListInfo(InfoBase):  # 包括歌单和专辑
    type: SongListType

    id: str
    title: str
    imgurl: str
    songcount: int | None
    publishtime: int | None  # 单位秒
    author: str  # 歌单作者/专辑艺术家
    mid: str | None = None

    @property
    def format_publishtime(self) -> str:
        return datetime.datetime.fromtimestamp(self.publishtime, tz=datetime.timezone.utc).strftime("%Y-%m-%d") if self.publishtime else ""


@dataclass(frozen=True, slots=True)
class LyricInfo(InfoBase):
    songinfo: SongInfo
    id: str | None = None
    accesskey: str | None = None
    duration: int | None = None
    creator: str | None = None
    score: int | None = None

    path: Path | None = None
    data: bytearray | bytes | None = None

    cached: bool = False

    @property
    def format_duration(self) -> str:
        return f"{self.duration // 1000 // 60:02}:{self.duration // 1000 % 60:02}" if self.duration else ""

    def to_dict(self) -> dict[str, str | int | bool | SongInfo | bytearray | bytes]:
        return {k: v for k, v in asdict(self).items() if v is not None}

    @classmethod
    def from_dict(cls, info: dict[str, str | int | bool | SongInfo | bytearray | bytes | dict | frozenset[str] | Language | Source | None]) -> "LyricInfo":
        if "songinfo" not in info:
            songinfo = SongInfo.from_dict(info)  # type: ignore[]
        elif isinstance(info["songinfo"], (SongInfo, dict)):
            songinfo = SongInfo.from_dict(info["songinfo"]) if isinstance(info["songinfo"], dict) else info["songinfo"]
        else:
            msg = "info['songinfo'] must be a SongInfo instance"
            raise TypeError(msg)
        return cls(
            source=get_enum(Source, info["source"]),
            songinfo=songinfo,
            id=str(info["id"]) if "id" in info and isinstance(info["id"], str | int) else None,
            accesskey=info["accesskey"] if "accesskey" in info and isinstance(info["accesskey"], str) else None,
            duration=info["duration"] if "duration" in info and isinstance(info["duration"], int) else None,
            creator=info["creator"] if "creator" in info and isinstance(info["creator"], str) else None,
            score=info["score"] if "score" in info and isinstance(info["score"], int) else None,
            path=Path(info["path"]) if "path" in info and isinstance(info["path"], str | Path) else None,
            data=info["data"] if "data" in info and isinstance(info["data"], (bytearray, bytes)) else None,
            cached=info["cached"] if "cached" in info and isinstance(info["cached"], bool) else False,
        )


@dataclass(frozen=True, slots=True)
class SearchInfo(InfoBase):
    source: Source | list[Source]
    keyword: str
    search_type: SearchType
    page: int | None


A = TypeVar("A", SongInfo, SongListInfo, LyricInfo)


class APIResultList(Sequence[A]):
    __slots__ = ("_items", "_source_ranges", "cached", "info")

    def __init__(
        self,
        result: "Iterable[A] | APIResultList[A]",
        info: InfoBase | None = None,
        ranges: tuple[int, int, int] | Mapping[Source, tuple[int, int, int]] | None = None,
        cached: bool | None = None,
    ) -> None:
        if isinstance(result, APIResultList):
            self._items = result._items  # noqa: SLF001
            self._source_ranges = dict(result._source_ranges)  # noqa: SLF001
            self.info = info if info is not None else result.info
            self.cached = cached if cached is not None else result.cached
        else:
            self._source_ranges = self._process_ranges(ranges, {item.source for item in result})
            self._items = self._create_ordered_items(result)  # 始终按source_ranges顺序交叉合并元素
            self.info = info
            self.cached = cached if cached is not None else False

        self._validate_ranges()

    def _process_ranges(
        self,
        ranges: tuple[int, int, int] | Mapping[Source, tuple[int, int, int]] | None,
        sources: set[Source],
    ) -> dict[Source, tuple[int, int, int]]:
        if ranges is None:
            return {}

        if isinstance(ranges, Mapping):
            return dict(ranges)

        if len(sources) > 1:
            msg = "有多个数据源，但只提供了一个范围元组"
            raise ValueError(msg)
        return {next(iter(sources)): ranges} if sources else {}

    def _create_ordered_items(self, items: Iterable[A]) -> tuple[A, ...]:
        """预先生成交叉排序的元组"""
        if not self._source_ranges:
            return ()

        groups: dict[Source, list[A]] = defaultdict(list)
        for item in items:
            groups[item.source].append(item)

        valid_sources = [source for source in Source.__members__.values() if source in groups]

        return tuple(
            item
            for group in zip_longest(*(groups[source] for source in valid_sources))
            for item in group
            if item is not None
        )

    def _validate_ranges(self) -> None:
        total_in_ranges = sum(end - start + 1 for start, end, _ in self._source_ranges.values())
        if len(self._items) != total_in_ranges:
            msg = "ranges 的总数不等于结果的长度"
            raise ValueError(msg)

    @property
    def source_ranges(self) -> MappingProxyType[Source, tuple[int, int, int]]:
        return MappingProxyType(self._source_ranges)

    @property
    def sources(self) -> list[Source]:
        return list(self.source_ranges.keys())

    def __len__(self) -> int:
        return len(self._items)

    def __getitem__(self, index: int) -> A:
        return self._items[index]

    def __iter__(self) -> Iterator[A]:
        return iter(self._items)

    def __add__(self, other: "APIResultList[A]") -> "APIResultList[A]":
        """两个APIResultList对象相加,元素仍然按来源交叉排序"""
        if not isinstance(other, APIResultList) or not isinstance(self.info, type(other.info)):
            return NotImplemented

        merged_items = self._items + other._items
        return APIResultList(
            result=merged_items,
            info=self._merge_info(other),
            ranges=self._merge_ranges(other),
            cached=self.cached and other.cached,
        )

    def _merge_info(self, other: "APIResultList[A]") -> InfoBase | None:
        if isinstance(self.info, SearchInfo):
            return SearchInfo(
                source=list(dict.fromkeys([*self.sources, *other.sources])),
                keyword=self.info.keyword,
                search_type=self.info.search_type,
                page=None,
            )
        return self.info

    def _merge_ranges(self, other: "APIResultList[A]") -> dict[Source, tuple[int, int, int]]:
        merged_ranges = {}
        all_sources = {*self.source_ranges.keys(), *other.source_ranges.keys()}

        for source in all_sources:
            self_range = self.source_ranges.get(source)
            other_range = other.source_ranges.get(source)

            if not self_range:
                merged_ranges[source] = other_range
                continue

            if not other_range:
                merged_ranges[source] = self_range
                continue

            s_start, s_end, s_total = self_range
            o_start, o_end, o_total = other_range

            if s_end + 1 == o_start:
                merged_ranges[source] = (s_start, o_end, max(s_total, o_total))
            elif o_end + 1 == s_start:
                merged_ranges[source] = (o_start, s_end, max(s_total, o_total))
            else:
                msg = f"无法合并范围：{self_range} 和 {other_range}"
                raise ValueError(msg)

        return merged_ranges

    @property
    def more(self) -> tuple[Source, ...]:
        return tuple(source for source, (start, end, total) in self.source_ranges.items() if end - start + 1 < total)
