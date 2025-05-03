# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

from LDDC.common.models import LyricsData, LyricsLine, LyricsType, LyricsWord, MultiLyricsData, Source
from LDDC.common.time import time2ms

from .utils import judge_lyrics_type

_TAG_SPLIT_PATTERN = re.compile(r"^\[(?P<k>\w+):(?P<v>[^\]]*)\]$")  # 标签匹配表达式
_LINE_SPLIT_PATTERN = re.compile(r"^\[(\d+):(\d+)\.(\d+)\](.*)$")  # 歌词行匹配表达式
_ENHANCED_WORD_SPLIT_PATTERN = re.compile(r"<(\d+):(\d+)\.(\d+)>((?:(?!<\d+:\d+\.\d+>).)*)(?:<(\d+):(\d+)\.(\d+)>$)?")
_WORD_SPLIT_PATTERN = re.compile(r"((?:(?!\[\d+:\d+\.\d+\]).)*)(?:\[(\d+):(\d+)\.(\d+)\])?")  # 歌词字匹配表达式
_MULTI_LINE_SPLIT_PATTERN = re.compile(r"^((?:\[\d+:\d+\.\d+\]){2,})(.*)$")
_TIMESTAMPS_PATTERN = re.compile(r"\[(\d+):(\d+)\.(\d+)\]")


def _lrc2list_data(lrc: str, source: Source | None = None) -> tuple[dict[str, str], list[LyricsData]]:
    """将普通LRC、增强型LRC、逐字LRC、网易云非标准LRC转换为LyricsData列表

    Args:
        lrc (str): LRC字符串
        source (Source | None, optional): LRC来源. Defaults to None.

    Returns:
        tuple[dict[str, str], list[LyricsData]]: 标签字典, LyricsData列表

    """
    lrc_lists: list[LyricsData] = [LyricsData([])]
    start_time_lists: list[list] = [[]]

    def add_line(line: LyricsLine) -> None:
        for i, lrc_list in enumerate(lrc_lists):
            if line.start not in start_time_lists[i]:
                # 没有开始时间相同的歌词行
                if line.start is not None:
                    lrc_list.append(line)
                    start_time_lists[i].append(line.start)
                break
        else:
            if line[2]:
                lrc_lists.append(LyricsData([line]))
                start_time_lists.append([line.start])

    tags = {}

    for raw_line in lrc.splitlines():
        line = raw_line.strip()
        if not line or not line.startswith("["):
            continue

        if line_match := _LINE_SPLIT_PATTERN.match(line):  # 歌词行处理
            m, s, ms, line_content = line_match.groups()
            start, end, words = time2ms(m, s, ms), None, []
            words: list[LyricsWord]

            if source == Source.NE and (multi_match := _MULTI_LINE_SPLIT_PATTERN.match(line)):
                # 如果转换的是网易云歌词且这一行有开头有几个连在一起的时间戳表示这几个时间戳的行都是这个歌词
                timestamps, line_content = multi_match.groups()
                # 歌词行开头有多个时间戳
                for ts_match in _TIMESTAMPS_PATTERN.finditer(timestamps):
                    start = time2ms(*ts_match.groups())
                    add_line(LyricsLine(start, None, [LyricsWord(start, None, line_content)]))
                continue

            if "<" in line_content and ">" in line_content:
                # 歌词行为增强格式
                for enhanced_word_parts in _ENHANCED_WORD_SPLIT_PATTERN.finditer(line_content):
                    s_m, s_s, s_ms, word_str, e_m, e_s, e_ms = enhanced_word_parts.groups()
                    word_start = time2ms(s_m, s_s, s_ms)
                    word_end = time2ms(e_m, e_s, e_ms) if e_m and e_s and e_ms else None
                    end = word_end or end

                    # 添加上一字的结束时间
                    if words:  # 上一字存在
                        words[-1] = LyricsWord(words[-1][0], word_start, words[-1][2])

                    # 添加歌词字到歌词行
                    if word_str:
                        words.append(LyricsWord(word_start, word_end, word_str))
            else:
                # 歌词行不为增强格式
                word_parts = _WORD_SPLIT_PATTERN.findall(line_content)
                if word_parts:
                    # 逐字
                    for w_i, (word_str, e_m, e_s, e_ms) in enumerate(word_parts):
                        word_start = start if not words else words[-1].end
                        word_end = time2ms(e_m, e_s, e_ms) if e_m and e_s and e_ms else None
                        if w_i == len(word_parts) - 1:  # 当前歌词为最后一行歌词
                            end = word_end or end

                        # 添加歌词字到歌词行
                        if word_str:
                            words.append(LyricsWord(word_start, word_end, word_str))

            add_line(LyricsLine(start, end, words))
            continue

        if tag_match := _TAG_SPLIT_PATTERN.match(line):  # 标签行处理
            tags[tag_match.group("k")] = tag_match.group("v")
            continue

    # 按起始时间排序
    for i, lrc_list in enumerate(lrc_lists):
        lrc_lists[i] = LyricsData(sorted([line for line in lrc_list if line.start is not None], key=lambda x: x.start))  # type: ignore[]  已确保line.start不为None
        for i_, line in enumerate(lrc_lists[i]):
            if i_ != 0 and lrc_lists[i][i_ - 1].end is None and line.start is not None:
                # 上一行歌词结束时间不存在, 当前行歌词开始时间存在, 则上一行歌词结束时间等于当前行歌词开始时间
                lrc_lists[i][i_ - 1] = LyricsLine(lrc_lists[i][i_ - 1].start, line.start, lrc_lists[i][i_ - 1].words)

        # 清除空行
        lrc_lists[i] = LyricsData([line for line in lrc_lists[i] if line.words])

    return tags, lrc_lists


def lrc2mdata(lrc: str, source: Source | None = None) -> tuple[dict[str, str], MultiLyricsData]:
    tags, lrc_lists = _lrc2list_data(lrc, source)

    if not lrc_lists:
        return {}, MultiLyricsData({})
    if len(lrc_lists) == 1:
        return tags, MultiLyricsData({"orig": lrc_lists[0]})

    if len(lrc_lists) == 2:
        if judge_lyrics_type(lrc_lists[0]) == LyricsType.VERBATIM and judge_lyrics_type(lrc_lists[1]) == LyricsType.VERBATIM:
            return tags, MultiLyricsData({"roma": lrc_lists[0], "orig": lrc_lists[1]})
        return tags, MultiLyricsData({"orig": lrc_lists[0], "ts": lrc_lists[1]})
    return tags, MultiLyricsData({"roma": lrc_lists[0], "orig": lrc_lists[1], "ts": lrc_lists[2]})


def lrc2data(lrc: str, source: Source | None = None) -> tuple[dict[str, str], LyricsData]:
    tags, lrc_lists = _lrc2list_data(lrc, source)
    # 合并为一个LyricsData
    for i, lrc_list in enumerate(lrc_lists):
        if i == 0:
            continue
        for line_list1 in lrc_list:
            for line_list2 in reversed(lrc_lists[0]):
                if line_list1[0] == line_list2[0]:
                    # 歌词行起始时间相同,向后插入
                    lrc_lists[0].insert(lrc_lists[0].index(line_list2) + 1, line_list1)
                    break
    return tags, lrc_lists[0]
