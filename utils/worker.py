# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import logging
import os
import re
import sys
import time
from enum import Enum

from diskcache import Cache
from PySide6.QtCore import (
    Q_ARG,
    QMetaObject,
    QObject,
    QRunnable,
    Qt,
    QThreadPool,
    Signal,
)

from ui.sidebar_window import SidebarWindow
from utils.api import (
    SearchType,
    Source,
    get_latest_version,
    kg_get_songlist,
    kg_search,
    ne_get_songlist,
    ne_search,
    qm_get_album_song_list,
    qm_get_songlist_song_list,
    qm_search,
)
from utils.data import Data
from utils.lyrics import LyricProcessingError, Lyrics
from utils.song_info import get_audio_file_info, parse_cue
from utils.utils import (
    escape_filename,
    escape_path,
    get_save_path,
    replace_info_placeholders,
    text_difference,
)

match sys.platform:
    case "linux" | "darwin":
        cache_dir = os.path.expanduser("~/.config/LDDC/cache")
    case _:
        cache_dir = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "cache")
cache = Cache(cache_dir)
cache_version = 2
if "version" not in cache or cache["version"] != cache_version:
    cache.clear()
cache["version"] = cache_version


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

    def __init__(self, taskid: int, keyword: str | dict, search_type: SearchType, source: Source) -> None:
        super().__init__()
        self.taskid = taskid
        self.keyword = keyword  # str: 关键字, dict: 歌曲信息
        self.search_type = search_type
        self.source = source
        self.signals = SearchSignal()

    def run(self) -> None:
        logging.debug("开始搜索")
        if isinstance(self.keyword, dict):
            keyword = {"keyword": f"{self.keyword['artist']} - {self.keyword['title']}",
                       "duration": self.keyword["duration"], "hash": self.keyword["hash"]}
        else:
            keyword = self.keyword
        if ("serach", str(keyword), self.search_type, self.source) in cache:
            logging.debug(f"从缓存中获取搜索结果,类型:{self.search_type}, 关键字:{keyword}")
            search_return = cache[("serach", str(keyword), self.search_type, self.source)]
        else:
            for _i in range(3):
                match self.source:
                    case Source.QM:
                        search_return = qm_search(keyword, self.search_type)
                    case Source.KG:
                        if isinstance(keyword, dict) and self.search_type == SearchType.LYRICS:
                            search_return = kg_search(keyword, SearchType.LYRICS)
                        else:
                            search_return = kg_search(keyword, self.search_type)
                    case Source.NE:
                        search_return = ne_search(keyword, self.search_type)
                if isinstance(search_return, str):
                    continue
                break
            if isinstance(search_return, str):
                self.signals.error.emit(search_return)
                return
            if not search_return:
                self.signals.error.emit("没有任何结果")
                return
            cache[("serach", str(keyword), self.search_type, self.source)] = search_return

        if self.source == Source.KG and isinstance(self.keyword, dict) and self.search_type == SearchType.LYRICS:
            # 为歌词搜索结果添加歌曲信息(歌词保存需要)
            result = [dict(self.keyword, **item) for item in search_return]
        else:
            result = search_return
        self.signals.result.emit(self.taskid, self.search_type.value, result)
        logging.debug("发送结果信号")


class LyricProcessingSignal(QObject):
    result = Signal(int, dict)
    error = Signal(str)


