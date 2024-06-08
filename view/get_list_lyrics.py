# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from PySide6.QtCore import Signal
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import QDialog, QMessageBox, QWidget

from ui.get_list_lyrics_ui import Ui_get_list_lyrics
from view.msg_box import MsgBox


class GetListLyrics(QDialog, Ui_get_list_lyrics):
    closed = Signal()

    def __init__(self, parent: QWidget = None) -> None:
        super().__init__(parent)
        self.setupUi(self)
        self.ask_to_close = False

    def question_slot(self, but: QMessageBox.StandardButton) -> None:
        if but == QMessageBox.Yes:
            self.ask_to_close = False
            self.close()

    def closeEvent(self, arg__1: QCloseEvent) -> None:
        if self.ask_to_close:
            arg__1.ignore()
            MsgBox.question(self, self.tr("提示"), self.tr("是否要退出获取专辑/歌单歌词？"), QMessageBox.Yes | QMessageBox.No, QMessageBox.No, self.question_slot)
        else:
            self.closed.emit()
            super().closeEvent(arg__1)
