# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

from LDDC.backend.api import qm_get_lyrics
from LDDC.backend.decryptor import qrc_decrypt
from LDDC.backend.lyrics import Lyrics, LyricsData, LyricsLine, LyricsWord
from LDDC.utils.enum import QrcType
from LDDC.utils.error import LyricsProcessingError, LyricsRequestError
from LDDC.utils.logger import logger

from .share import lrc2list, plaintext2list

QRC_PATTERN = re.compile(r'<Lyric_1 LyricType="1" LyricContent="(?P<content>.*?)"/>', re.DOTALL)


def qrc2list(s_qrc: str) -> tuple[dict, LyricsData]:
    """将qrc转换为列表[(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]"""
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
            lrc_list.append(LyricsLine((int(line_start_time), int(line_start_time) + int(line_duration), [])))
            wrods_split_content = re.findall(wrods_split_pattern, line)
            if wrods_split_content:  # 判断是否为逐字歌词
                for text, starttime, duration in wrods_split_content:
                    if text != "\r":
                        lrc_list[-1][2].append(LyricsWord((int(starttime), int(starttime) + int(duration), text)))
            else:  # 如果不是逐字歌词
                lrc_list[-1][2].append(LyricsWord((int(line_start_time), int(line_start_time) + int(line_duration), line_content)))
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


def get_lyrics(lyrics: Lyrics) -> None:
    if lyrics.title is None or not isinstance(lyrics.artist, list) or lyrics.album is None or not isinstance(lyrics.id, int) or lyrics.duration is None:
        msg = "缺少必要参数"
        raise LyricsRequestError(msg)
    response = qm_get_lyrics(lyrics.title, lyrics.artist, lyrics.album, lyrics.id, lyrics.duration)
    if isinstance(response, str):
        raise LyricsRequestError(response)
    for key, value in [("orig", 'lyric'),
                       ("ts", 'trans'),
                       ("roma", 'roma')]:
        lrc = response[value]
        lrc_t = (response["qrc_t"] if response["qrc_t"] != 0 else response["lrc_t"]) if value == "lyric" else response[value + "_t"]
        if lrc != "" and lrc_t != "0":
            encrypted_lyric = lrc

            lyric = qrc_decrypt(encrypted_lyric, QrcType.CLOUD)

            if lyric is not None:
                tags, lyric = qrc_str_parse(lyric)

                if key == "orig":
                    lyrics.tags = tags

                lyrics[key] = lyric
        elif (lrc_t == "0" and key == "orig"):
            msg = "没有获取到可用的歌词"
            raise LyricsProcessingError(msg)
