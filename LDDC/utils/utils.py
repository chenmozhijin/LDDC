# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import contextlib
import locale
import os
import re
import sys
from collections import OrderedDict
from collections.abc import Iterable
from typing import Any

from charset_normalizer import from_bytes, from_path

from .enum import LocalMatchFileNameMode, LocalMatchSaveMode, LyricsFormat
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
    if sys.version_info >= (3, 11):
        sys_encoding = [locale.getencoding()]
    else:
        sys_encoding = [locale.getpreferredencoding(False)]
    if sys_encoding[0] in ("chinese", "csiso58gb231280", "euc-cn", "euccn", "eucgb2312-cn", "gb2312-1980", "gb2312-80", "iso-ir-58", "936", "cp936", "ms936"):
        sys_encoding = ["gb18030", "chinese", "csiso58gb231280", "euc-cn", "euccn", "eucgb2312-cn", "gb2312-1980", "gb2312-80", "iso-ir-58", "936", "cp936",
                        "ms936"]
    file_content = None
    with contextlib.suppress(Exception):
        if file_data is not None:
            file_content = file_data.decode(sys_encoding[0])
        elif file_path is not None:
            with open(file_path, encoding=sys_encoding[0]) as f:
                file_content = f.read()
        else:
            msg = "文件路径和文件数据不能同时为空"
            raise ValueError(msg)
        if sys_encoding[0] == "gb18030" and "锘縍EM" in file_content:
            file_content = None
        if sign_word is not None and file_content is not None:
            for sign in sign_word:
                if sign not in file_content:
                    file_content = None
                    break

    if file_content is None:
        if file_data is not None:
            results = from_bytes(file_data)
        elif file_path is not None:
            results = from_path(file_path)
        else:
            msg = "文件路径和文件数据不能同时为空"
            raise ValueError(msg)

        from LDDC.utils.logger import logger
        logger.debug(f"Charset normalizer results: {"\n".join([m.encoding for m in results])}")

        filtered_results = []
        if sign_word is not None:
            for result in results:
                for sign in sign_word:
                    if sign not in str(result):
                        break
                else:
                    filtered_results.append(result)

        for result in filtered_results:
            if result.encoding in sys_encoding:
                file_content = str(result)
                break
        else:
            if filtered_results:
                file_content = str(filtered_results[0])

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


def get_local_match_save_path(save_mode: LocalMatchSaveMode,
                              file_name_mode: LocalMatchFileNameMode,
                              song_info: dict,
                              lyrics_format: LyricsFormat,
                              file_name_format: str,
                              langs: list[str],
                              save_root_path: str | None = None,
                              lrc_info: dict | None = None,
                              allow_placeholder: bool = False) -> str | int:
    """获取本地匹配歌词保存路径

    :param save_mode: 保存模式
    :param file_name_mode: 文件名模式
    :param song_info: 歌曲信息
    :param lyrics_format: 歌词格式
    :param file_name_format: 文件名格式
    :param langs: 歌词语言
    :param save_root_path: 保存根目录
    :param lrc_info: 歌词信息
    :return: 保存路径 -1: 保存根目录为空 -2: 歌词信息为空
    :rtype: str | int
    """
    match save_mode:
        case LocalMatchSaveMode.MIRROR:
            if save_root_path is None:
                return -1
            song_root_path = song_info.get("root_path")
            if song_root_path is None:
                return -3
            save_folder = os.path.join(save_root_path,
                                       os.path.dirname(os.path.relpath(song_info["file_path"], song_root_path)))
        case LocalMatchSaveMode.SONG:
            save_folder = os.path.dirname(song_info["file_path"])

        case LocalMatchSaveMode.SPECIFY:
            if save_root_path is None:
                return -1
            save_folder = save_root_path

    save_folder = escape_path(save_folder).strip()
    ext = get_lyrics_format_ext(lyrics_format)

    match file_name_mode:
        case LocalMatchFileNameMode.SONG:
            if song_info["type"] == "cue":
                save_folder = os.path.join(save_folder, os.path.splitext(os.path.basename(song_info["file_path"]))[0])
                if lrc_info is None:
                    if allow_placeholder:
                        save_filename = file_name_format + ext
                    else:
                        return -2
                else:
                    save_filename = escape_filename(
                        replace_info_placeholders(file_name_format, lrc_info, langs)) + ext
            else:
                save_filename = os.path.splitext(os.path.basename(song_info["file_path"]))[0] + ext

        case LocalMatchFileNameMode.FORMAT:
            if lrc_info is None:
                if allow_placeholder:
                    save_filename = file_name_format + ext
                else:
                    return -2
            else:
                save_filename = escape_filename(
                    replace_info_placeholders(file_name_format, lrc_info, langs)) + ext

    return os.path.join(save_folder, save_filename)


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
