# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

"""获取专辑/歌单歌词界面"""

import random
from pathlib import Path

from PySide6.QtCore import Qt, QTimer, Signal, Slot
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import QDialog, QMessageBox, QWidget

from LDDC.common.data.config import cfg
from LDDC.common.models import APIResultList, Language, Lyrics, LyricsFormat, SongInfo
from LDDC.common.task_manager import TaskManager
from LDDC.common.utils import save2fomat_path
from LDDC.core.api.lyrics import get_lyrics
from LDDC.gui.components.msg_box import MsgBox
from LDDC.gui.ui.get_list_lyrics_ui import Ui_get_list_lyrics


class GetListLyrics(QDialog, Ui_get_list_lyrics):
    closed = Signal()

    def __init__(self, parent: QWidget, songs: APIResultList[SongInfo], lyric_langs: list[str], lyrics_format: LyricsFormat, save_folder: Path) -> None:
        super().__init__(parent)
        self.setupUi(self)
        self.setWindowModality(Qt.WindowModality.WindowModal)

        self.ask_to_close = True
        self.canceled =False

        self.songs = songs
        self.lyric_langs = lyric_langs
        self.lyrics_format = lyrics_format
        self.save_folder = save_folder
        self.file_name_format = cfg["lyrics_file_name_fmt"]
        self.skip_inst_lyrics = cfg["skip_inst_lyrics"]
        self.curent_index = 0

        self.taskmanger = TaskManager({"get_lyrics": []})

    @Slot()
    def cancel(self) -> None:
        self.pushButton.clicked.disconnect(self.cancel)
        self.pushButton.clicked.connect(self.close)
        self.pushButton.setText(self.tr("关闭"))
        self.ask_to_close = False
        self.canceled = True
        self.taskmanger.clear_task("get_lyrics")

    def open(self) -> None:
        # 初始化进度条
        self.progressBar.setValue(0)
        self.progressBar.setMaximum(len(self.songs))

        self.pushButton.setText(self.tr("取消"))
        self.pushButton.clicked.connect(self.cancel)

        self.get_lyrics()
        super().open()

    @Slot()
    def get_lyrics(self) -> None:
        if self.canceled:
            return
        info = self.songs[self.progressBar.value()]

        def callback(result: Lyrics | Exception | None) -> None:
            if isinstance(result, Lyrics):
                text = self.tr("获取 {0} 歌词成功").format(info.artist_title(replace=True))
                if result.is_inst() and self.skip_inst_lyrics:
                    text += self.tr("但歌曲为纯音乐,已跳过")
                else:
                    try:
                        save_path = save2fomat_path(
                            result.to(self.lyrics_format, self.lyric_langs),
                            self.save_folder,
                            self.file_name_format + self.lyrics_format.ext,
                            info,
                            self.lyric_langs,
                        )
                        text += self.tr(",成功保存到:") + str(save_path)
                    except Exception as e:
                        text += self.tr(",保存失败:") + str(e)
            elif result is None:
                text = self.tr("{0} 为纯音乐歌曲,已跳过").format(info.artist_title(replace=True))
            else:
                text = self.tr("获取 {0} 歌词失败:").format(info.artist_title(replace=True)) + str(result)

            self.plainTextEdit.appendPlainText(text)
            self.progressBar.setValue(self.progressBar.value() + 1)
            if self.progressBar.value() == self.progressBar.maximum():
                self.pushButton.setText(self.tr("关闭"))
                self.pushButton.clicked.connect(self.close)
                self.ask_to_close = False
                MsgBox.information(self, self.tr("提示"), self.tr("获取歌词完成"))
            elif isinstance(result, Lyrics) and result.info.cached is False:
                QTimer.singleShot(random.randint(500, 1000), self.get_lyrics)  # noqa: S311
            else:
                self.get_lyrics()

        if info.language == Language.INSTRUMENTAL and self.skip_inst_lyrics:
            callback(None)
            return

        self.taskmanger.new_multithreaded_task(
            "get_lyrics",
            get_lyrics,
            callback,
            callback,
            info,
        )

    def question_slot(self, but: QMessageBox.StandardButton) -> None:
        if but == QMessageBox.StandardButton.Yes:
            self.ask_to_close = False
            self.close()

    def closeEvent(self, arg__1: QCloseEvent) -> None:
        if self.ask_to_close:
            arg__1.ignore()
            MsgBox.question(
                self,
                self.tr("提示"),
                self.tr("是否要退出获取专辑/歌单歌词？"),
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
                self.question_slot,
            )
        else:
            self.closed.emit()
            super().closeEvent(arg__1)
