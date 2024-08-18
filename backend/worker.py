# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import os
import re
import time
from itertools import zip_longest
from typing import Any, Literal

from PySide6.QtCore import (
    QCoreApplication,
    QEventLoop,
    QObject,
    QRunnable,
    Qt,
    QTimer,
    Signal,
    Slot,
)

from utils.cache import cache
from utils.data import cfg, local_song_lyrics
from utils.enum import (
    LocalMatchFileNameMode,
    LocalMatchSaveMode,
    LyricsFormat,
    LyricsProcessingError,
    LyricsType,
    SearchType,
    Source,
)
from utils.error import LyricsRequestError, LyricsUnavailableError
from utils.logger import DEBUG, logger
from utils.thread import in_main_thread, threadpool
from utils.utils import (
    escape_filename,
    escape_path,
    get_artist_str,
    get_lyrics_format_ext,
    get_save_path,
    replace_info_placeholders,
)
from utils.version import compare_versions
from view.msg_box import MsgBox

from .api import (
    gh_get_latest_version,
    kg_get_songlist,
    kg_search,
    ne_get_songlist,
    qm_get_album_song_list,
    qm_get_songlist_song_list,
)
from .calculate import calculate_artist_score, calculate_title_score, text_difference
from .converter import convert2
from .fetcher import get_lyrics
from .lyrics import Lyrics
from .searcher import search
from .song_info import file_extensions as audio_formats
from .song_info import get_audio_file_info, parse_cue


class CheckUpdateSignal(QObject):
    show_new_version_dialog = Signal(str, str, str, str)  # 版本号, 版本信息


class CheckUpdate(QRunnable):
    def __init__(self, is_auto: bool, name: str, repo: str, version: str) -> None:
        super().__init__()
        self.isAuto = is_auto
        self.name = name
        if repo.startswith("https://github.com/"):
            repo = repo[len("https://github.com/"):]
        self.repo = repo
        self.version = version
        self.signals = CheckUpdateSignal()

    def run(self) -> None:
        is_success, last_version, body = gh_get_latest_version(self.repo)
        if is_success:

            if compare_versions(self.version, last_version) == -1:
                self.signals.show_new_version_dialog.emit(self.name, self.repo, last_version, body)
            elif not self.isAuto:
                in_main_thread(
                    MsgBox.information, None,
                    QCoreApplication.translate("CheckUpdate", "检查更新"), QCoreApplication.translate("CheckUpdate", "已经是最新版本"),
                )
        elif not self.isAuto:
            in_main_thread(
                MsgBox.critical, None, QCoreApplication.translate("CheckUpdate", "检查更新"),
                QCoreApplication.translate("CheckUpdate", "检查更新失败，错误:{0}").format(last_version),
            )


class SearchSignal(QObject):
    error = Signal(str)
    result = Signal(int, SearchType, list)


class SearchWorker(QRunnable):

    def __init__(self,
                 taskid: int,
                 keyword: str,
                 search_type: SearchType,
                 source: Source | list[Source],
                 page: int | str = 1,
                 info: dict | None = None) -> None:
        super().__init__()
        self.taskid = taskid
        self.keyword = keyword  # str: 关键字, dict: 歌曲信息
        self.search_type = search_type
        self.source = source
        self.info = info
        self.page = int(page)
        self.signals = SearchSignal()

    def handle_search_result(self, task_id: int, _search_type: SearchType, result: list) -> None:
        self.search_task_finished += 1
        self.search_task[task_id] = result
        if self.search_task_finished == len(self.search_task):
            self.loop.exit()

    def handle_search_error(self, error: str) -> None:
        self.search_task_finished += 1
        self.error = error

    def run(self) -> None:
        if isinstance(self.source, Source):
            try:
                result = search(self.keyword, self.search_type, self.source, self.info, self.page)
            except Exception as e:
                logger.exception("搜索时遇到错误")
                msg = f"搜索时遇到错误:\n{e.__class__.__name__}: {e!s}"
                self.signals.error.emit(msg)
                return
            self.signals.result.emit(self.taskid, self.search_type, result)
            logger.debug("发送结果信号")
        elif isinstance(self.source, list):
            self.loop = QEventLoop()
            self.search_task = {}
            self.error = None
            self.search_task_finished = 0
            for task_id, source in enumerate(self.source):
                cache_key = (self.search_type, source, self.keyword, self.info, self.page)
                result = cache.get(cache_key)
                if isinstance(result, list):
                    self.handle_search_result(task_id, self.search_type, result)
                else:
                    self.search_task[task_id] = None
                    worker = SearchWorker(task_id, self.keyword, self.search_type, source, self.page, self.info)
                    worker.signals.result.connect(self.handle_search_result)
                    worker.signals.error.connect(self.handle_search_error)
                    threadpool.start(worker)

            if self.search_task_finished != len(self.search_task):
                self.loop.exec()

            results = [item for group in zip_longest(*self.search_task.values()) for item in group if item is not None]
            if results or not self.error:
                self.signals.result.emit(self.taskid, self.search_type, results)
            else:
                self.signals.error.emit(self.error)
        else:
            msg = f"source type {type(self.source)} is not supported"
            raise TypeError(msg)


