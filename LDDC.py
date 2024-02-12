# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from __future__ import annotations

__version__ = "v0.1.0"
import logging
import os
import resource.resource_rc
import sys
import time

from PySide6.QtCore import (
    Q_ARG,
    QMetaObject,
    QModelIndex,
    QMutex,
    QObject,
    QRunnable,
    Qt,
    QThreadPool,
    QUrl,
    Signal,
    Slot,
)
from PySide6.QtGui import QDesktopServices, QIcon
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QMessageBox,
    QTableWidget,
    QTableWidgetItem,
    QWidget,
)

from api import QMSearchType, get_latest_version, qm_search
from data import Data
from lyrics import Lyrics
from ui.about_ui import Ui_about
from ui.settings_ui import Ui_settings
from ui.sidebar_window import Position as SBPosition
from ui.sidebar_window import SidebarWindow
from ui.single_search_ui import Ui_single_search
from utils import (
    get_save_path,
    str2log_level,
)

data_mutex = QMutex()
current_directory = os.path.dirname(os.path.abspath(__file__))
data = Data(current_directory, data_mutex)

if not os.path.exists("log"):
    os.mkdir("log")
logging.basicConfig(filename=f'log\\{time.strftime("%Y.%m.%d",time.localtime())}.log',
                    encoding="utf-8", format="[%(levelname)s]%(asctime)s\
                          - %(module)s(%(lineno)d) - %(funcName)s:%(message)s",
                    level=str2log_level(data.cfg["log_level"]))
logger = logging.getLogger()

threadpool = QThreadPool()
logging.debug(f"最大线程数: {threadpool.maxThreadCount()}")

cache = {
    "serach": {},
    "lyrics": {},
}
cache_mutex = QMutex()

resource.resource_rc.qInitResources()

class SearchSignal(QObject):
    error = Signal(str)
    result = Signal(list)

class SearchWorker(QRunnable):

    def __init__(self, keyword:str, search_type:QMSearchType) -> None:
        super().__init__()
        self.keyword = keyword
        self.search_type = search_type
        self.signals = SearchSignal()

    def run(self) -> None:
        logging.debug("开始搜索歌曲")
        cache_mutex.lock()
        if (self.keyword, self.search_type) in cache["serach"]:
            logging.debug(f"从缓存中获取搜索结果,类型:{self.search_type}, 关键字:{self.keyword}")
            result = cache["serach"][(self.keyword, self.search_type)]
            cache_mutex.unlock()
        else:
            cache_mutex.unlock()
            result = qm_search(self.keyword, self.search_type)
            if isinstance(result, str):
                self.signals.error.emit(result)
                return
            cache_mutex.lock()
            cache["serach"][(self.keyword, self.search_type)] = result
            cache_mutex.unlock()

        self.signals.result.emit(result)
        logging.debug("发送结果信号")


class LyricProcessingSignal(QObject):
    result = Signal(dict, list, str)
    error = Signal(str)

class LyricProcessingWorker(QRunnable):

    def __init__(self, task:dict) -> None:
        super().__init__()
        self.task = task
        self.signals = LyricProcessingSignal()

    def run(self) -> None:
        if self.task["type"] == "get_merged_lyric":
            self.get_merged_lyric(self.task["song_info"], self.task["lyric_type"])


    def get_lyrics(self, song_info:dict) -> None|Lyrics:
        logging.debug(f"开始获取歌词：{song_info['id']}")
        cache_mutex.lock()
        if (song_info["source"], song_info['id']) in cache["lyrics"]:
            lyrics = cache["lyrics"][(song_info["source"], song_info['id'])]
            logging.info(f"从缓存中获取歌词：源:{song_info['source']}, id:{song_info['id']}")
            cache_mutex.unlock()
        else:
            cache_mutex.unlock()
            lyrics = Lyrics(song_info)
            error = lyrics.download_and_decrypt()
            if error is not None:
                logging.error(f"获取歌词失败：源:{song_info['source']}, id: {song_info['id']},错误：{error}")
                self.signals.error.emit(error)
                return None
            cache_mutex.lock()
            cache["lyrics"][(song_info["source"], song_info['id'])] = lyrics
            cache_mutex.unlock()
        return lyrics

    def get_merged_lyric(self, song_info:dict, lyric_type:list) -> None:
        logging.debug(f"开始获取合并歌词：{song_info['id']}")
        lyrics = self.get_lyrics(song_info)
        if lyrics is None:
            return
        data_mutex.lock()
        type_mapping = {"原文": "orig", "译文": "ts", "罗马音": "roma"}
        lyrics_order = [type_mapping[type_] for type_ in data.cfg["lyrics_order"] if type_mapping[type_] in lyric_type]
        data_mutex.unlock()

        merged_lyrics = lyrics.merge(lyrics_order)
        self.signals.result.emit(song_info, list(lyrics.keys()), merged_lyrics)
        logging.debug("发送结果信号")


