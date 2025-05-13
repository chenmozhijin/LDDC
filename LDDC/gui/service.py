# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import re
import shlex
import subprocess
import sys
import time
from abc import abstractmethod
from copy import deepcopy
from pathlib import Path
from random import SystemRandom
from threading import Lock
from typing import Literal

import psutil
from PySide6.QtCore import (
    QCoreApplication,
    QObject,
    QSharedMemory,
    Qt,
    QThread,
    QTimer,
    Signal,
    Slot,
)
from PySide6.QtNetwork import (
    QHostAddress,
    QLocalServer,
    QLocalSocket,
    QTcpServer,
    QTcpSocket,
)

from LDDC.common.args import args
from LDDC.common.data.config import cfg
from LDDC.common.data.local_song_lyrics_db import local_song_lyrics
from LDDC.common.logger import DEBUG, logger
from LDDC.common.models import (
    FSLyricsData,
    FSLyricsLine,
    FSLyricsWord,
    Lyrics,
    LyricsFormat,
    LyricsType,
    SongInfo,
    Source,
)
from LDDC.common.path_processor import escape_filename
from LDDC.common.paths import auto_save_dir, command_line
from LDDC.common.task_manager import TaskManager
from LDDC.common.thread import cross_thread_func, in_main_thread, in_other_thread
from LDDC.common.utils import has_content
from LDDC.core.algorithm import assign_lyrics_positions, find_closest_match
from LDDC.core.api.lyrics import get_lyrics
from LDDC.core.auto_fetch import auto_fetch
from LDDC.core.converter import convert2
from LDDC.gui.view.desktop_lyrics import DesktopLyric, DesktopLyrics, DesktopLyricsWidget, Direction
from LDDC.gui.view.update import check_update

random = SystemRandom()
api_version = 1


class ServiceInstanceBase(QThread):
    task = Signal(dict)
    stop = Signal()

    def __init__(self, service: "LDDCService", instance_id: int, client_id: int, pid: int | None = None) -> None:
        super().__init__()
        self.service = service
        self.instance_id = instance_id
        self.pid = pid
        self.client_id = client_id
        self.moveToThread(self)  # 让信号连接的函数在此线程运行

    @abstractmethod
    @Slot(dict)
    def handle_task(self, task: dict) -> None: ...

    @abstractmethod
    def init(self) -> None: ...

    @Slot()
    def handle_stop(self) -> None:
        self.quit()
        logger.info("Service instance %s stopped", self.instance_id)
        self.service.instance_finished.emit(self.instance_id)

    def run(self) -> None:
        logger.info("Service instance %s started", self.instance_id)

        self.stop.connect(self.handle_stop)
        self.task.connect(self.handle_task)

        self.init()
        self.exec()


instance_dict: dict[int, ServiceInstanceBase] = {}
instance_dict_lock = Lock()


def clean_dead_instance() -> bool:
    to_stop = []
    with instance_dict_lock:
        for instance_id, instance in instance_dict.items():
            if instance.pid is not None and not psutil.pid_exists(instance.pid):
                to_stop.append(instance_id)

    for instance_id in to_stop:
        instance_dict[instance_id].stop.emit()
    return bool(to_stop)


def check_any_instance_alive() -> bool:
    clean_dead_instance()
    return bool([True for instance in instance_dict.values() if instance.isRunning()])


class Client:
    def __init__(self, socket: QTcpSocket | QLocalSocket) -> None:
        self.socket = socket
        self.buffer = bytearray()