class LyricProcessingSignal(QObject):
    result = Signal(int, dict)
    error = Signal(str)


class LyricProcessingWorker(QRunnable):

    def __init__(self, task: dict) -> None:
        super().__init__()
        self.task = task
        self.signals = LyricProcessingSignal()
        self.is_running = True

    def run(self) -> None:
        if self.task["type"] == "get_converted_lyrics":
            self.taskid = self.task["id"]
            self.get_converted_lyrics(self.task["song_info"], self.task["lyric_langs"])

        elif self.task["type"] == "get_lyric":
            self.taskid = self.task["id"]
            lyrics, from_cache = self.get_lyrics(self.task["song_info"])
            if isinstance(lyrics, Exception):
                self.signals.result.emit(self.taskid, {"error_str": str(lyrics), "error_type": lyrics.__class__.__name__})
            else:
                self.signals.result.emit(self.taskid, {"result": lyrics})

        elif self.task["type"] == "get_list_lyrics":
            self.skip_inst_lyrics = cfg["skip_inst_lyrics"]
            for count, song_info in enumerate(self.task["song_info_list"]):
                if not self.is_running:
                    logger.debug("任务被取消")
                    break
                self.count = count + 1
                match song_info['source']:
                    case Source.QM | Source.NE:
                        info = song_info
                    case Source.KG:
                        if self.skip_inst_lyrics and song_info['language'] in ["纯音乐", '伴奏']:
                            self.signals.error.emit(f"{get_artist_str(song_info['artist'])} - {song_info['title']} 为纯音乐,已跳过")
                            continue
                        search_return = kg_search(f"{get_artist_str(song_info['artist'], sep='、')} - {song_info['title']}", SearchType.LYRICS, song_info)
                        if isinstance(search_return, str):
                            self.signals.error.emit(QCoreApplication.translate("LyricProcess", "搜索歌词时出现错误{0}").format(search_return))
                            continue
                        if not search_return:
                            self.signals.error.emit(
                                QCoreApplication.translate("LyricProcess",
                                                           "搜索歌词没有任何结果,源:{0}, 歌名:{1}, : {2}").format(
                                                               song_info['source'], song_info['title'], song_info['hash']))
                            continue
                        info = song_info
                        info.update(search_return[0])
                from_cache = self.get_converted_lyrics(info, self.task["lyric_langs"])
                if not from_cache:  # 检查是否来自缓存
                    time.sleep(1)
        self.is_running = False

    def stop(self) -> None:
        self.is_running = False

    def get_lyrics(self, song_info: dict) -> tuple[Exception | Lyrics, bool]:
        logger.debug("开始获取歌词: %s", song_info['id'])
        from_cache = False
        lyrics = None
        error = None
        for _ in range(3):
            try:
                lyrics, from_cache = get_lyrics(**song_info)
                break
            except LyricsRequestError as e:
                error = e
                continue
            except LyricsUnavailableError as e:
                logger.warning("歌词不可用: %s", e)
                error = e
                break
            except Exception as e:
                logger.exception("获取歌词时发生错误, song_info: %s", song_info)
                error = e
                break

        if not lyrics:
            if error:
                return error, from_cache
            return Exception(), from_cache
        return lyrics, from_cache

    def get_converted_lyrics(self, song_info: dict, lyric_langs: list) -> bool:
        logger.debug("开始获取合并歌词: %s", song_info.get('id', song_info.get('hash', '')))
        lyrics, from_cache = self.get_lyrics(song_info)
        if not isinstance(lyrics, Lyrics):
            song_name_str = QCoreApplication.translate("LyricProcess", "歌名:") + song_info["title"] if "title" in song_info else ""
            msg = f"获取歌词失败：{song_name_str}, 源:{song_info['source']}, id: {song_info['id']}"
            logger.exception(msg)
            self.signals.error.emit(f"{msg}\n{lyrics.__class__.__name__}: {lyrics!s}")  # 此时的 lyrics 是错误信息
            return from_cache

        langs_order = [lang for lang in cfg["langs_order"] if lang in lyric_langs]

        try:
            converted_lyrics = convert2(lyrics, langs_order, self.task["lyrics_format"], self.task.get("offset", 0))
        except Exception as e:
            logger.exception("合并歌词失败")
            self.signals.error.emit(QCoreApplication.translate("LyricProcess", "合并歌词失败：{0}").format(str(e)))
            return from_cache

        if not self.is_running:
            logger.debug("任务被取消")
            return from_cache

        if self.task["type"] == "get_converted_lyrics":
            self.signals.result.emit(self.taskid,
                                     {'info': {**song_info, 'lyrics_format': self.task["lyrics_format"]},
                                      'lyrics': lyrics, 'converted_lyrics': converted_lyrics})

        elif self.task["type"] == "get_list_lyrics":
            save_folder, file_name = get_save_path(self.task["save_folder"],
                                                   self.task["lyrics_file_name_fmt"] + get_lyrics_format_ext(self.task["lyrics_format"]),
                                                   song_info,
                                                   langs_order)
            save_path = os.path.join(save_folder, file_name)  # 获取保存路径
            inst = bool(self.skip_inst_lyrics and lyrics.is_inst())
            self.signals.result.emit(self.count, {'info': song_info, 'save_path': save_path, 'converted_lyrics': converted_lyrics, 'inst': inst})
        logger.debug("发送结果信号")
        return from_cache


