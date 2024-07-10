# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import contextlib
from collections.abc import Iterable
from pathlib import Path

from chardet import detect

from .enum import LyricsFormat

try:
    version = __import__("__main__").__version__.replace("v", "")
except Exception:
    version = None


def get_lyrics_format_ext(lyrics_format: LyricsFormat) -> str:
    match lyrics_format:
        case LyricsFormat.VERBATIMLRC | LyricsFormat.LINEBYLINELRC | LyricsFormat.ENHANCEDLRC:
            return ".lrc"
        case LyricsFormat.SRT:
            return ".srt"
        case LyricsFormat.ASS:
            return ".ass"


def time2ms(m: int | str, s: int | str, ms: int | str) -> int:
    """时间转毫秒"""
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

    detect_result = detect(raw_data)
    if detect_result['confidence'] > 0.7:
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
        raise UnicodeDecodeError(reason=msg, object=raw_data)

    logger.debug("文件 %s 解码成功,编码为 %s", file_path, encoding)
    return file_content


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


def compare_version_numbers(current_version: str, last_version: str) -> bool:
    last_version = tuple(int(i.split("-")[0]) for i in last_version.replace("v", "").split("."))
    current_version = tuple(int(i.split("-")[0]) for i in current_version.replace("v", "").split("."))
    if last_version == current_version and "beta" in current_version and "beta" not in last_version:
        return True
    return current_version < last_version


def get_artist_str(artist: str | list, sep: str = "/") -> str:
    return sep.join(artist) if isinstance(artist, list) else artist


def get_divmod_time(ms: int) -> tuple[int, int, int, int]:
    return divmod(ms, 3600000)[0], divmod(ms, 60000)[0], *divmod(ms, 1000)


def ms2formattime(ms: int) -> str:
    _h, m, s, ms = get_divmod_time(ms)
    return f"{int(m):02d}:{int(s):02d}.{int(ms):03d}"
