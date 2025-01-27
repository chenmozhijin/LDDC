# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from copy import deepcopy
from typing import TYPE_CHECKING, Literal, NewType, TypeVar, overload

if TYPE_CHECKING:
    from LDDC.utils.enum import Source

LyricsWord = NewType("LyricsWord", tuple[int | None, int | None, str])
LyricsLine = NewType("LyricsLine", tuple[int | None, int | None, list[LyricsWord]])
LyricsData = NewType("LyricsData", list[LyricsLine])
MultiLyricsData = NewType("MultiLyricsData", dict[str, LyricsData])

# FS 是 full_timestamps 的缩写
FSLyricsWord = NewType("FSLyricsWord", tuple[int, int, str])
FSLyricsLine = NewType("FSLyricsLine", tuple[int, int, list[FSLyricsWord]])
FSLyricsData = NewType("FSLyricsData", list[FSLyricsLine])
FSMultiLyricsData = NewType("FSMultiLyricsData", dict[str, FSLyricsData])

T = TypeVar("T")
LT = TypeVar('LT', bound='LyricsBase')


@overload
def get_full_timestamps_lyrics_data(data: LyricsData, duration: int | None, only_line: Literal[False], skip_none: Literal[True]) -> FSLyricsData:
    ...


@overload
def get_full_timestamps_lyrics_data(data: LyricsData, duration: int | None, only_line: Literal[True], skip_none: bool = False) -> LyricsData:
    ...


@overload
def get_full_timestamps_lyrics_data(data: LyricsData, duration: int | None, only_line: bool = False, skip_none: Literal[False] = False) -> LyricsData:
    ...


def get_full_timestamps_lyrics_data(data: LyricsData, duration: int | None, only_line: bool = False, skip_none: bool = False) -> LyricsData | FSLyricsData:
    """获取完整时间戳的歌词数据

    :param data: 歌词数据
    :param end_time: 歌曲结束时间
    :param only_line: 是否只推算行时间戳
    :param skip_none: 是否跳过无法推算时间戳的行
    """
    result = LyricsData([])
    fsresult = FSLyricsData([])
    for i, line in enumerate(data):
        line_start_time = line[2][0][0] if line[0] is None and line[2] and line[2][0][0] is not None else line[0]
        line_end_time = line[2][-1][1] if line[1] is None and line[2] and line[2][-1][1] is not None else line[1]
        if line_start_time is None:
            if i == 0:
                line_start_time = 0
            elif data[i - 1][1] is not None:
                line_start_time = data[i - 1][1]

        if line_end_time is None:
            if i == len(data) - 1:
                if duration is not None and line_start_time is not None:
                    if duration >= line_start_time:
                        line_end_time = duration
                else:
                    line_end_time = duration
            elif data[i + 1][0] is not None:
                line_end_time = data[i + 1][0]

        if only_line:
            if not skip_none or (line_start_time is not None and line_end_time is not None):
                result.append(LyricsLine((line_start_time, line_end_time, line[2])))
            continue

        words: list[LyricsWord] = []
        fswords = []
        for j, word in enumerate(line[2]):
            word_start_time = word[0]
            word_end_time = word[1]
            if word_start_time is None:
                if j == 0 and line_start_time is not None:
                    word_start_time = line_start_time
                elif j != 0 and line[2][j - 1][1] is not None:
                    word_start_time = line[2][j - 1][1]

            if word_end_time is None:
                if j == len(line[2]) - 1 and line_end_time is not None:
                    word_end_time = line_end_time
                elif j != len(line[2]) - 1 and line[2][j + 1][0] is not None:
                    word_end_time = line[2][j + 1][0]

            if not skip_none:
                words.append(LyricsWord((word_start_time, word_end_time, word[2])))
            else:
                if word_start_time is None or word_end_time is None:
                    continue
                fswords.append(FSLyricsWord((word_start_time, word_end_time, word[2])))

        if not skip_none:
            result.append(LyricsLine((line_start_time, line_end_time, words)))
        else:
            if line_start_time is None or line_end_time is None:
                continue
            fsresult.append(FSLyricsLine((line_start_time, line_end_time, fswords)))

    if only_line is False and skip_none is True:
        return fsresult
    return result


