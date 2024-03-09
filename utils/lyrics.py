# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import logging
import re
from base64 import b64decode
from enum import Enum

from bs4 import BeautifulSoup

from decryptor import QrcType, krc_decrypt, qrc_decrypt
from utils.api import Source, get_krc, get_qrc, ne_get_lyric, qm_get_lyric
from utils.utils import ms2formattime, time2ms


class LyricType(Enum):
    PlainText = 0
    JSONVERBATIM = 1
    JSONLINE = 2
    LRC = 3
    QRC = 4
    KRC = 5
    YRC = 6


class LyricProcessingError(Enum):
    REQUEST = 0
    DECRYPT = 1
    NOT_FOUND = 2
    UNSUPPORTED = 3


def judge_lyric_type(text: str) -> LyricType:
    if "<?xml " in text[:10] or "<QrcInfos>" in text[:10]:
        return LyricType.QRC
    if "[" in text and "]" in text:
        return LyricType.LRC
    return LyricType.PlainText


def has_content(line: str) -> bool:
    """检查是否有实际内容"""
    content = re.sub(r"\[\d+:\d+\.\d+\]|\[\d+,\d+\]", "", line).strip()
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
    lrc_list: list[tuple[int, int, list[tuple[int, int, str]]]] = []
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
    lrc_list: list[tuple[int, int, list[tuple[int, int, str]]]] = []

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


def lrc2list(lrc: str) -> tuple[dict, list]:
    """将lrc转换为列表[(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]"""
    lrc_list: list[tuple[int, int | None, list[tuple[int, int | None, str]]]] = []
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

        line = []
        for wrods_split_content in wrods_split_contents:
            m, s, ms, word_content = wrods_split_content
            word_start_time = time2ms(m, s, ms)
            if line:
                line[-1][1] = word_start_time
            lrc_list.append((word_start_time, None, word_content))

        lrc_list.append(line)
    return tags, lrc_list


def plaintext2list(plaintext: str) -> list[list[None, None, list[None, None, str]]]:
    lrc_list: list[tuple[None, None, list[tuple[None, None, str]]]] = []
    for line in plaintext.splitlines():
        lrc_list.append((None, None, [(None, None, line)]))
    return lrc_list


def krc2dict(krc: str) -> tuple[dict, dict]:
    """将明文krc转换为字典{歌词类型: [(行起始时间, 行结束时间, [(字起始时间, 字结束时间, 字内容)])]}"""
    lrc_dict: dict[str: list[tuple[int, int, list[tuple[int, int, str]]]]] = {}
    tag_split_pattern = re.compile(r"^\[(\w+):([^\]]*)\]$")
    tags: dict[str: str] = {}

    line_split_pattern = re.compile(r'^\[(\d+),(\d+)\](.*)$')  # 逐行匹配
    wrods_split_pattern = re.compile(r'(?:\[\d+,\d+\])?<(\d+),(\d+),\d+>((?:.(?!\d+,\d+,\d+>))*)')  # 逐字匹配
    orig_list: list[tuple[int, int, list[tuple[int, int, str]]]] = []  # 原文歌词
    roma_list: list[tuple[int, int, list[tuple[int, int, str]]]] = []
    ts_list: list[tuple[int, int, list[tuple[int, int, str]]]] = []

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
            orig_list[-1][2].append((int(line_start_time) + int(word_start_time), int(line_start_time) + int(word_start_time) + int(word_duration), word_content))

    if "language" in tags and tags["language"].strip() != "":
        languages = json.loads(b64decode(tags["language"].strip()))
        for language in languages["content"]:
            if language["type"] == 0:  # 逐字(罗马音)
                for i, line in enumerate(orig_list):
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


def lrclist2str(lrc_list: list) -> str:
    lrc_str = ""
    for line_list in lrc_list:
        lrc_str += linelist2str(line_list) + "\n"  # 换行
    return lrc_str


def linelist2str(line_list: list[tuple[int, int | None, list[tuple[int, int | None, str]]]]) -> str:
    lrc_str = ""
    if line_list[0] is None and line_list[1] is None:
        lrc_str += line_list[2][0][2]
    elif len(line_list[2]) == 1 and line_list[0] is not None and line_list[1] is not None:
        lrc_str += f"[{ms2formattime(line_list[0])}]{line_list[2][0][2]}[{ms2formattime(line_list[1])}]"
    elif len(line_list[2]) == 1 and line_list[0] is not None:
        lrc_str += f"[{ms2formattime(line_list[0])}]{line_list[2][0][2]}"
    elif len(line_list[2]) > 1 and line_list[0] is not None and line_list[1] is not None:
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


