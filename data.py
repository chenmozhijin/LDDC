# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import ast
import logging
import os
import sqlite3

from PySide6.QtCore import QMutex


class Data:

    def __init__(self, current_directory: str, mutex: QMutex) -> None:
        self.mutex = mutex
        self.db_path = os.path.join(current_directory, "data.db")
        self.db_version = 1
        try:
            self.conn = sqlite3.connect(self.db_path)
        except Exception:
            logging.exception("连接数据库失败")
            raise
        else:
            self.cfg = {
                "log_level": "INFO",
                "lyrics_file_name_format": "%<artist> - %<title> (%<id>)",
                "default_save_path": os.path.join(current_directory, "lyrics"),
                "lyrics_order": ["罗马音", "原文", "译文"],
                "skip_inst_lyrics": True,
                "get_normal_lyrics": True,
            }
            self.init_db()
            self.read_config()

    def save_version(self, version: int) -> None:
        c = self.conn.cursor()  # 清空表格,确保只存储一个版本信息
        c.execute("DELETE FROM version")
        c.execute("INSERT INTO version (version) VALUES (?)", (version,))  # 插入版本信息
        self.conn.commit()  # 提交更改

    def read_version(self) -> int | None:
        c = self.conn.cursor()
        c.execute("SELECT version FROM version")  # 选择版本信息
        version = c.fetchone()  # 读取结果
        # 如果有版本信息则返回版本号,否则返回None
        return version[0] if version else None

    def init_db(self) -> None:
        c = self.conn.cursor()
        c.execute('''CREATE TABLE IF NOT EXISTS version (
                      version INTEGER)''')
        orig_version = self.read_version()
        if orig_version is None:
            self.save_version(self.db_version)
        elif orig_version != self.db_version:
            msg = f"数据库版本错误: 期望版本{self.db_version}, 实际版本{orig_version}"
            raise RuntimeError(msg)
        c.execute("""CREATE TABLE IF NOT EXISTS config(
                      ID INTEGER PRIMARY KEY AUTOINCREMENT,
                       item TEXT NOT NULL,
                      value TEXT)""")

    def read_config(self) -> None:
        self.mutex.lock()
        c = self.conn.cursor()
        c.execute("SELECT * FROM config")
        for setting in c.fetchall():
            if isinstance(self.cfg[setting[1]], str):
                self.cfg[setting[1]] = setting[2]
            elif isinstance(self.cfg[setting[1]], bool):
                if setting[2] == '1':
                    self.cfg[setting[1]] = True
                else:
                    self.cfg[setting[1]] = False
            elif isinstance(self.cfg[setting[1]], int):
                self.cfg[setting[1]] = int(setting[2])
            elif isinstance(self.cfg[setting[1]], list):
                self.cfg[setting[1]] = ast.literal_eval(setting[2])
        self.mutex.unlock()

    def write_config(self, item: str, value: any) -> None:
        self.mutex.lock()
        self.cfg[item] = value
        if value in [True, False]:
            value = 1 if value else 0
        c = self.conn.cursor()
        c.execute("SELECT * FROM config WHERE item=?", (item,))
        if c.fetchone() is None:
            c.execute("INSERT INTO config(item, value) VALUES (?, ?)", (item, str(value)))
        else:
            c.execute("UPDATE config SET value=? WHERE item=?", (str(value), item))
        self.conn.commit()
        self.mutex.unlock()
