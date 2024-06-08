import json
import logging
import sys
import time
from abc import abstractmethod
from argparse import Namespace
from random import SystemRandom

from PySide6.QtCore import (
    QDataStream,
    QMutex,
    QObject,
    QSharedMemory,
    Signal,
)
from PySide6.QtNetwork import (
    QHostAddress,
    QLocalServer,
    QLocalSocket,
    QTcpServer,
    QTcpSocket,
)

from view.desktop_lyrics import DesktopLyricsWidget

random = SystemRandom()
api_version = 1


class ServiceInstanceBase(QObject):

    @abstractmethod
    def handle_task(self, task: dict) -> None:
        ...

    def handle_del_task(self, task: dict) -> None:
        pass


instance_dict: dict[int, ServiceInstanceBase] = {}
instance_dict_mutex = QMutex()


def instance_handle_task(instance_id: int, task: dict) -> None:
    instance_dict_mutex.lock()
    instance = instance_dict.get(instance_id)
    if not instance:
        logging.error(f"未找到实例：{instance_id}")
    instance.handle_task(task)
    if task.get("task") == "del_instance":
        del instance_dict[instance_id]


class LDDCService(QObject):
    show_signal = Signal()
    handle_task = Signal(int, dict)

    def __init__(self, arg: Namespace) -> None:
        super().__init__()
        self.q_server = QLocalServer(self)
        self.q_server_name = "LDDCService"
        self.socketserver = None
        self.shared_memory = QSharedMemory(self)
        self.shared_memory.setKey("LDDCLOCK")

        self.clients: dict[int, tuple[QTcpSocket, bytearray]] = {}
        self.start_service(arg)

    def is_already_running(self) -> bool:
        if self.shared_memory.attach() or (not self.shared_memory.create(1)):
            return True
        return False

    def start_service(self, arg: Namespace) -> None:
        if self.is_already_running():
            # 说明已经有其他LDDC服务启动
            logging.info("LDDC服务已经启动")
            q_client = QLocalSocket(self)
            q_client.connectToServer(self.q_server_name)
            if not q_client.waitForConnected(1000):
                logging.error("LDDC服务连接失败")
                sys.exit(1)
            message = "get_service_port" if arg.get_service_port else "show"
            q_client.write(message.encode())
            q_client.flush()
            if q_client.waitForReadyRead(1000):
                response = q_client.readAll().data().decode()
                logging.info(f"收到服务端消息：{response}")
                sys.exit(0)
        else:
            self.q_server.listen(self.q_server_name)
            # 找到一个可用的端口
            self.socketserver = QTcpServer(self)
            while True:
                port = random.randint(10000, 65535)  # 随机生成一个端口
                if self.socketserver.listen(QHostAddress("127.0.0.1"), port):
                    self.socket_port = port
                    break
                logging.error(f"端口{port}被占用")

            logging.info(f"LDDC服务启动成功, 端口: {self.socket_port}")
            if arg.get_service_port:
                print(self.socket_port)
            self.q_server.newConnection.connect(self.on_q_server_new_connection)

    def stop_service(self) -> None:
        self.q_server.close()
        self.socketserver.close()
        self.shared_memory.detach()

    def on_q_server_new_connection(self) -> None:
        client_connection = self.q_server.nextPendingConnection()
        if client_connection:
            client_connection.readyRead.connect(lambda: self.q_server_read_client(client_connection))

    def q_server_read_client(self, client_connection: QLocalSocket) -> None:
        data = client_connection.readAll().data().decode()
        logging.info(f"收到客户端消息：{data}")
        match data:
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
                logging.error(f"未知消息：{data}")

    def socket_on_new_connection(self) -> None:
        client_socket = self.socketserver.nextPendingConnection()
        client_id = id(client_socket)
        self.clients[client_id] = (client_socket, bytearray())
        client_socket.readyRead.connect(lambda: self.socket_read_data(client_id))
        client_socket.disconnected.connect(lambda: self.handle_disconnection(client_id))

    def handle_disconnection(self, client_id: int) -> None:
        self.clients[client_id][0].deleteLater()
        del self.clients[client_id]

    def socket_read_data(self, client_id: int) -> None:
        """
        处理客户端发送的数据(前4字节应为消息长度)
        """
        client_socket = self.clients[client_id][0]
        if client_socket.bytesAvailable() > 0:
            self.clients[client_id][1].append(client_socket.readAll())
            buffer = self.clients[client_id][1]
            while True:
                if len(buffer) < 4:
                    break

                stream = QDataStream(buffer)
                stream.setByteOrder(QDataStream.BigEndian)
                message_length = stream.readUInt32()

                if len(buffer) < 4 + message_length:
                    break

                message_data = buffer[4:4 + message_length]
                self.clients[client_id][1] = buffer[4 + message_length:]

                self.handle_socket_message(message_data, client_id)

    def handle_socket_message(self, message_data: bytes, client_id: int) -> None:
        data = message_data.decode()
        logging.info(f"收到客户端消息：{data}")
        try:
            json_data = json.loads(data)
            if not isinstance(json_data, dict) or "task" not in json_data:
                logging.error(f"数据格式错误：{data}")
                return
        except json.JSONDecodeError:
            logging.exception(f"JSON解码错误：{data}")
            return

        if "id" not in json_data:
            match json_data["task"]:
                case "new_desktop_lyrics_instance":
                    instance_id = random.randint(0, 1024)
                    instance_dict_mutex.lock()
                    instance_dict[instance_id] = DesktopLyricsInstance(instance_id)
                    instance_dict_mutex.unlock()
                    response = {"v": api_version, "id": instance_id}
                    self.send_response(client_id, json.dumps(response))
        else:
            self.handle_task.emit(json_data["id"], json_data)

    def send_response(self, client_id: int, response: str) -> None:
        client_socket = self.clients[client_id][0]
        response_bytes = response.encode('utf-8')
        response_length = len(response_bytes)
        length_bytes = response_length.to_bytes(4, byteorder='big')

        client_socket.write(length_bytes + response_bytes)
        client_socket.flush()


class DesktopLyricsInstance(ServiceInstanceBase):

    def __init__(self, instance_id: int) -> None:
        super().__init__()
        self.instance_id = instance_id
        self.Widget = DesktopLyricsWidget()
        self.Widget.show()

    def handle_task(self, task: dict) -> None:
        match task["task"]:
            case "chang_music":
                pass
            case "sync":
                # 同步当前播放时间
                playback_time = self.get_playback_time(task)
                if playback_time is not None:
                    self.Widget.set_current_time(playback_time)
            case "pause":
                # 暂停歌词
                self.Widget.pause()

            case "proceed":
                # 继续歌词
                playback_time = self.get_playback_time(task)
                if playback_time is not None:
                    self.Widget.proceed(playback_time)

            case "stop":
                # 停止歌词
                self.Widget.reset()

    def get_playback_time(self, task: dict) -> int:
        # 获取当前播放时间
        playback_time = task.get("playback_time")  # 单位为毫秒
        send_time = task.get("send_time")
        if isinstance(playback_time, int) and isinstance(send_time, float):
            # 补偿网络延迟
            playback_time = playback_time + (int(time.time() * 1000) - int(send_time * 1000))
        return playback_time
