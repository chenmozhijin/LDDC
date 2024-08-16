# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from enum import Enum
from typing import Any

from PySide6.QtCore import QCoreApplication


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
    MULTI = 0
    QM = 1
    KG = 2
    NE = 3
    Local = 100

    # 定义 Source 类的序列化方法
    def __json__(self, o: Any) -> str:
        if isinstance(o, Source):
            return str(o.name)
        msg = f"Object of type {o.__class__.__name__} is not JSON serializable"
        raise TypeError(msg)

    def __str__(self) -> str:
        match self:
            case Source.MULTI:
                return QCoreApplication.translate("Source", "聚合")
            case Source.QM:
                return QCoreApplication.translate("Source", "QQ音乐")
            case Source.KG:
                return QCoreApplication.translate("Source", "酷狗音乐")
            case Source.NE:
                return QCoreApplication.translate("Source", "网易云音乐")
            case Source.Local:
                return QCoreApplication.translate("Source", "本地")
            case _:
                return str(self.name)


class LocalMatchSaveMode(Enum):
    # 镜像/歌曲/指定
    MIRROR = 0
    SONG = 1
    SPECIFY = 2


class LocalMatchFileNameMode(Enum):
    # 歌曲/格式
    SONG = 0
    FORMAT = 1


class Direction(Enum):
    LEFT = 1
    RIGHT = 2
    TOP = 3
    BOTTOM = 4
    TOP_LEFT = 5
    TOP_RIGHT = 6
    BOTTOM_LEFT = 7
    BOTTOM_RIGHT = 8
