# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
__version__ = "v0.7.0-beta"
import argparse
import logging
import os
import sys
import time

from PySide6.QtCore import (
    QObject,
    Qt,
    QThread,
    Signal,
    Slot,
)
from PySide6.QtGui import QCloseEvent, QIcon
from PySide6.QtWidgets import QApplication

import res.resource_rc
from backend.service import LDDCService, instance_handle_task
from backend.worker import CheckUpdate
from ui.sidebar_window import SidebarButtonPosition, SidebarWindow
from utils.data import cfg
from utils.threadpool import threadpool
from utils.translator import apply_translation
from utils.utils import (
    str2log_level,
)
from view.about import AboutWidget
from view.encrypted_lyrics import EncryptedLyricsWidget
from view.local_match import LocalMatchWidget
from view.msg_box import MsgBox
from view.search import SearchWidget
from view.setting import SettingWidget
from view.update import UpdateQDialog

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
logger.setLevel(str2log_level(cfg["log_level"]))

res.resource_rc.qInitResources()


class MainWindow(SidebarWindow):

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("LDDC")
        self.resize(1050, 600)
        self.setWindowIcon(QIcon(":/LDDC/img/icon/logo.png"))
        self.set_sidebar_width(100)

        self.search_widget = SearchWidget(self)
        self.local_match_widget = LocalMatchWidget()
        self.settings_widget = SettingWidget(logger, self.widget_changed)
        self.about_widget = AboutWidget(__version__)
        self.encrypted_lyrics_widget = EncryptedLyricsWidget()
        self.init_widgets()
        self.connect_signals()
        self.check_update(True)

    def init_widgets(self) -> None:
        self.clear_widgets()
        self.add_widget(self.tr("搜索"), self.search_widget)
        self.add_widget(self.tr("本地匹配"), self.local_match_widget)
        self.add_widget(self.tr("打开\n加密歌词"), self.encrypted_lyrics_widget)
        self.add_widget(self.tr("关于"), self.about_widget, SidebarButtonPosition.BOTTOM)
        self.add_widget(self.tr("设置"), self.settings_widget, SidebarButtonPosition.BOTTOM)

    def closeEvent(self, event: QCloseEvent) -> None:
        exit_manager.exit()
        super().closeEvent(event)

    def connect_signals(self) -> None:
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.search_widget.update_preview_lyric)  # 修改歌词顺序时更新预览
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.encrypted_lyrics_widget.update_lyrics())
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.encrypted_lyrics_widget.change_lyrics_type)

        self.settings_widget.lrc_ms_digit_count_spinBox.valueChanged.connect(
            self.search_widget.update_preview_lyric)
        self.settings_widget.lrc_ms_digit_count_spinBox.valueChanged.connect(
            self.encrypted_lyrics_widget.update_lyrics)

        self.about_widget.checkupdate_pushButton.clicked.connect(lambda: self.check_update(False))

    def check_update(self, is_auto: bool) -> None:
        worker = CheckUpdate(is_auto, self, __version__)
        worker.signals.show_message.connect(self.show_message)
        worker.signals.show_new_version_dialog.connect(self.show_new_version_dialog)
        threadpool.start(worker)

    def show_new_version_dialog(self, last_version: str, body: str) -> None:
        self.update_dialog = UpdateQDialog(self, last_version, body)

    @Slot(str, str, str)
    def show_message(self, message_type: str, title: str = "", message: str = "") -> None:
        match message_type:
            case "info":
                MsgBox.information(self, title, message)
            case "warning":
                MsgBox.warning(self, title, message)
            case "error":
                MsgBox.critical(self, title, message)

    def retranslateUi(self) -> None:
        self.search_widget.retranslate_ui()
        self.local_match_widget.retranslateUi(self.local_match_widget)
        self.settings_widget.retranslateUi(self.settings_widget)
        self.about_widget.retranslateUi(self.about_widget)
        self.encrypted_lyrics_widget.retranslateUi(self.encrypted_lyrics_widget)
        self.init_widgets()

    @Slot()
    def show_window(self) -> None:
        self.show()
        if self.isMinimized():
            self.showNormal()
        self.raise_()
        self.activateWindow()


class ExitManager(QObject):
    close_signal = Signal()

    def exit(self) -> None:
        self.close_signal.emit()
        service_thread.quit()
        service_thread.wait()
        app.quit()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--get-service-port", action='store_true', dest='get_service_port')
    app = QApplication(sys.argv)

    exit_manager = ExitManager()

    service = LDDCService(parser.parse_args())
    service_thread = QThread(app)
    service.moveToThread(service_thread)
    service_thread.start()
    service.handle_task.connect(instance_handle_task)
    exit_manager.close_signal.connect(service.stop_service, Qt.BlockingQueuedConnection)

    main_window = MainWindow()
    service.show_signal.connect(main_window.show_window)
    apply_translation(main_window)
    main_window.show()
    sys.exit(app.exec())
