# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

"""LDDC的主窗口"""

from PySide6.QtCore import Qt, Slot
from PySide6.QtGui import QCloseEvent, QIcon, QShowEvent
from PySide6.QtWidgets import QMessageBox

from LDDC.ui.sidebar_window import SidebarWindow
from LDDC.utils.enum import Direction
from LDDC.utils.exit_manager import exit_manager
from LDDC.utils.translator import language_changed

from .about import AboutWidget
from .local_match import LocalMatchWidget
from .msg_box import MsgBox
from .open_lyrics import OpenLyricsWidget
from .search import SearchWidget
from .setting import SettingWidget


class MainWindow(SidebarWindow):

    def __init__(self) -> None:
        super().__init__()
        exit_manager.windows.append(self)
        self.is_inited = False

    def showEvent(self, event: QShowEvent) -> None:
        # 直到要显示时才初始化
        if not self.is_inited:
            self.init()
        return super().showEvent(event)

    def init(self) -> None:
        """初始化主窗口"""
        self.setWindowTitle("LDDC")
        self.resize(1060, 600)
        self.setWindowIcon(QIcon(":/LDDC/img/icon/logo.png"))
        self.set_sidebar_width(100)

        self.search_widget = SearchWidget()
        self.local_match_widget = LocalMatchWidget()
        self.settings_widget = SettingWidget()
        self.about_widget = AboutWidget()
        self.open_lyrics_widget = OpenLyricsWidget()
        self.init_widgets()
        self.connect_signals()
        self.is_inited = True

    def init_widgets(self) -> None:
        self.add_widget(self.tr("搜索"), self.search_widget)
        self.add_widget(self.tr("本地匹配"), self.local_match_widget)
        self.add_widget(self.tr("打开歌词"), self.open_lyrics_widget)
        self.add_widget(self.tr("关于"), self.about_widget, Direction.BOTTOM)
        self.add_widget(self.tr("设置"), self.settings_widget, Direction.BOTTOM)

    def closeEvent(self, event: QCloseEvent) -> None:
        if self.local_match_widget.matching:
            def question_slot(but: QMessageBox.StandardButton) -> None:
                if but == QMessageBox.StandardButton.Yes and self.local_match_widget.workers:
                    self.local_match_widget.workers[0].stop()
                    if exit_manager.window_close_event(self):
                        self.destroy()
                        self.deleteLater()
                    else:
                        self.hide()

            MsgBox.question(self, self.tr("提示"), self.tr("正在匹配歌词，是否退出？"),
                            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No, QMessageBox.StandardButton.No, question_slot)
            event.ignore()
            return

        if exit_manager.window_close_event(self):
            super().closeEvent(event)
        else:
            event.ignore()
            self.hide()

    def connect_signals(self) -> None:
        self.widget_changed.connect(self.settings_widget.update_cache_size)  # 更新缓存大小
        language_changed.connect(self.retranslateUi)

        self.local_match_widget.search_song.connect(self.search_widget.auto_fetch)
        self.local_match_widget.search_song.connect(lambda: self.set_current_widget(0))

    @Slot()
    def retranslateUi(self) -> None:
        self.search_widget.retranslateUi()
        self.local_match_widget.retranslateUi(self.local_match_widget)
        self.settings_widget.retranslateUi(self.settings_widget)
        self.about_widget.retranslateUi(self.about_widget)
        self.open_lyrics_widget.retranslateUi(self.open_lyrics_widget)

        # 重新设置侧边栏按钮
        current_widget = self.current_widget
        self.clear_widgets()
        self.init_widgets()
        self.set_current_widget(current_widget)

    @Slot()
    def show_window(self) -> None:
        if self.isMinimized():
            self.showNormal()

        self.setWindowFlag(Qt.WindowType.WindowStaysOnTopHint, True)
        self.show()
        self.setWindowFlag(Qt.WindowType.WindowStaysOnTopHint, False)
        self.show()

        self.setFocus()


main_window = MainWindow()
