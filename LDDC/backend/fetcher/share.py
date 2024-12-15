# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

from LDDC.backend.lyrics import LyricsData, LyricsLine, LyricsWord, MultiLyricsData
from LDDC.utils.enum import LyricsType, Source
from LDDC.utils.utils import time2ms


def judge_lyrics_type(lyrics: LyricsData) -> LyricsType:
    lyrics_type = LyricsType.PlainText
    for line in lyrics:
        if len(line[2]) > 1:
            lyrics_type = LyricsType.VERBATIM
            break

        if line[0] is not None:
            lyrics_type = LyricsType.LINEBYLINE

    return lyrics_type


def _lrc2list_list(lrc: str, source: Source | None = None) -> tuple[dict[str, str], list[LyricsData]]:
    lrc_lists: list[LyricsData] = [LyricsData([])]
    start_time_lists: list[list] = [[]]

    def add_line(line: LyricsLine) -> None:
        for i, lrc_list in enumerate(lrc_lists):
            if line[0] not in start_time_lists[i]:
                # 没有开始时间相同的歌词行
                if line[0] is not None:
                    lrc_list.append(line)
                    start_time_lists[i].append(line[0])
                break
        else:
            if line[2]:
                lrc_lists.append(LyricsData([line]))
                start_time_lists.append([line[0]])

    tags = {}

    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")  # 标签匹配表达式
    line_split_pattern = re.compile(r"^\[(\d+):(\d+).(\d+)\](.*)$")  # 歌词行匹配表达式
    enhanced_word_split_pattern = re.compile(r"<(\d+):(\d+).(\d+)>([^<]*)(?:<(\d+):(\d+).(\d+)>$)?")
    word_split_pattern = re.compile(r"([^\[]*)(?:\[(\d+):(\d+).(\d+)\])?")

    multi_line_split_pattern = re.compile(r"^((?:\[\d+:\d+\.\d+\]){2,})(.*)$")
    timestamps_pattern = re.compile(r"\[(\d+):(\d+).(\d+)\]")

    for line_str in lrc.splitlines():
        line_data = line_str.strip()
        if not line_data or not line_data.startswith("["):
            continue

        line_split_content: list[str] = line_split_pattern.findall(line_str)
        if line_split_content:  # 歌词行
            m, s, ms, line_content = line_split_content[0]
            start, end, words = time2ms(m, s, ms), None, []

            if source == Source.NE:
                # 如果转换的是网易云歌词且这一行有开头有几个连在一起的时间戳表示这几个时间戳的行都是这个歌词
                multi_line_split_content = multi_line_split_pattern.findall(line_str)
                if multi_line_split_content:
                    # 歌词行开头有多个时间戳
                    timestamps, line_content = multi_line_split_content[0]
                    for m, s, ms in timestamps_pattern.findall(timestamps):
                        start = time2ms(m, s, ms)
                        add_line(LyricsLine((start, None, [LyricsWord((start, None, line_content))])))
                    continue

            if "<" in line_content and ">" in line_content:
                # 歌词行为增强格式
                enhanced_word_split_content: list[str] | None = enhanced_word_split_pattern.findall(line_content)
                if enhanced_word_split_content:
                    for s_m, s_s, s_ms, word_str, e_m, e_s, e_ms in enhanced_word_split_content:
                        word_start, word_end = time2ms(s_m, s_s, s_ms), None
                        if e_m and e_s and e_ms:
                            # 结束时间存在(即行末)
                            word_end = time2ms(e_m, e_s, e_ms)
                            end = word_end

                        # 添加上一字的结束时间
                        if words:  # 上一字存在
                            words[-1] = LyricsWord((words[-1][0], word_start, words[-1][2]))

                        # 添加歌词字到歌词行
                        if word_str:
                            words.append(LyricsWord((word_start, word_end, word_str)))
            else:
                enhanced_word_split_content = None

            if not enhanced_word_split_content:
                # 歌词行不为增强格式
                word_split_content: list[str] = word_split_pattern.findall(line_content)
                if word_split_content:
                    # 逐字

                    for w_i, (word_str, e_m, e_s, e_ms) in enumerate(word_split_content):
                        word_start, word_end = None, None
                        if e_m and e_s and e_ms:
                            # 结束时间存在
                            word_end = time2ms(e_m, e_s, e_ms)
                            if w_i == len(word_split_content) - 1:
                                # 当前歌词为最后一行歌词
                                end = word_end

                        # 添加开始时间
                        word_start = start if not words else words[-1][1]

                        # 添加歌词字到歌词行
                        if word_str:
                            words.append(LyricsWord((word_start, word_end, word_str)))
                elif line_content.strip():
                    words = [LyricsWord((start, None, line_content))]  # 开始时间, 结束时间, 歌词

            add_line(LyricsLine((start, end, words)))
            continue

        tag_split_content = tag_split_pattern.findall(line_str)
        if tag_split_content:  # 标签行
            tags.update({tag_split_content[0][0]: tag_split_content[0][1]})

    # 按起始时间排序
    for i, lrc_list in enumerate(lrc_lists):
        lrc_lists[i] = LyricsData(sorted((line for line in lrc_list if line[0] is not None), key=lambda x: x[0]))  # type: ignore[]
        for i_, line in enumerate(lrc_lists[i]):
            if i_ != 0 and lrc_lists[i][i_ - 1][1] is None and line[0] is not None:
                # 上一行歌词结束时间不存在, 当前行歌词开始时间存在, 则上一行歌词结束时间等于当前行歌词开始时间
                lrc_lists[i][i_ - 1] = LyricsLine((lrc_lists[i][i_ - 1][0], line[0], lrc_lists[i][i_ - 1][2]))

        # 清除空行
        lrc_lists[i] = LyricsData([line for line in lrc_lists[i] if line[2]])

    return tags, lrc_lists


def lrc2dict(lrc: str, source: Source | None = None) -> tuple[dict[str, str], MultiLyricsData]:
    tags, lrc_lists = _lrc2list_list(lrc, source)

    if not lrc_lists:
        return {}, MultiLyricsData({})
    if len(lrc_lists) == 1:
        return tags, MultiLyricsData({"orig": lrc_lists[0]})

    type0 = judge_lyrics_type(lrc_lists[0])
    type1 = judge_lyrics_type(lrc_lists[1])

    if len(lrc_lists) == 2:
        if type0 == LyricsType.VERBATIM and type1 == LyricsType.VERBATIM:
            return tags, MultiLyricsData({"roma": lrc_lists[0], "orig": lrc_lists[1]})
        return tags, MultiLyricsData({"orig": lrc_lists[0], "ts": lrc_lists[1]})
    return tags, MultiLyricsData({"roma": lrc_lists[0], "orig": lrc_lists[1], "ts": lrc_lists[2]})


def lrc2list(lrc: str, source: Source | None = None) -> tuple[dict[str, str], LyricsData]:
    tags, lrc_lists = _lrc2list_list(lrc, source)
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


def plaintext2list(plaintext: str) -> LyricsData:
    lrc_list = LyricsData([])
    for line in plaintext.splitlines():
        lrc_list.append(LyricsLine((None, None, [LyricsWord((None, None, line))])))
    return lrc_list
