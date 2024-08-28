# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import os
import re

from backend.lyrics import Lyrics
from utils.enum import QrcType, Source
from utils.error import LyricsFormatError, LyricsNotFoundError, LyricsProcessingError
from utils.utils import read_unknown_encoding_file

from .kg import krc2dict, krc_decrypt
from .qm import qrc_decrypt, qrc_str_parse
from .share import lrc2dict

QRC_MAGICHEADER = b'\x98%\xb0\xac\xe3\x02\x83h\xe8\xfcl'
KRC_MAGICHEADER = b'krc18'


def json2lyrics(json_data: dict, lyrics: Lyrics) -> None:
    if not isinstance(json_data, dict):
        msg = "JSON歌词数据必须是一个字典"
        raise LyricsProcessingError(msg)

    for key, type_ in (("version", int), ("info", dict), ("tags", dict), ("lyrics", dict)):
        if key not in json_data:
            msg = f"JSON歌词数据缺少必要的键: {key}"
            raise LyricsProcessingError(msg)
        if not isinstance(json_data[key], type_):
            msg = f"JSON歌词数据中包含值类型不正确的键: {key}"
            raise LyricsProcessingError(msg)

    if json_data["version"] != 0:
        msg = "JSON歌词数据版本号不正确"
        raise LyricsProcessingError(msg)

    for key, value in json_data["info"].items():
        key: str
        value: str | int

        if key == "source" and isinstance(value, str):
            lyrics.source = Source.__members__.get(value)
            if lyrics.source is None:
                msg = f"JSON歌词数据中包含不正确的值: {value}"
                raise LyricsProcessingError(msg)

        elif ((key in ("source", "title", "album", "mid", "accesskey") and not isinstance(value, str)) or
                (key == "duration" and not isinstance(value, int)) or
                (key == "artist" and not isinstance(value, str | list)) or
                (key == "id" and not isinstance(value, str | int))):
            msg = f"JSON歌词数据中包含值类型不正确的键: {key}"
            raise LyricsProcessingError(msg)
        else:
            setattr(lyrics, key, value)

    for key, value in json_data["tags"].items():
        if not isinstance(key, str):
            msg = f"JSON歌词数据中包含值类型不正确的键: {key}"
            raise LyricsProcessingError(msg)
        if not isinstance(value, str):
            msg = f"JSON歌词数据中包含不正确的值: {value}"
            raise LyricsProcessingError(msg)
        lyrics.tags[key] = value

    for key, lyrics_data in json_data["lyrics"].items():
        lyrics_data: list[list]
        if not isinstance(key, str | int):
            msg = f"JSON歌词数据中包含不正确的键: {key}"
            raise LyricsProcessingError(msg)

        lyrics[key] = []
        for line in lyrics_data:
            lyrics[key].append((line[0], line[1], [tuple(word) for word in line[2]]))


def get_lyrics(lyrics: Lyrics, path: str | None, data: bytes | None = None) -> None:
    if data is None:
        if not path or not os.path.isfile(path):
            msg = f"没有找到歌词: {path}"
            raise LyricsNotFoundError(msg)

        with open(path, 'rb') as f:
            data = f.read()

    # 判断歌词格式
    if data.startswith(QRC_MAGICHEADER) and path:
        # QRC歌词格式

        # 做到打开任意qrc文件都会读取同一首歌其他类型的qrc
        qrc_path = re.search(r"^(?P<prefix>.*)_qm(?P<qrc_type>Roma|ts)?\.qrc$", path)
        if qrc_path:
            qrc_types = {qrc_path.group("qrc_type"): data, **{k: None for k in ("", "Roma", "ts") if k != qrc_path.group("qrc_type")}}
            for qrc_type, qrc_data in qrc_types.items():

                if not qrc_data and os.path.isfile(f"{qrc_path.group('prefix')}_qm{qrc_type}.qrc"):
                    with open(f"{qrc_path.group('prefix')}_qm{qrc_type}.qrc", 'rb') as f:
                        qrc_data_ = f.read()
                    if qrc_data_.startswith(QRC_MAGICHEADER):
                        qrc_data = qrc_data_  # noqa: PLW2901

                if qrc_data:
                    lyric = qrc_decrypt(qrc_data, QrcType.LOCAL)
                    tags, lyric = qrc_str_parse(lyric)
                    lyrics.tags.update(tags)
                    match qrc_type:
                        case "":
                            lyrics["orig"] = lyric
                        case "Roma":
                            lyrics["roma"] = lyric
                        case "ts":
                            lyrics["ts"] = lyric
        elif data:
            lyrics.tags, lyric = qrc_str_parse(qrc_decrypt(data, QrcType.LOCAL))
            lyrics[0] = lyric

    elif data.startswith(KRC_MAGICHEADER):
        # KRC歌词格式
        lyrics.tags, multi_lyrics_data = krc2dict(krc_decrypt(data))
        lyrics.update(multi_lyrics_data)

    else:
        # 其他歌词格式
        try:
            # JSON歌词格式
            json_data = json.loads(data)
            json2lyrics(json_data, lyrics)
        except Exception:
            if path and path.lower().split('.')[-1] == 'lrc':
                # LRC歌词格式
                try:
                    file_text = read_unknown_encoding_file(file_data=data, sign_word=("[", "]", ":"))
                    lyrics.tags, multi_lyrics_data = lrc2dict(file_text)
                    lyrics.update(multi_lyrics_data)
                except UnicodeDecodeError:
                    msg = f"不支持的歌词格式: {path}"
                    raise LyricsFormatError(msg) from UnicodeDecodeError
