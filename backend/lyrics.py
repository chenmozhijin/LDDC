# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from typing import TYPE_CHECKING, NewType

if TYPE_CHECKING:
    from utils.enum import Source

LyricsWord = NewType("LyricsWord", tuple[int | None, int | None, str])
LyricsLine = NewType("LyricsLine", tuple[int | None, int | None, list[LyricsWord]])
LyricsData = NewType("LyricsData", list[LyricsLine])
MultiLyricsData = NewType("MultiLyricsData", dict[str, LyricsData])


def get_full_timestamps_lyrics_data(data: LyricsData, end_time: int | None, only_line: bool = False) -> LyricsData:
    """获取完整时间戳的歌词数据

    :param data: 歌词数据
    :param end_time: 歌曲结束时间
    :param only_line: 是否只推算行时间戳
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

        if line_end_time is None:
            if i == len(data) - 1:
                line_end_time = end_time
            elif data[i + 1][0] is not None:
                line_end_time = data[i + 1][0]

        if only_line:
            result.append(LyricsLine((line_start_time, line_end_time, line[2])))

        words = []
        for j, word in enumerate(line[2]):
            word_start_time = word[0]
            word_end_time = word[1]
            if word_start_time is None:
                if j == 0 and line_start_time:
                    word_start_time = line_start_time
                elif j != 0 and line[2][j - 1][1] is not None:
                    word_start_time = line[2][j - 1][1]

            if word_end_time is None:
                if j == len(line[2]) - 1 and line_end_time:
                    word_end_time = line_end_time
                elif j != len(line[2]) - 1 and line[2][j + 1][0] is not None:
                    word_end_time = line[2][j + 1][0]

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

    def add_offset(self, multi_lyrics_data: MultiLyricsData | None = None, offset: int = 0) -> MultiLyricsData:
        """添加偏移量

        :param multi_lyrics_data:歌词
        :param offset:偏移量
        :return: 偏移后的歌词
        """
        if not multi_lyrics_data:
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

    def get_full_timestamps_lyrics(self) -> "Lyrics":
        """获取完整时间戳的歌词"""
        full_timestamps_lyrics = Lyrics({"source": self.source,
                                         "title": self.title,
                                         "artist": self.artist,
                                         "album": self.album,
                                         "id": self.id,
                                         "mid": self.mid,
                                         "duration": self.duration,
                                         "accesskey": self.accesskey})

        full_timestamps_lyrics.types = self.types
        full_timestamps_lyrics.tags = self.tags
        for lang, lyrics_data in self.items():
            full_timestamps_lyrics[lang] = get_full_timestamps_lyrics_data(data=lyrics_data,
                                                                           end_time=self.duration * 1000 if self.duration else None,
                                                                           only_line=False)
        return full_timestamps_lyrics
