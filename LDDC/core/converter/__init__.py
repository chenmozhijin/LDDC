# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json

from LDDC.common.data.config import cfg
from LDDC.common.logger import logger
from LDDC.common.models import Language, LyricsBase, LyricsFormat, LyricsType, Source
from LDDC.core.algorithm import find_closest_match

from .ass import ass_converter
from .lrc import lrc_converter
from .srt import srt_converter


def convert2(lyrics: LyricsBase,
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

        def handle_info(info: dict) -> dict:
            json_info = {}
            for key, value in info.items():
                if key in ("path", "data", "cached", "songinfo"):
                    continue
                if isinstance(value, Source | Language):
                    json_info[key] = value.name
                elif isinstance(value, frozenset):
                    json_info[key] = list(value)
                elif value is not None:
                    json_info[key] = value
            return json_info

        json_dict = {"version": 1, "info": handle_info(lyrics.info.to_dict()), "tags": lyrics.tags, "lyrics": dict(lyrics)}
        json_dict["info"]["songinfo"] = handle_info(lyrics.info.songinfo.to_dict())
        return json.dumps(json_dict, ensure_ascii=False)

    if not langs:
        return ""

    lyrics_dict = lyrics.add_offset(offset=offset)

    if "LDDC_ts" in lyrics_dict:  # 使用LDDC的翻译覆盖原本的翻译
        lyrics_dict["ts"] = lyrics_dict.pop("LDDC_ts")


    langs_order: list[str] = [lang for lang in cfg["langs_order"] if lang in langs and lang in lyrics_dict]
    langs_order += [lang for lang in langs if lang not in langs_order and lang in lyrics_dict]

    langs_mapping = {lang: find_closest_match(data1=lyrics_dict["orig"],
                                              data2=lyrics_dict[lang],
                                              data3=lyrics_dict.get("orig_lrc"),
                                              source=lyrics.source)
                     for lang in langs_order if lang not in ("orig", "orig_lrc")}
    if lyrics.types["orig"] == LyricsType.PlainText:
        logger.warning("将纯文本转换为纯文本")
        lyrics_format = LyricsFormat.LINEBYLINELRC

    match lyrics_format:
        case LyricsFormat.VERBATIMLRC | LyricsFormat.LINEBYLINELRC | LyricsFormat.ENHANCEDLRC:
            return lrc_converter(lyrics.tags, lyrics_dict, lyrics_format, langs_mapping, langs_order)
        case LyricsFormat.SRT:
            return srt_converter(lyrics_dict, langs_mapping, langs_order, lyrics.duration)
        case LyricsFormat.ASS:
            return ass_converter(lyrics, lyrics_dict, langs_mapping, langs_order)

    msg = f"不支持的歌词格式: {lyrics_format}"
    raise NotImplementedError(msg)
