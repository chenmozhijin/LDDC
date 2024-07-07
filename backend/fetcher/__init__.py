# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from types import UnionType
from typing import get_args

from backend.lyrics import Lyrics, LyricsData
from utils.cache import cache
from utils.enum import Source
from utils.error import LyricsProcessingError
from utils.logger import logger

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
    return_cache_status: bool = False,
    **kwargs: str | int,
) -> Lyrics:
    """获取歌词

    :param source: 歌词源
    :param use_cache: 是否使用缓存
    :param return_cache_status: 是否返回缓存状态
    :param title: 歌曲名
    :param artist: 歌手名
    :param album: 专辑名
    :param id: 歌曲id(int)
    :param mid: 歌曲mid
    :param duration: 歌曲时长(秒int)
    :param accesskey: 歌曲访问密钥
    :param path: 本地歌词路径
    :param data: 歌词数据
    :return: 歌词
    """
    logger.debug("Fetching lyrics for %s", kwargs)
    # 检查参数类型
    for key, arg in kwargs.items():
        msg = None
        if key in TYPE_MAPPING and not isinstance(arg, TYPE_MAPPING[key]):
            if isinstance(TYPE_MAPPING[key], type):
                expected_type_str = TYPE_MAPPING[key].__name__
            else:
                expected_type_str = " or ".join([t.__name__ for t in get_args(TYPE_MAPPING[key])])
            msg = f"Invalid type for {key}: expected {expected_type_str}, got {type(arg).__name__}"

        if msg:
            raise TypeError(msg)

    query = {"source": source, **{arg: kwargs[arg] for arg in kwargs if arg in QUERY_PARAMS}}
    query = {key: query[key] for key in sorted(query)}
    if use_cache:
        lyrics = cache.get(query)
        if lyrics:
            logger.debug("Using cache for %s", query)
            if return_cache_status:
                return lyrics, True
            return lyrics
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
            if "path" not in kwargs:
                msg = "Local lyrics requires path"
                raise ValueError(msg)
            local_get_lyrics(lyrics, path=kwargs["path"], data=kwargs.get("data"))

    if not lyrics:
        msg = "没有获取到可用的歌词"
        raise LyricsProcessingError(msg)

    for key, lyric in lyrics.items():
        lyric: LyricsData
        lyrics.types[key] = judge_lyrics_type(lyric)

    # 缓存歌词
    logger.debug("缓存歌词 query: %s", query)
    if source != Source.Local:
        cache.set(query, lyrics, expire=14400)
    else:
        cache.set(query, lyrics, expire=10)

    if return_cache_status:
        return lyrics, False
    return lyrics
