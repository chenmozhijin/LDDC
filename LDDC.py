# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
__version__ = "v0.4.1"
import logging
import os
import sys
import time

from PySide6.QtCore import (
    QThreadPool,
    QUrl,
    Slot,
)
from PySide6.QtGui import QCloseEvent, QDesktopServices, QIcon
from PySide6.QtWidgets import (
    QApplication,
    QMessageBox,
)

import res.resource_rc
from ui.sidebar_window import Position as SBPosition
from ui.sidebar_window import SidebarWindow
from utils.data import Data
from utils.utils import (
    str2log_level,
)
from utils.worker import CheckUpdate
from view.about import AboutWidget
from view.encrypted_lyrics import EncryptedLyricsWidget
from view.local_match import LocalMatchWidget
from view.search import SearchWidget
from view.setting import SettingWidget

current_directory = os.path.dirname(os.path.abspath(__file__))
match sys.platform:
    case "linux" | "darwin":
        log_dir = os.path.expanduser("~/.config/LDDC/log")
    case _:
        log_dir = os.path.join(current_directory, "log")

if not os.path.exists(log_dir):
    os.mkdir(log_dir)
logging.basicConfig(filename=os.path.join(log_dir, f'{time.strftime("%Y.%m.%d",time.localtime())}.log'),
                    encoding="utf-8", format="[%(levelname)s]%(asctime)s\
                          - %(module)s(%(lineno)d) - %(funcName)s:%(message)s")
logger = logging.getLogger()
data = Data(current_directory)
data_mutex = data.mutex
logger.setLevel(str2log_level(data.cfg["log_level"]))

threadpool = QThreadPool()
logging.debug(f"最大线程数: {threadpool.maxThreadCount()}")

res.resource_rc.qInitResources()


class MainWindow(SidebarWindow):

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("LDDC")
        self.resize(1050, 600)
        self.setWindowIcon(QIcon(":/LDDC/img/icon/logo.png"))
        self.set_sidebar_width(80)

        self.search_widget = SearchWidget(self, data, threadpool)
        self.local_match_widget = LocalMatchWidget(data, threadpool)
        self.settings_widget = SettingWidget(data, logger)
        self.about_widget = AboutWidget(__version__)
        self.encrypted_lyrics_widget = EncryptedLyricsWidget(data)

        self.add_widget("搜索", self.search_widget)
        self.add_widget("本地匹配", self.local_match_widget)
        self.add_widget("打开\n加密歌词", self.encrypted_lyrics_widget)
        self.add_widget("关于", self.about_widget, SBPosition.BOTTOM)
        self.add_widget("设置", self.settings_widget, SBPosition.BOTTOM)
        self.connect_signals()
        self.check_update(True)

    def closeEvent(self, event: QCloseEvent) -> None:
        data.conn.commit()
        data.conn.close()
        super().closeEvent(event)

    def connect_signals(self) -> None:
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.search_widget.update_preview_lyric)  # 修改歌词顺序时更新预览
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.encrypted_lyrics_widget.change_lyrics_type)

        self.about_widget.checkupdate_pushButton.clicked.connect(lambda: self.check_update(False))

    def check_update(self, is_auto: bool) -> None:
        worker = CheckUpdate(is_auto, self, __version__)
        threadpool.start(worker)

    @Slot(str, str, str)
    def show_message(self, message_type: str, title: str = "", message: str = "") -> None:
        match message_type:
            case "info":
                QMessageBox.information(self, title, message)
            case "warning":
                QMessageBox.warning(self, title, message)
            case "error":
                QMessageBox.critical(self, title, message)
            case "update":
                title = "发现新版本"
                message = "发现新版本,是否前往GitHub下载？"
                if QMessageBox.question(self, title, message) == QMessageBox.Yes:
                    QDesktopServices.openUrl(QUrl("https://github.com/chenmozhijin/LDDC/releases/latest"))


if __name__ == "__main__":
    app = QApplication(sys.argv)

    main_window = MainWindow()
    main_window.show()
    sys.exit(app.exec())
