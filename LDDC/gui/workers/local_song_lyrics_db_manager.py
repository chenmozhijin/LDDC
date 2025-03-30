# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from threading import Lock
from typing import ClassVar

from mutagen._util import MutagenError
from PySide6.QtCore import (
    QCoreApplication,
    QMimeData,
)

from LDDC.common.data.config import cfg
from LDDC.common.exceptions import LyricsNotFoundError
from LDDC.common.logger import logger
from LDDC.common.models import FileNameMode, LyricsFormat, SaveMode, SongInfo, Source
from LDDC.common.path_processor import escape_filename, replace_info_placeholders
from LDDC.common.task_manager import TaskSignal, TaskWorker
from LDDC.core.auto_fetch import auto_fetch
from LDDC.core.parser.cue import parse_cue
from LDDC.core.song_info import audio_formats, get_audio_file_infos, parse_drop_infos, write_lyrics

class LocalSongLyricsDBSignals(QObject):
    


class LocalSongLyricsDBWorker(TaskWorker):
    progress = TaskSignal(int, int)
    finished = TaskSignal(bool, str)
    def __init__(self, task: Literal["backup", "restore", "clear", "change_dir", "del_all", "export"], *args: Any, **kwargs: Any) -> None:
        super().__init__()
        self.signals = LocalSongLyricsDBSignals()
        self.task = task
        self.args = args
        self.kwargs = kwargs

    def run(self) -> None:
        msg = QCoreApplication.translate("LocalSongLyricsDB", "成功")
        try:
            match self.task:
                case "backup":
                    msg = self.backup(*self.args, **self.kwargs)
                case "restore":
                    msg = self.restore(*self.args, **self.kwargs)
                case "clear":
                    msg = self.clear(*self.args, **self.kwargs)
                case "change_dir":
                    msg = self.change_dir(*self.args, **self.kwargs)
                case "del_all":
                    msg = self.del_all(*self.args, **self.kwargs)
                case "export":
                    msg = self.export(*self.args, **self.kwargs)
        except Exception as e:
            self.signals.finished.emit(False, str(e))
            logger.exception(e)
        else:
            self.signals.finished.emit(True, msg)

    def backup(self, path: str) -> str:
        if not path.endswith(".json"):
            path += ".json"
        with open(path, "w", encoding="UTF-8") as f:
            json.dump([{
                "title": item[1] if item[1] != '' else None,
                "artist": item[2] if item[2] != '' else None,
                "album": item[3] if item[3] != '' else None,
                "duration": item[4] if item[4] != -1 else None,
                "song_path": item[5] if item[5] != '' else None,
                "track_number": item[6] if item[6] != '' else None,
                "lyrics_path": item[7] if item[7] != '' else None,
                "config": json.loads(item[8]),
            } for item in local_song_lyrics.get_all()], f, ensure_ascii=False)
        return QCoreApplication.translate("LocalSongLyricsDB", "备份成功")

    def restore(self, path: str) -> str:
        with open(path, encoding="UTF-8") as f:
            json_data = json.load(f)
        if not isinstance(json_data, list):
            msg = "数据格式错误, 应为列表"
            raise TypeError(msg)

        local_song_lyrics.del_all()
        for item in json_data:
            local_song_lyrics.set_song(**item)
        return QCoreApplication.translate("LocalSongLyricsDB", "恢复成功")

    def clear(self) -> str:
        """清理无效数据"""
        all_data = local_song_lyrics.get_all()
        data_len = len(all_data)
        frequency = max(data_len // 20, 1)
        count = 0
        for i, (id_, _title, _artist, _album, _duration, song_path, _track_number, lyrics_path, _config) in enumerate(all_data):
            song_path: str
            lyrics_path: str | None
            if (song_path.startswith("file://") and not os.path.exists(song_path[7:])) or (lyrics_path and not os.path.exists(lyrics_path)):
                local_song_lyrics.del_item(id_)
                count += 1
            if i % frequency == 0:
                self.signals.progress.emit(i, data_len)

        return QCoreApplication.translate("LocalSongLyricsDB", "清理成功, 共清理了 {0} 条数据").format(count)

    def del_all(self) -> str:
        local_song_lyrics.del_all()
        return QCoreApplication.translate("LocalSongLyricsDB", "删除成功")

    def change_dir(self, old_dir: str, new_dir: str, del_old: bool) -> str:
        all_data = local_song_lyrics.get_all()
        data_len = len(all_data)
        frequency = max(data_len // 20, 1)
        success_count = 0
        for i, (id_, title, artist, album, duration, song_path, track_number, lyrics_path, config) in enumerate(all_data):
            change = False
            song_path: str
            lyrics_path: str | None
            if song_path.startswith("file://") and song_path[7:].startswith(old_dir):
                new_song_path = "file://" + new_dir + song_path[7 + len(old_dir):]
                if os.path.exists(new_song_path[7:]):
                    change = True
                    song_path = new_song_path  # noqa: PLW2901
            if lyrics_path and lyrics_path.startswith(old_dir):
                new_lyrics_path = new_dir + lyrics_path[len(old_dir):]
                if os.path.exists(new_lyrics_path):
                    change = True
                    lyrics_path = new_lyrics_path  # noqa: PLW2901
            if change:
                local_song_lyrics.set_song(title, artist, album, duration, song_path, track_number, lyrics_path, json.loads(config))
                if del_old:
                    local_song_lyrics.del_item(id_)
                success_count += 1
            if i % frequency == 0:
                self.signals.progress.emit(i, data_len)
        return QCoreApplication.translate("LocalSongLyricsDB", "修改成功, 共修改了 {0} 条数据").format(success_count)

    def export(self,
               save_mode: LocalMatchSaveMode,
               lyrics_format: LyricsFormat,
               langs: list[str],
               file_name_mode: LocalMatchFileNameMode,
               save_root_path: str) -> str:
        all_data = local_song_lyrics.get_all()
        data_len = len(all_data)
        frequency = max(data_len // 20, 1)
        file_name_format = cfg["lyrics_file_name_fmt"]
        success_count = 0
        skip_count = 0
        for i, (_id, title, artist, album, duration, song_path, track_number, lyrics_path, config) in enumerate(all_data):
            song_path: str
            if json.loads(config).get("inst") is True or not lyrics_path:
                skip_count += 1
                continue
            try:
                lyrics = get_lyrics(Source.Local, False, path=lyrics_path)[0]
            except Exception:
                logger.exception("获取歌词失败: %s", lyrics_path)
                continue
            song_info = {"title": title,
                         "artist": artist,
                         "album": album,
                         "duration": duration,
                         "file_path": song_path,
                         "track_number": track_number,
                         "type": "song" if not song_path.endswith(".cue") else "cue"}
            if cfg["lrc_tag_info_src"] == 1:
                # 从歌曲文件获取标签信息
                lyrics = lyrics.update_info(song_info)
            converted_lyrics = convert2(lyrics, langs, lyrics_format)
            save_path = get_local_match_save_path(save_mode=save_mode,
                                                  file_name_mode=file_name_mode,
                                                  song_info=song_info,
                                                  lyrics_format=lyrics_format,
                                                  langs=langs,
                                                  save_root_path=save_root_path,
                                                  lrc_info=lyrics.get_info(),
                                                  file_name_format=file_name_format)
            if isinstance(save_path, int):
                logger.error("获取歌词保存路径失败，错误码: %s", save_path)
                continue

            try:
                if not os.path.exists(os.path.dirname(save_path)):
                    os.makedirs(os.path.dirname(save_path))

                with open(save_path, "w", encoding="utf-8") as f:
                    f.write(converted_lyrics)
            except Exception:
                logger.exception("保存歌词失败")
                continue
            success_count += 1

            if i % frequency == 0:
                self.signals.progress.emit(i, data_len)

        return QCoreApplication.translate("LocalSongLyricsDB", "导出成功, 共导出了 {0}/{1} 条数据").format(success_count, data_len - skip_count)