class LyricsBase(dict):
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
        elif self.tags.get("ti"):
            info["title"] = self.tags["ti"]
        if self.artist:
            info["artist"] = self.artist
        elif self.tags.get("ar"):
            info["artist"] = self.tags["ar"]
        if self.album:
            info["album"] = self.album
        elif self.tags.get("al"):
            info["album"] = self.tags["al"]
        if self.id:
            info["id"] = self.id
        if self.mid:
            info["mid"] = self.mid
        if self.duration:
            info["duration"] = self.duration
        if self.accesskey:
            info["accesskey"] = self.accesskey
        return info

    def update_info(self: LT, info: dict) -> LT:
        lyrics = deepcopy(self)
        mapping = {
            "title": "ti",
            "artist": "ar",
            "album": "al",
        }
        for key in self.INFO_KEYS:
            if key in info:
                lyrics[key] = info[key]

            if key in ("title", "artist", "album"):
                if key in info:
                    lyrics.tags[mapping[key]] = info[key]
                else:
                    lyrics.tags.pop(mapping[key], None)

        return lyrics

    def get_duration(self) -> int:
        if self.duration is not None:
            return self.duration * 1000
        if self.get("orig"):
            last_line = self["orig"][-1]
            last_start, last_end, last_words = last_line
            if last_end is not None:
                return last_end
            if last_words:
                last_word_start, last_word_end, _ = last_words[-1]
                if last_word_end is not None:
                    return last_word_end
                if last_word_start is not None:
                    return last_word_start
            if last_start is not None:
                return last_start
        elif self:
            for data in self.values():
                if data:
                    last_line = data[-1]
                    break
            else:
                return 0
            if last_line[1] is not None:
                return last_line[1]
            if last_line[2]:
                if last_line[2][-1][1] is not None:
                    return last_line[2][-1][1]
                if last_line[2][-1][0] is not None:
                    return last_line[2][-1][0]
            if last_line[0] is not None:
                return last_line[0]
        return 0

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

    def get_fslyrics(self, duration_ms: int | None = None) -> "FSLyrics":
        """获取完整时间戳的歌词

        :param duration_ms: 歌曲时长
        :param skip_none: 是否跳过没有时间戳的歌词
        :return: 完整时间戳的歌词
        """
        full_timestamps_lyrics = FSLyrics({"source": self.source,
                                           "title": self.title,
                                           "artist": self.artist,
                                           "album": self.album,
                                           "id": self.id,
                                           "mid": self.mid,
                                           "duration": self.duration,
                                           "accesskey": self.accesskey})

        duration = duration_ms if duration_ms else self.get_duration()
        full_timestamps_lyrics.types = self.types
        full_timestamps_lyrics.tags = self.tags
        for lang, lyrics_data in self.items():
            full_timestamps_lyrics[lang] = get_full_timestamps_lyrics_data(data=lyrics_data,
                                                                           duration=duration,
                                                                           only_line=False,
                                                                           skip_none=True)
        return full_timestamps_lyrics

    def is_inst(self) -> bool:
        """检查是否为纯歌词"""
        if 0 < len(self["orig"]) < 10:
            text = "".join(w[2] for w in self["orig"][-1][2]).strip()
            if text in ("此歌曲为没有填词的纯音乐，请您欣赏", "纯音乐，请欣赏"):
                return True
        return False


class Lyrics(LyricsBase):
    def __getitem__(self, item: str) -> LyricsData:
        return super().__getitem__(item)

    def __setitem__(self, key: str, value: LyricsData) -> None:
        super().__setitem__(key, value)

    def __delitem__(self, key: str) -> None:
        super().__delitem__(key)

    def get(self, key: str, default: T = None) -> LyricsData | T:
        return super().get(key, default)


class FSLyrics(LyricsBase):
    def __getitem__(self, item: str) -> FSLyricsData:
        return super().__getitem__(item)

    def __setitem__(self, key: str, value: FSLyricsData) -> None:
        super().__setitem__(key, value)

    def __delitem__(self, key: str) -> None:
        super().__delitem__(key)

    def get(self, key: str, default: T = None) -> FSLyricsData | T:
        return super().get(key, default)
