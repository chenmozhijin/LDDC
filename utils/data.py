# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import json
import os
import sqlite3
from typing import Any

from PySide6.QtCore import QMutex, QMutexLocker, QObject, Signal

from .paths import config_dir, data_dir, default_save_lyrics_dir


class ConfigSigal(QObject):
    lyrics_changed = Signal(tuple)
    desktop_lyrics_changed = Signal(tuple)


class Config(dict):
    def __init__(self) -> None:
        self.mutex = None
        self.config_path = os.path.join(config_dir, "config.json")
        self.__singal = ConfigSigal()
        self.lyrics_changed = self.__singal.lyrics_changed
        self.desktop_lyrics_changed = self.__singal.desktop_lyrics_changed

        self.default_cfg = {
            "log_level": "INFO",
            "lyrics_file_name_fmt": "%<artist> - %<title> (%<id>)",
            "default_save_path": default_save_lyrics_dir,
            "langs_order": ["roma", "orig", "ts"],
            "skip_inst_lyrics": True,
            "auto_select": True,
            "language": "auto",
            "lrc_ms_digit_count": 3,
            "add_end_timestamp_line": False,
            "last_ref_line_time_sty": 0,  # 0: 与当前原文起始时间相同 1: 与下一行原文起始时间接近
            "auto_check_update": True,

            "desktop_lyrics_played_colors": [(0, 255, 255), (0, 128, 255)],
            "desktop_lyrics_unplayed_colors": [(255, 0, 0), (255, 128, 128)],
            "desktop_lyrics_font_size": 18.0,
            "desktop_lyrics_font_family": "",
            "desktop_lyrics_rect": (),  # 默认为空自动移动到屏幕中央
            "desktop_lyrics_default_langs": ["orig", "ts"],
            "desktop_lyrics_langs_order": ["roma", "orig", "ts"],
            "desktop_lyrics_sources": ["QM", "KG", "NE"],
            "desktop_lyrics_refresh_rate": -1,  # -1为自动

        }

        self.reset()
        self.read_config()
        self.mutex = QMutex()

    def reset(self) -> None:
        for key, value in self.default_cfg.items():
            self[key] = value

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
                        elif isinstance(value, list) and isinstance(self[key], tuple):
                            self[key] = tuple(value)
            except Exception:
                self.write_config()

    def setitem(self, key: Any, value: Any) -> None:
        self[key] = value

    def __getitem__(self, key: Any) -> Any:
        if self.mutex is None:
            return super().__getitem__(key)
        with QMutexLocker(self.mutex):
            return super().__getitem__(key)

    def __setitem__(self, key: Any, value: Any) -> None:
        if self.mutex is None:
            super().__setitem__(key, value)
            return
        with QMutexLocker(self.mutex):
            super().__setitem__(key, value)
            self.write_config()

        if key in ("langs_order", "lrc_ms_digit_count", "add_end_timestamp_line", "last_ref_line_time_sty"):
            self.lyrics_changed.emit((key, value))
        elif key in ("desktop_lyrics_font_family", "desktop_lyrics_played_colors", "desktop_lyrics_unplayed_colors",
                     "desktop_lyrics_default_langs", "desktop_lyrics_refresh_rate", "desktop_lyrics_langs_order"):
            self.desktop_lyrics_changed.emit((key, value))

    def __delitem__(self, key: Any) -> None:
        if self.mutex is None:
            super().__delitem__(key)
            return
        with QMutexLocker(self.mutex):
            super().__delitem__(key)
            self.write_config()
        return


cfg = Config()


class LocalSongLyricsDB(QObject):
    changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        self.mutex = QMutex()
        self.path = os.path.join(data_dir, "local_song_lyrics.db")
        self.conn = sqlite3.connect(self.path, check_same_thread=False)
        self.init_db()

    def init_db(self) -> None:
        with QMutexLocker(self.mutex):
            cur = self.conn.execute("""
                CREATE TABLE IF NOT EXISTS songs (
                    id INTEGER PRIMARY KEY,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    album TEXT NOT NULL,
                    duration INTEGER NOT NULL,
                    song_path TEXT NOT NULL,
                    track_number TEXT NOT NULL,
                    lyrics_path TEXT,
                    config TEXT,
                    UNIQUE (title, artist, album, duration, song_path, track_number)
                )
            """)
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_title_artist_album_duration_song_path_track_number
                ON songs (title, artist, album, duration, song_path, track_number)
            """)
            self.conn.commit()

    def handle_null(self, **kargs: str | int | None) -> tuple[int | str, ...]:
        return tuple(v if v is not None else (-1 if k == "duration" else '') for k, v in kargs.items())

    def set_song(self,
                 title: str | None,
                 artist: str | None,
                 album: str | None,
                 duration: int | None,
                 song_path: str | None,
                 track_number: str | None,
                 lyrics_path: str | None,
                 config: dict) -> None:
        with QMutexLocker(self.mutex):
            # sqlite 不认为两个 NULL 是相等的
            self.conn.execute("""
                INSERT OR REPLACE INTO songs (title, artist, album, duration, song_path, track_number, lyrics_path, config)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (*self.handle_null(title=title, artist=artist, album=album, duration=duration, song_path=song_path, track_number=track_number),
                  lyrics_path, json.dumps(config, ensure_ascii=False)))
            self.conn.commit()
        self.changed.emit()

    def query(self,
              title: str | None,
              artist: str | None,
              album: str | None,
              duration: int | None,
              song_path: str | None,
              track_number: str | None) -> tuple[str, dict] | None:
        parameters = self.handle_null(title=title, artist=artist, album=album, duration=duration, song_path=song_path, track_number=track_number)
        with QMutexLocker(self.mutex):
            cur = self.conn.execute("""SELECT lyrics_path, config FROM songs
                                       WHERE title = ? AND artist = ? AND album = ? AND duration = ? AND song_path = ? AND track_number = ?""",
                                    parameters)
            result = cur.fetchone()
        if result:
            return result[0], json.loads(result[1])
        return None

    def del_item(self, id_: int) -> None:
        with QMutexLocker(self.mutex):
            self.conn.execute("""DELETE FROM songs WHERE id = ?""", (id_,))

    def get_item(self, id_: int) -> dict[str, int | str | dict | None] | None:
        with QMutexLocker(self.mutex):
            cur = self.conn.execute("""SELECT title, artist, album, duration, song_path, track_number, lyrics_path, config FROM songs WHERE id = ?""", (id_,))
            query_result = cur.fetchone()
        if query_result:
            return {
                "title": query_result[0] if query_result[0] != '' else None,
                "artist": query_result[1] if query_result[1] != '' else None,
                "album": query_result[2] if query_result[2] != '' else None,
                "duration": query_result[3] if query_result[3] != -1 else None,
                "song_path": query_result[4] if query_result[4] != '' else None,
                "track_number": query_result[5] if query_result[5] != '' else None,
                "lyrics_path": query_result[6] if query_result[6] != '' else None,
                "config": json.loads(query_result[7]),
            }
        return None

    def del_all(self) -> None:
        with QMutexLocker(self.mutex):
            self.conn.execute("""DELETE FROM songs""")
            self.conn.commit()
            self.changed.emit()

    def get_all(self) -> list:
        with QMutexLocker(self.mutex):
            cur = self.conn.execute("""SELECT id, title, artist, album, duration, song_path, track_number, lyrics_path, config FROM songs""")
            return cur.fetchall()

    def close(self) -> None:
        with QMutexLocker(self.mutex):
            self.conn.close()


local_song_lyrics = LocalSongLyricsDB()
