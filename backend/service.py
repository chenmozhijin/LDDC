# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import os
import re
import shlex
import subprocess
import sys
import time
from abc import abstractmethod
from collections import deque
from copy import deepcopy
from random import SystemRandom
from typing import Literal

import psutil
from PySide6.QtCore import (
    QCoreApplication,
    QEventLoop,
    QMutex,
    QObject,
    QRunnable,
    QSharedMemory,
    Qt,
    QTimer,
    Signal,
)
from PySide6.QtNetwork import (
    QHostAddress,
    QLocalServer,
    QLocalSocket,
    QTcpServer,
    QTcpSocket,
)

from backend.calculate import find_closest_match
from backend.converter import convert2
from backend.fetcher import get_lyrics
from backend.lyrics import Lyrics
from backend.worker import AutoLyricsFetcher
from utils.args import args
from utils.data import cfg, local_song_lyrics
from utils.enum import LyricsFormat, LyricsType, Source
from utils.logger import DEBUG, logger
from utils.paths import auto_save_dir, command_line
from utils.thread import in_main_thread, threadpool
from utils.utils import escape_filename, get_artist_str, has_content
from view.desktop_lyrics import DesktopLyrics, DesktopLyricsWidget
from view.update import check_update

random = SystemRandom()
api_version = 1


class ServiceInstanceSignal(QObject):
    handle_task = Signal(dict)
    stop = Signal()


class ServiceInstanceBase(QRunnable):

    def __init__(self, service: "LDDCService", instance_id: int, client_id: int, pid: int | None = None) -> None:
        super().__init__()
        self.service = service
        self.instance_id = instance_id
        self.pid = pid
        self.client_id = client_id

        self.signals = ServiceInstanceSignal()
        self.signals.stop.connect(self.stop)

    @abstractmethod
    def handle_task(self, task: dict) -> None:
        ...

    @abstractmethod
    def init(self) -> None:
        ...

    def stop(self) -> None:
        self.loop.quit()
        logger.info("Service instance %s stopped", self.instance_id)
        instance_dict_mutex.lock()
        del instance_dict[self.instance_id]
        instance_dict_mutex.unlock()

    def run(self) -> None:
        logger.info("Service instance %s started", self.instance_id)
        self.signals.handle_task.connect(self.handle_task)
        self.loop = QEventLoop()
        self.init()
        self.loop.exec()


instance_dict: dict[int, ServiceInstanceBase] = {}
instance_dict_mutex = QMutex()


def clean_dead_instance() -> bool:
    to_stop = []
    instance_dict_mutex.lock()
    for instance_id, instance in instance_dict.items():
        if instance.pid is not None and not psutil.pid_exists(instance.pid):
            to_stop.append(instance_id)
    instance_dict_mutex.unlock()

    for instance_id in to_stop:
        instance_dict[instance_id].signals.stop.emit()
    return bool(to_stop)


def check_any_instance_alive() -> bool:
    clean_dead_instance()
    return bool(instance_dict)


class Client:
    def __init__(self, socket: QTcpSocket | QLocalSocket) -> None:
        self.socket = socket
        self.buffer = bytearray()


