# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import logging
import os
import time

from PySide6.QtCore import (
    Q_ARG,
    QMetaObject,
    QMutex,
    QObject,
    QRunnable,
    Qt,
    Signal,
)

from api import (
    get_latest_version,
    qm_get_album_song_list,
    qm_get_songlist_song_list,
    qm_search,
)
from data import Data
from lyrics import Lyrics
from ui.sidebar_window import SidebarWindow
from utils import (
    get_save_path,
)

cache = {
    "serach": {},
    "lyrics": {},
    "songlist": {},
}
cache_mutex = QMutex()


class CheckUpdate(QRunnable):
    def __init__(self, is_auto: bool, windows: SidebarWindow, version: str) -> None:
        super().__init__()
        self.isAuto = is_auto
        self.windows = windows
        self.version = version

    def run(self) -> None:
        is_success, last_version = get_latest_version()
        if is_success:

            def compare_version_numbers(current_version: str, last_version: str) -> bool:
                last_version = [int(i) for i in last_version.replace("v", "").split(".")]
                current_version = [int(i) for i in current_version.replace("v", "").split(".")]
                return current_version < last_version

            if compare_version_numbers(self.version, last_version):
                QMetaObject.invokeMethod(self.windows, "show_message", Qt.QueuedConnection,
                                         Q_ARG(str, "update"), Q_ARG(str, "检查更新"), Q_ARG(str, f"发现新版本{last_version},是否前往GitHub下载？"))
            elif not self.isAuto:
                QMetaObject.invokeMethod(self.windows, "show_message", Qt.QueuedConnection,
                                         Q_ARG(str, "info"), Q_ARG(str, "检查更新"), Q_ARG(str, "已经是最新版本"))
        elif not self.isAuto:
            QMetaObject.invokeMethod(self.windows, "show_message", Qt.QueuedConnection,
                                     Q_ARG(str, "error"), Q_ARG(str, "检查更新"), Q_ARG(str, f"检查更新失败，错误:{last_version}"))


class SearchSignal(QObject):
    error = Signal(str)
    result = Signal(int, int, list)


class SearchWorker(QRunnable):

    def __init__(self, taskid: int, keyword: str, search_type: int) -> None:
        super().__init__()
        self.taskid = taskid
        self.keyword = keyword
        self.search_type = search_type
        self.signals = SearchSignal()

    def run(self) -> None:
        logging.debug("开始搜索歌曲")
        cache_mutex.lock()
        if (self.keyword, self.search_type) in cache["serach"]:
            logging.debug(f"从缓存中获取搜索结果,类型:{self.search_type}, 关键字:{self.keyword}")
            search_return = cache["serach"][(self.keyword, self.search_type)]
            cache_mutex.unlock()
        else:
            cache_mutex.unlock()
            search_return = qm_search(self.keyword, self.search_type)
            if isinstance(search_return, str):
                self.signals.error.emit(search_return)
                return
            if not search_return:
                self.signals.error.emit("没有任何结果")
                return
            cache_mutex.lock()
            cache["serach"][(self.keyword, self.search_type)] = search_return
            cache_mutex.unlock()

        self.signals.result.emit(self.taskid, self.search_type, search_return)
        logging.debug("发送结果信号")


class LyricProcessingSignal(QObject):
    result = Signal(int, dict)
    error = Signal(str)


