# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from itertools import combinations
from typing import TYPE_CHECKING

import pytest
from PySide6.QtCore import QPoint, Qt
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QFileDialog
from pytestqt.qtbot import QtBot

from LDDC.common.models import LyricsFormat, SearchType, SongListInfo, SongListType, Source

from .helper import close_msg_boxs, create_audio_file, grab, screenshot_path, select_file, test_artifacts_path, verify_audio_lyrics, verify_lyrics

if TYPE_CHECKING:
    from LDDC.gui.view.main_window import MainWindow


def search(qtbot: QtBot, search_type: SearchType, keyword: str, main_window: "MainWindow") -> None:
    main_window.search_widget.search_keyword_lineEdit.setText(keyword)

    for i in range(main_window.search_widget.source_comboBox.count() - 1, -1, -1):
        main_window.search_widget.source_comboBox.setCurrentIndex(i)

        if main_window.search_widget.search_type_comboBox.count() > search_type.value:
            main_window.search_widget.search_type_comboBox.setCurrentIndex(search_type.value)
        else:
            continue

        main_window.search_widget.search_pushButton.click()

        def check_table() -> bool:
            return main_window.search_widget.results_tableWidget.rowCount() > 0

        qtbot.waitUntil(check_table, timeout=15000)
        qtbot.wait(20)
        grab(main_window, screenshot_path / f"search_{search_type.name.lower()}_{Source(i).name.lower()}")

        # preview
        # 双击第一行
        for _ in range(2):
            QTest.mouseDClick(
                main_window.search_widget.results_tableWidget.viewport(),
                Qt.MouseButton.LeftButton,
                pos=QPoint(
                    int(main_window.search_widget.results_tableWidget.width() * 0.5),
                    int(main_window.search_widget.results_tableWidget.horizontalHeader().height()),
                ),
            )

        orig_lyrics = main_window.search_widget.lyrics

        def check_preview_lyric() -> bool:
            return main_window.search_widget.lyrics != orig_lyrics and len(main_window.search_widget.preview_plainTextEdit.toPlainText()) > 15  # noqa: B023

        def check_album_table() -> bool:
            path = main_window.search_widget.path
            return bool(path and path[-1] and isinstance(path[-1].info, SongListInfo) and path[-1].info.type == SongListType.ALBUM)

        def check_song_list_table() -> bool:
            path = main_window.search_widget.path
            return bool(path and path[-1] and isinstance(path[-1].info, SongListInfo) and path[-1].info.type == SongListType.SONGLIST)

        match search_type:
            case SearchType.SONG:
                qtbot.waitUntil(check_preview_lyric, timeout=15000)
                grab(main_window, screenshot_path / "preview_lyrics")
                verify_lyrics(main_window.search_widget.preview_plainTextEdit.toPlainText())
            case SearchType.ALBUM:
                qtbot.waitUntil(check_album_table, timeout=15000)
                grab(main_window, screenshot_path / "show_album_song")
                assert main_window.search_widget.results_tableWidget.rowCount() > 0
            case SearchType.SONGLIST:
                qtbot.waitUntil(check_song_list_table, timeout=15000)
                grab(main_window, screenshot_path / "show_songlist_song")
    assert main_window.search_widget.results_tableWidget.rowCount() > 0
    qtbot.wait(200)


def test_search_song(qtbot: QtBot, main_window: "MainWindow") -> None:
    main_window.show()
    main_window.set_current_widget(0)
    qtbot.wait(300)  # 等待窗口加载完成
    search(qtbot, SearchType.SONG, "鈴木このみ - アルカテイル", main_window)


def test_save_to_dir(qtbot: QtBot, main_window: "MainWindow") -> None:
    assert main_window.search_widget.preview_plainTextEdit.toPlainText() != ""
    orig_path = main_window.search_widget.save_path_lineEdit.text()
    main_window.search_widget.save_path_lineEdit.setText(str(test_artifacts_path / "lyrics" / "search song"))
    main_window.search_widget.save_preview_lyric_pushButton.click()
    qtbot.wait(200)
    close_msg_boxs(main_window.search_widget)
    main_window.search_widget.save_path_lineEdit.setText(orig_path)
    qtbot.wait(200)

    assert (test_artifacts_path / "lyrics" / "search song").iterdir()


def test_save_to_tag(monkeypatch: pytest.MonkeyPatch, main_window: "MainWindow") -> None:
    monkeypatch.setattr(QFileDialog, "open", lambda *args, **kwargs: None)  # noqa: ARG005
    assert main_window.search_widget.preview_plainTextEdit.toPlainText() != ""
    for audio_format in ["mp3", "ogg", "tta", "wav", "flac"]:
        path = test_artifacts_path / "audio" / "search song" / f"test.{audio_format}"
        create_audio_file(path, audio_format, 1, {"title": "アルカテイル", "artist": "鈴木このみ"})
        main_window.search_widget.save_to_tag_pushButton.click()
        select_file(main_window.search_widget, path)
        close_msg_boxs(main_window.search_widget)
        verify_audio_lyrics(path)


