# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import logging
import re
from base64 import b64decode
from typing import NewType

from PySide6.QtCore import QCoreApplication

from utils.data import cfg
from utils.enum import (
    LyricsFormat,
    LyricsProcessingError,
    LyricsType,
    QrcType,
    Source,
)
from utils.utils import time2ms

from .api import get_krc, ne_get_lyric, qm_get_lyric
from .decryptor import krc_decrypt, qrc_decrypt

try:
    main = __import__("__main__")
    version = main.__version__.replace("v", "")
except Exception:
    version = ""

LyricsWord = NewType("LyricsWord", tuple[int | None, int | None, str])
LyricsLine = NewType("LyricsLine", tuple[int | None, int | None, list[LyricsWord]])
LyricsData = NewType("LyricsData", list[LyricsLine])
MultiLyricsData = NewType("MultiLyricsData", dict[str, LyricsData])


def _get_divmod_time(ms: int) -> tuple[int, int, int, int]:
    total_s, ms = divmod(ms, 1000)
    h, remainder = divmod(total_s, 3600)
    m, s = divmod(remainder, 60)
    return h, m, s, ms


def ms2formattime(ms: int) -> str:
    _h, m, s, ms = _get_divmod_time(ms)
    lrc_ms_digit_count = cfg["lrc_ms_digit_count"]
    if lrc_ms_digit_count == 2:
        ms = round(ms / 10)
        if ms == 100:
            ms = 0
            s += 1
        return f"{int(m):02d}:{int(s):02d}.{int(ms):02d}"
    return f"{int(m):02d}:{int(s):02d}.{int(ms):03d}"  # lrc_ms_digit_count == 3


def ms2srt_timestamp(ms: int) -> str:
    h, m, s, ms = _get_divmod_time(ms)

    return f"{int(h):02d}:{int(m):02d}:{int(s):02d},{int(ms):03d}"


def ms2ass_timestamp(ms: int) -> str:
    h, m, s, ms = _get_divmod_time(ms)

    return f"{int(h):02d}:{int(m):02d}:{int(s):02d}.{int(ms):03d}"


def judge_lyric_type(text: str) -> LyricsType:
    if re.findall(r'<Lyric_1 LyricType="1" LyricContent="(.*?)"/>', text, re.DOTALL):
        return LyricsType.QRC
    if "[" in text and "]" in text:
        return LyricsType.LRC
    return LyricsType.PlainText


def has_content(line: str) -> bool:
    """检查是否有实际内容"""
    content = re.sub(r"\[\d+:\d+\.\d+\]|\[\d+,\d+\]|<\d+:\d+\.\d+>", "", line).strip()
    if content in ("", "//"):
        return False
    if len(content) == 2 and content[0].isupper() and content[1] == "：":
        # 歌手标签行
        return False
    return True


def get_clear_lyric(lyric: str) -> str:
    # 为保证find_closest_match的准确性不可直接用于原歌词
    start_double_timestamp_pattern = re.compile(r"^(\[\d+:\d+\.\d+\])\[\d+:\d+\.\d+\]")  # 行首双重时间戳匹配表达式
    end_double_timestamp_pattern = re.compile(r"(\[\d+:\d+\.\d+\])\[\d+:\d+\.\d+\]")  # 行尾双重时间戳匹配表达式
    result = []
    for line in lyric.splitlines():
        line1 = start_double_timestamp_pattern.sub(r"\1", line)
        line1 = end_double_timestamp_pattern.sub(r"\1", line1)
        if has_content(line1):
            result.append(line1)
    return "\n".join(result)


def qrc2list(qrc: str) -> tuple[dict, list]:
    """将qrc转换为列表[(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]"""
    qrc = re.findall(r'<Lyric_1 LyricType="1" LyricContent="(.*?)"/>', qrc, re.DOTALL)[0]
    qrc_lines = qrc.split('\n')
    tags = {}
    lrc_list: LyricsData = []
    wrods_split_pattern = re.compile(r'(?:\[\d+,\d+\])?((?:(?!\(\d+,\d+\)).)+)\((\d+),(\d+)\)')  # 逐字匹配
    line_split_pattern = re.compile(r'^\[(\d+),(\d+)\](.*)$')  # 逐行匹配
    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")

    for i in qrc_lines:
        line = i.strip()
        line_split_content = re.findall(line_split_pattern, line)
        if line_split_content:  # 判断是否为歌词行
            line_start_time, line_duration, line_content = line_split_content[0]
            lrc_list.append((int(line_start_time), int(line_start_time) + int(line_duration), []))
            wrods_split_content = re.findall(wrods_split_pattern, line)
            if wrods_split_content:  # 判断是否为逐字歌词
                for text, starttime, duration in wrods_split_content:
                    if text != "\r":
                        lrc_list[-1][2].append((int(starttime), int(starttime) + int(duration), text))
            else:  # 如果不是逐字歌词
                lrc_list[-1][2].append((int(line_start_time), int(line_start_time) + int(line_duration), line_content))
        else:
            tag_split_content = re.findall(tag_split_pattern, line)
            if tag_split_content:
                tags.update({tag_split_content[0][0]: tag_split_content[0][1]})

    return tags, lrc_list


