# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import json
import time

from PySide6.QtCore import QTimer
from PySide6.QtNetwork import QHostAddress, QTcpServer, QTcpSocket
from pytestqt.qtbot import QtBot

from LDDC.common.data.local_song_lyrics_db import local_song_lyrics
from LDDC.gui.service import DesktopLyricsInstance, LDDCService, api_version, instance_dict, random

from .helper import grab, screenshot_path


class _TestLDDCService(LDDCService):

    def start_service(self) -> None:
        self.q_server.listen(self.q_server_name)
        # 找到一个可用的端口
        self.socketserver = QTcpServer(self)
        while True:
            port = random.randint(10000, 65535)  # 随机生成一个端口
            if self.socketserver.listen(QHostAddress("127.0.0.1"), port):
                self.socket_port = port
                break

        self.q_server.newConnection.connect(self.on_q_server_new_connection)
        self.socketserver.newConnection.connect(self.socket_on_new_connection)

        self.check_any_instance_alive_timer = QTimer(self)
        self.check_any_instance_alive_timer.timeout.connect(self._clean_dead_instance)
        self.check_any_instance_alive_timer.start(1000)
        self.instance_finished.connect(self.del_instance)

        self.send_msg.connect(self.socket_send_message)


def test_desktop_lyrics(qtbot: QtBot) -> None:
    service = _TestLDDCService()
    qtbot.wait(20)
    clinet = QTcpSocket()
    clinet.connectToHost(QHostAddress("127.0.0.1"), service.socket_port)
    assert clinet.waitForConnected(1000)

    def send_msg(msg: dict) -> None:
        bytes_msg = json.dumps(msg).encode("utf-8")
        # 前面加上4个字节的长度
        clinet.write(len(bytes_msg).to_bytes(4, "big"))
        clinet.write(bytes_msg)
        clinet.flush()

    def recv_msg() -> dict:
        qtbot.wait(20)
        buffer = bytearray()
        length = -1
        while clinet.bytesAvailable() > 0 and (length == -1 or len(buffer) < length):
            qtbot.wait(10)
            buffer += clinet.readAll().data()
            if length == -1 and len(buffer) >= 4:
                length = int.from_bytes(buffer[:4], "big")
                buffer = buffer[4:]
        return json.loads(buffer.decode("utf-8"))
    # 新建一个桌面歌词实例
    send_msg({
        "task": "new_desktop_lyrics_instance",
        "available_tasks": ["play", "pause", "stop", "prev", "next"],
        "info": {"name": "test"},
        "api_ver": 1})

    result = recv_msg()
    service_version = result["v"]
    instance_id = result["id"]
    assert service_version == api_version
    assert instance_id in instance_dict
    instance = instance_dict[instance_id]
    assert isinstance(instance, DesktopLyricsInstance)

    def wait_widget() -> bool:
        return instance.widget.isVisible()

    qtbot.waitUntil(wait_widget, timeout=10000)

    instance.widget.set_transparency(True)
    qtbot.wait(20)
    grab(instance.widget, screenshot_path/  "desktop_lyrics_transparency", "widget")
    instance.widget.set_transparency(False)

    # 切换音乐
    send_msg({
        "task": "chang_music",
        "id": instance_id,
        "title": "アスタロア",
        "artist": "鈴木このみ",
        "album": "アスタロア/青き此方/夏の砂時計",
        "duration": 278000,
        "path": "[test]test_music_path[test]"})
    qtbot.wait(30)
    grab(instance.widget, screenshot_path/  "desktop_lyrics_auto_sreaching", "widget")

    def check_lyrics() -> bool:
        return bool(instance.lyrics)
    qtbot.waitUntil(check_lyrics, timeout=30000)

    # 尝试从关联数据库中获取歌词
    send_msg({
        "task": "chang_music",
        "id": instance_id,
        "title": "アスタロア",
        "artist": "鈴木このみ",
        "album": "アスタロア/青き此方/夏の砂時計",
        "duration": 278000,
        "path": "[test]test_music_path[test]"})
    qtbot.waitUntil(check_lyrics, timeout=30000)

    # 播放音乐
    start_time = time.time()
    send_msg({
        "task": "start",
        "id": instance_id,
        "playback_time": 0,
        "send_time": start_time})
    qtbot.wait(5000)
    grab(instance.widget, screenshot_path/  "desktop_lyrics_playing", "widget")
    instance.widget.control_bar.show()
    qtbot.wait(100)
    instance.widget.set_transparency(True)
    grab(instance.widget, screenshot_path/  "desktop_lyrics_playing_with_control_bar", "widget")
    instance.widget.control_bar.hide()
    instance.widget.set_transparency(False)

    # 暂停音乐
    send_msg({
        "task": "pause",
        "id": instance_id,
        "playback_time": int((time.time() - start_time) * 1000),
        "send_time": time.time()})
    qtbot.wait(20)
    assert not instance.widget.playing

    # 继续歌词
    send_msg({
        "task": "proceed",
        "id": instance_id,
        "playback_time": int((time.time() - start_time) * 1000),
        "send_time": time.time()})
    qtbot.wait(20)
    assert instance.widget.playing
    qtbot.wait(1000)

    # 停止音乐
    send_msg({
        "task": "stop",
        "id": instance_id,
        "playback_time": int((time.time() - start_time) * 1000),
        "send_time": time.time()})

    instance.widget.control_bar.select_button.click()
    instance.widget.hide()
    qtbot.wait(200)
    grab(instance.widget.selector, screenshot_path/ "desktop_lyrics_selector")
    instance.widget.selector.close()

    from LDDC.gui.view.local_song_lyrics_db_manager import local_song_lyrics_db_manager
    local_song_lyrics_db_manager.show()
    qtbot.wait(200)
    grab(local_song_lyrics_db_manager, screenshot_path/ "desktop_lyrics_db_manager")
    local_song_lyrics_db_manager.close()

    # 删除实例
    send_msg({
        "task": "del_instance",
        "id": instance_id})

    def check_del_instance() -> bool:
        return instance_id not in instance_dict
    qtbot.waitUntil(check_del_instance, timeout=10000)

    for id_, _title, _artist, _album, _duration, song_path, _track_number, _lyrics_path, _config in local_song_lyrics.get_all():
        if song_path == "[test]test_music_path[test]":
            local_song_lyrics.del_item(id_)
            break
