# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from enum import Enum
from typing import Any, TypeVar

try:
    from PySide6.QtCore import QCoreApplication
except ImportError:
    QCoreApplication = None
__all__ = ["Direction", "FileNameMode", "LyricsFormat", "LyricsType", "QrcType", "SaveMode", "SearchType", "SongListType"]


class Direction(Enum):
    LEFT = 1
    RIGHT = 2
    TOP = 3
    BOTTOM = 4
    TOP_LEFT = 5
    TOP_RIGHT = 6
    BOTTOM_LEFT = 7
    BOTTOM_RIGHT = 8


class SearchType(Enum):
    SONG = 0
    ALBUM = 1
    SONGLIST = 2
    ARTIST = 3
    LYRICS = 7


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

    @property
    def ext(self) -> str:
        match self:
            case LyricsFormat.VERBATIMLRC | LyricsFormat.LINEBYLINELRC | LyricsFormat.ENHANCEDLRC:
                return ".lrc"
            case LyricsFormat.SRT:
                return ".srt"
            case LyricsFormat.ASS:
                return ".ass"
            case LyricsFormat.QRC:
                return ".qrc"
            case LyricsFormat.KRC:
                return ".krc"
            case LyricsFormat.YRC:
                return ".yrc"
            case LyricsFormat.JSON:
                return ".json"
            case _:
                msg = f"Unknown lyrics format: {self}"
                raise ValueError(msg)


class LyricsType(Enum):
    PlainText = 0
    VERBATIM = 1
    LINEBYLINE = 2


class QrcType(Enum):
    LOCAL = 0
    CLOUD = 1


class Source(Enum):
    MULTI = 0
    QM = 1
    KG = 2
    NE = 3
    LRCLIB = 4
    Local = 100

    def __str__(self) -> str:
        if not QCoreApplication:
            return self.name
        match self:
            case Source.MULTI:
                return QCoreApplication.translate("Source", "聚合")
            case Source.QM:
                return QCoreApplication.translate("Source", "QQ音乐")
            case Source.KG:
                return QCoreApplication.translate("Source", "酷狗音乐")
            case Source.NE:
                return QCoreApplication.translate("Source", "网易云音乐")
            case Source.LRCLIB:
                return QCoreApplication.translate("Source", "Lrclib")
            case Source.Local:
                return QCoreApplication.translate("Source", "本地")
            case _:
                return str(self.name)

    @property
    def supported_search_types(self) -> tuple[SearchType, ...]:
        match self:
            case Source.MULTI:
                return (SearchType.SONG, SearchType.ALBUM, SearchType.SONGLIST)
            case Source.QM:
                return (SearchType.SONG, SearchType.ALBUM, SearchType.SONGLIST)
            case Source.KG:
                return (SearchType.SONG, SearchType.ALBUM, SearchType.SONGLIST)
            case Source.NE:
                return (SearchType.SONG, SearchType.ALBUM, SearchType.SONGLIST)
            case Source.LRCLIB:
                return (SearchType.SONG,)
            case _:
                return ()


class TranslateSource(Enum):
    BING = 0
    GOOGLE = 1
    OPENAI = 2


class TranslateTargetLanguage(Enum):
    SIMPLIFIED_CHINESE = 0
    TRADITIONAL_CHINESE = 1
    ENGLISH = 2
    JAPANESE = 3
    KOREAN = 4
    SPANISH = 5
    FRENCH = 6
    PORTUGUESE = 7
    GERMAN = 8
    RUSSIAN = 9


class Language(Enum):
    INSTRUMENTAL = 0
    OTHER = 1

    CHINESE = 2
    ENGLISH = 3
    JAPANESE = 4
    KOREAN = 5


class SongListType(Enum):
    ALBUM = 0
    SONGLIST = 1


T = TypeVar("T", bound=Enum)


def get_enum(enum_type: type[T], value: Any) -> T:
    if isinstance(value, enum_type):
        return value
    if isinstance(value, str) and value in enum_type.__members__:
        return enum_type[value]
    return enum_type(value)


class FileNameMode(Enum):
    # 歌曲/格式
    FORMAT_BY_LYRICS = 0
    FORMAT_BY_SONG = 1
    SONG = 2


class SaveMode(Enum):
    # 镜像/歌曲/指定
    MIRROR = 0
    SONG = 1
    SPECIFY = 2