def yrc2list(yrc: str) -> list:
    """将yrc转换为列表[(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]"""
    lrc_list: LyricsData = []

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
        lrc_list.append((int(line_start_time), int(line_start_time) + int(line_duration), []))

        wrods_split_content = re.findall(wrods_split_pattern, line_content)
        if not wrods_split_content:
            lrc_list[-1][2].append((int(line_start_time), int(line_start_time) + int(line_duration), line_content))
            continue

        for word_start_time, word_duration, word_content in wrods_split_content:
            lrc_list[-1][2].append((int(word_start_time), int(word_start_time) + int(word_duration), word_content))

    return lrc_list


def lrc2list(lrc: str, source: Source | None = None) -> tuple[dict, list]:
    """将lrc转换为列表[(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]"""
    lrc_list: LyricsData = []
    tags = {}

    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")
    line_split_pattern = re.compile(r"^\[(\d+):(\d+).(\d+)\](.*)$")
    line_split_pattern_withend = re.compile(r"^\[(\d+):(\d+).(\d+)\](.*)\[(\d+):(\d+).(\d+)\]$")
    wrods_split_pattern = re.compile(r"\[(\d+):(\d+).(\d+)\]((?:.(?!\d+:\d+.\d+\]))*)")  # 逐字匹配
    for i in lrc.splitlines():
        line = i.strip()
        if not line.startswith("["):
            continue

        tag_split_content = re.findall(tag_split_pattern, line)
        if tag_split_content:  # 标签行
            tags.update({tag_split_content[0][0]: tag_split_content[0][1]})
            continue

        line_split_withend_content = re.findall(line_split_pattern_withend, line)
        if not line_split_withend_content:
            line_split_content = re.findall(line_split_pattern, line)
            if not line_split_content:
                continue
            m, s, ms, line_content = line_split_content[0]
            line_end_time = None
            line_start_time = time2ms(m, s, ms)
        else:
            m, s, ms, line_content, m2, s2, ms2 = line_split_withend_content[0]
            line_start_time = time2ms(m, s, ms)
            line_end_time = time2ms(m2, s2, ms2)
        lrc_list.append((line_start_time, line_end_time, []))

        wrods_split_contents = re.findall(wrods_split_pattern, line_content)
        if not wrods_split_contents:
            lrc_list[-1][2].append((line_start_time, line_end_time, line_content))
            continue

        if (source == Source.NE and
            len([word_content for m, s, ms, word_content in wrods_split_contents if word_content != ""]) == 1 and
                wrods_split_contents[-1][3] != ""):
            # 如果转换的是网易云歌词且这一行有开头有几个连在一起的时间戳表示这几个时间戳的行都是这个歌词
            line_content = wrods_split_contents[-1][3]
            lrc_list[-1][2].append((line_start_time, line_end_time, line_content))
            for m, s, ms, _line_content in wrods_split_contents:
                line_start_time = time2ms(m, s, ms)
                lrc_list.append((line_start_time, None, [(line_start_time, None, line_content)]))
            continue

        line = lrc_list[-1][2]
        for m, s, ms, word_content in wrods_split_contents:
            word_start_time = time2ms(m, s, ms)
            if line:
                line[-1] = (line[-1][0], word_start_time, line[-1][2])
            line.append((word_start_time, None, word_content))

    return tags, lrc_list


def plaintext2list(plaintext: str) -> list[list[None, None, list[None, None, str]]]:
    lrc_list: LyricsData = []
    for line in plaintext.splitlines():
        lrc_list.append((None, None, [(None, None, line)]))
    return lrc_list


