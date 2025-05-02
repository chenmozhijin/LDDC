# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os
from pathlib import Path

from LDDC.common.models import FileNameMode, LyricsFormat, SaveMode, SongInfo


def replace_placeholders(text: str, mapping_table: dict) -> str:
    for placeholder, value in mapping_table.items():
        text = text.replace(placeholder, str(value))
    return text


def escape_path(path: str) -> str:
    drive_letter = ""
    replacement_dict = {
        ":": "：",
        "*": "＊",
        "?": "？",
        '"': "＂",
        "<": "＜",
        ">": "＞",
        "|": "｜",
        "\n": "",
    }
    if path[0].isupper() and path[1] == ":" and path[2] == "\\":
        drive_letter = path[:3]
        path = path[3:]

    return drive_letter + replace_placeholders(path, replacement_dict)


def escape_filename(filename: str) -> str:
    replacement_dict = {
        "/": "／",
        "\\": "＼",
        ":": "：",
        "*": "＊",
        "?": "？",
        '"': "＂",
        "<": "＜",
        ">": "＞",
        "|": "｜",
        "\n": "",
    }

    return replace_placeholders(filename, replacement_dict)


def replace_info_placeholders(text: str, info: SongInfo, lyric_langs: list) -> str:
    """替换路径中的歌曲信息占位符"""
    if not info.id and "%<id>" in text:
        text = text.replace("(%<id>)", "").replace("（%<id>）", "")
    mapping_table = {
        "%<title>": escape_filename(info.title or "?"),
        "%<artist>": escape_filename(info.str_artist or "?"),
        "%<id>": escape_filename(info.id or "?"),
        "%<album>": escape_filename(info.album or "?"),
        "%<langs>": escape_filename("-".join(lyric_langs)),
    }
    return replace_placeholders(text, mapping_table)


def get_save_path(folder: Path, file_name_format: str, info: SongInfo, lyric_langs: list) -> tuple[Path, str]:
    folder = Path(escape_path(replace_info_placeholders(str(folder), info, lyric_langs)).strip())
    file_name = escape_filename(replace_info_placeholders(file_name_format, info, lyric_langs))
    return folder, file_name


def get_local_match_save_path(
    save_mode: SaveMode,
    file_name_mode: FileNameMode,
    local_info: SongInfo,
    lyrics_format: LyricsFormat,
    file_name_format: str,
    langs: list[str],
    save_root_path: Path | None = None,
    cloud_info: SongInfo | None = None,
    allow_placeholder: bool = False,
    song_root_path: Path | None = None,
) -> Path | int:
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
    if not local_info.path:
        msg = "没有本地歌曲路径"
        raise ValueError(msg)
    match save_mode:
        case SaveMode.MIRROR:
            if save_root_path is None:
                return -1
            if song_root_path is None:
                return -3
            save_folder = save_root_path / Path(os.path.relpath(local_info.path, song_root_path)).parent
            # save_folder = save_root_path / local_info.path.relative_to(song_root_path).parent  慢三倍
        case SaveMode.SONG:
            save_folder = local_info.path.parent

        case SaveMode.SPECIFY:
            if save_root_path is None:
                return -1
            save_folder = save_root_path

    ext = lyrics_format.ext

    match file_name_mode:
        case FileNameMode.SONG:
            if local_info.from_cue is True:
                save_folder = save_folder / local_info.path.stem
                if cloud_info is None:
                    if allow_placeholder:
                        save_filename = file_name_format + ext
                    else:
                        return -2
                else:
                    save_filename = escape_filename(replace_info_placeholders(file_name_format, local_info, langs)) + ext
            else:
                save_filename = local_info.path.stem + ext

        case FileNameMode.FORMAT_BY_LYRICS:
            if cloud_info is None:
                if allow_placeholder:
                    save_filename = file_name_format + ext
                else:
                    return -2
            else:
                save_filename = escape_filename(replace_info_placeholders(file_name_format, cloud_info, langs)) + ext

        case FileNameMode.FORMAT_BY_SONG:
            if local_info.from_cue is False and not local_info.title:
                save_filename = local_info.path.stem + ext
            else:
                save_filename = escape_filename(replace_info_placeholders(file_name_format, local_info, langs)) + ext

    return save_folder / save_filename
