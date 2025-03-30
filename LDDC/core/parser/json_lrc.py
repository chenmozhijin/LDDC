# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from LDDC.common.exceptions import LyricsProcessingError
from LDDC.common.models import LyricInfo, Lyrics, LyricsData, LyricsLine, LyricsWord, Source


def json2lyrics(json_data: dict) -> Lyrics:
    if not isinstance(json_data, dict):
        msg = "JSON歌词数据必须是一个字典"
        raise LyricsProcessingError(msg)

    for key, type_ in (("version", int), ("info", dict), ("tags", dict), ("lyrics", dict)):
        if key not in json_data:
            msg = f"JSON歌词数据缺少必要的键: {key}"
            raise LyricsProcessingError(msg)
        if not isinstance(json_data[key], type_):
            msg = f"JSON歌词数据中包含值类型不正确的键: {key}"
            raise LyricsProcessingError(msg)

    if json_data["version"] > 1:
        msg = "JSON歌词数据版本号不正确"
        raise LyricsProcessingError(msg)

    info = {}

    for key, value in json_data["info"].items():
        key: str
        value: str | int

        if key == "source" and isinstance(value, str):
            source = Source.__members__.get(value)
            if source is None:
                msg = f"JSON歌词数据中包含不正确的值: {value}"
                raise LyricsProcessingError(msg)

        elif (
            (key in ("source", "title", "album", "mid", "accesskey") and not isinstance(value, str))
            or (key == "duration" and not isinstance(value, int))
            or (key == "artist" and not isinstance(value, str | list))
            or (key == "id" and not isinstance(value, str | int))
        ):
            msg = f"JSON歌词数据中包含值类型不正确的键: {key}"
            raise LyricsProcessingError(msg)
        else:
            info[key] = value


    lyrics = Lyrics(LyricInfo.from_dict(json_data["info"]))

    for key, value in json_data["tags"].items():
        if not isinstance(key, str):
            msg = f"JSON歌词数据中包含值类型不正确的键: {key}"
            raise LyricsProcessingError(msg)
        if not isinstance(value, str):
            msg = f"JSON歌词数据中包含不正确的值: {value}"
            raise LyricsProcessingError(msg)
        lyrics.tags[key] = value

    for key, lyrics_data in json_data["lyrics"].items():
        lyrics_data: list[list]
        if not isinstance(key, str):
            msg = f"JSON歌词数据中包含不正确的键: {key}"
            raise LyricsProcessingError(msg)

        lyrics[key] = LyricsData([])
        for line in lyrics_data:
            lyrics[key].append(LyricsLine(line[0], line[1], [LyricsWord(*word) for word in line[2]]))

    return lyrics