def krc2dict(krc: str) -> tuple[dict, dict]:
    """将明文krc转换为字典{歌词类型: [(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]}"""
    lrc_dict: MultiLyricsData = {}
    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")
    tags: dict[str: str] = {}

    line_split_pattern = re.compile(r'^\[(\d+),(\d+)\](.*)$')  # 逐行匹配
    wrods_split_pattern = re.compile(r'(?:\[\d+,\d+\])?<(\d+),(\d+),\d+>((?:.(?!\d+,\d+,\d+>))*)')  # 逐字匹配
    orig_list: LyricsData = []  # 原文歌词
    roma_list: LyricsData = []
    ts_list: LyricsData = []

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
        orig_list.append((int(line_start_time), int(line_start_time) + int(line_duration), []))

        wrods_split_content = re.findall(wrods_split_pattern, line_content)
        if not wrods_split_content:
            orig_list[-1][2].append((int(line_start_time), int(line_start_time) + int(line_duration), line_content))
            continue

        for word_start_time, word_duration, word_content in wrods_split_content:
            orig_list[-1][2].append((int(line_start_time) + int(word_start_time),
                                     int(line_start_time) + int(word_start_time) + int(word_duration), word_content))

    if "language" in tags and tags["language"].strip() != "":
        languages = json.loads(b64decode(tags["language"].strip()))
        for language in languages["content"]:
            if language["type"] == 0:  # 逐字(罗马音)
                offset = 0  # 用于跳过一些没有内容的行,它们不会存在与罗马音的字典中
                for i, line in enumerate(orig_list):
                    i = i - offset  # noqa: PLW2901
                    if "".join([w[2] for w in line[2]]) == "":
                        # 如果该行没有内容,则跳过
                        offset += 1
                        continue

                    roma_line = (line[0], line[1], [])
                    for j, word in enumerate(line[2]):
                        roma_line[2].append((word[0], word[1], language["lyricContent"][i][j]))
                    roma_list.append(roma_line)
            elif language["type"] == 1:  # 逐行(翻译)
                for i, line in enumerate(orig_list):
                    ts_list.append((line[0], line[1], [(line[0], line[1], language["lyricContent"][i][0])]))

    tags_str = ""
    for key, value in tags.items():
        if key in ["al", "ar", "au", "by", "offset", "ti"]:
            tags_str += f"[{key}:{value}]\n"

    for key, lrc_list in ({"orig": orig_list, "roma": roma_list, "ts": ts_list}).items():
        if lrc_list:
            lrc_dict[key] = lrc_list
    return tags, lrc_dict


def tagsdict2str(tags_dict: dict, lrc_type: str) -> str:
    tags_str = ""
    if not tags_dict:
        return tags_str
    match lrc_type:
        case "lrc":
            for key, value in tags_dict.items():
                if key in ["al", "ar", "au", "by", "offset", "ti"]:
                    tags_str += f"[{key}:{value}]\n"
        case "krc":
            for key in ["id", "ar", "ti", "by", "hash", "offset", "al", "sign", "qq", "total", "offset", "language", "manualoffset"]:
                if key in tags_dict:
                    tags_str += f"[{key}:{tags_dict[key]}]\n"
                else:
                    tags_str += f"[{key}:]\n"

    return tags_str


def lrclist2str(lrc_list: list, verbatim: bool = True) -> str:
    lrc_str = ""
    for line_list in lrc_list:
        lrc_str += linelist2str(line_list, verbatim) + "\n"  # 换行
    return lrc_str


def linelist2str(line_list: LyricsLine, verbatim: bool = True, enhanced: bool = False) -> str:
    """
    将歌词行列表转换为LRC歌词字符串
    :param line_list: 歌词行列表
    :param verbatim: 是否逐字模式
    :param Enhanced: 是否为增强格式歌词
    :return: LRC歌词字符串
    """
    lrc_str = ""
    if line_list[0] is None and line_list[1] is None:  # 纯文本
        lrc_str += line_list[2][0][2]

    elif enhanced is True and line_list[0] is not None:
        if len(line_list[2]) == 1:
            lrc_str += f"[{ms2formattime(line_list[0])}]" + line_list[2][0][2]
        else:
            lrc_str += f"[{ms2formattime(line_list[0])}]"  # 添加行首时间戳

            for i, word in enumerate(line_list[2]):
                lrc_str += f"<{ms2formattime(word[0])}>" + word[2]

                if word[1] is not None and (
                    (i + 1 != len(line_list[2])
                     and word[1] != line_list[2][i + 1][0])
                        or (i + 1 == len(line_list[2])
                            and word[1] != line_list[1])):
                    lrc_str += f"<{ms2formattime(word[1])}>"

            if line_list[1]:
                lrc_str += f"<{ms2formattime(line_list[1])}>"  # 添加行尾时间戳

    elif verbatim is False:  # 非逐字模式
        if line_list[0] is not None:
            lrc_str += f"[{ms2formattime(line_list[0])}]"
        lrc_str += "".join([word[2]for word in line_list[2] if word[2] != ""])
    elif len(line_list[2]) == 1 and line_list[0] is not None and line_list[1] is not None:  # 原歌词非逐字有行首尾时间戳
        lrc_str += f"[{ms2formattime(line_list[0])}]{line_list[2][0][2]}[{ms2formattime(line_list[1])}]"
    elif len(line_list[2]) == 1 and line_list[0] is not None:  # 原歌词非逐字只有行首时间戳
        lrc_str += f"[{ms2formattime(line_list[0])}]{line_list[2][0][2]}"
    elif len(line_list[2]) > 1 and line_list[0] is not None and line_list[1] is not None:  # 原歌词逐字有行首尾时间戳
        lrc_str += f"[{ms2formattime(line_list[0])}]"  # 添加行首时间戳
        last_end = line_list[0]

        for word in line_list[2]:
            if last_end != word[0]:
                lrc_str += f"[{ms2formattime(word[0])}]"

            lrc_str += word[2]

            if word[1] and word[1] != line_list[1]:
                lrc_str += f"[{ms2formattime(word[1])}]"
            last_end = word[1]

        if line_list[1]:
            lrc_str += f"[{ms2formattime(line_list[1])}]"  # 添加尾首时间戳
    else:
        logging.warning(f"转换为lrc时忽略行{line_list}")
    return lrc_str


