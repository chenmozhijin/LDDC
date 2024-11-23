# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from types import UnionType
from typing import get_args

from LDDC.backend.lyrics import Lyrics, LyricsData
from LDDC.utils.cache import cache
from LDDC.utils.enum import Source
from LDDC.utils.error import LyricsUnavailableError
from LDDC.utils.logger import logger

from .kg import get_lyrics as kg_get_lyrics
from .local import get_lyrics as local_get_lyrics
from .ne import get_lyrics as ne_get_lyrics
from .qm import get_lyrics as qm_get_lyrics
from .share import judge_lyrics_type


def is_verbatim(lrc_list: list) -> bool:
    isverbatim = False
    for line_list in lrc_list:
        if len(line_list[2]) > 1:
            isverbatim = True
            break
    return isverbatim


TYPE_MAPPING: dict[str, type | UnionType] = {
    "title": str,
    "album": str,
    "mid": str,
    "accesskey": str,
    "path": str,
    "duration": int,
    "artist": list | str,
    "data": bytearray | bytes,
    "id": int | str,
}


QUERY_PARAMS = ("title", "artist", "album", "mid", "accesskey", "id", "duration", "path")


def get_lyrics(
    source: Source,
    use_cache: bool = True,
    **kwargs: str | int | bytearray | bytes | None,
) -> tuple[Lyrics, bool]:
    """获取歌词

    :param source: 歌词源
    :param use_cache: 是否使用缓存
    :param title: 歌曲名
    :param artist: 歌手名
    :param album: 专辑名
    :param id: 歌曲id(int)
    :param mid: 歌曲mid
    :param duration: 歌曲时长(秒int)
    :param accesskey: 歌曲访问密钥
    :param path: 本地歌词路径
    :param data: 歌词数据
    :return: (歌词, 是否使用缓存)
    """
    logger.debug("Fetching lyrics for %s", kwargs)
    # 检查参数类型
    for key, arg in kwargs.items():
        msg = None
        if key in TYPE_MAPPING and not isinstance(arg, TYPE_MAPPING[key]):
            expected_type = TYPE_MAPPING[key]
            expected_type_str = " or ".join([t.__name__ for t in get_args(expected_type)]) if isinstance(expected_type, UnionType) else expected_type.__name__
            msg = f"Invalid type for {key}: expected {expected_type_str}, got {type(arg).__name__}"

        if msg:
            raise TypeError(msg)

    if source != Source.Local:
        cache_key = {"source": source, **{arg: kwargs[arg] for arg in kwargs if arg in QUERY_PARAMS}}
        cache_key = tuple((key, cache_key[key]) for key in sorted(cache_key))
        if use_cache:
            lyrics = cache.get(cache_key)
            if isinstance(lyrics, Lyrics):
                logger.debug("Using cache for %s", cache_key)
                return lyrics, True
    # 创建歌词对象
    lyrics = Lyrics({"source": source, **{arg[0]: arg[1] for arg in kwargs.items() if arg[0] in Lyrics.INFO_KEYS}})

    # 获取歌词
    match source:
        case Source.QM:
            if "id" not in kwargs or "duration" not in kwargs or "title" not in kwargs or "artist" not in kwargs or "album" not in kwargs:
                msg = f"QM lyrics requires title, artist, album, id, duration, kwargs: {kwargs}"
                raise ValueError(msg)
            qm_get_lyrics(lyrics)
        case Source.KG:
            if "id" not in kwargs or "accesskey" not in kwargs:
                msg = "KG lyrics requires id, accesskey"
                raise ValueError(msg)
            kg_get_lyrics(lyrics)
        case Source.NE:
            if "id" not in kwargs:
                msg = "NE lyrics requires id"
                raise ValueError(msg)
            ne_get_lyrics(lyrics)
        case Source.Local:
            data = kwargs.get("data")
            path = kwargs.get("path")
            if not data and not path:
                msg = "Local lyrics requires data or path"
                raise ValueError(msg)

            if isinstance(data, bytearray | bytes | None) and isinstance(path, str | None):
                local_get_lyrics(lyrics, path=path, data=data)

            elif not isinstance(data, bytearray | bytes | None):
                msg = f"Invalid type for data: expected bytearray or bytes, got {type(data).__name__}"
                raise TypeError(msg)
            elif not isinstance(path, str | None):
                msg = f"Invalid type for path: expected str or None, got {type(path).__name__}"
                raise TypeError(msg)

    if not lyrics:
        msg = "没有获取到可用的歌词"
        raise LyricsUnavailableError(msg)

    for key, lyric in lyrics.items():
        lyric: LyricsData
        lyrics.types[key] = judge_lyrics_type(lyric)

    # 缓存歌词
    if source != Source.Local:
        logger.debug("缓存歌词 query: %s", cache_key)
        cache.set(cache_key, lyrics, expire=14400)

    return lyrics, False
