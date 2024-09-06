# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import contextlib
import locale
import re
import sys
from collections import OrderedDict
from collections.abc import Iterable
from typing import Any

from charset_normalizer import from_bytes, from_path

from .enum import LyricsFormat
from .error import DecodingError


def get_lyrics_format_ext(lyrics_format: LyricsFormat) -> str:
    """返回歌词格式对应的文件扩展名"""
    match lyrics_format:
        case LyricsFormat.VERBATIMLRC | LyricsFormat.LINEBYLINELRC | LyricsFormat.ENHANCEDLRC:
            return ".lrc"
        case LyricsFormat.SRT:
            return ".srt"
        case LyricsFormat.ASS:
            return ".ass"
        case _:
            msg = f"Unknown lyrics format: {lyrics_format}"
            raise ValueError(msg)


def time2ms(m: int | str, s: int | str, ms: int | str) -> int:
    """时间转毫秒"""
    if isinstance(ms, str) and len(ms) == 2:
        ms += "0"
    return (int(m) * 60 + int(s)) * 1000 + int(ms)


def read_unknown_encoding_file(file_path: str | None = None, file_data: bytes | None = None, sign_word: Iterable[str] | None = None) -> str:
    """读取未知编码的文件"""
    if file_data is not None:
        results = from_bytes(file_data)
    elif file_path is not None:
        results = from_path(file_path)
    else:
        msg = "文件路径和文件数据不能同时为空"
        raise ValueError(msg)
    file_content = None
    if sign_word is not None:
        for result in results:
            for sign in sign_word:
                if sign not in str(result):
                    break
            else:
                file_content = str(result)
                break
    else:
        best = results.best()
        if best is not None:
            file_content = str(best)

    if file_content is None:
        with contextlib.suppress(Exception):
            if sys.version_info >= (3, 11):
                encoding = locale.getencoding()
            else:
                encoding = locale.getpreferredencoding(False)
            if encoding in ("chinese", "csiso58gb231280", "euc-cn", "euccn", "eucgb2312-cn", "gb2312-1980", "gb2312-80", "iso-ir-58", "936", "cp936", "ms936"):
                encoding = "gb18030"
            if file_data is not None:
                file_content = file_data.decode(encoding)
            elif file_path is not None:
                with open(file_path, encoding=encoding) as f:
                    file_content = f.read()
            if sign_word is not None and file_content is not None:
                for sign in sign_word:
                    if sign not in file_content:
                        file_content = None
                        break
    if file_content is None:
        msg = "无法解码文件"
        raise DecodingError(msg)

    return file_content


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


def replace_info_placeholders(text: str, info: dict, lyric_langs: list) -> str:
    """替换路径中的歌曲信息占位符"""
    mapping_table = {
        "%<title>": escape_filename(info['title']),
        "%<artist>": escape_filename("/".join(info["artist"]) if isinstance(info["artist"], list) else info["artist"]),
        "%<id>": escape_filename(str(info["id"])),
        "%<album>": escape_filename(info["album"]),
        "%<langs>": escape_filename("-".join(lyric_langs)),
    }
    return replace_placeholders(text, mapping_table)


def get_save_path(folder: str, file_name_format: str, info: dict, lyric_langs: list) -> tuple[str, str]:
    folder = escape_path(replace_info_placeholders(folder, info, lyric_langs)).strip()
    file_name = escape_filename(replace_info_placeholders(file_name_format, info, lyric_langs))
    return folder, file_name


def get_artist_str(artist: str | list | None, sep: str = "/") -> str:
    if artist is None:
        return ""
    return sep.join(artist) if isinstance(artist, list) else artist


def get_divmod_time(ms: int) -> tuple[int, int, int, int]:
    total_s, ms = divmod(ms, 1000)
    h, remainder = divmod(total_s, 3600)
    return h, *divmod(remainder, 60), ms


def ms2formattime(ms: int) -> str:
    _h, m, s, ms = get_divmod_time(ms)
    return f"{int(m):02d}:{int(s):02d}.{int(ms):03d}"


class LimitedSizeDict(OrderedDict):
    def __init__(self, max_size: int, *args: Any, **kwargs: Any) -> None:
        self.max_size = max_size
        super().__init__(*args, **kwargs)

    def __setitem__(self, key: Any, value: Any) -> None:
        if len(self) >= self.max_size:
            self.popitem(last=False)  # 删除最早插入的项目
        super().__setitem__(key, value)


def has_content(line: str) -> bool:
    """检查是否有实际内容"""
    content = re.sub(r"\[\d+:\d+\.\d+\]|\[\d+,\d+\]|<\d+:\d+\.\d+>", "", line).strip()
    if content in ("", "//"):
        return False
    return not (len(content) == 2 and content[0].isupper() and content[1] == "：")  # 歌手标签行
