# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import re
import sys
import time
from abc import abstractmethod
from random import SystemRandom

import psutil
from PySide6.QtCore import (
    QEventLoop,
    QMutex,
    QObject,
    QProcess,
    QRunnable,
    QSharedMemory,
    QTimer,
    Signal,
)
from PySide6.QtGui import QGuiApplication
from PySide6.QtNetwork import (
    QHostAddress,
    QLocalServer,
    QLocalSocket,
    QTcpServer,
    QTcpSocket,
)

from backend.lyrics import LyricsWord, MultiLyricsData
from backend.worker import AutoLyricsFetcher  # noqa: F401
from utils.args import args
from utils.data import local_song_lyrics  # noqa: F401
from utils.logger import DEBUG, logger
from utils.paths import command_line
from utils.threadpool import threadpool
from view.desktop_lyrics import DesktopLyricsWidget

random = SystemRandom()
api_version = 1


class ServiceInstanceSignal(QObject):
    handle_task = Signal(dict)
    stop = Signal()


class ServiceInstanceBase(QRunnable):

    def __init__(self, instance_id: int, pid: int | None = None) -> None:
        super().__init__()
        self.instance_id = instance_id
        self.pid = pid
        self.signals = ServiceInstanceSignal()
        self.signals.handle_task.connect(self.handle_task)
        self.signals.stop.connect(self.stop)

    @abstractmethod
    def handle_task(self, task: dict) -> None:
        ...

    def stop(self) -> None:
        self.loop.quit()
        instance_dict_mutex.lock()
        del instance_dict[self.instance_id]
        instance_dict_mutex.unlock()

    def run(self) -> None:
        logger.info("Service instance %s started", self.instance_id)
        self.loop = QEventLoop()
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
    show_signal = Signal()
    handle_task = Signal(int, dict)
    instance_del = Signal()

    def __init__(self) -> None:
        super().__init__()
        self.q_server = QLocalServer(self)
        self.q_server_name = "LDDCService"
        self.socketserver = None
        self.shared_memory = QSharedMemory(self)
        self.shared_memory.setKey("LDDCLOCK")

        self.clients: dict[int, Client] = {}
        self.start_service()

    def start_service(self) -> None:

        if args.get_service_port and not self.shared_memory.attach():
            cmd = command_line.split(" ")
            program = cmd[0]
            arguments = (*cmd[1:], "--not-show") if len(cmd) > 1 else "--not-show"
            arguments = tuple(re.sub(r'"([^"]+)"', r'\1', arg) for arg in arguments)

            QProcess.startDetached(program, arguments)  # 注意在调试模式下无法新建一个独立进程
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
                    self.show_signal.emit()
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

    def stop_service(self) -> None:
        self.q_server.close()
        if self.socketserver:
            self.socketserver.close()
        self.shared_memory.detach()
        self.check_any_instance_alive_timer.stop()

    def on_q_server_new_connection(self) -> None:
        client_connection = self.q_server.nextPendingConnection()
        if client_connection:
            client_connection.readyRead.connect(lambda: self.q_server_read_client(client_connection))

    def q_server_read_client(self, client_connection: QLocalSocket) -> None:
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
                self.show_signal.emit()
                client_connection.write(b"message_received")
                client_connection.flush()
                client_connection.disconnectFromServer()
            case _:
                logger.error("未知消息：%s", response)

    def socket_on_new_connection(self) -> None:
        if not self.socketserver:
            return
        client_socket = self.socketserver.nextPendingConnection()
        client_id = id(client_socket)
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
                    instance_id = random.randint(0, 1024)
                    instance_dict_mutex.lock()
                    instance_dict[instance_id] = DesktopLyricsInstance(instance_id, json_data.get("pid"))
                    instance_dict_mutex.unlock()
                    threadpool.start(instance_dict[instance_id])
                    logger.info("创建新实例：%s", instance_id)
                    response = {"v": api_version, "id": instance_id}
                    self.send_response(client_id, json.dumps(response))
        elif json_data["id"] in instance_dict:
            if json_data["task"] == "del_instance":
                instance_dict[json_data["id"]].signals.stop.emit()
                self.instance_del.emit()
            else:
                instance_dict[json_data["id"]].signals.handle_task.emit(json_data)

    def send_response(self, client_id: int, response: str) -> None:
        logger.debug("发送响应：%s", response)
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

    def __init__(self, instance_id: int, pid: int | None = None) -> None:
        super().__init__(instance_id, pid)
        self.widget = DesktopLyricsWidget()

    def handle_task(self, task: dict) -> None:
        match task["task"]:
            case "chang_music":
                logger.debug("chang_music")

            case "sync":
                # 同步当前播放时间
                playback_time = self.get_playback_time(task)
                a = self.start_time
                self.start_time = int(time.time() * 1000) - playback_time
                logger.debug("sync, self.start_time: %s | %s", self.start_time, self.start_time - a)

            case "pause":
                # 暂停歌词
                logger.debug("pause")
                if self.timer.isActive():
                    self.timer.stop()

            case "proceed":
                # 继续歌词
                logger.debug("proceed")
                playback_time = self.get_playback_time(task)
                if playback_time is not None:
                    self.start_time = int(time.time() * 1000) - playback_time
                else:
                    self.start_time = int(time.time() * 1000) - self.current_time
                if not self.timer.isActive():
                    self.timer.start(int(self.update_frequency))
                logger.debug("proceed, self.start_time: %s", self.start_time)

            case "stop":
                logger.debug("stop")
                # 停止歌词
                self.reset()

    def get_playback_time(self, task: dict) -> float:
        # 获取当前播放时间
        playback_time = task.get("playback_time")  # 单位为毫秒
        send_time = task.get("send_time")
        if isinstance(playback_time, int) and isinstance(send_time, float):
            # 补偿网络延迟
            delay = (time.time() - send_time) * 1000
            logger.debug("delay: %s ms", delay)
            if delay > 0:
                playback_time = playback_time - round(delay)
        else:
            msg = "playback_time or send_time is not int or float"
            raise TypeError(msg)
        return playback_time

    def run(self) -> None:
        self.timer = QTimer()
        refresh_rate = QGuiApplication.primaryScreen().refreshRate()
        self.update_frequency = 1000 // refresh_rate  # 更新频率,单位:毫秒
        self.timer.timeout.connect(self.update_lyrics)
        self.reset()
        super().run()

    def reset(self) -> None:
        """重置歌词"""
        self.start_time = 0  # 当前unix时间 - 已播放的时间
        self.current_time = 0.0  # 当前已播放时间,单位:毫秒
        self.lyrics = MultiLyricsData({})
        self.order_lyrics = []

        if self.timer.isActive():
            self.timer.stop()

    def update_lyrics(self) -> None:  # noqa: PLR0915
        """更新歌词"""
        self.current_time = time.time() * 1000 - self.start_time
        lyrics_to_display = {"l": [], "r": []}
        return

        def add2lyrics_to_display(lyrics_lines: list[tuple[list[LyricsWord], str, int]]) -> None:
            for _lyrics_line, key, alpha in lyrics_lines:
                before = ""
                current: tuple[str, float] | None = ("", 0)
                after = ""

                all_chars = ""
                for start, end, chars in _lyrics_line:
                    all_chars += chars
                    if end <= self.current_time:
                        # 已经播放过的歌词字
                        before += chars
                    elif start <= self.current_time <= end:
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

                    elif self.current_time <= start:
                        # 未播放的歌词字
                        after += chars

                lyrics_to_display[key].append((before, current, after, alpha))

                self.widget.lyrics_to_display_mutex.lock()
                self.widget.lyrics_to_display = lyrics_to_display
                self.widget.lyrics_to_display_mutex.unlock()

        for lyrics_type in self.order_lyrics:
            if lyrics_type not in self.lyrics:
                continue

            lyrics_data = self.lyrics[lyrics_type]
            for index, lyrics_line in enumerate(lyrics_data):
                if lyrics_line[0] <= self.current_time <= lyrics_line[1]:
                    lyrics_lines = [(lyrics_line[2], "l" if (index % 2) == 0 else "r", 255)]
                    if 0 < index < len(lyrics_data) - 1:
                        if lyrics_data[index - 1][0] < self.current_time < lyrics_data[index + 1][1]:
                            # 计算透明度(淡入淡出)
                            kp = (lyrics_data[index + 1][0] - self.current_time) / (lyrics_data[index + 1][0] - lyrics_data[index - 1][1])
                            if kp > 0.5:
                                lyrics_lines.append((lyrics_data[index - 1][2], "l" if ((index - 1) % 2) == 0 else "r", 255 * (kp - 0.5) * 2))
                            else:
                                lyrics_lines.append((lyrics_data[index + 1][2], "l" if ((index + 1) % 2) == 0 else "r", 255 * (0.5 - kp) * 2))
                        else:
                            lyrics_lines.append((lyrics_data[index + 1][2], "l" if ((index + 1) % 2) == 0 else "r", 255))

                    elif index > 0:
                        # 最后一个
                        lyrics_lines.append((lyrics_data[index - 1][2], "l" if ((index - 1) % 2) == 0 else "r", 255))
                    elif index == 0:
                        # 第一个
                        lyrics_lines.append(
                            (lyrics_data[index + 1][2], "l" if ((index + 1) % 2) == 0 else "r", 255 * self.current_time / lyrics_data[index + 1][0]))

                    add2lyrics_to_display(lyrics_lines)
                    break
            else:
                before_lyrics_lines = None
                after_lyrics_lines = None
                lyrics_lines = []
                for index, lyrics_line in enumerate(lyrics_data):
                    if lyrics_line[1] < self.current_time:
                        before_lyrics_lines = (index, lyrics_line)
                    elif lyrics_line[0] > self.current_time:
                        after_lyrics_lines = (index, lyrics_line)
                        break

                if before_lyrics_lines and after_lyrics_lines:
                    if after_lyrics_lines[0] < len(lyrics_data) - 1 and after_lyrics_lines[0] - 2 >= 0:
                        next_before_index = before_lyrics_lines[0] + 2
                        next_before_lyrics_lines = lyrics_data[before_lyrics_lines[0] + 2]
                        previous_after_index = after_lyrics_lines[0] - 2
                        previous_after_lyrics_lines = lyrics_data[after_lyrics_lines[0] - 2]
                        after_lyrics_index = after_lyrics_lines[0]
                        after_lyrics_lines = after_lyrics_lines[1]
                        before_lyrics_index = before_lyrics_lines[0]
                        before_lyrics_lines = before_lyrics_lines[1]
                        kp = (next_before_lyrics_lines[0] - self.current_time) / (next_before_lyrics_lines[0] - before_lyrics_lines[1])
                        if kp > 0.5:
                            lyrics_lines.append((before_lyrics_lines[2], "l" if (before_lyrics_index % 2) == 0 else "r", 255 * (kp - 0.5) * 2))
                        else:
                            lyrics_lines.append((next_before_lyrics_lines[2], "l" if (next_before_index % 2) == 0 else "r", 255 * (0.5 - kp) * 2))

                        kp = (after_lyrics_lines[0] - self.current_time) / (after_lyrics_lines[0] - previous_after_lyrics_lines[0])
                        if kp > 0.5:
                            lyrics_lines.append((previous_after_lyrics_lines[2], "l" if (previous_after_index % 2) == 0 else "r", 255 * (kp - 0.5) * 2))
                        else:
                            lyrics_lines.append((after_lyrics_lines[2], "l" if (after_lyrics_index % 2) == 0 else "r", 255 * (0.5 - kp) * 2))
                        add2lyrics_to_display(lyrics_lines)
                    elif after_lyrics_lines[0] == len(lyrics_data) - 1 and after_lyrics_lines[0] - 2 >= 0:
                        previous_after_index = after_lyrics_lines[0] - 2
                        previous_after_lyrics_lines = lyrics_data[after_lyrics_lines[0] - 2]
                        after_lyrics_index = after_lyrics_lines[0]
                        after_lyrics_lines = after_lyrics_lines[1]

                        kp = (after_lyrics_lines[0] - self.current_time) / (after_lyrics_lines[0] - previous_after_lyrics_lines[0])
                        if kp > 0.5:
                            lyrics_lines.append((previous_after_lyrics_lines[2], "l" if (previous_after_index % 2) == 0 else "r", 255 * (kp - 0.5) * 2))
                        else:
                            lyrics_lines.append((after_lyrics_lines[2], "l" if (after_lyrics_index % 2) == 0 else "r", 255 * (0.5 - kp) * 2))
                        add2lyrics_to_display(lyrics_lines)

                elif not before_lyrics_lines and after_lyrics_lines:
                    # 开头
                    next_lyrics_index = after_lyrics_lines[0] + 1
                    next_lyrics_lines = lyrics_data[after_lyrics_lines[0] + 1]
                    after_lyrics_index = after_lyrics_lines[0]
                    after_lyrics_lines = after_lyrics_lines[1]
                    lyrics_lines.append(
                        (after_lyrics_lines[2], "l" if (after_lyrics_index % 2) == 0 else "r", 255 * self.current_time / after_lyrics_lines[0]))
                    lyrics_lines.append((next_lyrics_lines[2], "l" if (next_lyrics_index % 2) == 0 else "r", 255 * self.current_time / next_lyrics_lines[0]))
