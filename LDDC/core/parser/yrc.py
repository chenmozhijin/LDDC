# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

from LDDC.common.models import LyricsData, LyricsLine, LyricsWord


def yrc2list(yrc: str) -> LyricsData:
    """将yrc转换为列表[(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]"""
    lrc_list = LyricsData([])

    line_split_pattern = re.compile(r'^\[(\d+),(\d+)\](.*)$')  # 逐行匹配
    wrods_split_pattern = re.compile(r'(?:\[\d+,\d+\])?\((\d+),(\d+),\d+\)((?:.(?!\d+,\d+,\d+\)))*)')  # 逐字匹配
    for i in yrc.splitlines():
        line = i.strip()
        if not line.startswith("["):
            continue

        line_split_content = re.findall(line_split_pattern, line)
        if not line_split_content:
            continue
        line_start_time, line_duration, line_content = line_split_content[0]
        lrc_list.append(LyricsLine(int(line_start_time), int(line_start_time) + int(line_duration), []))

        wrods_split_content = re.findall(wrods_split_pattern, line_content)
        if not wrods_split_content:
            lrc_list[-1][2].append(LyricsWord(int(line_start_time), int(line_start_time) + int(line_duration), line_content))
            continue

        for word_start_time, word_duration, word_content in wrods_split_content:
            lrc_list[-1][2].append(LyricsWord(int(word_start_time), int(word_start_time) + int(word_duration), word_content))

    return lrc_list