class CheckUpdate(QRunnable):
    def __init__(self, is_auto:bool, windows:SidebarWindow) -> None:
        super().__init__()
        self.isAuto = is_auto
        self.windows = windows

    def run(self) -> None:
        is_success, last_version = get_latest_version()
        if is_success:

            def compare_version_numbers(current_version:str, last_version:str) -> bool:
                last_version = [int(i) for i in last_version.replace("v", "").split(".")]
                current_version = [int(i) for i in current_version.replace("v", "").split(".")]
                return current_version < last_version

            if compare_version_numbers(__version__, last_version):
                QMetaObject.invokeMethod(self.windows, "show_message", Qt.QueuedConnection,
                                         Q_ARG(str, "update"), Q_ARG(str, "检查更新"), Q_ARG(str, f"发现新版本{last_version},是否前往GitHub下载？"))
            elif not self.isAuto:
                QMetaObject.invokeMethod(self.windows, "show_message", Qt.QueuedConnection,
                                         Q_ARG(str, "info"), Q_ARG(str, "检查更新"), Q_ARG(str, "已经是最新版本"))
        elif not self.isAuto:
            QMetaObject.invokeMethod(self.windows, "show_message", Qt.QueuedConnection,
                                     Q_ARG(str, "error"), Q_ARG(str, "检查更新"), Q_ARG(str, f"检查更新失败，错误:{last_version}"))


class MainWindow(SidebarWindow):

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("LDDC")
        self.resize(1050, 600)
        self.setWindowIcon(QIcon(":/LDDC/img/icon/logo.png"))

        self.single_search_weidget = SingleSearchWidget()
        self.settings_widget = SettingWidget()
        self.about_widget = AboutWidget()

        self.add_widget("单曲搜索", self.single_search_weidget)
        self.add_widget("关于", self.about_widget, SBPosition.BOTTOM)
        self.add_widget("设置", self.settings_widget, SBPosition.BOTTOM)
        self.connect_signals()
        self.check_update(True)


    def connect_signals(self) -> None:
        self.settings_widget.lyrics_order_listWidget.droped.connect(
            self.single_search_weidget.preview_lyric)  # 修改歌词顺序时更新预览

        self.about_widget.checkupdate_pushButton.clicked.connect(lambda: self.check_update(False))

    def check_update(self, is_auto:bool) -> None:
        worker = CheckUpdate(is_auto, self)
        threadpool.start(worker)

    @Slot(str, str, str)
    def show_message(self, message_type: str, title:str="", message: str="") -> None:
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