class LyricProcessingWorker(QRunnable):

    def __init__(self, task: dict, data_mutex: QMutex, data: Data) -> None:
        super().__init__()
        self.task = task
        self.data_mutex = data_mutex
        self.data = data
        self.signals = LyricProcessingSignal()
        self.is_running = True

    def run(self) -> None:
        if self.task["type"] == "get_merged_lyric":
            self.taskid = self.task["id"]
            self.get_merged_lyric(self.task["song_info"], self.task["lyric_type"])
        if self.task["type"] == "get_list_lyrics":
            self.data_mutex.lock()
            self.skip_inst_lyrics = self.data.cfg["skip_inst_lyrics"]
            self.data_mutex.unlock()
            for count, song_info in enumerate(self.task["song_info_list"]):
                if not self.is_running:
                    logging.debug("任务被取消")
                    break
                self.count = count + 1
                from_cache = self.get_merged_lyric(song_info, self.task["lyric_type"])
                if not from_cache:  # 检查是否来自缓存
                    time.sleep(1)

    def stop(self) -> None:
        self.is_running = False

    def get_lyrics(self, song_info: dict) -> tuple[None | Lyrics, bool]:
        logging.debug(f"开始获取歌词：{song_info['id']}")
        from_cache = False
        cache_mutex.lock()
        if (song_info["source"], song_info['id']) in cache["lyrics"]:
            lyrics = cache["lyrics"][(song_info["source"], song_info['id'])]
            logging.info(f"从缓存中获取歌词：源:{song_info['source']}, id:{song_info['id']}")
            cache_mutex.unlock()
            from_cache = True
        else:
            cache_mutex.unlock()
            lyrics = Lyrics(song_info)
            error1 = lyrics.download_and_decrypt()
            if error1 is not None:
                logging.error(f"获取歌词失败：源:{song_info['source']}, 歌名:{song_info['title']}, id: {song_info['id']},错误：{error1}")

                self.data_mutex.lock()
                get_normal_lyrics = self.data.cfg["get_normal_lyrics"]
                self.data_mutex.unlock()
                if get_normal_lyrics:
                    logging.info(f"尝试获取普通歌词：源:{song_info['source']}, 歌名:{song_info['title']}, id: {song_info['id']}")

                    error2 = lyrics.download_normal_lyrics()
                    if error2 is not None:
                        self.signals.error.emit(f"歌名:{song_info['title']}的歌词获取失败:\n错误1：{error1}\n错误2:{error2}")
                        return None, False
                else:
                    self.signals.error.emit(f"获取歌名:{song_info['title']}的加密歌词失败:{error1}")
                    return None, False

            cache_mutex.lock()
            cache["lyrics"][(song_info["source"], song_info['id'])] = lyrics
            cache_mutex.unlock()
        return lyrics, from_cache

    def get_merged_lyric(self, song_info: dict, lyric_type: list) -> bool:
        logging.debug(f"开始获取合并歌词：{song_info['id']}")
        lyrics, from_cache = self.get_lyrics(song_info)
        if lyrics is None:
            return from_cache
        self.data_mutex.lock()
        type_mapping = {"原文": "orig", "译文": "ts", "罗马音": "roma"}
        lyrics_order = [type_mapping[type_] for type_ in self.data.cfg["lyrics_order"] if type_mapping[type_] in lyric_type]
        self.data_mutex.unlock()

        merged_lyric = lyrics.merge(lyrics_order)

        if not self.is_running:
            logging.debug("任务被取消")
            return from_cache

        if self.task["type"] == "get_merged_lyric":
            self.signals.result.emit(self.taskid, {'info': song_info, 'available_types': list(lyrics.keys()), 'merged_lyric': merged_lyric})

        elif self.task["type"] == "get_list_lyrics":
            save_folder, file_name = get_save_path(self.task["save_folder"], self.task["lyrics_file_name_format"] + ".lrc", song_info, list(lyrics.keys()))
            save_path = os.path.join(save_folder, file_name)  # 获取保存路径
            inst = bool(self.skip_inst_lyrics and merged_lyric.startswith("[00:00:00]此歌曲为没有填词的纯音乐，请您欣赏"))
            self.signals.result.emit(self.count, {'info': song_info, 'save_path': save_path, 'merged_lyric': merged_lyric, 'inst': inst})
        logging.debug("发送结果信号")
        return from_cache


class GetSongListSignal(QObject):
    result = Signal(str, list)
    error = Signal(str)


class GetSongListWorker(QRunnable):

    def __init__(self, list_type: str, _id: str) -> None:
        super().__init__()
        self.list_type = list_type
        self.id = _id
        self.signals = GetSongListSignal()

    def run(self) -> None:
        cache_mutex.lock()
        if (self.list_type, self.id) in cache["songlist"]:
            self.signals.result.emit(self.list_type, cache["songlist"][(self.list_type, self.id)])
            cache_mutex.unlock()
            return
        cache_mutex.unlock()
        if self.list_type == "album":
            song_list = qm_get_album_song_list(self.id)
        elif self.list_type == "songlist":
            song_list = qm_get_songlist_song_list(self.id)

        if isinstance(song_list, list):
            self.signals.result.emit(self.list_type, song_list)
            cache_mutex.lock()
            cache["songlist"][(self.list_type, self.id)] = song_list
            cache_mutex.unlock()
        else:
            self.signals.error.emit(f"获取歌曲列表失败：{song_list}")
