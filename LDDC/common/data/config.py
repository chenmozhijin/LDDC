# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

"""数据管理模块

这个模块提供了:
- 配置文件管理
"""

import json
from threading import Lock
from typing import Any

from PySide6.QtCore import QObject, Signal

from LDDC.common.paths import config_dir, default_save_lyrics_dir


class ConfigSigal(QObject):
    lyrics_changed = Signal(tuple)
    desktop_lyrics_changed = Signal(tuple)


class Config(dict):
    """LDDC的配置管理类

    1. 使用Lock保证线程安全
    2. 使用方法类似字典
    3. 使用json格式存储配置文件
    注意: 用于Lock导致这个类并不高效,不应该在需要高性能的地方使用
    """

    def __init__(self) -> None:
        self.lock = None
        self.config_path = config_dir / "config.json"
        self.__singal = ConfigSigal()
        self.lyrics_changed = self.__singal.lyrics_changed  # 在歌词相关配置改变时发出信号
        self.desktop_lyrics_changed = self.__singal.desktop_lyrics_changed  # 在桌面歌词相关配置改变时发出信号

        self.default_cfg = {
            "lyrics_file_name_fmt": "%<artist> - %<title> (%<id>)",
            "default_save_path": str(default_save_lyrics_dir),
            "ID3_version": "v2.3",

            "multi_search_sources": ["QM", "KG", "NE"],

            "langs_order": ["roma", "orig", "ts"],
            "skip_inst_lyrics": True,
            "auto_select": True,
            "add_end_timestamp_line": False,
            "lrc_ms_digit_count": 3,
            "last_ref_line_time_sty": 0,  # 0: 与当前原文起始时间相同 1: 与下一行原文起始时间接近
            "lrc_tag_info_src": 0,  # 0: 从歌词源获取 1: 从歌曲文件获取

            "translate_source": "BING",
            "translate_target_lang": "SIMPLIFIED_CHINESE",
            "openai_base_url": "",
            "openai_api_key": "",
            "openai_model": "",

            "desktop_lyrics_played_colors": [(0, 255, 255), (0, 128, 255)],
            "desktop_lyrics_unplayed_colors": [(255, 0, 0), (255, 128, 128)],
            "desktop_lyrics_default_langs": ["orig", "ts"],
            "desktop_lyrics_langs_order": ["roma", "orig", "ts"],
            "desktop_lyrics_sources": ["QM", "KG", "NE"],
            "desktop_lyrics_font_family": "",
            "desktop_lyrics_refresh_rate": -1,  # -1为自动
            "desktop_lyrics_rect": (),  # 默认为空自动移动到屏幕中央
            "desktop_lyrics_font_size": 30.0,

            "language": "auto",
            "color_scheme": "auto",
            "log_level": "INFO",
            "auto_check_update": True,
        }

        self.reset()
        self.read_config()
        self.lock = Lock()

    def reset(self) -> None:
        for key, value in self.default_cfg.items():
            self[key] = value

    def write_config(self) -> None:
        with self.config_path.open("w", encoding="utf-8") as f:
            json.dump(self, f, ensure_ascii=False, indent=4)

    def read_config(self) -> None:
        if self.config_path.is_file():
            try:
                with self.config_path.open(encoding="utf-8") as f:
                    cfg = json.load(f)
                if isinstance(cfg, dict):
                    for key, value in cfg.items():
                        if key in self and type(value) is type(self[key]):
                            self[key] = value
                        elif isinstance(value, list) and isinstance(self[key], tuple):
                            self[key] = tuple(value)
                        elif isinstance(value, float) and isinstance(self[key], int):
                            self[key] = value
            except Exception:
                self.write_config()

    def setitem(self, key: Any, value: Any) -> None:
        self[key] = value

    def __getitem__(self, key: Any) -> Any:
        if self.lock is None:
            return super().__getitem__(key)
        with self.lock:
            return super().__getitem__(key)

    def __setitem__(self, key: Any, value: Any) -> None:
        if self.lock is None:
            super().__setitem__(key, value)
            return
        with self.lock:
            super().__setitem__(key, value)
            self.write_config()

        if key in ("langs_order", "lrc_ms_digit_count", "add_end_timestamp_line", "last_ref_line_time_sty", "lrc_tag_info_src"):
            self.lyrics_changed.emit((key, value))
        elif key in (
            "desktop_lyrics_font_family",
            "desktop_lyrics_played_colors",
            "desktop_lyrics_unplayed_colors",
            "desktop_lyrics_default_langs",
            "desktop_lyrics_refresh_rate",
            "desktop_lyrics_langs_order",
        ):
            self.desktop_lyrics_changed.emit((key, value))

    def __delitem__(self, key: Any) -> None:
        if self.lock is None:
            super().__delitem__(key)
            return
        with self.lock:
            super().__delitem__(key)
            self.write_config()
        return


cfg = Config()
