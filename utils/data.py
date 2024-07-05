# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import os
import sqlite3
from typing import Any

from PySide6.QtCore import QMutex, QMutexLocker

from .paths import config_dir, data_dir, default_save_lyrics_dir


class Config(dict):
    def __init__(self) -> None:
        self.mutex = None
        self.config_path = os.path.join(config_dir, "config.json")

        cfg = {
            "log_level": "INFO",
            "lyrics_file_name_format": "%<artist> - %<title> (%<id>)",
            "default_save_path": default_save_lyrics_dir,
            "lyrics_order": ["罗马音", "原文", "译文"],
            "skip_inst_lyrics": True,
            "auto_select": True,
            "language": "auto",
            "lrc_ms_digit_count": 3,
        }

        for key, value in cfg.items():
            self[key] = value
        self.read_config()
        self.mutex = QMutex()

    def write_config(self) -> None:
        with open(self.config_path, "w", encoding="utf-8") as f:
            json.dump(self, f, ensure_ascii=False, indent=4)

    def read_config(self) -> None:
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, encoding="utf-8") as f:
                    cfg = json.load(f)
                if isinstance(cfg, dict):
                    for key, value in cfg.items():
                        if key in self and type(value) is type(self[key]):
                            self[key] = value
            except Exception:
                self.write_config()

    def setitem(self, key: Any, value: Any) -> None:
        self[key] = value

    def __getitem__(self, key: Any) -> Any:
        if self.mutex is None:
            return super().__getitem__(key)
        self.mutex.lock()
        value = super().__getitem__(key)
        self.mutex.unlock()
        return value

    def __setitem__(self, key: Any, value: Any) -> None:
        if self.mutex is None:
            return super().__setitem__(key, value)
        self.mutex.lock()
        super().__setitem__(key, value)
        self.write_config()
        self.mutex.unlock()
        return None

    def __delitem__(self, key: Any) -> None:
        if self.mutex is None:
            return super().__delitem__(key)
        self.mutex.lock()
        super().__delitem__(key)
        self.write_config()
        self.mutex.unlock()
        return None


cfg = Config()
