# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from enum import Enum
from typing import Any


class QrcType(Enum):
    LOCAL = 0
    CLOUD = 1


class LyricsType(Enum):
    PlainText = 0
    VERBATIM = 1
    LINEBYLINE = 2


class LyricsProcessingError(Enum):
    REQUEST = 0
    DECRYPT = 1
    NOT_FOUND = 2
    UNSUPPORTED = 3


class LyricsFormat(Enum):
    VERBATIMLRC = 0
    LINEBYLINELRC = 1
    ENHANCEDLRC = 2
    SRT = 3
    ASS = 4
    QRC = 5
    KRC = 6
    YRC = 7
    JSON = 8


class SearchType(Enum):
    SONG = 0
    ARTIST = 1
    ALBUM = 2
    SONGLIST = 3
    LYRICS = 7


class Source(Enum):
    QM = 0
    KG = 1
    NE = 2
    Local = 100

    # 定义 Source 类的序列化方法
    def __json__(self, o: Any) -> str:
        if isinstance(o, Source):
            return str(o.name)
        msg = f"Object of type {o.__class__.__name__} is not JSON serializable"
        raise TypeError(msg)


class LocalMatchSaveMode(Enum):
    # 镜像/歌曲/指定
    MIRROR = 0
    SONG = 1
    SPECIFY = 2


class LocalMatchFileNameMode(Enum):
    # 歌曲/格式
    SONG = 0
    FORMAT = 1