class LDDCService(QObject):
    handle_task = Signal(int, dict)
    instance_del = Signal()
    send_msg = Signal(int, str)

    def __init__(self) -> None:
        super().__init__()
        self.q_server = QLocalServer(self)
        self.q_server_name = "LDDCService"
        self.socketserver = None
        self.shared_memory = QSharedMemory(self)
        self.shared_memory.setKey("LDDCLOCK")

        self.clients: dict[int, Client] = {}
        self.start_service()

        from utils.exit_manager import exit_manager
        exit_manager.close_signal.connect(self.stop_service, Qt.ConnectionType.BlockingQueuedConnection)

    def start_service(self) -> None:

        if args.get_service_port and not self.shared_memory.attach():
            cmd = shlex.split(command_line, posix=False)
            arguments = [re.sub(r'"([^"]+)"', r'\1', arg) for arg in [cmd[0]] + ([*cmd[1:], "--not-show"] if len(cmd) > 1 else ["--not-show"])]

            # 注意在调试模式下无法新建一个独立进程
            logger.info("在独立进程中启动LDDC服务,  命令行参数：%s", arguments)
            subprocess.Popen(arguments,  # noqa: S603
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             close_fds=True, creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS)

            wait_time = 0
            while not self.shared_memory.attach():
                time.sleep(0.05)
                wait_time += 0.05
                if wait_time > 5:
                    logger.error("LDDC服务启动失败")
                    sys.exit(1)
            logger.info("LDDC服务启动成功")

        if self.shared_memory.attach() or not self.shared_memory.create(1):
            # 说明已经有其他LDDC服务启动
            logger.info("LDDC服务已经启动")
            q_client = QLocalSocket()
            q_client.connectToServer(self.q_server_name)
            if not q_client.waitForConnected(1000):
                logger.error("LDDC服务连接失败")
                sys.exit(1)
            if args.get_service_port:
                message = "get_service_port"
            elif args.show is False:
                sys.exit(0)
            else:
                message = "show"
            q_client.write(message.encode())
            q_client.flush()
            logger.info("发送消息：%s", message)
            if q_client.waitForReadyRead(1000):
                response_data = q_client.readAll().data()
                if isinstance(response_data, memoryview):
                    response_data = response_data.tobytes()
                response = response_data.decode()
                logger.info("收到服务端消息：%s", response)
                if args.get_service_port:
                    print(response)  # 输出服务端监听的端口  # noqa: T201
                    sys.exit(0)
                else:
                    self.q_server.close()
                    sys.exit(0)
            else:
                logger.error("LDDC服务连接失败")
                sys.exit(1)
        else:
            self.q_server.listen(self.q_server_name)
            # 找到一个可用的端口
            self.socketserver = QTcpServer(self)
            while True:
                port = random.randint(10000, 65535)  # 随机生成一个端口
                if self.socketserver.listen(QHostAddress("127.0.0.1"), port):
                    self.socket_port = port
                    break
                logger.error("端口%s被占用", port)

            logger.info("LDDC服务启动成功, 端口: %s", self.socket_port)
            self.q_server.newConnection.connect(self.on_q_server_new_connection)
            self.socketserver.newConnection.connect(self.socket_on_new_connection)

            self.check_any_instance_alive_timer = QTimer(self)
            self.check_any_instance_alive_timer.timeout.connect(self._clean_dead_instance)
            self.check_any_instance_alive_timer.start(1000)

            self.send_msg.connect(self.socket_send_message)

    def stop_service(self) -> None:
        self.q_server.close()
        if self.socketserver:
            self.socketserver.close()
        self.shared_memory.detach()
        self.check_any_instance_alive_timer.stop()

    def on_q_server_new_connection(self) -> None:
        logger.info("q_server_new_connection")
        client_connection = self.q_server.nextPendingConnection()
        if client_connection:
            client_connection.readyRead.connect(self.q_server_read_client)

    def q_server_read_client(self) -> None:
        client_connection = self.sender()
        if not isinstance(client_connection, QLocalSocket):
            return
        response_data = client_connection.readAll().data()
        if isinstance(response_data, memoryview):
            response_data = response_data.tobytes()
        response = response_data.decode()
        logger.info("收到客户端消息:%s", response)
        match response:
            case "get_service_port":
                client_connection.write(str(self.socket_port).encode())
                client_connection.flush()
                client_connection.disconnectFromServer()
            case "show":
                def show_main_window() -> None:
                    from view.main_window import main_window
                    main_window.show_window()
                in_main_thread(show_main_window)
                client_connection.write(b"message_received")
                client_connection.flush()
                client_connection.disconnectFromServer()
            case _:
                logger.error("未知消息：%s", response)

    def socket_on_new_connection(self) -> None:
        if not self.socketserver:
            return
        client_socket = self.socketserver.nextPendingConnection()
        client_id = int(f"{id(client_socket) % (10 ** 5)}{(int(time.time() * 1000) % (10 ** 4))}")
        logger.info("客户端连接，客户端id：%s", client_id)
        self.clients[client_id] = Client(client_socket)
        client_socket.readyRead.connect(lambda: self.socket_read_data(client_id))
        client_socket.disconnected.connect(lambda: self.handle_disconnection(client_id))

    def handle_disconnection(self, client_id: int) -> None:
        client_socket = self.clients[client_id].socket
        if isinstance(client_socket, QTcpSocket):
            client_socket.deleteLater()
        del self.clients[client_id]

    def socket_read_data(self, client_id: int) -> None:
        """处理客户端发送的数据(前4字节应为消息长度)"""
        if self.clients[client_id].socket.bytesAvailable() > 0:
            self.clients[client_id].buffer.extend(self.clients[client_id].socket.readAll().data())

            while not len(self.clients[client_id].buffer) < 4:

                message_length = int.from_bytes(self.clients[client_id].buffer[:4], byteorder='big')  # 获取消息长度(前四字节)

                if len(self.clients[client_id].buffer) < 4 + message_length:
                    break

                message_data = self.clients[client_id].buffer[4:4 + message_length]
                self.clients[client_id].buffer = self.clients[client_id].buffer[4 + message_length:]

                self.handle_socket_message(message_data, client_id)

    def handle_socket_message(self, message_data: bytes, client_id: int) -> None:
        data = message_data.decode()
        try:
            json_data = json.loads(data)
            if not isinstance(json_data, dict) or "task" not in json_data:
                logger.error("数据格式错误: %s", data)
                return
        except json.JSONDecodeError:
            logger.exception("JSON解码错误: %s", data)
            return
        if logger.level <= DEBUG:
            logger.debug("收到客户端消息：%s", json.dumps(json_data, ensure_ascii=False, indent=4))
        if "id" not in json_data:
            match json_data["task"]:
                case "new_desktop_lyrics_instance":
                    instance_id = random.choice(list(set(range(1024 + len(instance_dict))) - set(instance_dict.keys())))
                    instance_dict_mutex.lock()
                    instance_dict[instance_id] = DesktopLyricsInstance(self, instance_id, json_data, client_id)
                    instance_dict_mutex.unlock()
                    threadpool.startOnReservedThread(instance_dict[instance_id])
                    logger.info("创建新实例：%s", instance_id)
                    response = {"v": api_version, "id": instance_id}
                    self.socket_send_message(client_id, json.dumps(response))
        elif json_data["id"] in instance_dict:
            if json_data["task"] == "del_instance":
                instance_dict[json_data["id"]].signals.stop.emit()
                self.instance_del.emit()
            else:
                instance_dict[json_data["id"]].signals.handle_task.emit(json_data)

    def socket_send_message(self, client_id: int, response: str) -> None:
        """向客户端发送消息(前4字节应为消息长度)"""
        logger.debug("%s 发送响应：%s", client_id, response)
        if client_id not in self.clients:
            logger.error("客户端ID不存在：%s, self.clients: %s", client_id, self.clients)
        client_socket = self.clients[client_id].socket
        response_bytes = response.encode('utf-8')
        response_length = len(response_bytes)
        length_bytes = response_length.to_bytes(4, byteorder='big')

        client_socket.write(length_bytes + response_bytes)
        client_socket.flush()

    def _clean_dead_instance(self) -> None:
        if clean_dead_instance():
            self.instance_del.emit()


