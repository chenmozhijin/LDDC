# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

from LDDC.common.exceptions import LyricsProcessingError
from LDDC.common.logger import logger
from LDDC.common.models import LyricsData, LyricsLine, LyricsWord

from .lrc import lrc2list
from .utils import plaintext2list

QRC_PATTERN = re.compile(r'<Lyric_1 LyricType="1" LyricContent="(?P<content>.*?)"/>', re.DOTALL)
QRC_MAGICHEADER = b'\x98%\xb0\xac\xe3\x02\x83h\xe8\xfcl'

def qrc2list(s_qrc: str) -> tuple[dict, LyricsData]:
    """将qrc转换为列表LyricsData"""
    m_qrc = QRC_PATTERN.search(s_qrc)
    if not m_qrc or not m_qrc.group("content"):
        msg = "不支持的歌词格式"
        raise LyricsProcessingError(msg)
    qrc: str = m_qrc.group("content")
    qrc_lines = qrc.split('\n')
    tags = {}
    lrc_list = LyricsData([])
    wrods_split_pattern = re.compile(r'(?:\[\d+,\d+\])?((?:(?!\(\d+,\d+\)).)+)\((\d+),(\d+)\)')  # 逐字匹配
    line_split_pattern = re.compile(r'^\[(\d+),(\d+)\](.*)$')  # 逐行匹配
    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")

    for i in qrc_lines:
        line = i.strip()
        line_split_content = re.findall(line_split_pattern, line)
        if line_split_content:  # 判断是否为歌词行
            line_start_time, line_duration, line_content = line_split_content[0]
            lrc_list.append(LyricsLine(int(line_start_time), int(line_start_time) + int(line_duration), []))
            wrods_split_content = re.findall(wrods_split_pattern, line)
            if wrods_split_content:  # 判断是否为逐字歌词
                for text, starttime, duration in wrods_split_content:
                    if text != "\r":
                        lrc_list[-1].words.append(LyricsWord(int(starttime), int(starttime) + int(duration), text))
            else:  # 如果不是逐字歌词
                lrc_list[-1].words.append(LyricsWord(int(line_start_time), int(line_start_time) + int(line_duration), line_content))
        else:
            tag_split_content = re.findall(tag_split_pattern, line)
            if tag_split_content:
                tags.update({tag_split_content[0][0]: tag_split_content[0][1]})

    return tags, lrc_list


def qrc_str_parse(lyric: str) -> tuple[dict, LyricsData]:
    if re.search(r'<Lyric_1 LyricType="1" LyricContent="(.*?)"/>', lyric, re.DOTALL):
        return qrc2list(lyric)
    if "[" in lyric and "]" in lyric:
        try:
            return lrc2list(lyric)
        except Exception:
            logger.exception("尝试将歌词以lrc格式解析时失败,解析为纯文本")
    return {}, plaintext2list(lyric)
