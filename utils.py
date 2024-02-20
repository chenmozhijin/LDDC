# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
def ms2formattime(ms: int) -> str:
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{int(m):02d}:{int(s):02d}.{int(ms):03d}"


def time2ms(m: int, s: int, ms: int) -> int:
    """时间转毫秒"""
    return int((m * 60 + s) * 1000 + ms)


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
    file_name = escape_path(replace_info_placeholders(file_name_format, info, lyrics_types))
    return folder, file_name
