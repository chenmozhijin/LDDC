# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
__version__ = "v0.7.0-beta"

import sys

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
from backend.service import (
    LDDCService,
    check_any_instance_alive,
)
from backend.worker import CheckUpdate
from ui.sidebar_window import SidebarButtonPosition, SidebarWindow
from utils.args import args
from utils.cache import cache, cache_version
from utils.logger import logger
from utils.threadpool import threadpool
from utils.translator import apply_translation
from view.about import AboutWidget
from view.local_match import LocalMatchWidget
from view.msg_box import MsgBox
from view.open_lyrics import OpenLyricsWidget
from view.search import SearchWidget
from view.setting import SettingWidget
from view.update import UpdateQDialog

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
        self.settings_widget = SettingWidget(self.widget_changed)
        self.about_widget = AboutWidget(__version__)
        self.open_lyrics_widget = OpenLyricsWidget()
        self.init_widgets()
        self.connect_signals()

    def init_widgets(self) -> None:
        self.clear_widgets()
        self.add_widget(self.tr("搜索"), self.search_widget)
        self.add_widget(self.tr("本地匹配"), self.local_match_widget)
        self.add_widget(self.tr("打开歌词"), self.open_lyrics_widget)
        self.add_widget(self.tr("关于"), self.about_widget, SidebarButtonPosition.BOTTOM)
        self.add_widget(self.tr("设置"), self.settings_widget, SidebarButtonPosition.BOTTOM)

    def closeEvent(self, event: QCloseEvent) -> None:
        if exit_manager.mainwindow_close_event():
            super().closeEvent(event)
        else:
            event.ignore()
            self.hide()

    def connect_signals(self) -> None:
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.search_widget.update_preview_lyric)  # 修改歌词顺序时更新预览
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.open_lyrics_widget.update_lyrics())
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.open_lyrics_widget.change_lyrics_type)

        self.settings_widget.lrc_ms_digit_count_spinBox.valueChanged.connect(
            self.search_widget.update_preview_lyric)
        self.settings_widget.lrc_ms_digit_count_spinBox.valueChanged.connect(
            self.open_lyrics_widget.update_lyrics)

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
        self.open_lyrics_widget.retranslateUi(self.open_lyrics_widget)
        self.init_widgets()

    @Slot()
    def show_window(self) -> None:
        if self.isMinimized():
            self.showNormal()
        self.activateWindow()

        # 在其他线程调用时self.raise_()没有用
        self.setWindowFlag(Qt.WindowStaysOnTopHint, True)
        self.show()
        self.setWindowFlag(Qt.WindowStaysOnTopHint, False)
        self.show()

        self.setFocus()


class ExitManager(QObject):
    close_signal = Signal()

    def get_window_show_state(self) -> bool:
        try:
            return not main_window.isHidden()
        except Exception:
            return False

    def exit(self) -> None:
        logger.info("Exit...")
        self.close_signal.emit()
        service_thread.quit()
        service_thread.wait()

        cache["version"] = cache_version
        cache.expire()
        cache.close()
        app.quit()

    def mainwindow_close_event(self) -> bool:
        if not check_any_instance_alive():
            self.exit()
            return True
        return False

    def close_event(self) -> bool:
        if not check_any_instance_alive() and not self.get_window_show_state():
            self.exit()
            return True
        return False


if __name__ == "__main__":

    app = QApplication(sys.argv)

    exit_manager = ExitManager()

    show = args.show
    if args.get_service_port:
        show = False
    service = LDDCService()
    service_thread = QThread(app)
    service.moveToThread(service_thread)
    service_thread.start()
    service.instance_del.connect(exit_manager.close_event)

    exit_manager.close_signal.connect(service.stop_service, Qt.BlockingQueuedConnection)

    main_window = MainWindow()
    service.show_signal.connect(main_window.show_window)
    apply_translation(main_window)
    if show:
        main_window.show()
        main_window.check_update(True)
    sys.exit(app.exec())
