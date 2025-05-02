# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import json
import re
from pathlib import Path

from LDDC.common.exceptions import LyricsFormatError
from LDDC.common.models import LyricInfo, Lyrics, QrcType, SongInfo, Source
from LDDC.common.utils import read_unknown_encoding_file
from LDDC.core.decryptor import krc_decrypt, qrc_decrypt
from LDDC.core.parser.ass import ass2mdata
from LDDC.core.parser.json_lrc import json2lyrics
from LDDC.core.parser.krc import KRC_MAGICHEADER, krc2mdata
from LDDC.core.parser.lrc import lrc2mdata
from LDDC.core.parser.qrc import QRC_MAGICHEADER, qrc_str_parse
from LDDC.core.parser.srt import srt2mdata
from LDDC.core.parser.utils import judge_lyrics_type

from .models import BaseAPI


class LocalAPI(BaseAPI):
    source = Source.Local

    def _get_input_data(
        self,
        info: LyricInfo | None = None,
        path: Path | None = None,
        data: str | bytearray | bytes | None = None,
    ) -> tuple[Path | None, bytes]:
        if isinstance(info, SongInfo):
            msg = "LocalAPI不支持SongInfo"
            raise NotImplementedError(msg)

        if not path and info:
            path = info.path

        if not data and info:
            data = info.data

        if not path and not data:
            msg = "没有任何文件路径和数据"
            raise ValueError(msg)

        if path and not data:
            data = path.read_bytes()

        if not data:
            msg = "没有任何文件数据"
            raise ValueError(msg)

        return path, bytes(data.encode("utf-8") if isinstance(data, str) else data)

    @classmethod
    def parse_qrc(cls, lyrics: Lyrics, data: bytes, path: Path | None = None) -> None:
        """QRC歌词格式解析"""
        # 做到打开任意qrc文件都会读取同一首歌其他类型的qrc
        if path:
            m_qrc_path = re.search(r"^(?P<prefix>.*)_qm(?P<qrc_type>Roma|ts)?\.qrc$", str(path))
        if path and m_qrc_path:
            qrc_types = {m_qrc_path.group("qrc_type"): data, **{k: None for k in ("", "Roma", "ts") if k != m_qrc_path.group("qrc_type")}}
            for qrc_type, qrc_data in qrc_types.items():
                if not qrc_data and (qrc_path := Path(f"{m_qrc_path.group('prefix')}_qm{qrc_type}.qrc")).is_file():
                    with qrc_path.open("rb") as f:
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
            lyrics["orig"] = lyric

    def get_lyrics(self, info: LyricInfo | None = None, path: Path | None = None, data: str | bytearray | bytes | None = None) -> Lyrics:
        path, data = self._get_input_data(info, path, data)

        lyrics = Lyrics(info.songinfo if info else SongInfo(Source.Local))
        # 判断歌词格式
        if data.startswith(QRC_MAGICHEADER):
            self.parse_qrc(lyrics, data, path)

        elif data.startswith(KRC_MAGICHEADER):
            # KRC歌词格式
            lyrics.tags, multi_lyrics_data = krc2mdata(krc_decrypt(data))
            lyrics.update(multi_lyrics_data)

        else:
            # 其他歌词格式
            try:
                # JSON歌词格式
                json_data = json.loads(data)
                lyrics = json2lyrics(json_data)
            except Exception:
                if not path or path.suffix.lower() in (".lrc", ".ass", ".srt"):
                    if not path:
                        parsers = [lrc2mdata, ass2mdata, srt2mdata]
                    elif path.suffix.lower() == ".ass":
                        parsers = [ass2mdata]
                    elif path.suffix.lower() == ".lrc":
                        parsers = [lrc2mdata]
                    elif path.suffix.lower() == ".srt":
                        parsers = [srt2mdata]
                    # LRC歌词格式
                    try:
                        file_text = read_unknown_encoding_file(file_data=data)
                        for parser in parsers:
                            result = parser(file_text)
                            tags = {}
                            if isinstance(result, tuple):
                                tags, multi_lyrics_data = result
                            else:
                                multi_lyrics_data = result
                            if any(lyric for lyric in multi_lyrics_data.values()):
                                lyrics.update(multi_lyrics_data)
                                lyrics.tags.update(tags)
                                break
                        else:
                            msg = f"不支持的歌词格式: {path}"
                            raise LyricsFormatError(msg)
                    except UnicodeDecodeError as e:
                        msg = f"不支持的歌词格式: {path}"
                        raise LyricsFormatError(msg) from e
                else:
                    msg = f"不支持的文件格式: {path}"
                    raise LyricsFormatError(msg) from None



        for key, lyric in lyrics.items():
            lyrics.types[key] = judge_lyrics_type(lyric)
        return lyrics
