# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from typing import TYPE_CHECKING, NewType

if TYPE_CHECKING:
    from utils.enum import Source

LyricsWord = NewType("LyricsWord", tuple[int | None, int | None, str])
LyricsLine = NewType("LyricsLine", tuple[int | None, int | None, list[LyricsWord]])
LyricsData = NewType("LyricsData", list[LyricsLine])
MultiLyricsData = NewType("MultiLyricsData", dict[str, LyricsData])


def get_full_timestamps_lyrics_data(data: LyricsData, duration: int | None, only_line: bool = False, skip_none: bool = False) -> LyricsData:
    """获取完整时间戳的歌词数据

    :param data: 歌词数据
    :param end_time: 歌曲结束时间
    :param only_line: 是否只推算行时间戳
    :param skip_none: 是否跳过无法推算时间戳的行
    """
    result = LyricsData([])
    for i, line in enumerate(data):
        line_start_time = line[2][0][0] if line[0] is None and line[2] and line[2][0][0] is not None else line[0]
        line_end_time = line[2][-1][1] if line[1] is None and line[2] and line[2][-1][1] is not None else line[1]
        if line_start_time is None:
            if i == 0:
                line_start_time = 0
            elif data[i - 1][1] is not None:
                line_start_time = data[i - 1][1]
            elif skip_none:
                continue

        if line_end_time is None:
            if i == len(data) - 1:
                line_end_time = duration
            elif data[i + 1][0] is not None:
                line_end_time = data[i + 1][0]
            elif skip_none:
                continue

        if only_line:
            result.append(LyricsLine((line_start_time, line_end_time, line[2])))
            continue

        words = []
        for j, word in enumerate(line[2]):
            word_start_time = word[0]
            word_end_time = word[1]
            if word_start_time is None:
                if j == 0 and line_start_time:
                    word_start_time = line_start_time
                elif j != 0 and line[2][j - 1][1] is not None:
                    word_start_time = line[2][j - 1][1]
                elif skip_none:
                    continue

            if word_end_time is None:
                if j == len(line[2]) - 1 and line_end_time:
                    word_end_time = line_end_time
                elif j != len(line[2]) - 1 and line[2][j + 1][0] is not None:
                    word_end_time = line[2][j + 1][0]
                elif skip_none:
                    continue

            words.append((word_start_time, word_end_time, word[2]))

        result.append(LyricsLine((line_start_time, line_end_time, words)))
    return result


class Lyrics(dict):
    INFO_KEYS = ("source", "title", "artist", "album", "id", "mid", "duration", "accesskey")

    def __init__(self, info: dict | None = None) -> None:
        if info is None:
            info = {}
        self.source: Source | None = info.get("source", None)
        self.title: str | None = info.get("title", None)
        self.artist: str | list | None = info.get("artist", None)
        self.album: str | None = info.get("album", None)
        self.id: int | str | None = info.get("id", None)
        self.mid: str | None = info.get("mid", None)
        self.duration: int | None = info.get("duration", None)
        self.accesskey: str | None = info.get("accesskey", None)

        self.types = {}
        self.tags = {}

    def get_info(self) -> dict:
        info = {}
        if self.source:
            info["source"] = self.source
        if self.title:
            info["title"] = self.title
        if self.artist:
            info["artist"] = self.artist
        if self.album:
            info["album"] = self.album
        if self.id:
            info["id"] = self.id
        if self.mid:
            info["mid"] = self.mid
        if self.duration:
            info["duration"] = self.duration
        if self.accesskey:
            info["accesskey"] = self.accesskey
        return info

    def get_duration(self) -> int:
        if self.duration is not None:
            return self.duration * 1000
        if self.get("orig"):
            last_line = self["orig"][-1]
            if last_line[1] is not None:
                return last_line[1]
            if last_line[2]:
                if last_line[2][-1][1] is not None:
                    return last_line[2][-1][1]
                if last_line[2][-1][0] is not None:
                    return last_line[2][-1][0]
            if last_line[0] is not None:
                return last_line[0]
        elif self:
            last_line = next(iter(self.values()))[-1]
            if last_line[1] is not None:
                return last_line[1]
            if last_line[2]:
                if last_line[2][-1][1] is not None:
                    return last_line[2][-1][1]
                if last_line[2][-1][0] is not None:
                    return last_line[2][-1][0]
            if last_line[0] is not None:
                return last_line[0]
        msg = "can not get duration"
        raise ValueError(msg)

    def add_offset(self, offset: int = 0) -> MultiLyricsData:
        """添加偏移量

        :param offset:偏移量
        :return: 偏移后的歌词数据
        """
        multi_lyrics_data = MultiLyricsData(self)

        if offset == 0:
            return multi_lyrics_data

        def _offset_time(time: int | None) -> int | None:
            if isinstance(time, int):
                return max(time + offset, 0)
            return time

        return MultiLyricsData({
            lang: LyricsData([
                LyricsLine((
                    _offset_time(lrc_line[0]),
                    _offset_time(lrc_line[1]),
                    [LyricsWord((_offset_time(word[0]), _offset_time(word[1]), word[2])) for word in lrc_line[2]],
                ))
                for lrc_line in lrc_list
            ])
            for lang, lrc_list in multi_lyrics_data.items()
        })

    def set_data(self, data: MultiLyricsData) -> None:
        for lang, lyrics_data in data.items():
            self[lang] = lyrics_data

    def get_full_timestamps_lyrics(self, duration_ms: int | None = None, skip_none: bool = False) -> "Lyrics":
        """获取完整时间戳的歌词

        :param duration_ms: 歌曲时长
        :param skip_none: 是否跳过没有时间戳的歌词
        :return: 完整时间戳的歌词
        """
        full_timestamps_lyrics = Lyrics({"source": self.source,
                                         "title": self.title,
                                         "artist": self.artist,
                                         "album": self.album,
                                         "id": self.id,
                                         "mid": self.mid,
                                         "duration": self.duration,
                                         "accesskey": self.accesskey})

        duration = duration_ms if duration_ms else (self.duration * 1000 if self.duration else None)
        full_timestamps_lyrics.types = self.types
        full_timestamps_lyrics.tags = self.tags
        for lang, lyrics_data in self.items():
            full_timestamps_lyrics[lang] = get_full_timestamps_lyrics_data(data=lyrics_data,
                                                                           duration=duration,
                                                                           only_line=False,
                                                                           skip_none=skip_none)
        return full_timestamps_lyrics

    def is_inst(self) -> bool:
        """检查是否为纯歌词"""
        if 0 < len(self["orig"]) < 10:
            text = "".join(w[2] for w in self["orig"][-1][2]).strip()
            if text in ("此歌曲为没有填词的纯音乐，请您欣赏", "纯音乐，请欣赏"):
                return True
        return False