class DesktopLyricsInstance(ServiceInstanceBase):

    def __init__(self, service: LDDCService, instance_id: int, json_data: dict, client_id: int) -> None:
        super().__init__(service, instance_id, client_id, json_data.get("pid"))
        self.client_info = json_data.get("info", {})  # 客户端信息
        self.available_tasks = json_data.get("available_tasks", [])  # 客户端可用的任务

        # 初始化实例变量
        # 任务ID 用于防止旧任务的结果覆盖新任务的结果
        self.taskid = 0

    def init(self) -> None:
        # 初始化界面
        in_main_thread(self.init_widget)
        if "name" in self.client_info and "repo" in self.client_info and "ver" in self.client_info:
            repo = self.client_info["repo"]
            name = self.client_info["name"]
            ver = self.client_info["ver"]
            if isinstance(repo, str) and isinstance(name, str) and isinstance(ver, str):
                in_main_thread(check_update, True, name, repo, ver)

        # 初始化定时器
        self.timer = QTimer()
        self.update_refresh_rate()
        self.timer.timeout.connect(self.update_lyrics)
        self.timer.setTimerType(Qt.TimerType.PreciseTimer)

        self.default_langs = cfg["desktop_lyrics_default_langs"]

        self.reset()
        self.widget.send_task.connect(self.send_task)
        self.widget.moved.connect(self.update_refresh_rate)
        self.widget.to_select.connect(self.to_select)
        self.widget.selector.lyrics_selected.connect(self.select_lyrics)

        self.widget.menu.action_set_inst.triggered.connect(self.set_inst)
        self.widget.menu.actino_set_auto_search.triggered.connect(self.set_auto_search)
        self.widget.menu.action_unlink_lyrics.triggered.connect(self.unlink_lyrics)

        cfg.desktop_lyrics_changed.connect(self.cfg_changed_slot)

    def init_widget(self) -> None:
        """初始化界面(主线程)"""
        self.widget = DesktopLyricsWidget(available_tasks=self.available_tasks)
        self.widget.show()

    def reset(self, reset_time: bool = True) -> None:
        """重置歌词"""
        if reset_time:
            self.start_time = int(time.time() * 1000)  # 当前unix时间 - 已播放的时间
            self.current_time = 0.0  # 当前已播放时间,单位:毫秒
        self.lyrics: None | Lyrics = None
        self.lyrics_path: None | str = None
        self.offseted_lyrics: None | Lyrics = None
        self.song_info = {}  # 歌曲信息
        self.config = {}

    def to_select(self, if_show: bool = False) -> None:
        if if_show and not in_main_thread(self.widget.selector.isVisible):
            return
        info = {"offset": self.config.get("offset", 0)}
        info["lyrics"] = self.lyrics
        if self.song_info:
            keyword = ""
            if self.song_info.get("artist"):
                keyword += get_artist_str(self.song_info["artist"])
            if self.song_info.get("title"):
                if keyword:
                    if len(keyword) > len(self.song_info["title"]) * 2:
                        keyword = ""
                    else:
                        keyword += " - "
                keyword += self.song_info["title"]
            info["keyword"] = keyword
        if self.timer.isActive():
            start = True
            self.timer.stop()
        else:
            start = False
        info["langs"] = self.config.get("langs", self.default_langs)
        in_main_thread(self.widget.selector.show, info)
        if start:
            self.timer.start()

    def send_message(self, msg: str) -> None:
        """发送消息给客户端"""
        self.service.send_msg.emit(self.client_id, msg)

    def send_task(self, task: str) -> None:
        """发送任务给客户端"""
        if task in self.available_tasks:
            self.send_message(json.dumps({"task": task}))

    def handle_task(self, task: dict) -> None:
        """处理客户端发送的任务"""
        # 同步播放时间
        if isinstance((playback_time := task.get("playback_time")), int):  # 单位为毫秒
            if isinstance((send_time := task.get("send_time")), float):  # 单位为秒
                delay = (time.time() - send_time) * 1000

                if delay > 0:
                    playback_time -= round(delay)
            last_start_time = self.start_time
            self.start_time = int(time.time() * 1000) - playback_time
            logger.info("同步播放时间 playback_time:%s|%s| delay:%s", playback_time, last_start_time - self.start_time, delay)

        # 处理任务
        logger.debug("instance %s handle task: %s", self.instance_id, task)
        match task["task"]:
            case "start":
                # 开始播放
                if not self.timer.isActive():
                    self.timer.start()

                self.widget.set_playing(True)
            case "chang_music":
                # 更换歌曲
                self.taskid += 1  # 防止自动搜索把上一首歌的歌词关联到这一首歌上

                lyrics = None
                self.reset()
                self.widget.new_lyrics.emit({})
                # 处理歌曲信息
                song_info = {k: task.get(k) for k in ("title", "artist", "album", "duration", "path", "track")}

                if (any((not isinstance(song_info[k], str | None)) for k in ("title", "artist", "album", "path")) or
                        not isinstance(song_info["duration"], int) or not isinstance(song_info["track"], int | str | None)):
                    logger.error("task:chang_music, invalid data")
                    return

                self.song_info = {**{k: v for k, v in song_info.items() if k in ("title", "artist", "album", "duration")}, "song_path": song_info["path"],
                                  "track_number": str(song_info["track"]) if isinstance(song_info["track"], int) else song_info["track"]}
                # 先在关联数据库中查找
                self.to_select(True)
                if (query_result := local_song_lyrics.query(**self.song_info)) is not None:
                    lyrics_path, config = query_result

                    try:
                        self.config.update(config)
                        if "langs" in config:
                            # 保证顺序一致
                            self.config["langs"] = [lang for lang in cfg["desktop_lyrics_langs_order"] if lang in self.config["langs"]]
                        logger.debug("config: %s", config)
                    except Exception:
                        logger.exception("更新歌词配置时错误")

                    if self.config.get("inst"):
                        self.set_inst()
                    else:
                        try:
                            lyrics, _from_cache = get_lyrics(Source.Local, path=lyrics_path)
                            self.lyrics_path = lyrics_path
                        except Exception:
                            logger.exception("读取歌词时错误,lyrics_path: %s", lyrics_path)

                if isinstance(lyrics, Lyrics):
                    self.set_lyrics(lyrics)
                elif not self.config.get("disable_auto_search"):
                    if isinstance(self.song_info["title"], str):
                        # 如果找不到,则自动获取歌词
                        self.widget.update_lyrics.emit(
                            DesktopLyrics(([(QCoreApplication.translate("DesktopLyrics", "自动获取歌词中..."), "", 0, "", 255, [])], [])),
                        )
                        self.taskid += 1
                        info = self.song_info.copy()
                        info["duration"] = info["duration"] / 1000
                        worker = AutoLyricsFetcher(info,
                                                   source=[Source[s] for s in cfg["desktop_lyrics_sources"]], taskid=self.taskid)
                        worker.signals.result.connect(self.handle_fetch_result)
                        threadpool.start(worker)
                    else:
                        # 没有标题无法自动获取歌词
                        self.auto_search_fail(QCoreApplication.translate("DesktopLyrics", "没有获取到标题信息, 无法自动获取歌词"))
                else:
                    self.show_artist_title()

                in_main_thread(self.widget.menu.actino_set_auto_search.setChecked, bool(self.config.get("disable_auto_search")))

            case "sync":
                # 同步歌词
                self.update_lyrics()

            case "pause":
                # 暂停歌词
                if self.timer.isActive():
                    self.timer.stop()
                self.widget.set_playing(False)

            case "proceed":
                # 继续歌词
                if not self.timer.isActive():
                    self.timer.start()
                logger.debug("proceed, self.start_time: %s", self.start_time)
                self.widget.set_playing(True)

            case "stop":
                # 停止歌词
                self.reset()
                if self.timer.isActive():
                    self.timer.stop()
                self.widget.set_playing(False)

    def handle_fetch_result(self, result: dict[str, dict | Lyrics | str | int | bool]) -> None:
        """处理自动获取歌词的结果"""
        if result.get("taskid") != self.taskid:
            # 任务id不匹配,忽略
            return

        if result.get("status") == "成功":
            lyrics = result.get("lyrics")
            if isinstance(lyrics, Lyrics):
                if lyrics.types.get("orig") != LyricsType.PlainText:
                    self.select_lyrics(lyrics, is_inst=result.get("is_inst") is True)
                    return
                result['status'] = QCoreApplication.translate("DesktopLyrics", "自动获取的歌词为纯文本，无法显示")

        self.auto_search_fail(QCoreApplication.translate("DesktopLyrics", "自动获取歌词失败:{0}").format(result.get("status")))
        logger.error("自动获取歌词失败: %s", result.get("status"))

    def select_lyrics(self, lyrics: Lyrics, path: str | None = None, langs: list[str] | None = None, offset: int = 0, is_inst: bool = False) -> None:
        if offset or self.config.get("offset"):
            self.config["offset"] = offset
        if langs:
            if langs != self.default_langs:
                self.config["langs"] = langs
            elif "langs" in self.config:
                self.config.pop("langs")

        if not self.song_info:
            return

        if is_inst or lyrics.is_inst():
            self.set_inst()
        else:
            self.config["inst"] = False
            self.taskid += 1  # 更新任务id防止自动搜索比手动选择慢时覆盖结果
            self.set_lyrics(lyrics)
            if lyrics.source != Source.Local:
                # 生成文件名
                file_name = " - ".join(item for item in [get_artist_str(lyrics.artist), lyrics.title] if item)
                if lyrics.source:
                    file_name += "｜" + lyrics.source.name
                if lyrics.id is not None:
                    file_name += f"({lyrics.id})"
                elif lyrics.mid is not None:
                    file_name += f"({lyrics.mid})"
                else:
                    file_name += f"(time:{time.time_ns()})"
                file_name += ".json"

                path = os.path.join(auto_save_dir, escape_filename(file_name))

                # 保存歌词
                try:
                    with open(path, "w", encoding="utf-8") as f:
                        f.write(convert2(lyrics, None, LyricsFormat.JSON))
                    self.lyrics_path = path
                except Exception as e:
                    logger.error("保存歌词失败: %s", e)
                    return

                logger.debug("保存歌词成功: %s", file_name)
            else:
                self.lyrics_path = path
            self.update_db_data()

    def set_lyrics(self, lyrics: Lyrics) -> None:
        self.widget.new_lyrics.emit({"type": lyrics.types.get("orig"), "source": lyrics.source, "inst": False})
        self.lyrics, self.offseted_lyrics = lyrics, deepcopy(lyrics)
        self.offseted_lyrics.set_data(
            self.offseted_lyrics.get_full_timestamps_lyrics(
                self.song_info.get("duration", self.offseted_lyrics.duration * 1000 if self.offseted_lyrics.duration else None), True).add_offset(
                    self.config.get("offset", 0)))
        self.lyrics_mapping = {lang: find_closest_match(data1=self.offseted_lyrics["orig"],
                                                        data2=self.offseted_lyrics[lang],
                                                        data3=self.offseted_lyrics.get("orig_lrc"),
                                                        source=lyrics.source)
                               for lang in self.offseted_lyrics if lang not in ("orig", "orig_lrc")}
        self.to_select(True)

    def set_inst(self) -> None:
        """设置纯音乐时显示的字"""
        if self.song_info:
            self.config["inst"] = True
            self.widget.new_lyrics.emit({"inst": True})
            self.unlink_lyrics(QCoreApplication.translate("DesktopLyrics", "纯音乐，请欣赏"))

    def set_auto_search(self, is_disable: bool | None = None) -> None:
        if self.song_info:
            self.config["disable_auto_search"] = is_disable if is_disable is not None else bool(not self.config.get("disable_auto_search"))
            self.update_db_data()

    def unlink_lyrics(self, msg: str = "") -> None:
        if self.song_info:
            self.lyrics_path = None
            self.lyrics = None
            self.offseted_lyrics = None
            self.update_db_data()
            self.show_artist_title(msg)

    def update_db_data(self) -> None:
        local_song_lyrics.set_song(**self.song_info, lyrics_path=self.lyrics_path, config={k: v for k, v in self.config.items()
                                                                                           if (k == "langs" and v != self.default_langs) or
                                                                                           k == "offset" and v != 0 or
                                                                                           k == "inst" and v is True or
                                                                                           k == "disable_auto_search" and v is True})

    def auto_search_fail(self, msg: str) -> None:
        self.show_artist_title(msg)
        QTimer.singleShot(3000, lambda taskid=self.taskid: self.show_artist_title() if taskid == self.taskid else None)

    def show_artist_title(self, msg: str = "") -> None:
        """显示歌手-歌曲名与msg

        :param msg: 要显示的字符串
        """
        artist_title = " - ".join(item for item in [self.song_info.get("artist"), self.song_info.get("title")] if item)
        self.widget.update_lyrics.emit(DesktopLyrics(([(artist_title, "", 0, "", 255, [])],
                                                      [(msg, "", 0, "", 255, [])])))

    def update_lyrics(self) -> None:  # noqa: C901, PLR0915
        # 更新界面的歌词,给Gui线程发送self.widget.update_lyrics信号
        if self.offseted_lyrics is None or "orig" not in self.offseted_lyrics:
            return

        orig = self.offseted_lyrics["orig"]
        duration = self.song_info.get("duration", self.offseted_lyrics.get_duration())

        # 计算当前时间
        self.current_time = int(time.time() * 1000) - self.start_time

        perv_lines: deque[tuple[int, tuple[int, int, list[tuple[int, int, str]]]]] = deque(maxlen=2)
        current_lines: list[tuple[int, tuple[int, int, list[tuple[int, int, str]]]]] = []  # 支持同时多行
        next_lines: deque[tuple[int, tuple[int, int, list[tuple[int, int, str]]]]] = deque(maxlen=2)

        right: list[tuple[str, str, float, str, int, list[tuple[int, int, str]]]] = []
        left: list[tuple[str, str, float, str, int, list[tuple[int, int, str]]]] = []

        # 计算当前时间对应的歌词
        for index, (start, end, words) in enumerate(orig):
            if words:
                start = words[0][0]  # noqa: PLW2901
                end = words[-1][1]  # noqa: PLW2901
            if end < self.current_time:
                perv_lines.append((index, (start, end, words)))
            elif start <= self.current_time <= end:
                current_lines.append((index, (start, end, words)))
            elif self.current_time < start and len(next_lines) < 2:
                next_lines.append((index, (start, end, words)))

        def add(index_line: tuple[int, tuple[int, int, list[tuple[int, int, str]]]], line_type: Literal["perv", "current", "next"]) -> None:
            i, line = index_line
            alpha = 255  # 透明度
            pos = right if i % 2 else left
            match line_type:
                case "perv":  # 已经播放过的行 -> 淡出

                    # 本行与下一个在此位置显示的行的时间间隔
                    interval = abs((orig[i + 2][2][0][0] if orig[i + 2][2] else orig[i + 2][0]) - line[1]) if i + 2 < len(orig) else abs(duration - line[1])
                    if interval == 0:
                        pass
                    else:
                        alpha = 255 * (0.5 - abs(self.current_time - line[1]) / interval) * 2

                case "next":  # 未播放过的行 -> 淡入
                    # 本行与上一个在此位置显示的行的时间间隔
                    interval = abs(line[0] - (orig[i - 2][2][-1][1] if orig[i - 2][2] else orig[i - 2][1])) if i - 2 >= 0 else abs(line[0])
                    alpha = 0 if interval == 0 else 255 * (0.5 - abs(line[0] - self.current_time) / interval) * 2

            alpha = int(min(max(alpha, 0), 255))  # 透明度限制在0-255

            def _add(_line: tuple[int, int, list[tuple[int, int, str]]], rubys: list | None = None) -> None:
                if not rubys:
                    rubys = []
                text = "".join(word[2] for word in _line[2])
                if not has_content(text):
                    # 没有内容
                    pos.append(("", "", 0, "", 0, []))
                    return
                match line_type:
                    case "perv":
                        pos.append(("".join(word[2] for word in _line[2]), "", 0, "", alpha, rubys))
                    case "next":
                        pos.append(("", "", 0, "".join(word[2] for word in _line[2]), alpha, rubys))
                    case "current":
                        before = ""
                        current: tuple[str, float] | None = ("", 0)
                        after = ""

                        for i, (start, end, chars) in enumerate(_line[2]):

                            if end <= self.current_time:
                                before += chars
                            elif start < self.current_time < end:
                                # 正在播放的歌词字
                                kp = (self.current_time - start) / (end - start)
                                for c_index, char in enumerate(chars, start=1):
                                    start_kp = (c_index - 1) / len(chars)
                                    end_kp = c_index / len(chars)
                                    if start_kp < kp < end_kp:
                                        # 正在播放的歌词字
                                        current = (char, (kp - start_kp) / (end_kp - start_kp))
                                    elif end_kp <= kp:
                                        # 已经播放过的歌词字
                                        before += char
                                    elif kp <= start_kp:
                                        # 未播放的歌词字
                                        after += char
                                if i + 1 < len(_line[2]):
                                    after += "".join(w[2] for w in _line[2][i + 1:])
                                break
                            else:
                                after += "".join(w[2] for w in _line[2][i:])
                                break

                        pos.append((before, current[0], current[1], after, alpha, rubys))

            for lang in self.config.get("langs", self.default_langs):
                if lang == "orig":
                    _add(line, [])
                elif lang in self.lyrics_mapping:
                    index = self.lyrics_mapping[lang].get(i)
                    if index is not None:
                        _line = self.offseted_lyrics[lang][index]  # type: ignore[reportOptionalSubscript]  不是生成器函数self.offseted_lyrics != None
                        if lang == "ts" and len(_line[2]) == 1:
                            _line = (line[0], line[1], [(line[0], line[1], _line[2][0][2])])  # 翻译同步原文
                        _add(_line)
                    else:
                        pos.append(("", "", 0, "", 0, []))

        if len(current_lines) == 0:
            # 没有找到当前时间对应的歌词
            if perv_lines and not next_lines:
                # 结尾
                for line in perv_lines:
                    add(line, "perv")
            elif next_lines and not perv_lines:
                # 开头
                for line in next_lines:
                    add(line, "next")
            elif perv_lines and next_lines:
                # 中间
                if len(perv_lines) == 2 and abs(perv_lines[0][1][1] - self.current_time) < abs(next_lines[0][1][0] - self.current_time):
                    # 上一行与当前行时间差较小
                    add(perv_lines[0], "perv")
                else:
                    add(next_lines[0], "next")
                if len(next_lines) == 2 and abs(next_lines[1][1][0] - self.current_time) < abs(perv_lines[-1][1][1] - self.current_time):
                    # 下一行与当前行时间差较小
                    add(next_lines[1], "next")
                else:
                    add(perv_lines[-1], "perv")

        elif len(current_lines) == 1:
            # 找到一行歌词
            if perv_lines and next_lines:
                if abs(perv_lines[-1][1][1] - self.current_time) < abs(next_lines[0][1][0] - self.current_time):
                    # 上一行与当前行时间差较小
                    add(perv_lines[-1], "perv")
                else:
                    # 下一行与当前行时间差较小
                    add(next_lines[0], "next")
            elif perv_lines:
                # 即将结尾
                add(perv_lines[-1], "perv")
            elif next_lines:
                # 开头
                add(next_lines[0], "next")

            add(current_lines[0], "current")

        else:
            # 找到多行歌词(显示两行以上会导致淡入淡出错误)
            for line in current_lines:
                add(line, "current")

        self.widget.update_lyrics.emit(DesktopLyrics((left, right)))

    def update_refresh_rate(self) -> None:
        """更新刷新率,使其与屏幕刷新率同步"""
        refresh_rate = self.widget.screen().refreshRate() if cfg["desktop_lyrics_refresh_rate"] == -1 else cfg["desktop_lyrics_refresh_rate"]
        interval = int(1000 / refresh_rate)
        if interval != self.timer.interval():
            logger.info("歌词刷新率更新,刷新间隔: %s ms, 歌词刷新率: %s Hz, 屏幕刷新率: %s Hz", interval, 1000 / interval, refresh_rate)
            self.timer.setInterval(interval)

    def cfg_changed_slot(self, k_v: tuple) -> None:
        """处理配置变更"""
        key, value = k_v
        match key:
            case "desktop_lyrics_default_langs":
                self.default_langs = value
                if "langs" in self.config and set(self.default_langs) == set(self.config["langs"]):
                    self.config.pop("langs", None)
                    self.update_db_data()
            case "desktop_lyrics_refresh_rate":
                self.update_refresh_rate()
            case "desktop_lyrics_langs_order":
                if "langs" in self.config:
                    self.config["langs"] = [lang for lang in value if lang in self.config["langs"]]
                    self.update_db_data()

    def stop(self) -> None:
        in_main_thread(self.widget.close)
        super().stop()