def linelist2asstext(line_list: LyricsLine) -> str:
    ass_text = ""
    if len(line_list[2]) == 1:
        return "".join([word[2]for word in line_list[2] if word[2] != ""])
    for word in line_list[2]:
        if word[0] is not None and word[1] is not None:
            k = abs(word[1] - word[0]) // 10
        else:
            return "".join([word[2]for word in line_list[2] if word[2] != ""])
        ass_text += r"{\kf" + str(k) + "}" + word[2]
    return ass_text


def is_same_line(line1: LyricsLine, line2: LyricsLine) -> bool:
    """检查行是否近似相同"""
    line1_str = "".join([word[2]for word in line1[2] if word[2] != ""])
    line2_str = "".join([word[2]for word in line2[2] if word[2] != ""])
    if line1_str == line2_str:
        return True
    clean1_line1 = re.sub(r'\s+', '', line1_str)
    clean1_line2 = re.sub(r'\s+', '', line2_str)
    if clean1_line1 == clean1_line2:
        return True
    clean2_line1 = re.sub(r'[(（][^）)]*[）)]', '', clean1_line1)
    clean2_line2 = re.sub(r'[(（][^）)]*[）)]', '', clean1_line2)
    if clean2_line1 == clean2_line2 != "":
        return True
    return False


def is_verbatim(lrc_list: list) -> bool:
    isverbatim = False
    for line_list in lrc_list:
        if len(line_list[2]) > 1:
            isverbatim = True
            break
    return isverbatim