class SingleSearchWidget(QWidget, Ui_single_search):

    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.connect_signals()

        self.lyric_preview_info = None
        self.preview_Lyric = {}

        threadpool = QThreadPool()
        logging.debug(f"最大线程数：{threadpool.maxThreadCount()}")
        self.path_lineEdit.setText(data.cfg["default_save_path"])
        self.Searchresults_tableWidget.set_proportion([0.4, 0.2, 0.4])

    def connect_signals(self) -> None:
        self.Search_pushButton.clicked.connect(self.search_song)
        self.Selectpath_pushButton.clicked.connect(self.select_savepath)
        self.Translate_checkBox.stateChanged.connect(self.preview_lyric)
        self.Romanized_checkBox.stateChanged.connect(self.preview_lyric)
        self.Save_pushButton.clicked.connect(self.save_lyric)
        self.Searchresults_tableWidget.doubleClicked.connect(self.preview_lyric)

    @Slot()
    def search_error(self, error:str) -> None:
        self.Search_pushButton.setEnabled(True)
        self.Search_pushButton.setText('搜索')
        self.show_message("error", error)

    @Slot()
    def lyric_processing_error(self, error:str) -> None:
        self.preview_plainTextEdit.setPlainText("")
        self.search_result_buttons_set_enabled(isenabled=True)
        self.preview_Lyric = {}
        self.show_message("error", error)

    @Slot()
    def save_lyric(self) -> None:
        if self.lyric_preview_info is None or not self.preview_Lyric:
            QMessageBox.warning(self, '警告', '请先下载并预览歌词并选择保存路径')
            return

        data_mutex.lock()
        save_folder, file_name = get_save_path(
            self.path_lineEdit.text(), data.cfg["lyrics_file_name_format"] + ".lrc", self.preview_Lyric["info"])
        data_mutex.unlock()
        try:
            if not os.path.exists(save_folder):
                os.makedirs(save_folder)
            with open(os.path.join(save_folder, file_name), 'w', encoding='utf-8') as f:
                f.write(self.preview_Lyric["lyric"])
            QMessageBox.information(self, '提示', '歌词保存成功')
        except Exception as e:
            QMessageBox.warning(self, '警告', f'歌词保存失败：{e}')

    @Slot()
    def select_savepath(self) -> None:
        save_path = QFileDialog.getExistingDirectory(self, "选择保存路径", dir=self.path_lineEdit.text())
        if save_path:
            self.path_lineEdit.setText(os.path.normpath(save_path))

    @Slot()
    def search_song(self) -> None:
        song_name = self.Songname_lineEdit.text()
        if not song_name:
            QMessageBox.warning(self, "警告", "请输入歌曲名")
            return

        self.Search_pushButton.setDisabled(True)
        self.Search_pushButton.setText('正在搜索...')
        self.Searchresults_tableWidget.setRowCount(0)

        worker = SearchWorker(song_name, QMSearchType.SONG)
        worker.signals.result.connect(self.update_search_result)
        worker.signals.error.connect(self.search_error)
        threadpool.start(worker)

    @Slot()
    def update_search_result(self, lyric_infos:list) -> None:
        self.Search_pushButton.setEnabled(True)
        self.Search_pushButton.setText('搜索')
        table = self.Searchresults_tableWidget
        table.setRowCount(0)


        for lyric_info in lyric_infos:
            table.insertRow(table.rowCount())
            if lyric_info["subtitle"] != "":
                name = lyric_info["name"] + "(" + lyric_info["subtitle"] + ")"
            else:
                name = lyric_info["name"]
            table.setItem(table.rowCount() - 1, 0, QTableWidgetItem(name))
            table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(lyric_info["artist"]))
            table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(lyric_info["album"]))

        table.setProperty("lyric_infos", lyric_infos)

    def search_result_buttons_set_enabled(self, *, isenabled:bool) -> None:
        self.Searchresults_tableWidget.setEnabled(isenabled)
        self.Translate_checkBox.setEnabled(isenabled)
        self.Romanized_checkBox.setEnabled(isenabled)
        self.Save_pushButton.setEnabled(isenabled)

    @Slot()
    def show_message(self, type_: str, message: str) -> None:
        if type_ == "error":
            QMessageBox.critical(self, "错误", message)

    @Slot()
    def update_lyric_preview(self, song_info:dict, lyric_types:list, lyric_text:str) -> None:
        logging.debug("开始update_lyric_preview")
        lyric_info_label_text = "歌词信息:"
        if 'ts' in lyric_types:
            lyric_info_label_text += "翻译:有"
        else:
            lyric_info_label_text += "翻译:无"
        if 'roma' in lyric_types:
            lyric_info_label_text += " 罗马音:有"
        else:
            lyric_info_label_text += " 罗马音:无"
        self.lyric_info_label.setText(lyric_info_label_text)
        self.preview_plainTextEdit.setPlainText(lyric_text)
        self.preview_Lyric = {"info": song_info, "lyric": lyric_text}
        self.search_result_buttons_set_enabled(isenabled=True)
        logging.debug("结束update_lyric_preview")

    @Slot()
    def preview_lyric(self, index: QModelIndex|None=None) -> None:
        sender = self.sender()  # 获取发送信号的按钮

        if isinstance(sender, QTableWidget):  # 如果信号来自搜索结果的按钮
            row = index.row()
            lyric_info = sender.property("lyric_infos")[row]  # 获取对应的信息

        elif self.lyric_preview_info:  # 如果信号来自 译文/罗马音 的选择框或设置且已经 下载&预览 过歌词
            lyric_info = self.lyric_preview_info

        else:
            logging.debug("lyric_info: None")
            return

        logging.debug(f"lyric_info: {lyric_info}")
        self.lyric_info_label.setText("歌词信息：无")
        self.preview_plainTextEdit.setPlainText("处理中...")
        self.search_result_buttons_set_enabled(isenabled=False)
        self.preview_Lyric = {}
        self.lyric_preview_info = lyric_info

        lyric_type = ['orig']
        if self.Translate_checkBox.isChecked():
            lyric_type.append('ts')
        if self.Romanized_checkBox.isChecked():
            lyric_type.append("roma")

        worker = LyricProcessingWorker({"type": "get_merged_lyric", "song_info": lyric_info, "lyric_type": lyric_type})
        worker.signals.result.connect(self.update_lyric_preview)
        worker.signals.error.connect(self.lyric_processing_error)
        threadpool.start(worker)

