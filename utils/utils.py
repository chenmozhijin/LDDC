# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from difflib import SequenceMatcher

from utils.data import data
from utils.enum import LyricsFormat


def get_divmod_time(ms: int) -> tuple[int, int, int, int]:
    total_s, ms = divmod(ms, 1000)
    h, remainder = divmod(total_s, 3600)
    m, s = divmod(remainder, 60)
    return h, m, s, ms


def ms2formattime(ms: int) -> str:
    _h, m, s, ms = get_divmod_time(ms)
    data.mutex.lock()
    lrc_ms_digit_count = data.cfg["lrc_ms_digit_count"]
    data.mutex.unlock()
    if lrc_ms_digit_count == 2:
        ms = round(ms / 10)
        return f"{int(m):02d}:{int(s):02d}.{int(ms):02d}"
    return f"{int(m):02d}:{int(s):02d}.{int(ms):03d}"  # lrc_ms_digit_count == 3


def ms2srt_timestamp(ms: int) -> str:
    h, m, s, ms = get_divmod_time(ms)

    return f"{int(h):02d}:{int(m):02d}:{int(s):02d},{int(ms):03d}"


def ms2ass_timestamp(ms: int) -> str:
    h, m, s, ms = get_divmod_time(ms)

    return f"{int(h):02d}:{int(m):02d}:{int(s):02d}.{int(ms):03d}"


def time2ms(m: int | str, s: int | str, ms: int | str) -> int:
    """时间转毫秒"""
    return (int(m) * 60 + int(s)) * 1000 + int(ms)


def get_lyrics_format_ext(lyrics_format: LyricsFormat) -> str:
    match lyrics_format:
        case LyricsFormat.VERBATIMLRC | LyricsFormat.LINEBYLINELRC:
            return ".lrc"
        case LyricsFormat.SRT:
            return ".srt"
        case LyricsFormat.ASS:
            return ".ass"


def str2log_level(level: str) -> int:
    match level:
        case "NOTSET":
            return 0
        case "DEBUG":
            return 10
        case "INFO":
            return 20
        case "WARNING":
            return 30
        case "ERROR":
            return 40
        case "CRITICAL":
            return 50


def tuple_to_list(obj: any) -> any:
    if isinstance(obj, list | tuple):
        return [tuple_to_list(item) for item in obj]
    return obj


def replace_placeholders(text: str, mapping_table: dict) -> str:
    for placeholder, value in mapping_table.items():
        text = text.replace(placeholder, str(value))
    return text


def escape_path(path: str) -> str:
    drive_letter = ""
    replacement_dict = {
        ':': '：',
        '*': '＊',
        '?': '？',
        '"': '＂',
        '<': '＜',
        '>': '＞',
        '|': '｜',
        '\n': '',
    }
    if path[0].isupper() and path[1] == ":" and path[2] == "\\":
        drive_letter = path[:3]
        path = path[3:]

    return drive_letter + replace_placeholders(path, replacement_dict)


def escape_filename(filename: str) -> str:
    replacement_dict = {
        '/': '／',
        '\\': '＼',
        ':': '：',
        '*': '＊',
        '?': '？',
        '"': '＂',
        '<': '＜',
        '>': '＞',
        '|': '｜',
        '\n': '',
    }

    return replace_placeholders(filename, replacement_dict)


def replace_info_placeholders(text: str, info: dict, lyrics_types: list) -> str:
    """替换路径中的歌曲信息占位符"""
    mapping_table = {
        "%<title>": escape_filename(info['title']),
        "%<artist>": escape_filename(info["artist"]),
        "%<id>": escape_filename(str(info["id"])),
        "%<album>": escape_filename(info["album"]),
        "%<types>": escape_filename("-".join(lyrics_types)),
    }
    return replace_placeholders(text, mapping_table)


def get_save_path(folder: str, file_name_format: str, info: dict, lyrics_types: list) -> tuple[str, str]:
    folder = escape_path(replace_info_placeholders(folder, info, lyrics_types)).strip()
    file_name = escape_filename(replace_info_placeholders(file_name_format, info, lyrics_types))
    return folder, file_name


def text_difference(text1: str, text2: str) -> float:
    # 计算编辑距离
    differ = SequenceMatcher(None, text1, text2)
    return differ.ratio()