class LDDCService(QObject):
    handle_task = Signal(int, dict)
    instance_del = Signal()
    instance_finished = Signal(int)
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

        from LDDC.gui.exit_manager import exit_manager

        exit_manager.close_signal.connect(self.stop_service, Qt.ConnectionType.BlockingQueuedConnection)

        QTimer.singleShot(0, self.init_api)

    def start_service(self) -> None:
        if command_line is None:
            msg = "You should start LDDCService by starting the LDDC main program"
            raise RuntimeError(msg)

        if args.get_service_port and not self.shared_memory.attach():
            cmd = shlex.split(command_line, posix=False)
            arguments = [re.sub(r'"([^"]+)"', r"\1", arg) for arg in [cmd[0]] + ([*cmd[1:], "--not-show"] if len(cmd) > 1 else ["--not-show"])]

            # 注意在调试模式下无法新建一个独立进程
            logger.info("在独立进程中启动LDDC服务,  命令行参数：%s", arguments)
            subprocess.Popen(
                arguments,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                close_fds=True,
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS,
            )

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
            self.instance_finished.connect(self.del_instance)

            self.send_msg.connect(self.socket_send_message)

    def init_api(self) -> None:
        from LDDC.core.api.lyrics import lyrics_api
        from LDDC.core.api.translate import translate_api

        in_other_thread(lambda: (lyrics_api.init(), translate_api.init()), None, None)

    @Slot()
    def stop_service(self) -> None:
        self.q_server.close()
        if self.socketserver:
            self.socketserver.close()
        self.shared_memory.detach()
        self.check_any_instance_alive_timer.stop()
        logger.info("LDDC服务停止完成")

    @Slot()
    def on_q_server_new_connection(self) -> None:
        logger.info("q_server_new_connection")
        client_connection = self.q_server.nextPendingConnection()
        if client_connection:
            client_connection.readyRead.connect(self.q_server_read_client)

    @Slot()
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
                    from LDDC.gui.view.main_window import main_window

                    main_window.show_window()

                in_main_thread(show_main_window)
                client_connection.write(b"message_received")
                client_connection.flush()
                client_connection.disconnectFromServer()
            case _:
                logger.error("未知消息：%s", response)

    @Slot()
    def socket_on_new_connection(self) -> None:
        if not self.socketserver:
            return
        client_socket = self.socketserver.nextPendingConnection()
        client_id = int(f"{id(client_socket) % (10**5)}{(int(time.time() * 1000) % (10**4))}")
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
                message_length = int.from_bytes(self.clients[client_id].buffer[:4], byteorder="big")  # 获取消息长度(前四字节)

                if len(self.clients[client_id].buffer) < 4 + message_length:
                    break

                message_data = self.clients[client_id].buffer[4 : 4 + message_length]
                self.clients[client_id].buffer = self.clients[client_id].buffer[4 + message_length :]

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
                    with instance_dict_lock:
                        instance_dict[instance_id] = DesktopLyricsInstance(self, instance_id, json_data, client_id)
                    instance_dict[instance_id].start()
                    logger.info("创建新实例：%s", instance_id)
                    response = {"v": api_version, "id": instance_id}
                    self.socket_send_message(client_id, json.dumps(response))
        elif json_data["id"] in instance_dict:
            if json_data["task"] == "del_instance":
                instance_dict[json_data["id"]].stop.emit()
                self.instance_del.emit()
            else:
                instance_dict[json_data["id"]].task.emit(json_data)

    @Slot(int, str)
    def socket_send_message(self, client_id: int, response: str) -> None:
        """向客户端发送消息(前4字节应为消息长度)"""
        logger.debug("%s 发送响应：%s", client_id, response)
        if client_id not in self.clients:
            logger.error("客户端ID不存在：%s, self.clients: %s", client_id, self.clients)
        client_socket = self.clients[client_id].socket
        response_bytes = response.encode("utf-8")
        response_length = len(response_bytes)
        length_bytes = response_length.to_bytes(4, byteorder="big")

        client_socket.write(length_bytes + response_bytes)
        client_socket.flush()

    @Slot()
    def _clean_dead_instance(self) -> None:
        if clean_dead_instance():
            self.instance_del.emit()

    @Slot(int)
    def del_instance(self, instance_id: int) -> None:
        with instance_dict_lock:
            instance_dict[instance_id].deleteLater()
            del instance_dict[instance_id]
            self.instance_del.emit()


