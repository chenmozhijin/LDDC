# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from typing import ParamSpec, TypeVar

from ._enums import Direction, FileNameMode, LyricsFormat, LyricsType, QrcType, SaveMode, SearchType, Source, TranslateSource, TranslateTargetLanguage
from ._info import APIResultList, Artist, Language, LyricInfo, SearchInfo, SongInfo, SongListInfo, SongListType
from ._lyrics import (
    FSLyrics,
    FSLyricsData,
    FSLyricsLine,
    FSLyricsWord,
    FSMultiLyricsData,
    Lyrics,
    LyricsBase,
    LyricsData,
    LyricsLine,
    LyricsWord,
    MultiLyricsData,
    get_full_timestamps_lyrics_data,
)

__all__ = [
    "APIResultList",
    "Artist",
    "Direction",
    "FSLyrics",
    "FSLyricsData",
    "FSLyricsLine",
    "FSLyricsWord",
    "FSMultiLyricsData",
    "FileNameMode",
    "Language",
    "LyricInfo",
    "Lyrics",
    "LyricsBase",
    "LyricsData",
    "LyricsFormat",
    "LyricsLine",
    "LyricsType",
    "LyricsWord",
    "MultiLyricsData",
    "P",
    "QrcType",
    "SaveMode",
    "SearchInfo",
    "SearchInfo",
    "SearchType",
    "SongInfo",
    "SongListInfo",
    "SongListType",
    "Source",
    "T",
    "TranslateSource",
    "TranslateTargetLanguage",
    "get_full_timestamps_lyrics_data",
]


P = ParamSpec("P")
T = TypeVar("T")
