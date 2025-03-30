# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from collections import UserDict
from collections.abc import MutableMapping
from dataclasses import replace
from typing import Literal, NamedTuple, NewType, TypeVar, overload

from ._enums import Language, LyricsFormat, LyricsType, Source
from ._info import Artist, LyricInfo, SongInfo


class LyricsWord(NamedTuple):
    start: int | None
    end: int | None
    text: str


class LyricsLine(NamedTuple):
    start: int | None
    end: int | None
    words: list[LyricsWord]


LyricsData = NewType("LyricsData", list[LyricsLine])
MultiLyricsData = NewType("MultiLyricsData", MutableMapping[str, LyricsData])


# FS 是 full_timestamps 的缩写
class FSLyricsWord(NamedTuple):
    start: int
    end: int
    text: str


class FSLyricsLine(NamedTuple):
    start: int
    end: int
    words: list[FSLyricsWord]


FSLyricsData = NewType("FSLyricsData", list[FSLyricsLine])
FSMultiLyricsData = NewType("FSMultiLyricsData", MutableMapping[str, FSLyricsData])


@overload
def get_full_timestamps_lyrics_data(data: LyricsData, duration: int | None, only_line: Literal[False], skip_none: Literal[True]) -> FSLyricsData: ...


@overload
def get_full_timestamps_lyrics_data(data: LyricsData, duration: int | None, only_line: Literal[True], skip_none: bool = False) -> LyricsData: ...


@overload
def get_full_timestamps_lyrics_data(data: LyricsData, duration: int | None, only_line: bool = False, skip_none: Literal[False] = False) -> LyricsData: ...


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
        # 处理行级时间戳
        line_start_time = line.start or (line.words[0].start if line.words else None)
        line_end_time = line.end or (line.words[-1].end if line.words else None)

        # 推算行开始时间
        if line_start_time is None:
            line_start_time = 0 if i == 0 else data[i - 1].end

        # 推算行结束时间
        if line_end_time is None:
            line_end_time = (
                (duration if duration is not None and line_start_time is not None and duration >= line_start_time else None)
                if i == len(data) - 1
                else data[i + 1].start
            )

        # 处理仅行时间戳模式
        if only_line:
            if not skip_none or (line_start_time is not None and line_end_time is not None):
                result.append(LyricsLine(line_start_time, line_end_time, line[2]))
            continue

        # 处理单词级时间戳
        words: list[LyricsWord] = []
        fswords: list[FSLyricsWord] = []
        for j, word in enumerate(line.words):
            # 推算单词开始时间
            word_start_time = (line_start_time if j == 0 else line.words[j - 1].end) if word.start is None else word.start

            # 推算单词结束时间
            word_end_time = (line_end_time if j == len(line.words) - 1 else line.words[j + 1].start) if word.end is None else word.end

            if skip_none:
                if word_start_time is None or word_end_time is None:  # 跳过无效时间戳
                    continue
                fswords.append(FSLyricsWord(word_start_time, word_end_time, word.text))
            else:
                words.append(LyricsWord(word_start_time, word_end_time, word.text))

        # 添加有效歌词行
        if not skip_none:
            result.append(LyricsLine(line_start_time, line_end_time, words))
        elif line_start_time is not None and line_end_time is not None:
            fsresult.append(FSLyricsLine(line_start_time, line_end_time, fswords))

    return fsresult if (not only_line and skip_none) else result


VT = TypeVar("VT", LyricsData, FSLyricsData)


