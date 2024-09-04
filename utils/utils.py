# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import contextlib
import locale
import re
import sys
from collections import OrderedDict
from collections.abc import Iterable
from pathlib import Path
from typing import Any

from chardet import detect

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
    from utils.logger import logger
    file_content = None
    if not sign_word:
        sign_word = []
    if not file_data and file_path:
        with Path(file_path).open('rb') as f:
            raw_data = f.read()
    elif file_data:
        raw_data = file_data
    else:
        msg = "file_path and file_data cannot be both None"
        raise ValueError(msg)

    with contextlib.suppress(Exception):
        if sys.version_info >= (3, 11):
            encoding = locale.getencoding()
        else:
            encoding = locale.getpreferredencoding(False)
        if encoding in ("chinese", "csiso58gb231280", "euc-cn", "euccn", "eucgb2312-cn", "gb2312-1980", "gb2312-80", "iso-ir-58", "936", "cp936", "ms936"):
            encoding = "gb18030"
        file_content = raw_data.decode(encoding)
        for sign in sign_word:
            if sign not in file_content:
                file_content = None
                break
        if encoding == "gb18030" and file_content and "锘縍EM" in file_content:  # 修复编码检测错误
            file_content = None

    if file_content is None:
        detect_result = detect(raw_data)
        if detect_result['confidence'] > 0.7 and detect_result['encoding']:
            encoding = detect_result['encoding'].replace('gb2312', 'gb18030').replace('gbk', 'gb18030')  # gbk is a subset of gb18030
            with contextlib.suppress(Exception):
                file_content = raw_data.decode(encoding)
                for sign in sign_word:
                    if sign not in file_content:
                        file_content = None
                        break

    if file_content is None:
        encodings = ("utf_8", "gb18030", "shift_jis", "cp949", "big5", "big5hkscs",
                     "euc_kr", "euc_jp", "iso2022_jp", "shift_jisx0213", "shift_jis_2004",
                     "utf_16", "utf_16_le", "utf_16_be", "utf_32", "utf_32_le", "utf_32_be",
                     "ascii", "cp950", "cp932", "iso2022_kr", "euc_jis_2004", "euc_jisx0213",
                     "iso2022_jp_1", "iso2022_jp_2", "iso2022_jp_2004", "iso2022_jp_3",
                     "iso2022_jp_ext", "latin_1", "cp874", "hz", "johab", "koi8_r", "koi8_u",
                     "koi8_t", "kz1048", "mac_cyrillic", "mac_greek", "mac_iceland",
                     "mac_latin2", "mac_roman", "mac_turkish", "ptcp154", "utf_7", "utf_8_sig",
                     "iso8859_2", "iso8859_3", "iso8859_4", "iso8859_5", "iso8859_6", "iso8859_7",
                     "iso8859_8", "iso8859_9", "iso8859_10", "iso8859_11", "iso8859_13",
                     "iso8859_14", "iso8859_15", "iso8859_16", "cp037", "cp273", "cp424",
                     "cp437", "cp500", "cp720", "cp737", "cp775", "cp850", "cp852", "cp855",
                     "cp856", "cp857", "cp858", "cp860", "cp861", "cp862", "cp863", "cp864",
                     "cp865", "cp866", "cp869", "cp875", "cp1006", "cp1026", "cp1125", "cp1140",
                     "cp1250", "cp1251", "cp1252", "cp1253", "cp1254", "cp1255", "cp1256", "cp1257",
                     "cp1258")
        for encoding in encodings:
            with contextlib.suppress(Exception):
                file_content = raw_data.decode(encoding)
                for sign in sign_word:
                    if sign not in file_content:
                        file_content = None
                        break
                if file_content is not None:
                    break

    if file_content is None:
        msg = "无法解码文件"
        raise DecodingError(msg)

    logger.debug("文件 %s 解码成功,编码为 %s", file_path, encoding)
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