class LyricProcessingWorker(QRunnable):

    def __init__(self, task: dict, data: Data) -> None:
        super().__init__()
        self.task = task
        self.data_mutex = data.mutex
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
                match song_info['source']:
                    case Source.QM | Source.NE:
                        info = song_info
                    case Source.KG:
                        if self.skip_inst_lyrics and song_info['language'] in ["纯音乐", '伴奏']:
                            self.signals.error.emit(f"{song_info['artist']} - {song_info['title']} 为纯音乐,已跳过")
                            continue
                        search_return = kg_search({"keyword": f"{song_info['artist']} - {song_info['title']}",
                                                   "duration": song_info["duration"],
                                                   "hash": song_info["hash"]},
                                                  SearchType.LYRICS)
                        if isinstance(search_return, str):
                            self.signals.error.emit(f"搜索歌词时出现错误{search_return}")
                            continue
                        if not search_return:
                            self.signals.error.emit(f"搜索歌词没有任何结果,源:{song_info['source']}, 歌名:{song_info['title']}, : {song_info['hash']}")
                            continue
                        info = song_info
                        info.update(search_return[0])
                from_cache = self.get_merged_lyric(info, self.task["lyric_type"])
                if not from_cache:  # 检查是否来自缓存
                    time.sleep(1)

    def stop(self) -> None:
        self.is_running = False

    def get_lyrics(self, song_info: dict) -> tuple[None | Lyrics, bool]:
        logging.debug(f"开始获取歌词：{song_info['id']}")
        from_cache = False
        if ("lyrics", song_info["source"], song_info['id'], song_info.get("accesskey", "")) in cache:
            lyrics = cache[("lyrics", song_info["source"], song_info['id'], song_info.get("accesskey", ""))]
            logging.info(f"从缓存中获取歌词：源:{song_info['source']}, id:{song_info['id']}, accesskey: {song_info.get('accesskey', '无')}")
            from_cache = True
        if not from_cache:
            lyrics = Lyrics(song_info)

            for _i in range(3):  # 重试3次
                error1, error1_type = lyrics.download_and_decrypt()
                if error1_type != LyricProcessingError.REQUEST:  # 如果正常或不是请求错误不重试
                    break
            if 'title' in song_info:
                song_name_str = "歌名:" + song_info['title']
            if error1 is not None:
                logging.error(f"获取歌词失败：{song_name_str}, 源:{song_info['source']}, id: {song_info['id']},错误：{error1}")

                self.data_mutex.lock()
                get_normal_lyrics = bool(self.data.cfg["get_normal_lyrics"] and song_info['source'] == Source.QM)
                self.data_mutex.unlock()
                if get_normal_lyrics:
                    logging.info(f"尝试获取普通歌词：{song_name_str},源:{song_info['source']}, id: {song_info['id']}")

                    for _i in range(3):  # 重试3次
                        error2, error2_type = lyrics.download_normal_lyrics()
                        if error2_type != LyricProcessingError.REQUEST:  # 如果正常或不是请求错误不重试
                            break

                    if error2 is not None:
                        self.signals.error.emit(f"歌名:{song_name_str}的歌词获取失败:\n错误1：{error1}\n错误2:{error2}")
                        return None, False
                else:
                    self.signals.error.emit(f"获取歌名:{song_name_str}的加密歌词失败:{error1}")
                    return None, False

            if error1_type != LyricProcessingError.REQUEST and not from_cache:  # 如果不是请求错误则缓存
                cache[("lyrics", song_info["source"], song_info['id'], song_info.get("accesskey", ""))] = lyrics
        return lyrics, from_cache

    def get_merged_lyric(self, song_info: dict, lyric_type: list) -> bool:
        logging.debug(f"开始获取合并歌词：{song_info.get('id', song_info.get('hash', ''))}")
        lyrics, from_cache = self.get_lyrics(song_info)
        if lyrics is None:
            return from_cache
        self.data_mutex.lock()
        type_mapping = {"原文": "orig", "译文": "ts", "罗马音": "roma"}
        lyrics_order = [type_mapping[type_] for type_ in self.data.cfg["lyrics_order"] if type_mapping[type_] in lyric_type]
        self.data_mutex.unlock()

        try:
            merged_lyric = lyrics.get_merge_lrc(lyrics_order)
        except Exception as e:
            logging.exception("合并歌词失败")
            self.signals.error.emit(f"合并歌词失败：{e}")

        if not self.is_running:
            logging.debug("任务被取消")
            return from_cache

        if self.task["type"] == "get_merged_lyric":
            self.signals.result.emit(self.taskid, {'info': song_info, 'lrc': lyrics, 'merged_lyric': merged_lyric})

        elif self.task["type"] == "get_list_lyrics":
            save_folder, file_name = get_save_path(self.task["save_folder"], self.task["lyrics_file_name_format"] + ".lrc", song_info, lyrics_order)
            save_path = os.path.join(save_folder, file_name)  # 获取保存路径
            inst = bool(self.skip_inst_lyrics and len(lyrics["orig"]) != 0 and (lyrics["orig"][0][2][0][2] == "此歌曲为没有填词的纯音乐，请您欣赏" or lyrics["orig"][0][2][0][2] == "纯音乐，请欣赏"))
            self.signals.result.emit(self.count, {'info': song_info, 'save_path': save_path, 'merged_lyric': merged_lyric, 'inst': inst})
        logging.debug("发送结果信号")
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
            self.signals.error.emit("获取歌曲列表失败, 列表数据为空")
        elif isinstance(song_list, str):
            self.signals.error.emit(f"获取歌曲列表失败：{song_list}")
        else:
            self.signals.error.emit("获取歌曲列表失败, 未知错误")