def is_same_line(line1: tuple[int, int | None, list[tuple[int, int | None, str]]], line2: tuple[int, int | None, list[tuple[int, int | None, str]]]) -> bool:
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
    list1: list[tuple[int, int | None, list[tuple[int, int | None, str]]]] = list1[:]
    list2: list[tuple[int, int | None, list[tuple[int, int | None, str]]]] = list2[:]
    if list3:
        list3: list[tuple[int, int | None, list[tuple[int, int | None, str]]]] = list3[:]
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


class Lyrics(dict[str: list[tuple[int | None, int | None, list[tuple[int | None, int | None, str]]]]]):
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
        self.accesskey = info.get("accesskey", None)

        self.lrc_types = {}
        self.lrc_isverbatim = {}
        self.tags = {}

    def download_and_decrypt(self) -> tuple[str | None, LyricProcessingError | None]:
        """
        下载与解密歌词
        :return: 错误信息, 错误类型 | None, None
        """
        if self.source not in [Source.QM, Source.KG, Source.NE]:
            return "不支持的源", LyricProcessingError.UNSUPPORTED

        match self.source:
            case Source.QM:
                response = get_qrc(self.id)
                if isinstance(response, str):
                    return f"请求qrc歌词失败,错误:{response}", LyricProcessingError.REQUEST
                qrc_xml = re.sub(r"^<!--|-->$", "", response.text.strip())
                qrc_suop = BeautifulSoup(qrc_xml, 'xml')
                for key, value in [("orig", 'content'),
                                   ("ts", 'contentts'),
                                   ("roma", 'contentroma')]:
                    find_result = qrc_suop.find(value)
                    if find_result is not None and find_result['timetag'] != "0":
                        encrypted_lyric = find_result.get_text()

                        cannot_decrypt = ["789C014000BFFF", "789C014800B7FF"]
                        for c in cannot_decrypt:
                            if encrypted_lyric.startswith(c):
                                return f"没有获取到可解密的歌词(encrypted_lyric starts with {c})", LyricProcessingError.NOT_FOUND

                        lyric, error = qrc_decrypt(encrypted_lyric, QrcType.CLOUD)

                        if lyric is not None:
                            lrc_type = judge_lyric_type(lyric)
                            if lrc_type == LyricType.QRC:
                                tags, lyric = qrc2list(lyric)
                            elif LyricType.LRC:
                                tags, lyric = lrc2list(lyric)
                            elif LyricType.PlainText:
                                tags = {}
                                lyric = plaintext2list(lyric)
                            self.lrc_types[key] = lrc_type

                            if key == "orig":
                                self.tags = tags

                            self[key] = lyric
                        elif error is not None:
                            return "解密歌词失败, 错误: " + error, LyricProcessingError.DECRYPT
                    elif (find_result['timetag'] == "0" and key == "orig"):
                        return "没有获取到可解密的歌词(timetag=0)", LyricProcessingError.NOT_FOUND

            case Source.KG:
                encrypted_krc = get_krc(self.id, self.accesskey)
                if isinstance(encrypted_krc, str):
                    return f"请求krc歌词失败,错误:{response}", LyricProcessingError.REQUEST
                krc, error = krc_decrypt(encrypted_krc)
                if krc is None:
                    error = f"错误:{error}" if error is not None else ""
                    return f"解密krc歌词失败,错误:{error}", LyricProcessingError.DECRYPT
                self.tags, lyric = krc2dict(krc)
                self.update(lyric)
                if 'orig' in lyric:
                    self.lrc_types['orig'] = LyricType.KRC
                if 'ts' in lyric:
                    self.lrc_types['ts'] = LyricType.JSONLINE
                if 'roma' in lyric:
                    self.lrc_types['roma'] = LyricType.JSONVERBATIM

            case Source.NE:
                lyrics = ne_get_lyric(self.id)
                if isinstance(lyrics, str):
                    return "请求网易云歌词失败, 错误: " + lyrics, LyricProcessingError.REQUEST
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
                    if 'by' in tags:
                        tags['by'] += f" & {lyrics['transUser']['nickname']}"
                    else:
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
                            self.lrc_types[key] = LyricType.YRC
                        elif lyric_type == LyricType.LRC:
                            self[key] = lrc2list(lyrics[value]['lyric'])[1]
                            self.lrc_types[key] = LyricType.LRC
                        elif lyric_type == LyricType.PlainText:
                            self[key] = plaintext2list(lyrics[value]['lyric'])
                            self.lrc_types[key] = LyricType.PlainText

        for key, lrc in self.items():
            # 判断是否逐字
            self.lrc_isverbatim[key] = is_verbatim(lrc)

        if "orig" not in self or self["orig"] is None:
            logging.error("没有获取到的歌词(orig=None)")
            return "没有获取到的歌词(orig=None)", LyricProcessingError.NOT_FOUND
        return None, None

    def download_normal_lyrics(self) -> tuple[str | None, LyricProcessingError | None]:
        result = qm_get_lyric(self.mid)
        if isinstance(result, str):
            return f"请求普通歌词时错误: {result}", LyricProcessingError.REQUEST
        orig, ts = result
        if orig is not None:
            if judge_lyric_type(orig) == LyricType.LRC:
                self.tags, self["orig"] = lrc2list(orig)
                self.lrc_types["orig"] = LyricType.LRC
            else:
                self["orig"] = plaintext2list(orig)
                self.lrc_types["orig"] = LyricType.PlainText
        if ts is not None:
            if judge_lyric_type(ts) == LyricType.LRC:
                tags, self["ts"] = lrc2list(ts)
                self.lrc_types["ts"] = LyricType.LRC
            else:
                self["ts"] = plaintext2list(ts)
                self.lrc_types["ts"] = LyricType.PlainText
            if not self.tags:
                self.tags = tags

        for key, lrc in self.items():
            # 判断是否逐字
            self.lrc_isverbatim[key] = is_verbatim(lrc)

        if self["orig"] is None and self["ts"] is None:
            return "没有获取到可用的歌词(orig=None and ts=None)", LyricProcessingError.NOT_FOUND
        return None, None

    def get_merge_lrc(self, lyrics_order: list) -> str:
        """
        合并歌词
        :param lyrics_order:歌词顺序,同时决定需要合并的类型
        :return: 合并后的歌词
        """
        match len(lyrics_order):
            case 0:
                logging.warning("没有需要合并的歌词")
                return ""
            case 1:
                if lyrics_order[0] in self:
                    return tagsdict2str(self.tags, "lrc") + get_clear_lyric(lrclist2str(self[lyrics_order[0]]))
                logging.warning("没有需要合并的歌词")
                return ""

        lyrics = [(key, lyric) for key, lyric in self.items() if key in lyrics_order]
        if len(lyrics) == 1:
            return tagsdict2str(self.tags, "lrc") + get_clear_lyric(lrclist2str(lyrics[0][1]))

        if 'orig' not in lyrics:  # 确保只勾选译文与罗马音时正常合并时
            lyrics.append(('orig', self['orig']))

        end_time_pattern = re.compile(r"(\[\d+:\d+\.\d+\])$")

        mapping_tables = {}
        lyric_lines = []

        if "ts" in self:
            mapping_tables["ts"] = find_closest_match(self["orig"], self["ts"], list3=self.get("orig_lrc", None), source=self.source)
        if "roma" in self:
            mapping_tables["roma"] = find_closest_match(self["orig"], self["roma"], list3=self.get("orig_lrc", None), source=self.source)

        def get_full_line(mapping_table: dict, orig_linelist: list) -> str:
            match_lines = [line for orig_line, line in mapping_table if orig_line == orig_linelist]
            if not match_lines:
                return ""

            line = match_lines[0]
            line_str = linelist2str(line).replace(f"[{ms2formattime(line[0])}]", "") if line[0] else linelist2str(line)

            if not has_content(line_str):
                return ""
            if orig_linelist[0] is not None:
                if re.search(end_time_pattern, line_str) or orig_linelist[1] is None:    # 检查是否有结束时间
                    return f"[{ms2formattime(orig_linelist[0])}]{line_str}"
                return f"[{ms2formattime(orig_linelist[0])}]{line_str}[{ms2formattime(orig_linelist[1])}]"
            return line_str

        for orig_linelist in self["orig"]:
            lines = ""
            full_orig_line = linelist2str(orig_linelist)  # 此时line为完整的原文歌词行

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