class SettingWidget(QWidget, Ui_settings):

    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.init_ui()
        self.connect_signals()

    def init_ui(self) -> None:
        self.lyrics_order_listWidget.clear()
        self.lyrics_order_listWidget.addItems(data.cfg["lyrics_order"])
        self.lyrics_file_name_format_lineEdit.setText(data.cfg["lyrics_file_name_format"])
        self.default_save_path_lineEdit.setText(data.cfg["default_save_path"])
        self.log_level_comboBox.setCurrentText(data.cfg["log_level"])

    def select_default_save_path(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "选择默认保存路径")
        if path:
            self.default_save_path_lineEdit.setText(os.path.normpath(path))

    def connect_signals(self) -> None:
        self.lyrics_order_listWidget.droped.connect(lambda: data.write_config(
                "lyrics_order",
                [self.lyrics_order_listWidget.item(i).text() for i in range(self.lyrics_order_listWidget.count())]))

        self.lyrics_file_name_format_lineEdit.textChanged.connect(
            lambda: data.write_config("lyrics_file_name_format", self.lyrics_file_name_format_lineEdit.text()))

        self.default_save_path_lineEdit.textChanged.connect(
            lambda: data.write_config("default_save_path", self.default_save_path_lineEdit.text()))

        self.log_level_comboBox.currentTextChanged.connect(
            lambda: data.write_config("log_level", self.log_level_comboBox.currentText()))
        self.log_level_comboBox.currentTextChanged.connect(
            lambda: logger.setLevel(str2log_level(self.log_level_comboBox.currentText())))

        self.select_default_save_path_pushButton.clicked.connect(self.select_default_save_path)


class AboutWidget(QWidget, Ui_about):
    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.init_ui()
        self.connect_signals()

    def init_ui(self) -> None:
        html = self.label.text()
        year = time.strftime("%Y", time.localtime())
        if year != "2024":
            year = "2024-" + year
        self.label.setText(html.replace("{year}", year))
        self.version_label.setText(self.version_label.text() + __version__)

    def connect_signals(self) -> None:
        self.github_pushButton.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/chenmozhijin/LDDC")))
        self.githubissues_pushButton.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/chenmozhijin/LDDC/issues")))


if __name__ == "__main__":
    if not os.path.exists("lyrics"):
        os.mkdir("lyrics")

    app = QApplication(sys.argv)

    main_window = MainWindow()
    main_window.show()
    sys.exit(app.exec())
