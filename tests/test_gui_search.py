# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# ruff: noqa: S101
import os
import shutil
from itertools import combinations

import pytest
from PySide6.QtCore import QPoint, Qt
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QFileDialog
from pytestqt.qtbot import QtBot

from LDDC.res import resource_rc
from LDDC.utils.enum import LyricsFormat, SearchType, Source

from .helper import close_msg_boxs, create_audio_file, grab, select_file, verify_audio_lyrics, verify_lyrics

resource_rc.qInitResources()
test_artifacts_path = os.path.join(os.path.dirname(__file__), "artifacts")
screenshot_path = os.path.join(test_artifacts_path, "screenshots")
if os.path.exists(test_artifacts_path):
    shutil.rmtree(test_artifacts_path)
os.makedirs(test_artifacts_path)
os.makedirs(screenshot_path)


def search(qtbot: QtBot, search_type: SearchType, keyword: str) -> None:
    from LDDC.view.main_window import main_window
    main_window.search_widget.search_keyword_lineEdit.setText(keyword)
    main_window.search_widget.search_type_comboBox.setCurrentIndex(search_type.value)

    for i in range(main_window.search_widget.source_comboBox.count() - 1, -1, -1):
        main_window.search_widget.source_comboBox.setCurrentIndex(i)
        main_window.search_widget.search_pushButton.click()

        def check_table() -> bool:
            return main_window.search_widget.results_tableWidget.rowCount() > 0
        qtbot.waitUntil(check_table, timeout=15000)
        qtbot.wait(20)
        grab(main_window, os.path.join(screenshot_path, f"search_{search_type.name.lower()}_{Source(i).name.lower()}.png"))

        # preview
        # 双击第一行
        for _ in range(2):
            QTest.mouseDClick(main_window.search_widget.results_tableWidget.viewport(),
                              Qt.MouseButton.LeftButton,
                              pos=QPoint(int(main_window.search_widget.results_tableWidget.width() * 0.5),
                                         int(main_window.search_widget.results_tableWidget.horizontalHeader().height())))

        orig_lyrics = main_window.search_widget.preview_lyric_result

        def check_preview_lyric() -> bool:
            return main_window.search_widget.preview_lyric_result != orig_lyrics and len(main_window.search_widget.preview_plainTextEdit.toPlainText()) > 15  # noqa: B023

        def check_album_table() -> bool:
            return main_window.search_widget.results_tableWidget.property("result_type")[0] == "album"

        def check_song_list_table() -> bool:
            return main_window.search_widget.results_tableWidget.property("result_type")[0] == "songlist"

        match search_type:
            case SearchType.SONG:
                qtbot.waitUntil(check_preview_lyric, timeout=15000)
                grab(main_window, os.path.join(screenshot_path, "preview_lyrics.png"))
                verify_lyrics(main_window.search_widget.preview_plainTextEdit.toPlainText())
            case SearchType.ALBUM:
                qtbot.waitUntil(check_album_table, timeout=15000)
                grab(main_window, os.path.join(screenshot_path, "show_album_song.png"))
                assert main_window.search_widget.results_tableWidget.rowCount() > 0
            case SearchType.SONGLIST:
                qtbot.waitUntil(check_song_list_table, timeout=15000)
                grab(main_window, os.path.join(screenshot_path, "show_songlist_song.png"))
    assert main_window.search_widget.results_tableWidget.rowCount() > 0
    qtbot.wait(200)


def test_search_song(qtbot: QtBot) -> None:
    from LDDC.view.main_window import main_window

    main_window.show()
    main_window.set_current_widget(0)
    qtbot.wait(300)  # 等待窗口加载完成
    search(qtbot, SearchType.SONG, "鈴木このみ - アルカテイル")


def test_save_to_dir() -> None:
    from LDDC.view.main_window import main_window

    assert main_window.search_widget.preview_plainTextEdit.toPlainText() != ""
    orig_path = main_window.search_widget.save_path_lineEdit.text()
    main_window.search_widget.save_path_lineEdit.setText(os.path.join(test_artifacts_path, "lyrics", "search song"))
    main_window.search_widget.save_preview_lyric_pushButton.click()
    close_msg_boxs(main_window.search_widget)
    main_window.search_widget.save_path_lineEdit.setText(orig_path)

    assert os.listdir(os.path.join(test_artifacts_path, "lyrics", "search song")) != []


def test_save_to_tag(monkeypatch: pytest.MonkeyPatch) -> None:
    from LDDC.view.main_window import main_window

    monkeypatch.setattr(QFileDialog, "open", lambda *args, **kwargs: None)  # noqa: ARG005
    assert main_window.search_widget.preview_plainTextEdit.toPlainText() != ""
    for audio_format in ["mp3", 'ogg', 'tta', 'wav', 'flac']:
        path = os.path.join(test_artifacts_path, "audio", "search song", f"test.{audio_format}")
        create_audio_file(path, audio_format, 1, {"title": "アルカテイル", "artist": "鈴木このみ"})
        main_window.search_widget.save_to_tag_pushButton.click()
        select_file(main_window.search_widget, path)
        close_msg_boxs(main_window.search_widget)
        verify_audio_lyrics(path)


