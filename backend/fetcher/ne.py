# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only\
import re

from backend.api import ne_get_lyrics
from backend.lyrics import Lyrics, LyricsData, LyricsLine, LyricsWord
from utils.enum import Source
from utils.error import LyricsRequestError

from .share import lrc2list, plaintext2list


def yrc2list(yrc: str) -> list:
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
        lrc_list.append(LyricsLine((int(line_start_time), int(line_start_time) + int(line_duration), [])))

        wrods_split_content = re.findall(wrods_split_pattern, line_content)
        if not wrods_split_content:
            lrc_list[-1][2].append(LyricsWord((int(line_start_time), int(line_start_time) + int(line_duration), line_content)))
            continue

        for word_start_time, word_duration, word_content in wrods_split_content:
            lrc_list[-1][2].append(LyricsWord((int(word_start_time), int(word_start_time) + int(word_duration), word_content)))

    return lrc_list


def get_lyrics(lyrics: Lyrics) -> None:
    if lyrics.id is None:
        msg = "Lyrics id is None"
        raise LyricsRequestError(msg)
    response = ne_get_lyrics(lyrics.id)
    tags = {}
    if lyrics.artist:
        tags.update({"ar": "/".join(lyrics.artist) if isinstance(lyrics.artist, list) else lyrics.artist})
    if lyrics.album:
        tags.update({"al": lyrics.album})
    if lyrics.title:
        tags.update({"ti": lyrics.title})
    if 'lyricUser' in response and 'nickname' in response['lyricUser']:
        tags.update({"by": response['lyricUser']['nickname']})
    if 'transUser' in response and 'nickname' in response['transUser']:
        if 'by' in tags and tags['by'] != response['transUser']['nickname']:
            tags['by'] += f" & {response['transUser']['nickname']}"
        elif 'by' not in tags:
            tags.update({"by": response['transUser']['nickname']})
    lyrics.tags = tags
    if 'yrc' in response and len(response['yrc']['lyric']) != 0:
        mapping_table = [("orig", 'yrc'),
                         ("ts", 'tlyric'),
                         ("roma", 'romalrc'),
                         ("orig_lrc", 'lrc')]
    else:
        mapping_table = [("orig", 'lrc'),
                         ("ts", 'tlyric'),
                         ("roma", 'romalrc')]
    for key, value in mapping_table:
        if value not in response:
            continue
        if isinstance(response[value]['lyric'], str) and len(response[value]['lyric']) != 0:
            if value == 'yrc':
                lyrics[key] = yrc2list(response[value]['lyric'])
            elif "[" in response[value]['lyric'] and "]" in response[value]['lyric']:
                lyrics[key] = lrc2list(response[value]['lyric'], source=Source.NE)[1]
            else:
                lyrics[key] = plaintext2list(response[value]['lyric'])
