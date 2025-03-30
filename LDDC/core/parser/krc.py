# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import re
from base64 import b64decode

from LDDC.common.models import LyricsData, LyricsLine, LyricsWord, MultiLyricsData

KRC_MAGICHEADER = b"krc18"


def krc2dict(krc: str) -> tuple[dict, MultiLyricsData]:
    """将明文krc转换为字典{歌词类型: [(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]}."""
    lrc_dict = MultiLyricsData({})
    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")
    tags: dict[str, str] = {}

    line_split_pattern = re.compile(r"^\[(\d+),(\d+)\](.*)$")  # 逐行匹配
    wrods_split_pattern = re.compile(r"(?:\[\d+,\d+\])?<(\d+),(\d+),\d+>((?:.(?!\d+,\d+,\d+>))*)")  # 逐字匹配
    orig_list = LyricsData([])  # 原文歌词
    roma_list = LyricsData([])
    ts_list = LyricsData([])

    for i in krc.splitlines():
        line = i.strip()
        if not line.startswith("["):
            continue

        tag_split_content = re.findall(tag_split_pattern, line)
        if tag_split_content:  # 标签行
            tags.update({tag_split_content[0][0]: tag_split_content[0][1]})
            continue

        line_split_content = re.findall(line_split_pattern, line)
        if not line_split_content:
            continue
        line_start_time, line_duration, line_content = line_split_content[0]
        orig_list.append(LyricsLine(int(line_start_time), int(line_start_time) + int(line_duration), []))

        wrods_split_content = re.findall(wrods_split_pattern, line_content)
        if not wrods_split_content:
            orig_list[-1].words.append(LyricsWord(int(line_start_time), int(line_start_time) + int(line_duration), line_content))
            continue

        for word_start_time, word_duration, word_content in wrods_split_content:
            orig_list[-1].words.append(
                LyricsWord(int(line_start_time) + int(word_start_time), int(line_start_time) + int(word_start_time) + int(word_duration), word_content),
            )

    if "language" in tags and tags["language"].strip() != "":
        languages = json.loads(b64decode(tags["language"].strip()))
        for language in languages["content"]:
            if language["type"] == 0:  # 逐字(罗马音)
                offset = 0  # 用于跳过一些没有内容的行,它们不会存在与罗马音的字典中
                for i, line in enumerate(orig_list):
                    if "".join([w.text for w in line.words]) == "":
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

    tags_str = ""
    for key, value in tags.items():
        if key in ["al", "ar", "au", "by", "offset", "ti"]:
            tags_str += f"[{key}:{value}]\n"

    for key, lrc_list in ({"orig": orig_list, "roma": roma_list, "ts": ts_list}).items():
        if lrc_list:
            lrc_dict[key] = lrc_list
    return tags, lrc_dict