class GetSongListSignal(QObject):
    result = Signal(int, str, list)
    error = Signal(str)


class GetSongListWorker(QRunnable):

    def __init__(self, taskid: int, list_type: str, list_id: str, source: Source) -> None:
        super().__init__()
        self.taskid = taskid
        self.list_type = list_type
        self.id = list_id
        self.source = source
        self.signals = GetSongListSignal()

    def run(self) -> None:
        if ("songlist", self.list_type, self.id) in cache:
            self.signals.result.emit(self.taskid, self.list_type, cache[("songlist", self.list_type, self.id)])
            return
        for _i in range(3):
            match self.source:
                case Source.QM:
                    if self.list_type == "album":
                        song_list = qm_get_album_song_list(self.id)
                    elif self.list_type == "songlist":
                        song_list = qm_get_songlist_song_list(self.id)
                case Source.NE:
                    song_list = ne_get_songlist(self.id, self.list_type)
                case Source.KG:
                    song_list = kg_get_songlist(self.id, self.list_type)
            if isinstance(song_list, list):
                break

        if isinstance(song_list, list) and song_list:
            self.signals.result.emit(self.taskid, self.list_type, song_list)
            cache[("songlist", self.list_type, self.id)] = song_list
        elif song_list == []:
            self.signals.error.emit(QCoreApplication.translate("LyricProcess", "获取歌曲列表失败, 列表数据为空"))
        elif isinstance(song_list, str):
            self.signals.error.emit(QCoreApplication.translate("LyricProcess", "获取歌曲列表失败：{0}").format(song_list))
        else:
            self.signals.error.emit(QCoreApplication.translate("LyricProcess", "获取歌曲列表失败, 未知错误"))


