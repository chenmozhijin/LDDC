# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import shutil
from itertools import product
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFileDialog
from pytestqt.qtbot import QtBot

from LDDC.common.models import FileNameMode
from LDDC.gui.workers.local_match import LocalMatchingStatusType, LocalMatchSave2TagMode

from .helper import close_msg_boxs, create_audio_file, get_tmp_dir, grab, screenshot_path, select_file, test_artifacts_path, verify_audio_lyrics, verify_lyrics

if TYPE_CHECKING:
    from LDDC.gui.view.main_window import MainWindow
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


def get_song_dir() -> Path:
    song_dir = get_tmp_dir()
    for song_ in SONGS_INFO:
        song = song_.copy()
        duration, path = song["duration"], song["path"]
        del song["duration"], song["path"]
        create_audio_file(
            Path(song_dir).joinpath(*path) / f"{song['artist']} - {song['title']}.flac",
            "flac",
            duration,
            song,
        )
    return song_dir


def test_gui_local_match(qtbot: QtBot, monkeypatch: pytest.MonkeyPatch, main_window: "MainWindow") -> None:
    main_window.show()
    main_window.set_current_widget(1)
    qtbot.wait(300)  # 等待窗口加载完成

    monkeypatch.setattr(QFileDialog, "open", lambda *args, **kwargs: None)  # noqa: ARG005
    main_window.local_match_widget.source_listWidget.set_soures(["QM", "KG", "NE", "LRCLIB"])
    orig_song_dir = get_song_dir()
    for file_name_mode_index, save2tagmode_index, save_mode_index in product(
        range(main_window.local_match_widget.filename_mode_comboBox.count()),
        range(main_window.local_match_widget.save2tag_mode_comboBox.count()),
        range(main_window.local_match_widget.save_mode_comboBox.count()),
    ):
        main_window.local_match_widget.songs_table.setRowCount(0)

        file_name_mode = FileNameMode(file_name_mode_index)
        save2tag_mode = LocalMatchSave2TagMode(save2tagmode_index)
        save_mode = FileNameMode(save_mode_index)

        song_dir = test_artifacts_path / "audio" / "local_match" / f"{file_name_mode.name}_{save2tag_mode.name}_{save_mode.name}"
        shutil.copytree(orig_song_dir, song_dir)
        main_window.local_match_widget.select_dirs_button.click()
        select_file(main_window.local_match_widget, song_dir)

        save_path = test_artifacts_path / "lyrics" / "local_match" / f"{file_name_mode.name}_{save2tag_mode.name}_{save_mode.name}"
        main_window.local_match_widget.save_path_button.click()
        select_file(main_window.local_match_widget, save_path)

        main_window.local_match_widget.filename_mode_comboBox.setCurrentIndex(file_name_mode_index)
        main_window.local_match_widget.save2tag_mode_comboBox.setCurrentIndex(save2tagmode_index)
        main_window.local_match_widget.save_mode_comboBox.setCurrentIndex(save_mode_index)
        main_window.local_match_widget.skip_existing_lyrics_checkbox.setChecked(False)

        def check_finished() -> bool:
            return (
                main_window.local_match_widget.taskmanager.is_finished()
                and not main_window.local_match_widget.status_label.text()
                and bool(main_window.local_match_widget.songs_table.rowCount())
            )

        qtbot.waitUntil(check_finished, timeout=10000)
        assert main_window.local_match_widget.songs_table.rowCount() == len(SONGS_INFO)
        qtbot.wait(20)
        grab(main_window, screenshot_path / f"local_match_prepare_{file_name_mode.name}_{save2tag_mode.name}_{save_mode.name}")
        main_window.local_match_widget.start_cancel_pushButton.click()
        qtbot.waitUntil(check_finished, timeout=100000)
        close_msg_boxs(main_window.local_match_widget)
        qtbot.wait(150)
        grab(main_window, screenshot_path / f"local_match_finish_{file_name_mode.name}_{save2tag_mode.name}_{save_mode.name}")

        for row in range(main_window.local_match_widget.songs_table.rowCount()):
            info_item = main_window.local_match_widget.songs_table.item(row, 0)
            assert info_item
            assert info_item.data(Qt.ItemDataRole.UserRole + 2).status == LocalMatchingStatusType.SUCCESS
            if save2tag_mode != LocalMatchSave2TagMode.ONLY_TAG:
                with info_item.data(Qt.ItemDataRole.UserRole + 2).path.open(encoding="utf-8") as f:
                    verify_lyrics(f.read())
        if save2tag_mode != LocalMatchSave2TagMode.ONLY_FILE:
            for root, _dirs, files in song_dir.walk():
                for file in files:
                    if file.endswith(".flac"):
                        verify_audio_lyrics(root / file)

        if save2tag_mode == LocalMatchSave2TagMode.ONLY_TAG or file_name_mode != FileNameMode.FORMAT_BY_LYRICS:
            # 检查能否跳过已存在歌词
            main_window.local_match_widget.skip_existing_lyrics_checkbox.setChecked(True)
            main_window.local_match_widget.start_cancel_pushButton.click()
            qtbot.waitUntil(check_finished, timeout=100000)
            close_msg_boxs(main_window.local_match_widget)
            qtbot.wait(150)
            grab(main_window.local_match_widget, screenshot_path / f"local_match_skip_existing_{file_name_mode.name}_{save2tag_mode.name}_{save_mode.name}")
            for row in range(main_window.local_match_widget.songs_table.rowCount()):
                info_item = main_window.local_match_widget.songs_table.item(row, 0)
                assert info_item
                assert info_item.data(Qt.ItemDataRole.UserRole + 2).status == LocalMatchingStatusType.SKIP_EXISTING