class LyricsBase(UserDict[str, VT]):
    __slots__ = ("tags", "types")

    def __init__(self, info: SongInfo | LyricInfo) -> None:
        super().__init__()
        if isinstance(info, SongInfo):
            self.info = LyricInfo(
                source=info.source,
                songinfo=info,
            )
        elif isinstance(info, LyricInfo):
            self.info = replace(info, data=None)

        self.types: dict[str, LyricsType] = {}
        self.tags: dict[str, str] = {}

    @property
    def source(self) -> Source:
        return self.info.source

    @property
    def title(self) -> str | None:
        return self.info.songinfo.title or self.tags.get("ti")

    @property
    def artist(self) -> Artist:
        return self.info.songinfo.artist or Artist(self.tags["ar"]) if "ar" in self.tags else Artist([])

    @property
    def album(self) -> str | None:
        return self.info.songinfo.album or self.tags.get("al")

    @property
    def id(self) -> int | str | None:
        return self.info.id or self.info.songinfo.id

    @property
    def mid(self) -> str | None:
        return self.info.songinfo.mid

    @property
    def duration(self) -> int | None:
        return self.info.duration

    @property
    def cached(self) -> bool:
        return self.info.cached

    def __bool__(self) -> bool:
        return any(lyric for lyric in self.values())

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
            if last_line.end is not None:
                return last_line.end
            if last_line.words:
                if last_line.words[-1].end is not None:
                    return last_line.words[-1].end
                if last_line.words[-1].start is not None:
                    return last_line.words[-1].start
            if last_line.start is not None:
                return last_line.start
        return 0

    @overload
    def add_offset(self: "FSLyrics", offset: int = 0) -> FSMultiLyricsData: ...

    @overload
    def add_offset(self: "Lyrics | LyricsBase", offset: int = 0) -> MultiLyricsData: ...

    def add_offset(self, offset: int = 0) -> MultiLyricsData | FSMultiLyricsData:
        """添加偏移量

        :param offset:偏移量
        :return: 偏移后的歌词数据
        """

        @overload
        def adjust_time(t: int) -> int: ...

        @overload
        def adjust_time(t: None) -> None: ...

        def adjust_time(t: int | None) -> int | None:
            return max(t + offset, 0) if t is not None else None

        if isinstance(self, FSLyrics):
            return FSMultiLyricsData(
                {
                    lang: FSLyricsData(
                        [
                            FSLyricsLine(
                                adjust_time(line.start),
                                adjust_time(line.end),
                                [
                                    FSLyricsWord(
                                        adjust_time(word.start),
                                        adjust_time(word.end),
                                        word.text,
                                    )
                                    for word in line.words
                                ],
                            )
                            for line in lines
                        ],
                    )
                    for lang, lines in self.items()
                },
            )

        return MultiLyricsData(
            {
                lang: LyricsData(
                    [
                        LyricsLine(
                            adjust_time(line.start),
                            adjust_time(line.end),
                            [
                                LyricsWord(
                                    adjust_time(word.start),
                                    adjust_time(word.end),
                                    word.text,
                                )
                                for word in line.words
                            ],
                        )
                        for line in lines
                    ],
                )
                for lang, lines in self.items()
            },
        )

    def is_inst(self) -> bool:
        """检查是否为纯歌词"""
        if self.info.songinfo.language == Language.INSTRUMENTAL:
            return True
        if 0 < len(self["orig"]) < 10:
            text = "".join(w.text for w in self["orig"][-1].words).strip()
            if text in ("此歌曲为没有填词的纯音乐，请您欣赏", "纯音乐，请欣赏"):
                return True
        return False
    def to(self, lyrics_format: LyricsFormat, langs: list[str] | None, offset: int = 0) -> str:
        """将歌词转换为指定格式"""
        from LDDC.core.converter import convert2

        return convert2(lyrics=self, lyrics_format=lyrics_format, langs=langs, offset=offset)


class Lyrics(LyricsBase[LyricsData]):
    """普通歌词类型(允许空时间戳)"""

    def get_fslyrics(self, duration_ms: int | None = None) -> "FSLyrics":
        """获取完整时间戳的歌词

        :param duration_ms: 歌曲时长
        :param skip_none: 是否跳过没有时间戳的歌词
        :return: 完整时间戳的歌词
        """
        full_timestamps_lyrics = FSLyrics(self.info)

        duration = duration_ms if duration_ms else self.get_duration()
        full_timestamps_lyrics.types = self.types
        full_timestamps_lyrics.tags = self.tags
        for lang, lyrics_data in self.items():
            full_timestamps_lyrics[lang] = get_full_timestamps_lyrics_data(data=lyrics_data, duration=duration, only_line=False, skip_none=True)
        return full_timestamps_lyrics

    def set_data(self, data: MultiLyricsData) -> None:
        for lang, lyrics_data in data.items():
            self[lang] = lyrics_data

    @classmethod
    def get_inst_lyrics(cls, info: SongInfo | LyricInfo) -> "Lyrics":
        lyrics = Lyrics(info)
        lyrics["orig"] = LyricsData([LyricsLine(None, None, [LyricsWord(None, None, "纯音乐，请欣赏")])])
        return lyrics


class FSLyrics(LyricsBase[FSLyricsData]):
    """完整时间戳歌词类型"""

    def set_data(self, data: FSMultiLyricsData) -> None:
        for lang, lyrics_data in data.items():
            self[lang] = lyrics_data
