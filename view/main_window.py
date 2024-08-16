# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from PySide6.QtCore import Qt, Slot
from PySide6.QtGui import QCloseEvent, QIcon, QShowEvent

from ui.sidebar_window import SidebarButtonPosition, SidebarWindow
from utils.exit_manager import exit_manager
from utils.translator import language_changed
from utils.version import __version__
from view.about import AboutWidget
from view.local_match import LocalMatchWidget
from view.open_lyrics import OpenLyricsWidget
from view.search import SearchWidget
from view.setting import SettingWidget


class MainWindow(SidebarWindow):

    def __init__(self) -> None:
        super().__init__()
        exit_manager.windows.append(self)
        self.is_inited = False

    def showEvent(self, event: QShowEvent) -> None:
        if not self.is_inited:
            self.init()
        return super().showEvent(event)

    def init(self) -> None:
        self.setWindowTitle("LDDC")
        self.resize(1050, 600)
        self.setWindowIcon(QIcon(":/LDDC/img/icon/logo.png"))
        self.set_sidebar_width(100)

        self.search_widget = SearchWidget(self)
        self.local_match_widget = LocalMatchWidget()
        self.settings_widget = SettingWidget(self.widget_changed)
        self.about_widget = AboutWidget(__version__)
        self.open_lyrics_widget = OpenLyricsWidget()
        self.init_widgets()
        self.connect_signals()
        self.is_inited = True

    def init_widgets(self) -> None:
        self.clear_widgets()
        self.add_widget(self.tr("搜索"), self.search_widget)
        self.add_widget(self.tr("本地匹配"), self.local_match_widget)
        self.add_widget(self.tr("打开歌词"), self.open_lyrics_widget)
        self.add_widget(self.tr("关于"), self.about_widget, SidebarButtonPosition.BOTTOM)
        self.add_widget(self.tr("设置"), self.settings_widget, SidebarButtonPosition.BOTTOM)

    def closeEvent(self, event: QCloseEvent) -> None:
        if exit_manager.window_close_event(self):
            super().closeEvent(event)
        else:
            event.ignore()
            self.hide()

    def connect_signals(self) -> None:

        language_changed.connect(self.retranslateUi)

    def retranslateUi(self) -> None:
        self.search_widget.retranslateUi()
        self.local_match_widget.retranslateUi(self.local_match_widget)
        self.settings_widget.retranslateUi(self.settings_widget)
        self.about_widget.retranslateUi(self.about_widget)
        self.open_lyrics_widget.retranslateUi(self.open_lyrics_widget)
        self.init_widgets()

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
