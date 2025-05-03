# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

from LDDC.common.models import LyricsData, LyricsLine, LyricsWord

_LINE_SPLIT_PATTERN = re.compile(r"^\[(\d+),(\d+)\](.*)$")  # 逐行匹配
_WORD_SPLIT_PATTERN = re.compile(r"(?:\[\d+,\d+\])?\((?P<start>\d+),(?P<duration>\d+),\d+\)(?P<content>(?:.(?!\d+,\d+,\d+\)))*)")  # 逐字匹配


def yrc2data(yrc: str) -> LyricsData:
    """将yrc转换为列表[(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]"""
    lrc_list = LyricsData([])

    for raw_line in yrc.splitlines():
        line = raw_line.strip()
        if not line.startswith("["):
            continue

        line_match = _LINE_SPLIT_PATTERN.match(line)
        if not line_match:
            continue
        line_start, line_duration, line_content = line_match.groups()
        line_start = int(line_start)
        line_end = line_start + int(line_duration)

        words = [
            LyricsWord(int(word_match.group("start")), int(word_match.group("start")) + int(word_match.group("duration")), word_match.group("content"))
            for word_match in _WORD_SPLIT_PATTERN.finditer(line_content)
        ]
        if not words:
            words = [LyricsWord(line_start, line_end, line_content)]

        lrc_list.append(LyricsLine(line_start, line_end, words))

    return lrc_list
