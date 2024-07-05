# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import logging
import re
from typing import NewType

from utils.data import cfg
from utils.enum import (
    LyricsFormat,
    LyricsType,
    Source,
)

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
        self.title = info.get("title", None)
        self.artist = info.get("artist", None)
        self.album = info.get("album", None)
        self.id = info.get("id", None)
        self.mid = info.get("mid", None)
        self.duration = info.get("duration", None)
        self.accesskey = info.get("accesskey", None)

        self.types = {}
        self.tags = {}

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

        if self.types["orig"] == LyricsType.PlainText:
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

            case LyricsFormat.JSON:
                json_dict = {"version": 0, "info": {}, "tags": self.tags, "lyrics": dict(self)}
                for key, value in vars(self).items():
                    if key in ("source", "title", "artist", "album", "id", "mid", "duration", "accesskey"):
                        if key == "source":
                            value: Source
                            json_dict["info"][key] = value.name
                        else:
                            json_dict["info"][key] = value

                return json.dumps(json_dict, ensure_ascii=False)
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
