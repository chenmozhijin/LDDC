# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional

from PySide6.QtCore import QCoreApplication

from LDDC.common.data.config import cfg
from LDDC.common.exceptions import LyricsFormatError
from LDDC.common.logger import logger
from LDDC.common.models import Lyrics, LyricsFormat, SongInfo, Source
from LDDC.common.task_manager import TaskSignal, TaskWorker
from LDDC.common.utils import read_unknown_encoding_file
from LDDC.core.api.lyrics.local import LocalAPI
from LDDC.core.converter import convert2
from LDDC.core.decryptor import krc_decrypt
from LDDC.core.parser.ass import ass2data
from LDDC.core.parser.json_lrc import json2lyrics
from LDDC.core.parser.krc import KRC_MAGICHEADER, krc2mdata
from LDDC.core.parser.lrc import lrc2data
from LDDC.core.parser.qrc import QRC_MAGICHEADER
from LDDC.core.parser.srt import srt2data
from LDDC.core.parser.utils import judge_lyrics_type


class ConverStatusType(Enum):
    SUCCESS = 0
    FAILURE = 1


@dataclass
class ConverStatus:
    type: ConverStatusType
    index: int


class BatchConvertWorker(TaskWorker):
    progress = TaskSignal[str, int, int, ConverStatus | None]()  # text, value, max_value, ConverStatus
    finished = TaskSignal[int, int]()  # success_count, fail_count

    def __init__(self, file_path_save_paths: list[tuple[Path, Path]], save_root_path: Optional[Path], target_format: LyricsFormat) -> None:
        super().__init__()
        self.file_path_save_paths = file_path_save_paths

        self.save_root_path = save_root_path
        self.target_format = target_format

    def _handle_format_error(self, file_path: Path) -> None:
        """处理不支持的歌词格式错误"""
        msg = f"不支持的歌词格式: {file_path}"
        raise LyricsFormatError(msg)

    def run_task(self) -> None:
        success = 0
        fail = 0
        total = len(self.file_path_save_paths)
        status: ConverStatus | None = None

        for i, (file_path, save_path) in enumerate(self.file_path_save_paths):
            if self.is_stopped:
                break

            self.progress.emit(QCoreApplication.translate("BatchConvert", "正在转换 {}").format(file_path.name), i, total, status)

            try:
                # 解析原文件
                with file_path.open("rb") as f:
                    data = f.read()
                lyrics = Lyrics(SongInfo(Source.Local))
                if data.startswith(QRC_MAGICHEADER):
                    LocalAPI.parse_qrc(lyrics, data, file_path)
                elif data.startswith(KRC_MAGICHEADER):
                    lyrics.tags, multi_lyrics_data = krc2mdata(krc_decrypt(data))
                    lyrics.update(multi_lyrics_data)
                elif file_path.suffix.lower() == ".json":
                    json_data = json.loads(data)
                    lyrics = json2lyrics(json_data)
                else:
                    file_text = read_unknown_encoding_file(file_data=data)
                    # 转换为data防止歌词语言类型推测错误
                    if file_path.suffix.lower() == ".lrc":
                        parsers = [lrc2data]
                    elif file_path.suffix.lower() == ".srt":
                        parsers = [srt2data]
                    elif file_path.suffix.lower() == ".ass":
                        parsers = [ass2data]
                    else:
                        parsers = [lrc2data, srt2data, ass2data]
                    for parser in parsers:
                        tags, lyrics_data = parser(file_text)
                        if lyrics_data:
                            break
                    else:
                        self._handle_format_error(file_path)

                    lyrics.tags.update(tags)
                    lyrics["orig"] = lyrics_data

                for key, lyric in lyrics.items():
                    lyrics.types[key] = judge_lyrics_type(lyric)

                # 转换格式
                converted = convert2(lyrics, cfg["langs_order"], self.target_format)

                # 保存文件
                save_path.parent.mkdir(parents=True, exist_ok=True)
                with save_path.open("w", encoding="utf-8") as f:
                    f.write(converted)

                success += 1
                status = ConverStatus(ConverStatusType.SUCCESS, i)

            except Exception:
                logger.exception(f"转换失败 {file_path}")
                status = ConverStatus(ConverStatusType.FAILURE, i)
                fail += 1

        self.progress.emit("", 0, 0, status)
        self.finished.emit(success, fail)
