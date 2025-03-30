# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

"""数据管理模块

这个模块提供了:
- 歌词关联数据库管理
"""

import json
import sqlite3
from pathlib import Path
from threading import Lock

from PySide6.QtCore import QObject, Signal

from LDDC.common.models import SongInfo, Source
from LDDC.common.paths import data_dir


class LocalSongLyricsDB(QObject):
    """歌词关联数据库管理类

    1. 使用sqlite3数据库管理本地歌曲歌词
    2. 使用Lock进行保证线程安全
    """

    changed = Signal()  # 用于更新歌词关联管理器UI

    def __init__(self) -> None:
        super().__init__()
        self.lock = Lock()
        self.path = data_dir / "local_song_lyrics.db"
        self.conn = sqlite3.connect(self.path, check_same_thread=False)
        self.init_db()

    def init_db(self) -> None:
        with self.lock:
            # 创建表
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
            # 创建索引
            cur.execute("""
                CREATE INDEX IF NOT EXISTS idx_title_artist_album_duration_song_path_track_number
                ON songs (title, artist, album, duration, song_path, track_number)
            """)
            self.conn.commit()

    def set_song(
        self,
        info: SongInfo,
        lyrics_path: Path | None,
        config: dict,
    ) -> None:
        """设置歌曲歌词关联,如果存在则更新,否则插入"""
        self.set_item(info.title, info.str_artist, info.album, info.duration, info.url, info.id, str(lyrics_path) if lyrics_path else None, config)

    def set_item(
        self,
        title: str | None,
        artist: str | None,
        album: str | None,
        duration: int | None,
        song_path: str | None,
        track_number: str | None,
        lyrics_path: str | None,
        config: dict,
    ) -> None:
        """设置歌曲歌词关联,如果存在则更新,否则插入"""
        with self.lock:
            # sqlite 不认为两个 NULL 是相等的
            self.conn.execute(
                """
                INSERT OR REPLACE INTO songs (title, artist, album, duration, song_path, track_number, lyrics_path, config)
                VALUES (:title, :artist, :album, :duration, :song_path, :track_number, :lyrics_path, :config)
            """,
                {
                    "title": title or "",
                    "artist": artist or "",
                    "album": album or "",
                    "duration": duration or -1,
                    "song_path": song_path or "",
                    "track_number": track_number or "",
                    "lyrics_path": lyrics_path or "",
                    "config": json.dumps(config, ensure_ascii=False),
                },
            )
            self.conn.commit()
        self.changed.emit()

    def set_songs(self, songs: list[tuple[SongInfo, Path | None, dict]]) -> None:
        self.set_items(
            [
                (info.title, info.str_artist, info.album, info.duration, info.url, info.id, str(lyrics_path) if lyrics_path else None, config)
                for info, lyrics_path, config in songs
            ],
        )

    def set_items(self, items: list[tuple[str | None, str | None, str | None, int | None, str | None, str | None, str | None, dict]]) -> None:
        with self.lock:
            self.conn.executemany(
                """
                INSERT OR REPLACE INTO songs (title, artist, album, duration, song_path, track_number, lyrics_path, config)
                VALUES (:title, :artist, :album, :duration, :song_path, :track_number, :lyrics_path, :config)
                """,
                [
                    {
                        "title": title or "",
                        "artist": artist or "",
                        "album": album or "",
                        "duration": duration or -1,
                        "song_path": song_path or "",
                        "track_number": track_number or "",
                        "lyrics_path": lyrics_path or "",
                        "config": json.dumps(config, ensure_ascii=False),
                    }
                    for title, artist, album, duration, song_path, track_number, lyrics_path, config in items
                ],
            )
            self.conn.commit()
        self.changed.emit()

    def query(self, info: SongInfo) -> tuple[Path, dict] | None:
        """查询歌曲歌词关联"""
        with self.lock:
            cur = self.conn.execute(
                """
                    SELECT lyrics_path, config FROM songs
                    WHERE title = :title
                      AND artist = :artist
                      AND album = :album
                      AND duration = :duration
                      AND song_path = :song_path
                      AND track_number = :track_number
                """,
                {
                    "title": info.title or "",
                    "artist": info.str_artist,
                    "album": info.album or "",
                    "duration": info.duration or -1,
                    "song_path": info.url if info.path else "",
                    "track_number": info.id or "",
                },
            )
            result = cur.fetchone()
        if result:
            return Path(result[0]) if result[0] else result[0], json.loads(result[1])
        return None

    def del_item(self, id_: int) -> None:
        """删除歌曲歌词关联"""
        with self.lock:
            self.conn.execute("""DELETE FROM songs WHERE id = ?""", (id_,))
        self.changed.emit()

    def del_items(self, ids: list[int]) -> None:
        """删除歌曲歌词关联"""
        with self.lock:
            self.conn.executemany("""DELETE FROM songs WHERE id = ?""", [(i,) for i in ids])
        self.changed.emit()

    def to_songinfo(self, info: dict) -> SongInfo:
        info = {
            "source": Source.Local,
            "title": info["title"] if info["title"] else None,
            "artist": info["artist"] if info["artist"] else None,
            "album": info["album"] if info["album"] else None,
            "duration": info["duration"] if info["duration"] > 0 else None,
            "path": info["song_path"] if info["song_path"] else None,
            "id": info["track_number"] if info["track_number"] else None,
        }
        return SongInfo.from_dict(info)

    def get_item(self, id_: int) -> dict | None:
        """根据id获取歌曲歌词关联信息(返回字典)"""
        with self.lock:
            cur = self.conn.execute("""SELECT title, artist, album, duration, song_path, track_number, lyrics_path, config FROM songs WHERE id = ?""", (id_,))
            query_result = cur.fetchone()
        if query_result:
            return {
                "title": query_result[0] if query_result[0] != "" else None,
                "artist": query_result[1] if query_result[1] != "" else None,
                "album": query_result[2] if query_result[2] != "" else None,
                "duration": query_result[3] if query_result[3] != -1 else None,
                "song_path": query_result[4] if query_result[4] != "" else None,
                "track_number": query_result[5] if query_result[5] != "" else None,
                "lyrics_path": query_result[6] if query_result[6] != "" else None,
                "config": json.loads(query_result[7]),
            }
        return None

    def get_songinfo(self, id_: int) -> tuple[SongInfo, Path | None, dict] | None:
        """根据id获取歌曲歌词关联信息(返回SongInfo)"""
        query_result = self.get_item(id_)
        if query_result:
            return (
                self.to_songinfo(query_result),
                Path(query_result["lyrics_path"]) if query_result["lyrics_path"] != "" else None,
                dict(query_result["config"]),
            )
        return None

    def del_all(self) -> None:
        """清空歌曲歌词关联数据库"""
        with self.lock:
            self.conn.execute("""DELETE FROM songs""")
            self.conn.commit()
        self.changed.emit()

    def get_all(self) -> list:
        """获取所有歌曲歌词关联信息(返回数据库查询结果)"""
        with self.lock:
            cur = self.conn.execute("""SELECT id, title, artist, album, duration, song_path, track_number, lyrics_path, config FROM songs""")
            return cur.fetchall()

    def get_all_songinfo(self) -> list[tuple[int, SongInfo, Path | None, dict]]:
        """获取所有歌曲歌词关联信息(返回SongInfo)"""
        data = self.get_all()
        return [
            (
                song[0],
                self.to_songinfo(
                    {
                        "title": song[1] if song[1] != "" else None,
                        "artist": song[2] if song[2] != "" else None,
                        "album": song[3] if song[3] != "" else None,
                        "duration": song[4] if song[4] != -1 else None,
                        "song_path": song[5] if song[5] != "" else None,
                        "track_number": song[6] if song[6] != "" else None,
                    },
                ),
                Path(song[7].removeprefix("file://")) if song[7] else None,
                dict(json.loads(song[8])),
            )
            for song in data
        ]

    def close(self) -> None:
        with self.lock:
            self.conn.close()


local_song_lyrics = LocalSongLyricsDB()