class LocalMatchSignal(QObject):
    massage = Signal(str)
    error = Signal(str, int)
    finished = Signal()
    progress = Signal(int, int)


class LocalMatchWorker(QRunnable):

    def __init__(self,
                 infos: dict,
                 ) -> None:
        super().__init__()
        self.signals = LocalMatchSignal()
        self.song_path: str = infos["song_path"]
        self.save_path: str = infos["save_path"]
        self.save_mode: LocalMatchSaveMode = infos["save_mode"]
        self.fliename_mode: LocalMatchFileNameMode = infos["flienmae_mode"]
        self.langs: list[str] = infos["langs_order"]
        self.lyrics_format: LyricsFormat = infos["lyrics_format"]
        self.source: list[Source] = infos["source"]

        self.is_running = True
        self.current_index = 0
        self.total_index = 0

        self.skip_inst_lyrics = cfg["skip_inst_lyrics"]
        self.file_name_format = cfg["lyrics_file_name_fmt"]

        self.min_score = infos["min_score"]

    def lyric_processing_error(self, error: str) -> None:
        self.signals.error.emit(error, 0)

    def stop(self) -> None:
        self.is_running = False

    def fetch_next_lyrics(self) -> None:
        info = self.song_infos[self.current_index]
        self.current_index += 1
        worker = AutoLyricsFetcher(info, self.min_score, self.source)
        worker.signals.result.connect(self.handle_fetch_result)
        threadpool.start(worker)

    def run(self) -> None:
        self.loop = QEventLoop()
        logger.info("开始本地匹配歌词,源:%s", self.source)
        try:
            self.start_time = time.time()
            # Setp 1 处理cue 与 遍历歌曲文件
            self.signals.massage.emit(QCoreApplication.translate("LocalMatch", "处理 cue 并 遍历歌曲文件..."))
            song_infos = []
            cue_audio_files = []
            cue_count = 0
            audio_file_paths = []
            for root, _dirs, files in os.walk(self.song_path):
                for file in files:
                    if not self.is_running:
                        self.signals.finished.emit()
                        return
                    if file.lower().endswith('.cue'):
                        file_path = os.path.join(root, file)
                        try:
                            songs, cue_audio_file_paths = parse_cue(file_path)
                            if len(songs) > 0:
                                song_infos.extend(songs)
                                cue_audio_files.extend(cue_audio_file_paths)
                                cue_count += 1
                            else:
                                logger.warning("没有在cue文件 %s 解析到歌曲", file_path)
                                self.signals.error.emit(QCoreApplication.translate("LocalMatch", "没有在cue文件 {0} 解析到歌曲").format(file_path), 0)
                        except Exception as e:
                            logger.exception("处理cue文件时错误")
                            self.signals.error.emit(f"处理cue文件时错误:{e}", 0)
                    elif file.lower().split(".")[-1] in audio_formats:
                        file_path = os.path.join(root, file)
                        audio_file_paths.append(file_path)

            for cue_audio_file in cue_audio_files:  # 去除cue中有的文件
                if cue_audio_file in audio_file_paths:
                    audio_file_paths.remove(cue_audio_file)
            msg = QCoreApplication.translate("LocalMatch", "共找到{0}首歌曲").format(f"{len(audio_file_paths) + len(song_infos)}")
            if cue_count > 0:
                msg += QCoreApplication.translate("LocalMatch", "，其中{0}首在{1}个cue文件中找到").format(f"{len(song_infos)}", str(cue_count))

            self.signals.massage.emit(msg)

            # Step 2 读取歌曲文件信息
            self.signals.massage.emit(QCoreApplication.translate("LocalMatch", "正在读取歌曲文件信息..."))
            total_paths = len(audio_file_paths)
            for i, audio_file_path in enumerate(audio_file_paths):
                self.signals.progress.emit(i, total_paths)
                if not self.is_running:
                    self.signals.finished.emit()
                    return
                song_info = get_audio_file_info(audio_file_path)
                if isinstance(song_info, str):
                    self.signals.error.emit(song_info, 0)
                    continue
                if isinstance(song_info, dict):
                    song_infos.append(song_info)

            # Step 3 根据信息搜索并获取歌词
            if logger.level <= DEBUG:
                logger.debug("song_infos: %s", json.dumps(song_infos, indent=4, ensure_ascii=False))
            self.total_index = len(song_infos)
            self.song_infos: list[dict] = song_infos
            if self.total_index > 0:
                self.signals.massage.emit(QCoreApplication.translate("LocalMatch", "正在搜索并获取歌词..."))
                self.fetch_next_lyrics()
            else:
                self.signals.massage.emit(QCoreApplication.translate("LocalMatch", "没有找到可查找歌词的歌曲"))
                self.signals.finished.emit()
        except Exception as e:
            logger.exception("搜索歌词时错误")
            self.signals.error.emit(str(e), 1)
        finally:
            self.loop.exec()
            self.signals.finished.emit()

    def handle_fetch_result(self, result: dict[str, dict | Lyrics | str]) -> None:
        try:
            song_info = result["orig_info"]
            if not isinstance(song_info, dict):
                return

            simple_song_info_str = f"{get_artist_str(song_info['artist'])} - {song_info['title']}" if "artist" in song_info else song_info["title"]
            progress_str = f"[{self.current_index}/{self.total_index}]"

            match result["status"]:
                case "成功":
                    if self.skip_inst_lyrics is False or result.get("is_inst") is False:
                        # 不是纯音乐或不要跳过纯音乐
                        lrc_info = result["result_info"]
                        lyrics = result["lyrics"]
                        if not isinstance(lrc_info, dict) or not isinstance(lyrics, Lyrics):
                            return

                        # Step 4 合并歌词
                        converted_lyrics = convert2(lyrics, self.langs, self.lyrics_format)
                        # Step 5 保存歌词
                        match self.save_mode:
                            case LocalMatchSaveMode.MIRROR:
                                save_folder = os.path.join(self.save_path,
                                                           os.path.dirname(os.path.relpath(song_info["file_path"], self.song_path)))
                            case LocalMatchSaveMode.SONG:
                                save_folder = os.path.dirname(song_info["file_path"])

                            case LocalMatchSaveMode.SPECIFY:
                                save_folder = self.save_path

                        save_folder = escape_path(save_folder).strip()
                        ext = get_lyrics_format_ext(self.lyrics_format)

                        match self.fliename_mode:
                            case LocalMatchFileNameMode.SONG:
                                if song_info["type"] == "cue":
                                    save_folder = os.path.join(save_folder, os.path.splitext(os.path.basename(song_info["file_path"]))[0])
                                    save_filename = escape_filename(
                                        replace_info_placeholders(self.file_name_format, lrc_info, self.langs)) + ext
                                else:
                                    save_filename = os.path.splitext(os.path.basename(song_info["file_path"]))[0] + ext

                            case LocalMatchFileNameMode.FORMAT:
                                save_filename = escape_filename(
                                    replace_info_placeholders(self.file_name_format, lrc_info, self.langs)) + ext

                        save_path = os.path.join(save_folder, save_filename)
                        try:
                            if not os.path.exists(os.path.dirname(save_path)):
                                os.makedirs(os.path.dirname(save_path))
                            with open(save_path, "w", encoding="utf-8") as f:
                                f.write(converted_lyrics)
                            msg = (f"{progress_str}" +
                                   QCoreApplication.translate("LocalMatch", "本地") + f": {simple_song_info_str} " +
                                   QCoreApplication.translate("LocalMatch", "匹配") + f": {get_artist_str(lrc_info['artist'])} - {lrc_info['title']} " +
                                   QCoreApplication.translate("LocalMatch", "成功保存到") + f"{save_path}")
                            self.signals.massage.emit(msg)
                        except Exception as e:
                            self.signals.error.emit(str(e), 0)
                    else:
                        # 是纯音乐并要跳过纯音乐
                        msg = (f"{progress_str}" +
                               QCoreApplication.translate("LocalMatch", "本地") + f": {simple_song_info_str} " +
                               QCoreApplication.translate("LocalMatch", "搜索结果") +
                               f":{simple_song_info_str} " + QCoreApplication.translate("LocalMatch", "跳过纯音乐"))
                        self.signals.massage.emit(msg)
                case "没有找到符合要求的歌曲":
                    msg = (f"{progress_str} {simple_song_info_str}:" + QCoreApplication.translate("LocalMatch", "没有找到符合要求的歌曲"))
                    self.signals.massage.emit(msg)
                case "搜索结果处理失败":
                    msg = (f"{progress_str} {simple_song_info_str}:" + QCoreApplication.translate("LocalMatch", "搜索结果处理失败"))
                    self.signals.massage.emit(msg)
                case "没有足够的信息用于搜索":
                    msg = (f"{progress_str} {simple_song_info_str}:" + QCoreApplication.translate("LocalMatch", "没有足够的信息用于搜索"))
                    self.signals.massage.emit(msg)
                case "超时":
                    msg = (f"{progress_str} {simple_song_info_str}:" + QCoreApplication.translate("LocalMatch", "超时"))
                    self.signals.massage.emit(msg)

        except Exception:
            logger.exception("合并或保存时出错")
            msg = (f"{progress_str} {simple_song_info_str}:" + QCoreApplication.translate("LocalMatch", "合并或保存时出错"))
            self.signals.massage.emit(msg)
        finally:
            self.signals.progress.emit(self.current_index, self.total_index)
            if self.current_index == self.total_index:
                self.signals.massage.emit(QCoreApplication.translate("LocalMatch", "匹配完成,耗时{0}秒").format(f"{time.time() - self.start_time}"))
                self.loop.quit()
            elif self.is_running:
                self.fetch_next_lyrics()
            else:
                self.loop.quit()