class LocalMatchSaveMode(Enum):
    # 镜像/歌曲/指定
    MIRROR = 0
    SONG = 1
    SPECIFY = 2


class LocalMatchFileNameMode(Enum):
    # 歌曲/格式
    SONG = 0
    FORMAT = 1


class LocalMatchSignal(QObject):
    massage = Signal(str)
    error = Signal(str, int)
    finished = Signal()


class LocalMatchWorker(QRunnable):

    def __init__(self,
                 song_path: str,
                 save_path: str | None,
                 save_mode: LocalMatchSaveMode,
                 flienmae_mode: LocalMatchFileNameMode,
                 lyrics_order: dict,
                 sources: list,
                 threadpool: QThreadPool,
                 data: Data,
                 ) -> None:
        super().__init__()
        self.signals = LocalMatchSignal()
        self.song_path = song_path
        self.save_path = save_path
        self.save_mode = save_mode
        self.fliename_mode = flienmae_mode
        self.lyrics_order = lyrics_order
        self.sources = sources
        self.threadpool = threadpool
        self.data = data
        self.data_mutex = data.mutex

        self.is_running = True
        self.current_index = 0
        self.total_index = 0

        self.data_mutex.lock()
        self.skip_inst_lyrics = self.data.cfg["skip_inst_lyrics"]
        self.file_name_format = self.data.cfg["lyrics_file_name_format"]
        self.data_mutex.unlock()

        self.LyricProcessingWorker = LyricProcessingWorker({}, self.data)
        self.LyricProcessingWorker.signals.error.connect(self.lyric_processing_error)

        self.min_title_pattern1 = re.compile(r"\(.*\)$|（.*）$|<.*>$|\[.*\]$|＜.*＞$|[-～~].*[-～~]$")
        self.min_title_pattern2 = re.compile(r"\(.*\)$|（.*）$|<.*>$|\[.*\]$|＜.*＞$|[-～~].*[-～~]$|"
                                             r"[oO]ff [Vv]ocal [Vv]er\.?(?:sion)?|\w+ [Ss]ize [Vv]er(?:sion)?\.?"
                                             r"|\w+ [Vv]er(?:sion)?\.?|[rR]emixed ?\w*$|-?[Ii]nst\.?(?:rumental)?|-?\w+ [Ss]tyle")

    def lyric_processing_error(self, error: str) -> None:
        self.signals.error.emit(error, 0)

    def stop(self) -> None:
        self.is_running = False

    def search_and_get(self, info: dict) -> list:
        # Step 1 搜索歌曲
        scores = []
        if info["artist"] is None:  # noqa: SIM108
            keywords = [info["title"]]
        else:
            keywords = [f"{info['artist']} - {info['title']}", info["title"]]
        min_title = re.sub(self.min_title_pattern1, "", info["title"].strip())
        min_title = re.sub(self.min_title_pattern2, "", min_title.strip())
        for source in self.sources:
            from_cache = False
            if not self.is_running:
                return None, None
            match source:
                case Source.QM:
                    search_api = qm_search
                case Source.NE:
                    search_api = ne_search
                case Source.KG:
                    search_api = kg_search
            for keyword in keywords:
                if not self.is_running:
                    return None, None
                if ("serach", str(keyword), SearchType.SONG, source) in cache:
                    logging.debug(f"从缓存中获取搜索结果,类型: 歌曲, 关键字:{keyword}")
                    search_return = cache[("serach", str(keyword), SearchType.SONG, source)]
                    from_cache = True

                if not from_cache:
                    logging.debug(f"从API中获取搜索结果,类型: 歌曲, 关键字:{keyword}")
                    for _i in range(3):
                        search_return = search_api(keyword, SearchType.SONG)
                        time.sleep(0.5)
                        if not isinstance(search_return, str):
                            break

                if isinstance(search_return, str):
                    self.signals.error.emit(search_return, 0)
                    continue
                if not search_return:
                    continue

                if not from_cache:
                    cache[("serach", str(keyword), SearchType.SONG, source)] = search_return

                if (info["artist"] is not None and
                    keyword == f"{info['artist']} - {info['title']}" and
                        (info['duration'] is None or abs(int(search_return[0]['duration']) - info['duration']) < 5)):
                    logging.debug(f"本地: {info}\n搜索结果:{search_return[0]}\n分数:1000")
                    scores.append((search_return[0], 1000))

                for song_info in search_return:
                    if song_info in [t[0] for t in scores]:
                        continue

                    if info['duration'] is not None and abs(int(song_info['duration']) - info['duration']) > 5:
                        continue

                    score = 0
                    if min_title in song_info["title"]:
                        score += 30
                    if info['duration'] is not None:
                        score += (10 - abs(int(song_info['duration']) - info['duration'])) * 3.5
                    if song_info['subtitle'] != "":
                        title_score1 = text_difference(song_info["title"] + f"({song_info['subtitle']})", info["title"]) * 35
                        title_score2 = text_difference(song_info["title"], info["title"]) * 35
                        if title_score1 > title_score2:
                            score += title_score1
                        else:
                            score += title_score2
                    else:
                        score += text_difference(song_info["title"], info["title"]) * 35
                    if info["artist"] is not None:
                        score += text_difference(song_info["artist"], info["artist"]) * 20
                    if info["album"] is not None:
                        score += text_difference(song_info["album"], info["album"]) * 10
                    logging.debug(f"本地: {info}\n搜索结果:{song_info}\n分数:{score}")
                    scores.append((song_info, score))

        scores = sorted(scores, key=lambda x: x[1], reverse=True)
        if len(scores) == 0:
            return None, None
        if self.skip_inst_lyrics and scores[0][0]['source'] == Source.KG and scores[0][0]['language'] in ["纯音乐", '伴奏']:
            if 'artist' in info:
                msg = f"[{self.current_index}/{self.total_index}]本地: {info['artist']} - {info['title']} 搜索结果:{scores[0][0]['artist']} - {scores[0][0]['title']} 跳过纯音乐"
            else:
                msg = f"[{self.current_index}/{self.total_index}]本地: {info['title']} 搜索结果:{scores[0][0]['artist']} - {scores[0][0]['title']} 跳过纯音乐"
            self.signals.massage.emit(msg)
            return None, None

        logging.debug(f"scores: {scores}")
        # Step 2 搜索歌词
        from_cache = False
        for index, data in enumerate(scores):
            if not self.is_running:
                return None, None
            song_info, score = data
            if song_info['source'] == Source.KG:
                keyword = {"keyword": f"{song_info['artist']} - {song_info['title']}",
                           "duration": song_info["duration"], "hash": song_info["hash"]}

                if ("serach", str(keyword), SearchType.LYRICS, Source.KG) in cache:
                    search_return = cache[("serach", str(keyword), SearchType.LYRICS, Source.KG)]
                    from_cache = True

                if not from_cache:
                    for _i in range(3):
                        search_return = kg_search(keyword, SearchType.LYRICS)
                        time.sleep(0.5)
                        if not isinstance(search_return, str):
                            break
                if isinstance(search_return, str):
                    self.signals.error.emit(search_return, 0)
                    continue
                if not search_return:
                    scores.remove(data)
                    continue

                cache[("serach", str(keyword), SearchType.LYRICS, Source.KG)] = search_return
                scores[index][0].update(search_return[0])

        # Step 3 获取歌词
        from_cache = False
        inst = False
        obtained_sources = []
        lyrics: list[tuple[Lyrics, int, dict]] = []
        for song_info, score in scores:
            if not self.is_running:
                return None, None
            if song_info['source'] in obtained_sources:
                continue
            lyric = None
            lyric, from_cache = self.LyricProcessingWorker.get_lyrics(song_info)
            if lyric is not None:
                obtained_sources.append(song_info['source'])
                logging.debug(f"lyric['orig']:{lyric['orig']}")
                if self.skip_inst_lyrics and len(lyric["orig"]) != 0 and (lyric["orig"][0][2][0][2] == "此歌曲为没有填词的纯音乐，请您欣赏" or lyric["orig"][0][2][0][2] == "纯音乐，请欣赏"):
                    inst = True
                    continue
                lyrics.append((lyric, score, song_info))
                inst = False
            if not from_cache:
                time.sleep(0.5)

        if len(lyrics) == 1:
            song_info = lyrics[0][2]
            lyrics = lyrics[0][0]
        elif len(lyrics) > 1:
            if lyrics[0][0].lrc_isverbatim['orig'] is True:
                song_info = lyrics[0][2]
                lyrics = lyrics[0][0]
            elif lyrics[1][0].lrc_isverbatim['orig'] is True and abs(lyrics[0][1] - lyrics[1][1]) < 15:
                song_info = lyrics[1][2]
                lyrics = lyrics[1][0]
            elif len(lyrics) > 2 and lyrics[2][0].lrc_isverbatim['orig'] is True and abs(lyrics[0][1] - lyrics[2][1]) < 15:
                song_info = lyrics[2][2]
                lyrics = lyrics[2][0]
            else:
                song_info = lyrics[0][2]
                lyrics = lyrics[0][0]

        # Step 4 合并歌词
        if isinstance(lyrics, Lyrics):
            merged_lyric = lyrics.get_merge_lrc(self.lyrics_order)
            return merged_lyric, song_info
        if 'artist' in info:
            if inst:
                msg = f"[{self.current_index}/{self.total_index}]本地: {info['artist']} - {info['title']} 搜索结果:{scores[0][0]['artist']} - {scores[0][0]['title']} 跳过纯音乐"
            else:
                msg = f"[{self.current_index}/{self.total_index}]本地: {info['artist']} - {info['title']} 搜索结果:{song_info['artist']} - {song_info['title']} 歌词获取失败"
        elif inst:
            msg = f"[{self.current_index}/{self.total_index}]本地: {info['title']} 搜索结果:{scores[0][0]['artist']} - {scores[0][0]['title']} 跳过纯音乐"
        else:
            msg = f"[{self.current_index}/{self.total_index}]本地: {info['title']} 搜索结果:{song_info['artist']} - {song_info['title']} 歌词获取失败"
        self.signals.massage.emit(msg)
        return None, None

    def run(self) -> None:
        logging.info(f"开始本地匹配歌词,源:{self.sources}")
        try:
            start_time = time.time()
            # Setp 1 处理cue 与 遍历歌曲文件
            self.signals.massage.emit("处理 cue 并 遍历歌曲文件...")
            song_infos = []
            cue_audio_files = []
            cue_count = 0
            audio_file_paths = []
            file_extensions = ['3g2', 'aac', 'aif', 'ape', 'apev2',
                               'dff', 'dsf', 'flac', 'm4a', 'm4b', 'mid',
                               'mp3', 'mp4', 'mpc', 'ofr', 'ofs', 'ogg',
                               'oggflac', 'oggtheora', 'opus', 'spx', 'tak',
                               'tta', 'wav', 'wma', 'wv']
            for root, _dirs, files in os.walk(self.song_path):
                for file in files:
                    if not self.is_running:
                        return
                    if file.lower().endswith('.cue'):
                        file_path = os.path.join(root, file)
                        try:
                            songs, audio_file_paths = parse_cue(file_path)
                            if len(songs) > 0:
                                song_infos.extend(songs)
                                cue_audio_files.extend(audio_file_paths)
                                cue_count += 1
                            else:
                                logging.warning(f"没有在cue文件 {file_path} 解析到歌曲")
                                self.signals.error.emit(f"没有在cue文件 {file_path} 解析到歌曲", 0)
                        except Exception as e:
                            logging.exception("处理cue文件时错误")
                            self.signals.error.emit(f"处理cue文件时错误:{e}", 0)
                    elif file.lower().split(".")[-1] in file_extensions:
                        file_path = os.path.join(root, file)
                        audio_file_paths.append(file_path)

            for cue_audio_file in cue_audio_files:  # 去除cue中有的文件
                if cue_audio_file in audio_file_paths:
                    audio_file_paths.remove(cue_audio_file)
            msg = f"共找到{len(audio_file_paths) + len(song_infos)}首歌曲"
            if cue_count > 0:
                msg += f"，其中{len(song_infos)}首在{cue_count}个cue文件中找到"

            self.signals.massage.emit(msg)

            # Step 2 读取歌曲文件信息
            self.signals.massage.emit("正在读取歌曲文件信息...")
            for audio_file_path in audio_file_paths:
                if not self.is_running:
                    return
                song_info = get_audio_file_info(audio_file_path)
                if isinstance(song_info, str):
                    self.signals.error.emit(song_info, 0)
                    continue
                if isinstance(song_info, dict):
                    song_infos.append(song_info)

            # Step 3 根据信息搜索并获取歌词
            self.signals.massage.emit("正在搜索并获取歌词...")
            merged_lyric = None
            import json
            logging.debug(f"song_infos: {json.dumps(song_infos, indent=4, ensure_ascii=False)}")
            self.total_index = len(song_infos)
            for index, song_info in enumerate(song_infos):
                self.current_index = index + 1
                if not self.is_running:
                    return
                try:
                    merged_lyric, lrc_info = self.search_and_get(song_info)
                except Exception as e:
                    logging.exception("搜索与获取歌词时错误")
                    self.signals.error.emit(f"搜索与获取歌词时错误:{e}", 0)
                if not self.is_running:
                    return
                if merged_lyric is not None:
                    match self.save_mode:
                        case LocalMatchSaveMode.MIRROR:
                            save_folder = os.path.join(self.save_path,
                                                       os.path.dirname(os.path.relpath(song_info["file_path"], self.song_path)))
                        case LocalMatchSaveMode.SONG:
                            save_folder = os.path.dirname(song_info["file_path"])

                        case LocalMatchSaveMode.SPECIFY:
                            save_folder = self.save_path

                    save_folder = escape_path(save_folder).strip()

                    match self.fliename_mode:
                        case LocalMatchFileNameMode.SONG:
                            if song_info["type"] == "cue":
                                save_folder = os.path.join(save_folder, os.path.splitext(os.path.basename(song_info["file_path"]))[0])
                                save_filename = escape_filename(replace_info_placeholders(self.file_name_format, lrc_info, self.lyrics_order)) + ".lrc"
                            else:
                                save_filename = os.path.splitext(os.path.basename(song_info["file_path"]))[0] + ".lrc"

                        case LocalMatchFileNameMode.FORMAT:
                            save_filename = escape_filename(replace_info_placeholders(self.file_name_format, lrc_info, self.lyrics_order)) + ".lrc"

                    save_path = os.path.join(save_folder, save_filename)
                    try:
                        if not os.path.exists(os.path.dirname(save_path)):
                            os.makedirs(os.path.dirname(save_path))
                        with open(save_path, "w", encoding="utf-8") as f:
                            f.write(merged_lyric)
                        if 'artist' in song_info:
                            msg = f"[{self.current_index}/{self.total_index}]本地: {song_info['artist']} - {song_info['title']} 匹配: {lrc_info['artist']} - {lrc_info['title']} 成功保存到{save_path}"
                        else:
                            msg = f"[{self.current_index}/{self.total_index}]本地: {song_info['title']} 匹配: {lrc_info['artist']} - {lrc_info['title']} 成功保存到{save_path}"
                        self.signals.massage.emit(msg)
                    except Exception as e:
                        self.signals.error.emit(str(e), 0)

        except Exception as e:
            logging.exception("匹配时出错")
            self.signals.error.emit(str(e), 1)
        else:
            self.signals.massage.emit(f"匹配完成,耗时{time.time() - start_time}秒")
            self.signals.finished.emit()