def test_lyrics_langs(qtbot: QtBot) -> None:
    from LDDC.view.main_window import main_window

    def change_langs(langs: list[str]) -> None:
        if set(main_window.search_widget.get_lyric_langs()) != set(langs):
            orig_text = main_window.search_widget.preview_plainTextEdit.toPlainText()

            if "orig" in langs:
                main_window.search_widget.original_checkBox.setChecked(True)
            else:
                main_window.search_widget.original_checkBox.setChecked(False)

            if "ts" in langs:
                main_window.search_widget.translate_checkBox.setChecked(True)
            else:
                main_window.search_widget.translate_checkBox.setChecked(False)

            if "roma" in langs:
                main_window.search_widget.romanized_checkBox.setChecked(True)
            else:
                main_window.search_widget.romanized_checkBox.setChecked(False)

            def check_langs_changed() -> bool:
                return main_window.search_widget.preview_plainTextEdit.toPlainText() != orig_text

            qtbot.waitUntil(check_langs_changed, timeout=15000)
            grab(main_window, os.path.join(screenshot_path, f"search_{'_'.join(langs)}.png"))

    for r in range(1, 4):
        for langs in combinations(["orig", "ts", "roma"], r):
            change_langs(list(langs))
            main_window.search_widget.search_pushButton.click()

    change_langs(["orig", "ts"])


def change_preview_format(qtbot: QtBot, lyrics_format: LyricsFormat) -> str:
    from LDDC.view.main_window import main_window

    assert main_window.search_widget.preview_lyric_result is not None

    if main_window.search_widget.lyricsformat_comboBox.currentIndex() != lyrics_format.value:
        orig_text = main_window.search_widget.preview_plainTextEdit.toPlainText()
        main_window.search_widget.lyricsformat_comboBox.setCurrentIndex(lyrics_format.value)

        def check_preview_result() -> bool:
            return bool(len(main_window.search_widget.preview_plainTextEdit.toPlainText()) > 20 and
                        main_window.search_widget.preview_plainTextEdit.toPlainText() != orig_text)

        qtbot.waitUntil(check_preview_result, timeout=15000)
        qtbot.wait(20)
    grab(main_window, os.path.join(screenshot_path, f"preview_{lyrics_format.name.lower()}.png"))
    return main_window.search_widget.preview_plainTextEdit.toPlainText()


def test_preview_linebyline_lrc(qtbot: QtBot) -> None:
    verify_lyrics(change_preview_format(qtbot, LyricsFormat.LINEBYLINELRC))


def test_preview_enhanced_lrc(qtbot: QtBot) -> None:
    verify_lyrics(change_preview_format(qtbot, LyricsFormat.ENHANCEDLRC))


def test_preview_srt(qtbot: QtBot) -> None:
    assert change_preview_format(qtbot, LyricsFormat.SRT) != ""


def test_preview_ass(qtbot: QtBot) -> None:
    assert change_preview_format(qtbot, LyricsFormat.ASS) != ""


def test_preview_verbatimlrc(qtbot: QtBot) -> None:
    verify_lyrics(change_preview_format(qtbot, LyricsFormat.VERBATIMLRC))


def test_search_song_list(qtbot: QtBot) -> None:
    search(qtbot, SearchType.SONGLIST, "key社")


def test_search_album(qtbot: QtBot) -> None:
    search(qtbot, SearchType.ALBUM, "アスタロア/青き此方/夏の砂時計")


def test_save_album_lyrics(qtbot: QtBot) -> None:
    from LDDC.view.main_window import main_window

    assert main_window.search_widget.results_tableWidget.rowCount() > 0
    assert main_window.search_widget.results_tableWidget.property("result_type")[0] == "album"

    # 保存歌词
    orig_path = main_window.search_widget.save_path_lineEdit.text()
    main_window.search_widget.save_path_lineEdit.setText(os.path.join(test_artifacts_path, "lyrics", "search album"))
    main_window.search_widget.save_list_lyrics_pushButton.click()

    def check_progress() -> bool:
        return main_window.search_widget.get_list_lyrics_box.progressBar.value() == main_window.search_widget.get_list_lyrics_box.progressBar.maximum()
    qtbot.waitUntil(check_progress, timeout=50000)
    close_msg_boxs(main_window.search_widget)

    grab(main_window, os.path.join(screenshot_path, "save_album_lyrics.png"))

    main_window.search_widget.get_list_lyrics_box.pushButton.click()
    main_window.search_widget.save_path_lineEdit.setText(orig_path)

    assert os.listdir(os.path.join(test_artifacts_path, "lyrics", "search album")) != []