def find_closest_match(list1: list, list2: list, list3: list | None = None, source: Source | None = None) -> list[tuple[list, list]]:
    list1: LyricsData = list1[:]
    list2: LyricsData = list2[:]
    if list3:
        list3: LyricsData = list3[:]
    # 存储合并结果的列表
    merged_dict = {}
    merged_list = []

    if source == Source.NE and list3:
        matchs1 = find_closest_match(list2, list3, source=Source.NE)
        for list1_line in list1:
            for match in matchs1:
                if is_same_line(list1_line, match[1]):
                    merged_list.append((list1_line, match[0]))
                    matchs1.remove(match)
                    break
        if len(merged_list) == 0:
            merged_list = []
        else:
            return merged_list

    if source in (Source.QM, Source.KG):
        if source == Source.QM:
            list12 = [item for item in list1 if len(item[2]) != 0]
            list22 = [item for item in list2 if len(item[2]) != 0]
        elif source == Source.KG:
            list12 = list1
            list22 = list2
        if len(list12) == len(list22):
            logging.info("qm/kg 匹配方法")
            for i, value in enumerate(list12):
                merged_list.append((value, list22[i]))
            return merged_list
        list12, list22 = None, None

    logging.info("other 匹配方法")

    for i, value in enumerate(list1):
        list1[i] = (value[0], value[1], tuple(value[2]))

    for i, value in enumerate(list2):
        list2[i] = (value[0], value[1], tuple(value[2]))

    # 遍历第一个列表中的每个时间戳和歌词
    i = 0
    while len(list1) > i:
        lyrics1 = list1[i]
        timestamp1 = lyrics1[0]
        if timestamp1 is None:
            i += 1
            continue
        # 找到在第二个列表中最接近的匹配项
        closest_lyrics2 = tuple(min(list2, key=lambda x: abs(x[0] - timestamp1)))
        closest_timestamp2 = closest_lyrics2[0]

        if closest_lyrics2 not in merged_dict:
            # 如果(closest_timestamp2, closest_lyrics2)还没有匹配
            merged_dict.update({closest_lyrics2: lyrics1})
        elif abs(timestamp1 - closest_timestamp2) < abs(merged_dict[closest_lyrics2][0] - closest_timestamp2):
            # 如果新的匹配比旧的更近
            list1.append(merged_dict[closest_lyrics2])
            merged_dict[closest_lyrics2] = lyrics1
        else:
            # 如果新的匹配比旧的更远
            available_items = [item for item in list2 if item not in merged_dict]
            if available_items:
                closest_lyrics22 = min(available_items, key=lambda x: abs(x[0] - timestamp1))
                closest_timestamp22 = closest_lyrics22[0]
                if merged_dict[closest_lyrics2][0] < timestamp1 and closest_timestamp22 < closest_timestamp2:
                    # 如果匹配顺序错误
                    merged_dict[closest_lyrics22] = merged_dict[closest_lyrics2]
                    merged_dict[closest_lyrics2] = lyrics1
                else:
                    merged_dict[closest_lyrics22] = lyrics1
                    if abs(closest_timestamp22 - timestamp1) > 1000:
                        logging.warning(f"{lyrics1}, {closest_lyrics22}匹配可能错误")
            else:
                logging.warning(f"{lyrics1}无法匹配")

        i += 1

    sorted_items = sorted(((key, value) for key, value in merged_dict.items()), key=lambda x: x[0])

    merged_list = []
    for items in sorted_items:
        item1 = (items[0][0], items[0][1], list(items[0][2]))
        item2 = (items[1][0], items[1][1], list(items[1][2]))
        merged_list.append((item2, item1))

    return merged_list