class DesktopLyricsInstance(ServiceInstanceBase):
    def __init__(self, service: LDDCService, instance_id: int, json_data: dict, client_id: int) -> None:
        super().__init__(service, instance_id, client_id, json_data.get("pid"))
        self.client_info = json_data.get("info", {})  # 客户端信息
        self.available_tasks = json_data.get("available_tasks", [])  # 客户端可用的任务

        # 初始化实例变量
        # 任务ID 用于防止旧任务的结果覆盖新任务的结果
        self.task_manager = TaskManager({"auto_fetch": []})

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
        # 连接gui信号
        self.widget.send_task.connect(self.send_task)
        self.widget.moved.connect(self.update_refresh_rate)
        self.widget.to_select.connect(self.to_select)
        self.widget.selector.lyrics_selected.connect(self.select_lyrics)

        self.widget.menu.action_set_inst.triggered.connect(self.set_inst)
        self.widget.menu.actino_set_auto_search.triggered.connect(self.set_auto_search)
        self.widget.menu.action_unlink_lyrics.triggered.connect(lambda: self.unlink_lyrics())

        cfg.desktop_lyrics_changed.connect(self.cfg_changed_slot)

    @cross_thread_func
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
        self.lyrics_path: None | Path = None
        self.song_info: SongInfo | None = None  # 歌曲信息
        self.assigned_lyrics_datas: dict[tuple[Literal[Direction.RIGHT, Direction.LEFT], int], list[tuple[int, FSLyricsLine]]] | None = None
        self.config = {}

    @Slot(bool)
    @Slot()
    def to_select(self, if_show: bool = False) -> None:
        """打开选择器"""
        if if_show and not in_main_thread(self.widget.selector.isVisible):
            return
        info = {"offset": self.config.get("offset", 0)}
        info["lyrics"] = self.lyrics
        if self.song_info:
            keyword = ""
            if self.song_info.artist:
                keyword += self.song_info.str_artist
            if self.song_info.title:
                if keyword:
                    if len(keyword) > len(self.song_info.title) * 2:
                        keyword = ""
                    else:
                        keyword += " - "
                keyword += self.song_info.title
            info["keyword"] = keyword
        if self.timer.isActive():
            start = True
            self.timer.stop()
        else:
            start = False
        info["langs"] = self.config.get("langs", self.default_langs)
        self.widget.show_selector.emit(info)
        if start:
            self.timer.start()

    def send_message(self, msg: str) -> None:
        """发送消息给客户端"""
        self.service.send_msg.emit(self.client_id, msg)

    @Slot(str)
    def send_task(self, task: str) -> None:
        """发送任务给客户端"""
        if task in self.available_tasks:
            self.send_message(json.dumps({"task": task}))

    @Slot()
    def handle_task(self, task: dict) -> None:
        """处理客户端发送的任务"""
        # 同步播放时间
        if isinstance((playback_time := task.get("playback_time")), int):  # 单位为毫秒
            delay = 0
            if isinstance((send_time := task.get("send_time")), float):  # 单位为秒
                delay = (time.time() - send_time) * 1000

                if delay > 0:
                    playback_time -= round(delay)
            last_start_time = self.start_time
            self.start_time = int(time.time() * 1000) - playback_time
            logger.debug("同步播放时间 playback_time:%s|%s| delay:%s", playback_time, last_start_time - self.start_time, delay)

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
                self.task_manager.clear_task("auto_fetch")  # 防止自动搜索把上一首歌的歌词关联到这一首歌上

                lyrics = None
                self.reset()
                self.widget.new_lyrics.emit({})
                # 处理歌曲信息
                song_info = {k: task.get(k) for k in ("title", "artist", "album", "duration", "path", "track")}

                if (
                    any((not isinstance(song_info[k], str | None)) for k in ("title", "artist", "album", "path"))
                    or not isinstance(song_info["duration"], int)
                    or not isinstance(song_info["track"], int | str | None)
                ):
                    logger.error("task:chang_music, invalid data")
                    return

                self.song_info = SongInfo.from_dict(
                    {
                        **{k: v for k, v in song_info.items() if k in ("title", "artist", "album", "duration", "path") if v is not None},
                        "id": str(song_info["track"]) if song_info["track"] is not None else None,
                        "source": Source.Local,
                    },
                )
                # 先在关联数据库中查找
                self.to_select(True)
                if (query_result := local_song_lyrics.query(self.song_info)) is not None:
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
                    elif lyrics_path:
                        try:
                            lyrics = get_lyrics(path=lyrics_path)
                            self.lyrics_path = lyrics_path
                        except Exception:
                            logger.exception("读取歌词时错误,lyrics_path: %s", lyrics_path)

                if self.config.get("inst"):
                    pass
                elif isinstance(lyrics, Lyrics):
                    self.set_lyrics(lyrics)
                elif not self.config.get("disable_auto_search"):
                    if self.song_info.title or self.song_info.path:
                        # 如果找不到,则自动获取歌词
                        text = QCoreApplication.translate("DesktopLyrics", "自动获取歌词中...")
                        self.widget.update_lyrics.emit(
                            DesktopLyrics([DesktopLyric([(text, len(text), 255, [])])]),
                        )
                        self.task_manager.new_multithreaded_task(
                            "auto_fetch",
                            auto_fetch,
                            lambda lyrics: self.select_lyrics(lyrics, is_inst=lyrics.is_inst())
                            if lyrics.types.get("orig") != LyricsType.PlainText
                            else self.auto_search_fail(QCoreApplication.translate("DesktopLyrics", "自动获取的歌词为纯文本，无法显示")),
                            lambda error: self.auto_search_fail(str(error))
                            if not re.findall(
                                r"伴奏|纯音乐|inst\.?(?:rumental)|off ?vocal(?: ?[Vv]er.)?",
                                self.song_info.title if self.song_info and self.song_info.title else "",
                            )
                            else self.set_inst(),
                            self.song_info,
                            sources=[Source[s] for s in cfg["desktop_lyrics_sources"]],
                        )
                    else:
                        # 没有标题/路径无法自动获取歌词
                        self.auto_search_fail(QCoreApplication.translate("DesktopLyrics", "没有获取到标题或文件名信息, 无法自动获取歌词"))
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

    @Slot(Lyrics, Path, list, int)
    def select_lyrics(self, lyrics: Lyrics, path: Path | None = None, langs: list[str] | None = None, offset: int = 0, is_inst: bool = False) -> None:
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
            self.task_manager.clear_task("auto_fetch")  # 更新任务id防止自动搜索比手动选择慢时覆盖结果
            self.set_lyrics(lyrics)
            if lyrics.info.source != Source.Local:
                # 生成文件名
                file_name = " - ".join(item for item in [str(lyrics.artist), lyrics.title] if item)
                if lyrics.info.source:
                    file_name += "｜" + lyrics.info.source.name
                if lyrics.id is not None:
                    file_name += f"({lyrics.id})"
                elif lyrics.mid is not None:
                    file_name += f"({lyrics.mid})"
                else:
                    file_name += f"(time:{time.time_ns()})"
                file_name += ".json"

                path = auto_save_dir / escape_filename(file_name)

                # 保存歌词
                try:
                    with path.open("w", encoding="utf-8") as f:
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
        self.widget.new_lyrics.emit({"type": lyrics.types.get("orig"), "source": lyrics.info.source, "inst": False})
        self.lyrics = lyrics

        self.duration = self.song_info.duration if self.song_info and self.song_info.duration else lyrics.get_duration()

        if not lyrics:
            self.assigned_lyrics_datas = None
            self.lyrics_mapping = None
            self.to_select(True)
            return

        offseted_lyrics = deepcopy(lyrics).get_fslyrics(self.song_info.duration if self.song_info else None)
        mulyrics_data = offseted_lyrics.add_offset(self.config.get("offset", 0))
        if "LDDC_ts" in mulyrics_data:
            mulyrics_data["ts"] = mulyrics_data.pop("LDDC_ts")
        mulyrics_data["orig"] = FSLyricsData(
            [
                line
                if not line.words or (line.words[0].start == line.start and line.words[-1].end == line.end)
                else FSLyricsLine(line.words[0].start, line.words[-1].end, line.words)
                for line in mulyrics_data["orig"]
            ],
        )

        self.lyrics_mapping = {
            lang: {
                orig_index: mulyrics_data[lang][index]
                for orig_index, index in find_closest_match(
                    data1=mulyrics_data["orig"],
                    data2=mulyrics_data[lang],
                    data3=mulyrics_data.get("orig_lrc"),
                    source=lyrics.info.source,
                ).items()
            }
            for lang in mulyrics_data
            if lang not in ("orig", "orig_lrc")
        }

        self.assigned_lyrics_datas = assign_lyrics_positions(mulyrics_data["orig"])

        self.to_select(True)

    @Slot()
    def set_inst(self) -> None:
        """设置纯音乐时显示的字"""
        if self.song_info:
            self.widget.new_lyrics.emit({"inst": True})
            self.unlink_lyrics(QCoreApplication.translate("DesktopLyrics", "纯音乐，请欣赏"))
            self.config["inst"] = True
            self.update_db_data()

    @Slot(bool)
    @Slot()
    def set_auto_search(self, is_disable: bool | None = None) -> None:
        if self.song_info:
            self.config["disable_auto_search"] = is_disable if is_disable is not None else bool(not self.config.get("disable_auto_search"))
            self.update_db_data()

    @Slot(str)
    def unlink_lyrics(self, msg: str = "") -> None:
        if self.song_info:
            self.lyrics_path = None
            self.lyrics = None
            self.assigned_lyrics_datas = None
            self.lyrics_mapping = None
            self.config = {}
            self.update_db_data()
            self.show_artist_title(msg)
            self.widget.new_lyrics.emit({})

    def update_db_data(self) -> None:
        if not self.song_info:
            msg = "No song_info"
            raise ValueError(msg)
        local_song_lyrics.set_song(
            self.song_info,
            lyrics_path=self.lyrics_path,
            config={
                k: v
                for k, v in self.config.items()
                if (k == "langs" and v != self.default_langs)
                or (k == "offset" and v != 0)
                or (k == "inst" and v is True)
                or (k == "disable_auto_search" and v is True)
            },
        )

    def auto_search_fail(self, msg: str) -> None:
        self.show_artist_title(msg)
        QTimer.singleShot(3000, lambda: self.show_artist_title() if not self.lyrics else None)

    def show_artist_title(self, msg: str = "") -> None:
        """显示歌手-歌曲名与msg

        :param msg: 要显示的字符串
        """
        artist_title = self.song_info.artist_title(replace=True) if self.song_info else "? - ?"
        self.widget.update_lyrics.emit(DesktopLyrics([DesktopLyric([(artist_title, len(artist_title), 255, [])]), DesktopLyric([(msg, len(msg), 255, [])])]))

    @Slot()
    def update_lyrics(self) -> None:
        # 更新界面的歌词,给Gui线程发送self.widget.update_lyrics信号
        if self.assigned_lyrics_datas is None or self.lyrics_mapping is None:
            return
        # 计算当前时间
        self.current_time = int(time.time() * 1000) - self.start_time

        right: DesktopLyric = DesktopLyric([])
        left: DesktopLyric = DesktopLyric([])

        for position in sorted(self.assigned_lyrics_datas, key=lambda x: x[1]):
            desktop_lyric = left if position[0] == Direction.LEFT else right
            perv_line, current_line, next_line = None, None, None
            perv_index, current_index, next_index = None, None, None
            for index, other_line in self.assigned_lyrics_datas[position]:
                if other_line.end < self.current_time:
                    perv_line, perv_index = other_line, index
                elif other_line.start <= self.current_time <= other_line.end:
                    current_line, current_index = other_line, index
                elif other_line.start > self.current_time:
                    next_line, next_index = other_line, index
                    break

            # 确定要显示的歌词行
            if current_line:
                orig_line, orig_index = current_line, current_index
            elif perv_line and next_line:
                # 决定显示上一行还是下一行
                if abs(perv_line.end - self.current_time) < abs(next_line.start - self.current_time):
                    orig_line, orig_index = perv_line, perv_index
                else:
                    orig_line, orig_index = next_line, next_index
                interval = (next_line.start - perv_line.end) // 2
            elif perv_line:
                orig_line, orig_index = perv_line, perv_index
                interval = self.duration - perv_line.end
            elif next_line:
                orig_line, orig_index = next_line, next_index
                interval = next_line.start
            else:
                continue

            if orig_index is None:
                msg = f"未知的歌词行: {orig_line}"
                raise ValueError(msg)

            # 计算透明度(淡入淡出效果)
            max_fade_time = 10000  # 第一行以外淡入淡出最长时间为10000ms
            if orig_line is current_line:
                alpha = 255
            elif orig_line is perv_line:  # 淡出
                fade_time, interval = (
                    (min(self.current_time - orig_line.end, 10000), min(interval, max_fade_time))
                    if position[1] != 0
                    else (self.current_time - orig_line.end, interval)
                )
                alpha = 255 - int((fade_time / interval) * 255) if interval != 0 else 255
            elif orig_line is next_line:  # 淡入
                fade_time, interval = (
                    (min(orig_line.start - self.current_time, 10000), min(interval, max_fade_time))
                    if position[1] != 0
                    else (orig_line.start - self.current_time, interval)
                )
                alpha = 255 - int((fade_time / interval) * 255) if interval != 0 else 255
            else:
                msg = f"未知的歌词行: {orig_line}"
                raise ValueError(msg)
            alpha = int(min(max(alpha, 0), 255))  # 透明度限制在0-255

            for lang in self.config.get("langs", self.default_langs):
                # 遍历所有语言的歌词行
                if lang == "orig":
                    display_line = orig_line
                elif lang in self.lyrics_mapping:
                    if other_line := self.lyrics_mapping[lang].get(orig_index):
                        if lang == "ts" and len(other_line.words) == 1:
                            other_line = FSLyricsLine(
                                orig_line.start,
                                orig_line.end,
                                [FSLyricsWord(orig_line.start, orig_line.end, other_line.words[0].text)],
                            )  # 翻译同步原文
                        display_line = other_line
                    else:
                        display_line = FSLyricsLine(orig_line.start, orig_line.end, [])  # 没有翻译时显示空行,防止位置跳变
                else:
                    continue

                text = "".join(word.text for word in display_line.words)  # 获取当前行歌词文本
                rubys = []

                # 添加歌词行
                if not has_content(text):
                    # 没有内容
                    desktop_lyric.append(("", 0, 0, []))
                elif orig_line is perv_line:
                    # 上一行歌词,淡出效果
                    desktop_lyric.append((text, len(text), alpha, rubys))
                elif orig_line is next_line:
                    # 下一行歌词,淡入效果
                    desktop_lyric.append((text, 0, alpha, rubys))
                elif orig_line is current_line:
                    # 当前行歌词,淡入淡出效果
                    current: float = 0.0

                    for start, end, chars in display_line.words:
                        if end <= self.current_time:
                            # 已经播放过的歌词字
                            current += len(chars)

                        if start < self.current_time < end:
                            # 正在播放的歌词字
                            kp = (self.current_time - start) / (end - start)
                            for c_index in range(1, len(chars) + 1):
                                start_kp = (c_index - 1) / len(chars)
                                end_kp = c_index / len(chars)
                                if start_kp <= kp <= end_kp:
                                    # 正在播放的歌词字
                                    current += (c_index - 1) + ((kp - start_kp) / (end_kp - start_kp))
                                    break

                    desktop_lyric.append((text, current, alpha, rubys))

        self.widget.update_lyrics.emit(DesktopLyrics([left, right]))

    @Slot()
    def update_refresh_rate(self) -> None:
        """更新刷新率,使其与屏幕刷新率同步"""
        refresh_rate = self.widget.screen().refreshRate() if cfg["desktop_lyrics_refresh_rate"] == -1 else cfg["desktop_lyrics_refresh_rate"]
        interval = int(1000 / refresh_rate)
        if interval != self.timer.interval():
            logger.info("歌词刷新率更新,刷新间隔: %s ms, 歌词刷新率: %s Hz, 屏幕刷新率: %s Hz", interval, 1000 / interval, refresh_rate)
            self.timer.setInterval(interval)

    @Slot(tuple)
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

    def handle_stop(self) -> None:
        in_main_thread(self.widget.close)
        super().handle_stop()
