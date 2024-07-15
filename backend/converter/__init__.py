# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import re

from backend.lyrics import Lyrics, LyricsData, LyricsLine
from utils.data import cfg
from utils.enum import LyricsFormat, LyricsType, Source
from utils.logger import logger

from .ass import ass_converter
from .lrc import lrc_converter
from .srt import srt_converter

CHECK_SAME_LINE_CLEAN_PATTERN = re.compile(r'[(（][^）)]*[）)]|\s+')


def is_same_line(line1: LyricsLine, line2: LyricsLine) -> bool:
    """检查行是否近似相同"""
    line1_str = "".join([word[2]for word in line1[2]])
    line2_str = "".join([word[2]for word in line2[2]])
    if line1_str == line2_str:
        return True
    cleaned_line1 = CHECK_SAME_LINE_CLEAN_PATTERN.sub('', line1_str)
    cleaned_line2 = CHECK_SAME_LINE_CLEAN_PATTERN.sub('', line2_str)
    return cleaned_line1 == cleaned_line2 != ""


def find_closest_match(data1: LyricsData, data2: LyricsData, data3: LyricsData | None = None, source: Source | None = None) -> dict[int, int]:
    """为原文匹配其他语言类型的歌词

    :param data1: 原文歌词
    :param data2: 其他语言类型的歌词
    :param data3: 原文歌词(逐行,仅ne源需要)
    :param source: 歌词来源
    :return: 匹配结果(引索)
    """
    if source == Source.NE and data3:
        data3_matched = find_closest_match(data3, data2, source=Source.NE)
        matched = {}
        for i1, line1 in enumerate(data1):
            for i3, i2 in data3_matched.items():
                if is_same_line(line1, data3[i3]):
                    matched[i1] = i2
                    data3_matched.pop(i3)
                    break
        if matched:
            return matched
        matched = {}

    if source in (Source.QM, Source.KG):
        if source == Source.QM:
            data1 = LyricsData([line for line in data1 if len(line[2]) != 0])
            data2 = LyricsData([line for line in data2 if len(line[2]) != 0])

        if len(data1) == len(data2):
            return {i: i for i in range(len(data1))}

    time_difference_list = [(i1, i2, abs(s1 - s2)) for i1, (s1, e1, t1) in enumerate(data1) if isinstance(s1, int)
                            for i2, (s2, e2, t2) in enumerate(data2) if isinstance(s2, int)]
    time_difference_list = sorted(time_difference_list, key=lambda x: x[2])

    matched = {}
    used_i1, used_i2 = set(), set()
    for i1, i2, _diff in time_difference_list:
        if i1 not in used_i1 and i2 not in used_i2:
            used_i1.add(i1)
            used_i2.add(i2)
            matched[i1] = i2
            if len(used_i1) == len(data1) or len(used_i2) == len(data2):
                break

    return matched


def convert2(lyrics: Lyrics,
             langs: list[str] | None,
             lyrics_format: LyricsFormat = LyricsFormat.VERBATIMLRC,
             offset: int = 0) -> str:
    """将Lyrics实例转换为指定格式的字符串

    :param lyrics: Lyrics实例
    :param langs: 要转换的语言列表
    :param lyrics_format: 要转换的歌词格式
    :param offset: 偏移量
    :return: 转换后的字符串
    """
    # json格式转换
    if lyrics_format == LyricsFormat.JSON:
        if langs is not None:
            msg = "JSON格式不支持选择歌词语言"
            raise NotImplementedError(msg)
        if offset != 0:
            msg = "JSON格式不支持偏移量"
            raise NotImplementedError(msg)

        json_dict = {"version": 0, "info": {}, "tags": lyrics.tags, "lyrics": dict(lyrics)}
        for key, value in vars(lyrics).items():
            if key in ("source", "title", "artist", "album", "id", "mid", "duration", "accesskey"):
                if key == "source":
                    value: Source
                    json_dict["info"][key] = value.name
                else:
                    json_dict["info"][key] = value

            return json.dumps(json_dict, ensure_ascii=False)

    if not langs:
        return ""

    lyrics_dict = lyrics.add_offset(offset=offset)

    lyrics_order: list[str] = [lang for lang in cfg["lyrics_order"] if lang in langs and lang in lyrics_dict]
    lyrics_order += [lang for lang in langs if lang not in lyrics_order and lang in lyrics_dict]

    langs_mapping = {lang: find_closest_match(data1=lyrics_dict["orig"],
                                              data2=lyrics_dict[lang],
                                              data3=lyrics_dict.get("orig_lrc"),
                                              source=lyrics.source)
                     for lang in lyrics_order if lang not in ("orig", "orig_lrc")}

    if lyrics.types["orig"] == LyricsType.PlainText:
        logger.warning("将纯文本转换为纯文本")
        lyrics_format = LyricsFormat.LINEBYLINELRC

    match lyrics_format:
        case LyricsFormat.VERBATIMLRC | LyricsFormat.LINEBYLINELRC | LyricsFormat.ENHANCEDLRC:
            return lrc_converter(lyrics.tags, lyrics_dict, lyrics_format, langs_mapping, lyrics_order)
        case LyricsFormat.SRT:
            return srt_converter(lyrics_dict, langs_mapping, lyrics_order, lyrics.duration)
        case LyricsFormat.ASS:
            return ass_converter(lyrics, lyrics_dict, langs_mapping, lyrics_order)

    msg = f"不支持的歌词格式: {lyrics_format}"
    raise NotImplementedError(msg)