class Lyrics(dict):
    def __init__(self, info: dict | None = None) -> None:
        if info is None:
            info = {}
        logging.info(f"初始化{info}")
        self.source = info.get("source", None)
        self.title = info.get('title', None)
        self.artist = info.get("artist", None)
        self.album = info.get("album", None)
        self.id = info.get("id", None)
        self.mid = info.get("mid", None)
        self.duration = info.get("duration", None)
        self.accesskey = info.get("accesskey", None)

        self.lrc_types = {}
        self.lrc_isverbatim = {}
        self.tags = {}

    def download_and_decrypt(self) -> tuple[str | None, LyricsProcessingError | None]:
        """
        下载与解密歌词
        :return: 错误信息, 错误类型 | None, None
        """
        if self.source not in [Source.QM, Source.KG, Source.NE]:
            return QCoreApplication.translate("lyrics", "不支持的源"), LyricsProcessingError.UNSUPPORTED

        match self.source:
            case Source.QM:
                response = qm_get_lyric({'album': self.album, 'artist': self.artist, 'title': self.title, 'id': self.id, 'duration': self.duration})
                if isinstance(response, str):
                    return QCoreApplication.translate("lyrics", "请求qrc歌词失败,错误:{0}").format(response), LyricsProcessingError.REQUEST
                for key, value in [("orig", 'lyric'),
                                   ("ts", 'trans'),
                                   ("roma", 'roma')]:
                    lrc = response[value]
                    lrc_t = (response["qrc_t"] if response["qrc_t"] != 0 else response["lrc_t"]) if value == "lyric" else response[value + "_t"]
                    if lrc != "" and lrc_t != "0":
                        encrypted_lyric = lrc

                        lyric, error = qrc_decrypt(encrypted_lyric, QrcType.CLOUD)

                        if lyric is not None:
                            lrc_type = judge_lyric_type(lyric)
                            if lrc_type == LyricsType.QRC:
                                tags, lyric = qrc2list(lyric)
                            elif lrc_type == LyricsType.LRC:
                                tags, lyric = lrc2list(lyric)
                            elif lrc_type == LyricsType.PlainText:
                                tags = {}
                                lyric = plaintext2list(lyric)
                            self.lrc_types[key] = lrc_type

                            if key == "orig":
                                self.tags = tags

                            self[key] = lyric
                        elif error is not None:
                            return QCoreApplication.translate("lyrics", "解密歌词失败, 错误: ") + error, LyricsProcessingError.DECRYPT
                    elif (lrc_t == "0" and key == "orig"):
                        return QCoreApplication.translate("lyrics", "没有获取到可用的歌词(timetag=0)"), LyricsProcessingError.NOT_FOUND

            case Source.KG:
                encrypted_krc = get_krc(self.id, self.accesskey)
                if isinstance(encrypted_krc, str):
                    return QCoreApplication.translate("lyrics", "请求krc歌词失败,错误:{0}").format(response), LyricsProcessingError.REQUEST
                krc, error = krc_decrypt(encrypted_krc)
                if krc is None:
                    error = f"错误:{error}" if error is not None else ""
                    return QCoreApplication.translate("lyrics", "解密krc歌词失败,错误:{0}").format(error), LyricsProcessingError.DECRYPT
                self.tags, lyric = krc2dict(krc)
                self.update(lyric)
                if 'orig' in lyric:
                    self.lrc_types['orig'] = LyricsType.KRC
                if 'ts' in lyric:
                    self.lrc_types['ts'] = LyricsType.JSONLINE
                if 'roma' in lyric:
                    self.lrc_types['roma'] = LyricsType.JSONVERBATIM

            case Source.NE:
                lyrics = ne_get_lyric(self.id)
                if isinstance(lyrics, str):
                    return QCoreApplication.translate("lyrics", "请求网易云歌词失败, 错误: ") + lyrics, LyricsProcessingError.REQUEST
                logging.debug(f"lyrics: {lyrics}")
                tags = {}
                if self.artist:
                    tags.update({"ar": self.artist})
                if self.album:
                    tags.update({"al": self.album})
                if self.title:
                    tags.update({"ti": self.title})
                if 'lyricUser' in lyrics and 'nickname' in lyrics['lyricUser']:
                    tags.update({"by": lyrics['lyricUser']['nickname']})
                if 'transUser' in lyrics and 'nickname' in lyrics['transUser']:
                    if 'by' in tags and tags['by'] != lyrics['transUser']['nickname']:
                        tags['by'] += f" & {lyrics['transUser']['nickname']}"
                    elif 'by' not in tags:
                        tags.update({"by": lyrics['transUser']['nickname']})
                self.tags = tags
                if 'yrc' in lyrics and len(lyrics['yrc']['lyric']) != 0:
                    mapping_table = [("orig", 'yrc'),
                                     ("ts", 'tlyric'),
                                     ("roma", 'romalrc'),
                                     ("orig_lrc", 'lrc')]
                else:
                    mapping_table = [("orig", 'lrc'),
                                     ("ts", 'tlyric'),
                                     ("roma", 'romalrc')]
                for key, value in mapping_table:
                    if value not in lyrics:
                        continue
                    if isinstance(lyrics[value]['lyric'], str) and len(lyrics[value]['lyric']) != 0:
                        lyric_type = judge_lyric_type(lyrics[value]['lyric'])
                        if value == 'yrc':
                            self[key] = yrc2list(lyrics[value]['lyric'])
                            self.lrc_types[key] = LyricsType.YRC
                        elif lyric_type == LyricsType.LRC:
                            self[key] = lrc2list(lyrics[value]['lyric'], source=Source.NE)[1]
                            self.lrc_types[key] = LyricsType.LRC
                        elif lyric_type == LyricsType.PlainText:
                            self[key] = plaintext2list(lyrics[value]['lyric'])
                            self.lrc_types[key] = LyricsType.PlainText

        for key, lrc in self.items():
            # 判断是否逐字
            self.lrc_isverbatim[key] = is_verbatim(lrc)

        if "orig" not in self or self["orig"] is None:
            logging.error("没有获取到歌词(orig=None)")
            return QCoreApplication.translate("lyrics", "没有获取到歌词(orig=None)"), LyricsProcessingError.NOT_FOUND
        return None, None

    def add_offset(self, multi_lyrics_data: MultiLyricsData, offset: int = 0) -> MultiLyricsData:
        """
        添加偏移量
        :param multi_lyrics_data:歌词
        :param offset:偏移量
        :return: 偏移后的歌词
        """
        if offset == 0:
            return multi_lyrics_data

        def _offset_time(time: int | None) -> int | None:
            if isinstance(time, int):
                return max(time + offset, 0)
            return time

        return {
            lrc_type: [
                (
                    _offset_time(lrc_line[0]),
                    _offset_time(lrc_line[1]),
                    [(_offset_time(word[0]), _offset_time(word[1]), word[2]) for word in lrc_line[2]],
                )
                for lrc_line in lrc_list
            ]
            for lrc_type, lrc_list in multi_lyrics_data.items()
        }

    def get_merge_lrc(self, lyrics_order: list, lyrics_format: LyricsFormat = LyricsFormat.VERBATIMLRC, offset: int = 0) -> str:
        """
        合并歌词
        :param lyrics_order:歌词顺序,同时决定需要合并的类型
        :param lyrics_format:歌词格式
        :param offset:偏移量
        :return: 合并后的歌词
        """
        if len(lyrics_order) == 0:
            logging.warning("没有需要合并的歌词")
            return ""

        lyrics_dict: MultiLyricsData = self.add_offset(MultiLyricsData(self), offset)

        lyrics = [(key, lyric) for key, lyric in lyrics_dict.items() if key in lyrics_order]

        if 'orig' not in lyrics:  # 确保只勾选译文与罗马音时正常合并时
            lyrics.append(('orig', lyrics_dict['orig']))

        end_time_pattern = re.compile(r"(\[\d+:\d+\.\d+\])$|(<\d+:\d+\.\d+>)$")

        mapping_tables = {}
        lyric_lines = []

        if "ts" in lyrics_dict:
            mapping_tables["ts"] = find_closest_match(lyrics_dict["orig"], lyrics_dict["ts"], list3=lyrics_dict.get("orig_lrc"), source=self.source)
        if "roma" in lyrics_dict:
            mapping_tables["roma"] = find_closest_match(lyrics_dict["orig"], lyrics_dict["roma"], list3=lyrics_dict.get("orig_lrc"), source=self.source)

        if self.lrc_types["orig"] == LyricsType.PlainText:
            lyrics_format = LyricsFormat.LINEBYLINELRC

        match lyrics_format:
            case LyricsFormat.VERBATIMLRC | LyricsFormat.LINEBYLINELRC | LyricsFormat.ENHANCEDLRC:
                def get_full_line(mapping_table: dict, orig_linelist: list) -> str:
                    match_lines = [line for orig_line, line in mapping_table if orig_line == orig_linelist]
                    if not match_lines:
                        return ""

                    line = match_lines[0]
                    line_str = linelist2str(line,
                                            bool(lyrics_format == LyricsFormat.VERBATIMLRC),
                                            bool(lyrics_format == LyricsFormat.ENHANCEDLRC)).replace(f"[{ms2formattime(line[0])}]", "")

                    if not has_content(line_str):
                        return ""
                    if orig_linelist[0] is not None:
                        if re.search(end_time_pattern, line_str) or orig_linelist[1] is None or lyrics_format == LyricsFormat.LINEBYLINELRC:  # 检查是添加末尾时间戳
                            return f"[{ms2formattime(orig_linelist[0])}]{line_str}"
                        if lyrics_format == LyricsFormat.ENHANCEDLRC:
                            if len(line[2]) != 1:
                                return f"[{ms2formattime(orig_linelist[0])}]{line_str}<{ms2formattime(orig_linelist[1])}>"
                            return f"[{ms2formattime(orig_linelist[0])}]{line_str}"
                        return f"[{ms2formattime(orig_linelist[0])}]{line_str}[{ms2formattime(orig_linelist[1])}]"
                    return line_str

                for orig_linelist in lyrics_dict["orig"]:
                    lines = ""
                    full_orig_line = linelist2str(orig_linelist,
                                                  bool(lyrics_format == LyricsFormat.VERBATIMLRC),
                                                  bool(lyrics_format == LyricsFormat.ENHANCEDLRC))  # 此时line为完整的原文歌词行

                    for type_ in lyrics_order:
                        if type_ == "orig":
                            line = full_orig_line
                        elif type_ in mapping_tables:
                            line = get_full_line(mapping_tables[type_], orig_linelist)
                        else:
                            continue

                        if lines != "" and line != "":
                            lines += "\n" + line
                        else:
                            lines += line

                    lyric_lines.append(lines)

                return tagsdict2str(self.tags, "lrc") + get_clear_lyric("\n".join(lyric_lines))

            case LyricsFormat.SRT:
                srt_lines = []
                for i, orig_linelist in enumerate(lyrics_dict["orig"]):
                    sn = i + 1
                    if orig_linelist[1] is None:
                        if i + 1 < len(lyrics_dict["orig"]):
                            endtime = lyrics_dict["orig"][i + 1][0]
                        elif self.duration is not None:
                            endtime = self.duration * 1000
                        else:
                            endtime = orig_linelist[0] + 10000  # 加十秒
                    else:
                        endtime = orig_linelist[1]

                    srt_lines.append(f"{sn}\n{ms2srt_timestamp(orig_linelist[0])} --> {ms2srt_timestamp(endtime)}\n")
                    for lrc_type in lyrics_order:
                        match lrc_type:
                            case "orig":
                                srt_lines.append("".join([word[2]for word in orig_linelist[2]]) + "\n")
                            case "ts" | "roma":
                                if lrc_type not in mapping_tables:
                                    continue
                                match_lines = [line for orig_line, line in mapping_tables[lrc_type] if orig_line == orig_linelist]
                                if match_lines:
                                    match_line_str = "".join([word[2]for word in match_lines[0][2]])
                                    if has_content(match_line_str):
                                        srt_lines.append(match_line_str + "\n")
                    srt_lines.append("\n")
                return "".join(srt_lines)

            case LyricsFormat.ASS:
                ass_lines = ["[Script Info]",
                             f"; Script generated by LDDC {version}",
                             "; https://github.com/chenmozhijin/LDDC"]

                if self.title is not None:
                    ass_lines.append(f"Title: {self.title}")
                ass_lines.extend(["ScriptType: v4.00+", "Timer: 100.0000", ""])

                ass_lines.extend([
                    "[V4+ Styles]",
                    "Format: Name, Fontname, Fontsize, PrimaryColour, "
                    "SecondaryColour, OutlineColour, BackColour, Bold, Italic, "
                    "Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle,"
                    " Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
                ])
                for lrc_type in lyrics_order:
                    if lrc_type in mapping_tables or lrc_type == "orig":
                        ass_lines.append(f"Style: {lrc_type},Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1")

                ass_lines.extend(["",
                                  "[Events]",
                                  "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"])
                for lrc_type in lyrics_order[::-1]:
                    if lrc_type in mapping_tables or lrc_type == "orig":
                        for i, orig_linelist in enumerate(lyrics_dict["orig"]):
                            ass_line = "Dialogue: 0,"
                            if orig_linelist[1] is None:
                                if i + 1 < len(lyrics_dict["orig"]):
                                    endtime = lyrics_dict["orig"][i + 1][0]
                                elif self.duration is not None:
                                    endtime = lyrics_dict.duration * 1000
                                else:
                                    endtime = orig_linelist[0] + 10000  # 加十秒
                            else:
                                endtime = orig_linelist[1]
                            ass_line += f"{ms2ass_timestamp(orig_linelist[0])},{ms2ass_timestamp(endtime)},{lrc_type},,0,0,0,,"
                            if lrc_type == "orig":
                                line = orig_linelist
                            else:
                                match_lines = [line for orig_line, line in mapping_tables[lrc_type] if orig_line == orig_linelist]
                                if not match_lines or not has_content("".join([word[2]for word in match_lines[0][2]])):
                                    continue
                                line = match_lines[0]
                            ass_line += linelist2asstext(line)
                            ass_lines.append(ass_line)

                return "\n".join(ass_lines)
        return ""

    def get_full_timestamps_lyrics(self) -> MultiLyricsData | False:
        """
        获取完整时间戳的歌词
        """
        multi_lyrics_data: MultiLyricsData = {}
        for lrc_type, lrc_data in self.items():
            multi_lyrics_data[lrc_type] = []
            for index, lrc_line in enumerate(lrc_data):
                if lrc_line[0] is None:
                    return False
                if lrc_line[1] is None:
                    if lrc_line[2] and lrc_line[2][-1][1] is not None:
                        lrc_line[1] = lrc_line[2][-1][1]
                    elif index + 1 < len(lrc_data) and lrc_data[index + 1][0] is not None:
                        lrc_line[1] = lrc_data[index + 1][0]
                    elif index + 1 == len(lrc_data) and self.duration is not None:
                        lrc_line[1] = self.duration * 1000
                    elif index + 1 == len(lrc_data):
                        logging.warning("歌词时间戳不完整，无法生成精准的完整时间戳的歌词")
                        lrc_line[1] = lrc_line[0] + 10000  # 加十秒
                    else:
                        return False
                for w_index, word in enumerate(lrc_line[2]):
                    if word[0] is None:
                        if w_index == 0:
                            lrc_line[2][w_index][0] = lrc_line[0]
                        else:
                            lrc_line[2][w_index][0] = lrc_line[2][w_index - 1][1]

                    if word[1] is None:
                        if w_index == len(lrc_line[2]) - 1:
                            lrc_line[2][w_index][1] = lrc_line[1]
                        elif lrc_line[2][w_index + 1][0] is not None:
                            lrc_line[2][w_index][1] = lrc_line[2][w_index + 1][0]
                        else:
                            logging.error("歌词逐字时间戳不完整，无法生成完整时间戳的歌词")
                            return False

                multi_lyrics_data[lrc_type].append(lrc_line)

        return multi_lyrics_data