def test_lyrics_langs(qtbot: QtBot, main_window: "MainWindow") -> None:
    assert main_window.search_widget.lyrics
    support_langs = main_window.search_widget.lyrics.types.keys()

    def change_langs(langs: list[str]) -> None:
        if {lang for lang in main_window.search_widget.langs if lang in support_langs} != {lang for lang in langs if lang in support_langs}:
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
            grab(main_window, screenshot_path / f"search_{'_'.join(langs)}")

    for r in range(1, 4):
        for langs in combinations(["orig", "ts", "roma"], r):
            change_langs(list(langs))
            main_window.search_widget.search_pushButton.click()

    change_langs(["orig", "ts"])


def change_preview_format(qtbot: QtBot, lyrics_format: LyricsFormat, main_window: "MainWindow") -> str:
    assert main_window.search_widget.lyrics is not None

    if main_window.search_widget.lyricsformat_comboBox.currentIndex() != lyrics_format.value:
        orig_text = main_window.search_widget.preview_plainTextEdit.toPlainText()
        main_window.search_widget.lyricsformat_comboBox.setCurrentIndex(lyrics_format.value)

        def check_preview_result() -> bool:
            return bool(
                len(main_window.search_widget.preview_plainTextEdit.toPlainText()) > 20
                and main_window.search_widget.preview_plainTextEdit.toPlainText() != orig_text,
            )

        qtbot.waitUntil(check_preview_result, timeout=15000)
        qtbot.wait(20)
    grab(main_window, screenshot_path / f"preview_{lyrics_format.name.lower()}")
    return main_window.search_widget.preview_plainTextEdit.toPlainText()


def test_preview_linebyline_lrc(qtbot: QtBot, main_window: "MainWindow") -> None:
    verify_lyrics(change_preview_format(qtbot, LyricsFormat.LINEBYLINELRC, main_window))


def test_preview_enhanced_lrc(qtbot: QtBot, main_window: "MainWindow") -> None:
    verify_lyrics(change_preview_format(qtbot, LyricsFormat.ENHANCEDLRC, main_window))


def test_preview_srt(qtbot: QtBot, main_window: "MainWindow") -> None:
    verify_lyrics(change_preview_format(qtbot, LyricsFormat.SRT, main_window))


def test_preview_ass(qtbot: QtBot, main_window: "MainWindow") -> None:
    verify_lyrics(change_preview_format(qtbot, LyricsFormat.ASS, main_window))


def test_preview_verbatimlrc(qtbot: QtBot, main_window: "MainWindow") -> None:
    verify_lyrics(change_preview_format(qtbot, LyricsFormat.VERBATIMLRC, main_window))


def test_translate_lyrics(qtbot: QtBot, main_window: "MainWindow") -> None:
    """测试歌词翻译功能"""
    main_window.show()
    main_window.set_current_widget(0)
    qtbot.wait(300)

    # 点击翻译按钮
    main_window.search_widget.translate_pushButton.click()

    qtbot.waitUntil(lambda: bool(main_window.search_widget.lyrics and "LDDC_ts" in main_window.search_widget.lyrics), timeout=15000)
    assert main_window.search_widget.lyrics
    assert "LDDC_ts" in main_window.search_widget.lyrics


def test_search_song_list(qtbot: QtBot, main_window: "MainWindow") -> None:
    search(qtbot, SearchType.SONGLIST, "key社", main_window)


def test_search_album(qtbot: QtBot, main_window: "MainWindow") -> None:
    search(qtbot, SearchType.ALBUM, "アスタロア/青き此方/夏の砂時計", main_window)


def test_save_album_lyrics(qtbot: QtBot, main_window: "MainWindow") -> None:
    assert main_window.search_widget.results_tableWidget.rowCount() > 0
    path = main_window.search_widget.path
    assert path
    assert path[-1]
    assert isinstance(path[-1].info, SongListInfo)
    assert path[-1].info.type == SongListType.ALBUM

    # 保存歌词
    orig_path = main_window.search_widget.save_path_lineEdit.text()
    main_window.search_widget.save_path_lineEdit.setText(str(test_artifacts_path / "lyrics" / "search album"))
    main_window.search_widget.save_list_lyrics_pushButton.click()
    from LDDC.gui.view.get_list_lyrics import GetListLyrics

    for child in main_window.search_widget.children():
        if isinstance(child, GetListLyrics):
            get_list_lyrics_box = child
            break
    else:
        pytest.fail("GetListLyrics not found")

    def check_progress() -> bool:
        return get_list_lyrics_box.progressBar.value() == get_list_lyrics_box.progressBar.maximum()

    qtbot.waitUntil(check_progress, timeout=50000)
    close_msg_boxs(get_list_lyrics_box)

    qtbot.wait(120)
    grab(main_window, screenshot_path / "save_album_lyrics")

    get_list_lyrics_box.pushButton.click()
    main_window.search_widget.save_path_lineEdit.setText(orig_path)

    get_list_lyrics_box.close()
    assert (test_artifacts_path / "lyrics" / "search album").iterdir()


def test_empty_keyword_search(qtbot: QtBot, main_window: "MainWindow") -> None:
    """测试空关键词搜索"""
    main_window.show()
    main_window.set_current_widget(0)
    qtbot.wait(300)

    main_window.search_widget.search_keyword_lineEdit.setText("")
    main_window.search_widget.search_pushButton.click()

    assert main_window.search_widget.search_pushButton.isEnabled() is True
    close_msg_boxs(main_window.search_widget)
