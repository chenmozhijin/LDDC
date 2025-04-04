# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import re
from base64 import b64decode

from LDDC.common.models import LyricsData, LyricsLine, LyricsWord, MultiLyricsData

KRC_MAGICHEADER = b"krc18"

_TAG_SPLIT_PATTERN = re.compile(r"^\[(\w+):([^\]]*)\]$")
_LINE_SPLIT_PATTERN = re.compile(r"^\[(\d+),(\d+)\](.*)$")  # 逐行匹配
_WORD_SPLIT_PATTERN = re.compile(r"(?:\[\d+,\d+\])?<(?P<start>\d+),(?P<duration>\d+),\d+>(?P<content>(?:.(?!\d+,\d+,\d+>))*)")  # 逐字匹配


def krc2mdata(krc: str) -> tuple[dict, MultiLyricsData]:
    """将明文krc转换为字典{歌词类型: [(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]}."""
    lrc_dict = MultiLyricsData({})
    tags: dict[str, str] = {}

    orig_list = LyricsData([])  # 原文歌词
    roma_list = LyricsData([])
    ts_list = LyricsData([])

    for raw_line in krc.splitlines():
        line = raw_line.strip()
        if not line.startswith("["):
            continue

        if tag_match := _TAG_SPLIT_PATTERN.match(line):
            tags[tag_match.group(1)] = tag_match.group(2)
            continue

        if line_match := _LINE_SPLIT_PATTERN.match(line):
            line_start, line_duration, line_content = line_match.groups()
            line_start = int(line_start)
            line_end = line_start + int(line_duration)

            words = [
                LyricsWord(
                    line_start + int(word_match.group("start")),
                    line_start + int(word_match.group("start")) + int(word_match.group("duration")),
                    word_match.group("content"),
                )
                for word_match in _WORD_SPLIT_PATTERN.finditer(line_content)
            ]
            if not words:
                words = [LyricsWord(line_start, line_end, line_content)]

            orig_list.append(LyricsLine(line_start, line_end, words))

    if "language" in tags and tags["language"].strip() != "":
        languages = json.loads(b64decode(tags["language"].strip()))
        for language in languages["content"]:
            if language["type"] == 0:  # 逐字(罗马音)
                offset = 0  # 用于跳过一些没有内容的行,它们不会存在与罗马音的字典中
                for i, line in enumerate(orig_list):
                    if all(not w.text for w in line.words):
                        # 如果该行没有内容,则跳过
                        offset += 1
                        continue

                    roma_list.append(
                        LyricsLine(
                            line.start,
                            line.end,
                            [LyricsWord(word.start, word.end, language["lyricContent"][i - offset][j]) for j, word in enumerate(line.words)],
                        ),
                    )
            elif language["type"] == 1:  # 逐行(翻译)
                for i, line in enumerate(orig_list):
                    ts_list.append(LyricsLine(line.start, line.end, [LyricsWord(line.start, line.end, language["lyricContent"][i][0])]))

    for key, lrc_list in ({"orig": orig_list, "roma": roma_list, "ts": ts_list}).items():
        if lrc_list:
            lrc_dict[key] = lrc_list
    return tags, lrc_dict