class AutoLyricsFetcherSignal(QObject):
    result = Signal(dict)


class AutoLyricsFetcher(QRunnable):

    def __init__(self, info: dict, min_score: float = 60, source: list[Source] | None = None, taskid: int | None = None) -> None:
        super().__init__()
        logger.debug("Init AutoLyricsFetcher, info: %s", info)
        self.info = info
        self.tastid = taskid
        if source:
            self.source = source
        else:
            self.source = [Source.QM, Source.KG, Source.NE]
        self.signals = AutoLyricsFetcherSignal()
        self.search_task = {}
        self.search_task_finished = 0
        self.get_task = {}
        self.get_task_finished = 0
        self.infos2get = []
        self.errors = []
        self.min_score = min_score
        self.obtained_lyrics: list[tuple[dict, Lyrics]] = []

        self.result = None

    def new_search_work(self, keyword: str, search_type: SearchType, source: Source, info: dict | None = None) -> None:
        task_id = len(self.search_task)
        self.search_task[task_id] = (keyword, search_type, source)
        worker = SearchWorker(task_id, *self.search_task[task_id], info=info)
        worker.signals.result.connect(self.handle_search_result, Qt.ConnectionType.BlockingQueuedConnection)
        worker.signals.error.connect(self.handle_search_error, Qt.ConnectionType.BlockingQueuedConnection)
        threadpool.start(worker)

    def new_get_work(self, song_info: dict) -> None:
        task_id = len(self.get_task)
        self.get_task[task_id] = song_info
        worker = LyricProcessingWorker({"id": task_id, "song_info": song_info, "type": "get_lyric"})
        worker.signals.result.connect(self.handle_get_result, Qt.ConnectionType.BlockingQueuedConnection)
        threadpool.start(worker)

    def search(self) -> None:
        artist: list | str | None = self.info.get('artist')
        keyword = f"{get_artist_str(artist)} - {self.info['title'].strip()}" if artist else self.info["title"].strip()
        for source in self.source:
            self.new_search_work(keyword, SearchType.SONG, source)

    @Slot(str)
    def handle_search_error(self, error: str) -> None:
        # 错误
        self.search_task_finished += 1
        self.errors.append(error)
        self.get_result()

    @Slot(int, SearchType, list)
    def handle_search_result(self, taskid: int, search_type: SearchType, infos: list[dict]) -> None:

        try:
            self.search_task_finished += 1
            keyword, _search_type, source = self.search_task[taskid]
            if source == Source.KG and search_type == SearchType.LYRICS:
                if infos:
                    self.new_get_work(infos[0])
                else:
                    self.get_result()
            duration: int | None = self.info.get('duration')
            artist: str | list | None = self.info.get('artist')
            if isinstance(artist, str):
                artist = artist.strip()

            score_info: list[tuple[float, dict]] = []
            for info in infos:
                if duration and abs(info.get('duration', -100) - duration) > 3:
                    continue

                artist_score = None
                title_score = calculate_title_score(self.info['title'], info.get('title', ''))
                album_score = max(text_difference(self.info.get('album', '').lower(), info.get('album', '').lower()) * 100, 0)
                if (isinstance(artist, str) and artist.strip()) or isinstance(artist, list) and [a for a in artist if a]:
                    artist_score = calculate_artist_score(artist, info.get('artist', ''))

                if artist_score is not None:
                    score = max(title_score * 0.5 + artist_score * 0.5, title_score * 0.5 + artist_score * 0.35 + album_score * 0.15)
                elif self.info.get('album', '').strip() and info.get('album', '').strip():
                    score = max(title_score * 0.7 + album_score * 0.3, title_score * 0.8)
                else:
                    score = title_score

                if score > self.min_score:
                    score_info.append((score, info))

            score_info = sorted(score_info, key=lambda x: x[0], reverse=True)
            best: tuple | None = score_info[0] if score_info else None
            if best:
                best_info = best[1]
                best_info['score'] = best[0]
                logger.info("关键词: %s 搜索结果: %s", keyword, best)
                if source == Source.KG and search_type == SearchType.SONG:
                    #  对酷狗音乐搜索到的歌曲搜索歌词
                    self.new_search_work(f"{get_artist_str(self.info.get('artist')), '、'} - {self.info['title'].strip()}",
                                         SearchType.LYRICS,
                                         Source.KG,
                                         info=best_info)
                else:
                    self.new_get_work(best_info)
            elif keyword == f"{get_artist_str(self.info.get('artist'))} - {self.info['title'].strip()}":
                # 尝试只搜索歌曲名
                self.new_search_work(self.info['title'].strip(), SearchType.SONG, source)
            else:
                logger.warning("无法从源:%s找到符合要求的歌曲:%s,", source, self.info)
        except Exception:
            logger.exception("搜索结果处理失败")
            self.send_result({"status": "搜索结果处理失败", "orig_info": self.info})
        finally:
            self.get_result()

    def handle_get_result(self, task_id: int, result: dict) -> None:
        try:
            self.get_task_finished += 1
            if "error_type" in result:
                if result["error_type"] != LyricsProcessingError.NOT_FOUND:
                    self.errors.append(result["error_str"])
            else:
                song_info: dict = self.get_task[task_id]
                result_lyrics: Lyrics = result["result"]
                self.obtained_lyrics.append((song_info, result_lyrics))
            self.get_result()
        except Exception:
            logger.exception("歌词结果处理失败, 'orig_info': %s, 'self.obtained_lyrics': %s", self.info, self.obtained_lyrics)
            self.send_result({"status": "歌词结果处理失败", "orig_info": self.info})

    def get_result(self) -> None:

        if self.search_task_finished == len(self.search_task) != 0 and not self.get_task:
            # 没有任何符合要求的歌曲
            logger.warning("没有找到符合要求的歌曲:%s", self.info)
            self.send_result({"status": "没有找到符合要求的歌曲", "orig_info": self.info})
            return

        if (self.search_task_finished != len(self.search_task) or
           len(self.get_task) != self.get_task_finished or
           len(self.get_task) == 0 or
           self.get_task_finished == 0):
            self.loop.processEvents()
            return

        if len(self.obtained_lyrics) == 0:
            self.send_result({"status": "没有找到符合要求的歌曲", "orig_info": self.info})
            return

        # 去除相似度低的
        highest_score = 0
        for obtained_lyric in self.obtained_lyrics:
            highest_score = max(obtained_lyric[0]['score'], highest_score)

        for obtained_lyric in self.obtained_lyrics:
            if abs(obtained_lyric[0]['score'] - highest_score) > 15:
                self.obtained_lyrics.remove(obtained_lyric)

        have_verbatim = [lyrics for lyrics in self.obtained_lyrics if lyrics[1].types.get("orig") == LyricsType.VERBATIM]
        have_ts = [lyrics for lyrics in self.obtained_lyrics if "ts" in lyrics[1]]
        have_roma = [lyrics for lyrics in self.obtained_lyrics if "roma" in lyrics[1]]

        have_verbatim_ts: list[tuple[dict, Lyrics]] = []
        have_verbatim_roma: list[tuple[dict, Lyrics]] = []
        have_verbatim_ts_roma: list[tuple[dict, Lyrics]] = []
        have_ts_roma: list[tuple[dict, Lyrics]] = []
        for lyrics in self.obtained_lyrics:
            if lyrics in have_verbatim and lyrics in have_ts:
                have_verbatim_ts.append(lyrics)
            if lyrics in have_verbatim and lyrics in have_roma:
                have_verbatim_roma.append(lyrics)
            if lyrics in have_verbatim and lyrics in have_ts and lyrics in have_roma:
                have_verbatim_ts_roma.append(lyrics)
            if lyrics in have_ts and lyrics in have_roma:
                have_ts_roma.append(lyrics)

        for lyrics_list in [have_verbatim_ts_roma, have_verbatim_ts, have_ts_roma, have_ts, have_verbatim_roma, have_verbatim, have_roma]:
            if lyrics_list:
                break
        else:
            lyrics_list = self.obtained_lyrics

        for source in self.source:
            for lyrics in lyrics_list:
                if lyrics[0]["source"] == source:
                    info = lyrics[0]
                    result = lyrics[1]
                    break
            else:
                continue
            break
        else:
            logger.warning("没有找到符合要求的歌曲:%s", self.info)
            self.send_result({"status": "没有找到符合要求的歌曲", "orig_info": self.info})
            return

        # 判断是否为纯音乐
        if ((info["source"] == Source.KG and info['language'] in ["纯音乐", '伴奏']) or result.is_inst() or
                re.findall(r"伴奏|纯音乐|inst\.?(?:rumental)|off ?vocal(?: ?[Vv]er.)?", info.get('title', '') + self.info['title'])):
            is_inst = True
        else:
            is_inst = False

        self.send_result({"status": "成功", "orig_info": self.info, "lyrics": result, "is_inst": is_inst, "result_info": info})

    def send_result(self, result: dict) -> None:
        self.result = result
        if self.tastid:
            self.result["taskid"] = self.tastid
        self.loop.exit()

    def run(self) -> None:
        self.loop = QEventLoop()
        if not self.info.get("title") or not self.info["title"].strip():
            self.send_result({"status": "没有足够的信息用于搜索", "orig_info": self.info})
            return
        self.search()
        self.timer = QTimer()
        self.timer.start(30 * 1000)
        self.timer.timeout.connect(lambda: self.send_result({"status": "超时", "orig_info": self.info}))
        self.loop.exec()
        self.timer.stop()
        self.signals.result.emit(self.result)  # 最后发送结果[不然容易出错(闪退、无响应)]


class LocalSongLyricsDBSignals(QObject):
    progress = Signal(int, int)
    finished = Signal(bool, str)


class LocalSongLyricsDBWorker(QRunnable):

    def __init__(self, task: Literal["backup", "restore", "clear", "change_dir", "del_all"], *args: Any, **kwargs: Any) -> None:
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
        count = 0
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
                count += 1
            if i % frequency == 0:
                self.signals.progress.emit(i, data_len)
        return QCoreApplication.translate("LocalSongLyricsDB", "修改成功, 共修改了 {0} 条数据").format(count)
