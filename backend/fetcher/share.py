# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import re

from backend.lyrics import LyricsData, MultiLyricsData
from utils.enum import LyricsType, Source
from utils.utils import time2ms


def judge_lyrics_type(lyrics: LyricsData) -> LyricsType:
    lyrics_type = LyricsType.PlainText
    for line in lyrics:
        if len(line[2]) > 1:
            lyrics_type = LyricsType.VERBATIM
            break

        if line[0] is not None:
            lyrics_type = LyricsType.LINEBYLINE

    return lyrics_type


def lrc2dict_list(lrc: str, source: Source | None = None, to_list: bool = False) -> tuple[dict[str, str], MultiLyricsData | LyricsData]:  # noqa: PLR0915
    lrc_lists: list[list] = [[]]
    start_time_lists: list[list] = [[]]

    def add_line_list(line_list: list[None | str | int | list]) -> None:
        for i, _lrc_list in enumerate(lrc_lists):
            if line_list[0] not in start_time_lists[i]:
                # 没有开始时间相同的歌词行
                if line_list[0] is not None:
                    lrc_lists[i].append((line_list[0], line_list[1], [tuple(word) for word in line_list[2]]))
                    start_time_lists[i].append(line_list[0])
                break
        else:
            if line_list[2]:
                lrc_lists.append([(line_list[0], line_list[1], [tuple(word) for word in line_list[2]])])
                start_time_lists.append([line_list[0]])

    tags = {}

    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")  # 标签匹配表达式
    line_split_pattern = re.compile(r"^\[(\d+):(\d+).(\d+)\](.*)$")  # 歌词行匹配表达式
    enhanced_word_split_pattern = re.compile(r"<(\d+):(\d+).(\d+)>([^<]*)(?:<(\d+):(\d+).(\d+)>$)?")
    word_split_pattern = re.compile(r"([^\[]*)(?:\[(\d+):(\d+).(\d+)\])?")

    multi_line_split_pattern = re.compile(r"^((?:\[\d+:\d+\.\d+\]){2,})(.*)$")
    timestamps_pattern = re.compile(r"\[(\d+):(\d+).(\d+)\]")

    for line in lrc.splitlines():
        line_data = line.strip()
        if not line_data or not line_data.startswith("["):
            continue

        tag_split_content = tag_split_pattern.findall(line)
        if tag_split_content:  # 标签行
            tags.update({tag_split_content[0][0]: tag_split_content[0][1]})
            continue

        line_split_content: list[str] = line_split_pattern.findall(line)
        if line_split_content:  # 歌词行
            line_list: list[None | str | int | list] = [None, None, []]
            m, s, ms, line_content = line_split_content[0]
            line_list[0] = time2ms(m, s, ms)

            if source == Source.NE:
                # 如果转换的是网易云歌词且这一行有开头有几个连在一起的时间戳表示这几个时间戳的行都是这个歌词
                multi_line_split_content = multi_line_split_pattern.findall(line)
                if multi_line_split_content:
                    # 歌词行开头有多个时间戳
                    timestamps, line_content = multi_line_split_content
                    for m, s, ms in timestamps_pattern.findall(timestamps):
                        line_list: list[None | str | int | list] = [None, None, []]
                        line_list[0] = time2ms(m, s, ms)
                        add_line_list(line_list)

            if line_content.strip().startswith("<") and line_content.strip().endswith(">"):
                # 歌词行为增强格式
                enhanced_word_split_content: list[str] = enhanced_word_split_pattern.findall(line_content)
                if enhanced_word_split_content:
                    for s_m, s_s, s_ms, word, e_m, e_s, e_ms in enhanced_word_split_content:
                        word_list = [time2ms(s_m, s_s, s_ms), None, word]  # 开始时间, 结束时间, 歌词
                        if e_m and e_s and e_ms:
                            # 结束时间存在(即行末)
                            word_list[1] = time2ms(e_m, e_s, e_ms)
                            line_list[1] = word_list[1]

                        # 添加上一字的结束时间
                        if line_list[2]:
                            line_list[2][-1][1] = word_list[0]

                        # 添加歌词字到歌词行
                        if word:
                            line_list[2].append(word_list)
            else:
                enhanced_word_split_content = None

            if not enhanced_word_split_content:
                # 歌词行不为增强格式
                word_split_content: list[str] = word_split_pattern.findall(line_content)
                if word_split_content:
                    # 逐字

                    for w_i, (word, e_m, e_s, e_ms) in enumerate(word_split_content):
                        word_list = [None, None, word]  # 开始时间, 结束时间, 歌词
                        if e_m and e_s and e_ms:
                            # 结束时间存在
                            word_list[1] = time2ms(e_m, e_s, e_ms)
                            if w_i == len(word_split_content) - 1:
                                # 当前歌词为最后一行歌词
                                line_list[1] = word_list[1]

                        # 添加开始时间
                        if not line_list[2]:
                            word_list[0] = line_list[0]
                        else:
                            word_list[0] = line_list[2][-1][1]

                        # 添加歌词字到歌词行
                        if word:
                            line_list[2].append(word_list)
                elif line_content.strip():
                    line_list[2] = [line_list[0], None, line_content]  # 开始时间, 结束时间, 歌词

            add_line_list(line_list)

    # 按起始时间排序
    for i, lrc_list in enumerate(lrc_lists):
        lrc_lists[i] = sorted(lrc_list, key=lambda x: x[0])
        for i_, line_list in enumerate(lrc_lists[i]):
            if i_ != 0 and lrc_lists[i][i_ - 1][1] is None and line_list[0] is not None:
                # 上一行歌词结束时间不存在, 当前行歌词开始时间存在, 则上一行歌词结束时间等于当前行歌词开始时间
                lrc_lists[i][i_ - 1] = (lrc_lists[i][i_ - 1][0], line_list[0], lrc_lists[i][i_ - 1][2])

    lrc_lists: list[LyricsData]

    if to_list:
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

    if not lrc_lists:
        return None, {}
    if len(lrc_lists) == 1:
        return tags, {"orig": lrc_lists[0]}

    type0 = judge_lyrics_type(lrc_lists[0])
    type1 = judge_lyrics_type(lrc_lists[1])

    if len(lrc_lists) == 2:
        if type0 == LyricsType.VERBATIM and type1 == LyricsType.VERBATIM:
            return tags, {"roma": lrc_lists[0], "orig": lrc_lists[1]}
        return tags, {"orig": lrc_lists[0], "ts": lrc_lists[1]}
    return tags, {"roma": lrc_lists[0], "orig": lrc_lists[1], "ts": lrc_lists[2]}


def plaintext2list(plaintext: str) -> list[list[None, None, list[None, None, str]]]:
    lrc_list: LyricsData = []
    for line in plaintext.splitlines():
        lrc_list.append((None, None, [(None, None, line)]))
    return lrc_list
