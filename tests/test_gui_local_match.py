# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# ruff: noqa: S101
import os
import shutil
from itertools import product

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFileDialog
from pytestqt.qtbot import QtBot

from LDDC.utils.enum import LocalMatchFileNameMode, LocalMatchSave2TagMode, LocalMatchSaveMode

from .helper import close_msg_boxs, create_audio_file, get_tmp_dir, grab, screenshot_path, select_file, test_artifacts_path, verify_audio_lyrics, verify_lyrics

SONGS_INFO = [
    {
        "title": "Little Busters!",
        "artist": "Rita",
        "album": "リトルバスターズ！ Original SoundTrack Disc1",
        "duration": 287,
        "track": "01",
        "path": ["key", "Little Busters!"],
    },
    {
        "title": "Saya's Song",
        "artist": "Lia",
        "album": "Little Busters! Ecstasy Tracks",
        "date": "2008-08-15",
        "duration": 303,
        "track": "14",
        "path": ["key", "Little Busters!"],
    },
    {
        "title": "Little Busters! -Ecstacy Ver.-",
        "artist": "Rita",
        "album": "Little Busters! Ecstasy Tracks",
        "date": "2008-08-15",
        "duration": 286,
        "track": "15",
        "path": ["key", "Little Busters!"],
    },
    {
        "title": "時を刻む唄",
        "artist": "Lia",
        "album": "時を刻む唄 / TORCH",
        "date": "2008-11-14",
        "duration": 291,
        "track": "01",
        "path": ["key", "clannad"],
    },
    {
        "title": "My Soul, Your Beats!",
        "artist": "Lia",
        "album": "My Soul, Your Beats!/Brave Song",
        "date": "2010-05-26",
        "duration": 275,
        "track": "01",
        "path": ["key", "angel beat"],
    },
    {
        "title": "Brave Song",
        "artist": "多田葵",
        "album": "My Soul, Your Beats!/Brave Song",
        "date": "2010-05-26",
        "duration": 325,
        "track": "02",
        "path": ["key", "angel beat"],
    },
    {
        "title": "Philosophyz",
        "artist": "水谷瑠奈 (NanosizeMir)",
        "album": "Rewrite Original SoundTrack",
        "date": "2011-08-12",
        "duration": 291,
        "track": "01",
        "path": ["key", "rewrite"],
    },
    {
        "title": "星の舟",
        "artist": "Lia",
        "album": "アニメ「planetarian ～星の人～ 」メインテーマ「星の舟」 CW「Gentle Jena」",
        "duration": 364,
        "path": ["key", "planetarian"],
    },
    {
        "title": "アルカテイル",
        "artist": "鈴木このみ",
        "album": "PCゲーム『Summer Pockets』オープニングテーマ「アルカテイル」",
        "duration": 289,
        "date": "2018.03.28",
        "path": ["key", "summer pockets"],
    },
    {
        "title": "アスタロア",
        "artist": "鈴木このみ",
        "album": "アスタロア/青き此方/夏の砂時計",
        "date": "2020",
        "duration": 278,
        "track": "01",
        "path": ["key", "summer pockets"],
    },
]


def get_song_dir() -> str:
    song_dir = get_tmp_dir()
    for song_ in SONGS_INFO:
        song = song_.copy()
        duration, path = song["duration"], song["path"]
        del song["duration"], song["path"]
        create_audio_file(
            os.path.join(song_dir, *path, f"{song["artist"]} - {song["title"]}.flac"),
            "flac",
            duration,
            song,
        )
    return song_dir


def test_gui_local_match(qtbot: QtBot, monkeypatch: pytest.MonkeyPatch) -> None:
    from LDDC.view.main_window import main_window

    main_window.show()
    main_window.set_current_widget(1)
    qtbot.wait(300)  # 等待窗口加载完成

    monkeypatch.setattr(QFileDialog, "open", lambda *args, **kwargs: None)  # noqa: ARG005
    orig_song_dir = get_song_dir()
    for file_name_mode_index, save2tagmode_index, save_mode_index in product(
        range(main_window.local_match_widget.filename_mode_comboBox.count()),
        range(main_window.local_match_widget.save2tag_mode_comboBox.count()),
        range(main_window.local_match_widget.save_mode_comboBox.count()),
    ):
        main_window.local_match_widget.songs_table.setRowCount(0)

        file_name_mode = LocalMatchFileNameMode(file_name_mode_index)
        save2tagmode = LocalMatchSave2TagMode(save2tagmode_index)
        save_mode = LocalMatchSaveMode(save_mode_index)

        song_dir = os.path.join(test_artifacts_path, "audio", "local_match", f"{file_name_mode.name}_{save2tagmode.name}_{save_mode.name}")
        shutil.copytree(orig_song_dir, song_dir)
        main_window.local_match_widget.select_dirs_button.click()
        select_file(main_window.local_match_widget, song_dir)

        save_path = os.path.join(test_artifacts_path, "lyrics", "local_match", f"{file_name_mode.name}_{save2tagmode.name}_{save_mode.name}")
        main_window.local_match_widget.save_path_button.click()
        select_file(main_window.local_match_widget, save_path)

        main_window.local_match_widget.filename_mode_comboBox.setCurrentIndex(file_name_mode_index)
        main_window.local_match_widget.save2tag_mode_comboBox.setCurrentIndex(save2tagmode_index)
        main_window.local_match_widget.save_mode_comboBox.setCurrentIndex(save_mode_index)

        def check_finished() -> bool:
            return not main_window.local_match_widget.workers and not main_window.local_match_widget.status_label.text()

        qtbot.waitUntil(check_finished, timeout=10000)
        assert main_window.local_match_widget.songs_table.rowCount() == len(SONGS_INFO)
        qtbot.wait(20)
        grab(main_window, os.path.join(screenshot_path, f"local_match_prepare_{file_name_mode.name}_{save2tagmode.name}_{save_mode.name}.png"))
        main_window.local_match_widget.start_cancel()
        qtbot.waitUntil(check_finished, timeout=100000)
        close_msg_boxs(main_window.local_match_widget)
        qtbot.wait(150)
        grab(main_window, os.path.join(screenshot_path, f"local_match_finish_{file_name_mode.name}_{save2tagmode.name}_{save_mode.name}.png"))

        for row in range(main_window.local_match_widget.songs_table.rowCount()):
            status_item = main_window.local_match_widget.songs_table.item(row, 6)
            assert status_item
            assert status_item.data(Qt.ItemDataRole.UserRole)["status"] == "成功"
            if save2tagmode != LocalMatchSave2TagMode.ONLY_TAG:
                with open(status_item.data(Qt.ItemDataRole.UserRole)["save_path"], encoding="utf-8") as f:
                    verify_lyrics(f.read())
        if save2tagmode != LocalMatchSave2TagMode.ONLY_FILE:
            for root, _dirs, files in os.walk(song_dir):
                for file in files:
                    if file.endswith(".flac"):
                        verify_audio_lyrics(os.path.join(root, file))
