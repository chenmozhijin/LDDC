# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import os

from PySide6.QtCore import (
    QModelIndex,
    QMutex,
    QThreadPool,
    Slot,
)
from PySide6.QtWidgets import (
    QFileDialog,
    QMessageBox,
    QTableWidgetItem,
    QWidget,
)

from api import (
    QMSearchType,
)
from data import Data
from ui.search_ui import Ui_search
from utils import get_save_path
from view.get_list_lyrics import GetListLyrics
from worker import GetSongListWorker, LyricProcessingWorker, SearchWorker


class SearchWidget(QWidget, Ui_search):
    def __init__(self, main_window: QWidget, data: Data, data_mutex: QMutex, threadpool: QThreadPool) -> None:
        super().__init__()
        self.setupUi(self)
        self.return_toolButton.setEnabled(False)
        self.main_window = main_window
        self.data = data
        self.data_mutex = data_mutex
        self.threadpool = threadpool
        self.connect_signals()
        self.search_type = QMSearchType.SONG

        self.songlist_result = None
        self.search_result = None
        self.preview_info = None

        self.save_path_lineEdit.setText(self.data.cfg["default_save_path"])

        self.get_list_lyrics_box = GetListLyrics(self)

        self.taskid = {
            "search": 0,
            "update_preview_lyric": 0,
        }  # 用于防止旧任务的结果覆盖新任务的结果

    def connect_signals(self) -> None:
        self.select_path_pushButton.clicked.connect(self.select_savepath)
        self.save_preview_lyric_pushButton.clicked.connect(self.save_preview_lyric)
        self.save_list_lyrics_pushButton.clicked.connect(self.save_list_lyrics)

        self.search_pushButton.clicked.connect(self.search_button_clicked)
        self.search_type_comboBox.currentTextChanged.connect(self.search_type_changed)
        self.results_tableWidget.doubleClicked.connect(self.select_results)

        self.translate_checkBox.stateChanged.connect(self.update_preview_lyric)
        self.romanized_checkBox.stateChanged.connect(self.update_preview_lyric)
        self.original_checkBox.stateChanged.connect(self.update_preview_lyric)

        self.return_toolButton.clicked.connect(self.return_search_result)

    def get_lyric_type(self) -> list:
        lyric_type = []
        if self.original_checkBox.isChecked():
            lyric_type.append('orig')
        if self.translate_checkBox.isChecked():
            lyric_type.append('ts')
        if self.romanized_checkBox.isChecked():
            lyric_type.append("roma")
        return lyric_type

    def save_list_lyrics(self) -> None:
        result_type = self.results_tableWidget.property("result_type")
        if (result_type is None or
                result_type[0] not in ["album", "songlist"]):
            QMessageBox.warning(self, '警告', '请先选择一个专辑或歌单')
            return

        self.data_mutex.lock()
        lyrics_file_name_format = self.data.cfg["lyrics_file_name_format"]
        self.data_mutex.unlock()
        save_folder = self.save_path_lineEdit.text()

        def get_list_lyrics_update(count: int | str, result: dict | None = None) -> None:
            text = ""
            if result is None:
                error = count[:]
                count = self.get_list_lyrics_box.progressBar.value() + 1
                self.get_list_lyrics_box.plainTextEdit.setPlainText(f"{text}\n{error}")
            else:
                save_path = result['save_path']
                save_folder = os.path.dirname(save_path)
                text += f"\n 获取{result['info']['title']} - {result['info']['artist']}({result['info']['id']})歌词成功"
                if result['inst']:  # 检查是否为纯音乐,并且设置跳过纯音乐
                    text += "但歌曲为纯音乐,已跳过"
                else:
                    # 保存
                    try:
                        if not os.path.exists(save_folder):
                            os.makedirs(save_folder)
                        with open(save_path, 'w', encoding='utf-8') as f:
                            f.write(result['merged_lyric'])
                    except Exception as e:
                        text += f"但保存歌词失败,原因:{e}"
                    else:
                        text += f",保存到{save_path}"
                self.get_list_lyrics_box.plainTextEdit.appendPlainText(text)

            self.get_list_lyrics_box.progressBar.setValue(count)

            if count == self.get_list_lyrics_box.progressBar.maximum():
                self.get_list_lyrics_box.ask_to_close = False
                self.get_list_lyrics_box.pushButton.setText("关闭")
                self.get_list_lyrics_box.closed.connect(None)
                self.get_list_lyrics_box.pushButton.clicked.connect(self.get_list_lyrics_box.close)
                QMessageBox.information(self.main_window, "提示", "获取歌词完成")
                self.main_window.setDisabled(False)

        self.main_window.setDisabled(True)
        self.get_list_lyrics_box.ask_to_close = True
        self.get_list_lyrics_box.progressBar.setValue(0)
        self.get_list_lyrics_box.pushButton.setText("取消")
        self.get_list_lyrics_box.progressBar.setMaximum(len(self.songlist_result["result"]))
        self.get_list_lyrics_box.plainTextEdit.setPlainText("")
        self.get_list_lyrics_box.show()
        self.get_list_lyrics_box.setEnabled(True)

        worker = LyricProcessingWorker({"type": "get_list_lyrics",
                                        "song_info_list": self.songlist_result["result"],
                                        "lyric_type": self.get_lyric_type(),
                                        "save_folder": save_folder,
                                        "lyrics_file_name_format": lyrics_file_name_format,
                                        },
                                       self.data_mutex, self.data)
        worker.signals.result.connect(get_list_lyrics_update)
        worker.signals.error.connect(get_list_lyrics_update)
        self.threadpool.start(worker)

        def cancel_get_list_lyrics() -> None:
            self.get_list_lyrics_box.ask_to_close = False
            self.get_list_lyrics_box.pushButton.setText("关闭")
            self.get_list_lyrics_box.closed.connect(None)
            self.get_list_lyrics_box.pushButton.clicked.connect(self.get_list_lyrics_box.close)
            self.main_window.setDisabled(False)
            worker.stop()

        self.get_list_lyrics_box.pushButton.clicked.connect(cancel_get_list_lyrics)
        self.get_list_lyrics_box.closed.connect(cancel_get_list_lyrics)

    @Slot()
    def save_preview_lyric(self) -> None:
        if self.preview_info is None or self.save_path_lineEdit.text() == "":
            QMessageBox.warning(self, '警告', '请先下载并预览歌词并选择保存路径')
            return

        if self.preview_plainTextEdit.toPlainText() == "":
            QMessageBox.warning(self, '警告', '歌词内容为空')
            return

        self.data_mutex.lock()
        save_folder, file_name = get_save_path(
            self.save_path_lineEdit.text().strip(),
            self.data.cfg["lyrics_file_name_format"] + ".lrc",
            self.preview_info["info"],
            self.preview_info['available_types'])

        self.data_mutex.unlock()

        save_path = os.path.join(save_folder, file_name)
        try:
            if not os.path.exists(save_folder):
                os.makedirs(save_folder)
            with open(save_path, 'w', encoding='utf-8') as f:
                f.write(self.preview_plainTextEdit.toPlainText())
            QMessageBox.information(self, '提示', '歌词保存成功')
        except Exception as e:
            QMessageBox.warning(self, '警告', f'歌词保存失败：{e}')

    @Slot()
    def select_savepath(self) -> None:
        save_path = QFileDialog.getExistingDirectory(self, "选择保存路径", dir=self.save_path_lineEdit.text())
        if save_path:
            self.save_path_lineEdit.setText(os.path.normpath(save_path))

    def search_type_changed(self, text: str) -> None:
        match text:
            case "单曲":
                self.search_type = QMSearchType.SONG
            case "专辑":
                self.search_type = QMSearchType.ALBUM
            case "歌手":
                self.search_type = QMSearchType.ARTIST
            case "歌单":
                self.search_type = QMSearchType.SONGLIST

    def return_search_result(self) -> None:
        if self.search_result is not None:
            search_type, result = self.search_result.values()
            self.search_result_slot(self.taskid["search"], search_type, result)

    @Slot(int, int, list)
    def search_result_slot(self, taskid: int, search_type: int, result: list) -> None:
        if taskid != self.taskid["search"]:
            return
        self.search_pushButton.setText('搜索')
        self.search_pushButton.setEnabled(True)
        self.return_toolButton.setEnabled(False)
        self.update_result_table(("search", search_type), result)

        self.search_result = {"type": search_type, "result": result}

    def search_error_slot(self, error: str) -> None:
        self.search_pushButton.setText('搜索')
        self.search_pushButton.setEnabled(True)
        QMessageBox.critical(self, "搜索错误", error)

    def search_button_clicked(self) -> None:
        self.search_pushButton.setText('正在搜索...')
        self.search_pushButton.setEnabled(False)
        keyword = self.search_keyword_lineEdit.text()
        self.taskid["search"] += 1
        worker = SearchWorker(self.taskid["search"], keyword, self.search_type)
        worker.signals.result.connect(self.search_result_slot)
        worker.signals.error.connect(self.search_error_slot)
        self.threadpool.start(worker)
        self.results_tableWidget.setRowCount(0)

    def update_preview_lyric_error_slot(self, error: str) -> None:
        QMessageBox.critical(self, "获取预览歌词错误", error)
        self.preview_plainTextEdit.setPlainText("")

    def update_preview_lyric_result_slot(self, taskid: int, result: dict) -> None:
        if taskid != self.taskid["update_preview_lyric"]:
            return
        self.preview_info = {"info": result["info"], 'available_types': result['available_types']}
        lyric_types_text = ""
        if "orig" in result['available_types']:
            lyric_types_text += "原文"
        if "ts" in result['available_types']:
            lyric_types_text += "、译文"
        if "roma" in result['available_types']:
            lyric_types_text += "、罗马音"
        self.lyric_types_lineEdit.setText(lyric_types_text)
        self.songid_lineEdit.setText(str(result['info']['id']))

        self.preview_plainTextEdit.setPlainText(result['merged_lyric'])

    def update_preview_lyric(self, info: dict | None = None) -> None:
        if not isinstance(info, dict) and self.preview_info is not None:
            info = self.preview_info["info"]
        elif not isinstance(info, dict) and self.preview_info is None:
            return

        self.taskid["update_preview_lyric"] += 1
        worker = LyricProcessingWorker(
            {"type": "get_merged_lyric", "song_info": info, "lyric_type": self.get_lyric_type(), "id": self.taskid["update_preview_lyric"]},
            self.data_mutex, self.data)
        worker.signals.result.connect(self.update_preview_lyric_result_slot)
        worker.signals.error.connect(self.update_preview_lyric_error_slot)
        self.threadpool.start(worker)

        self.preview_info = None
        self.preview_plainTextEdit.setPlainText("处理中...")

    def update_result_table(self, result_type: tuple, result: list | None = None) -> None:
        table = self.results_tableWidget
        table.setRowCount(0)

        match result_type[1]:
            case QMSearchType.SONG:
                table.setColumnCount(4)
                table.setHorizontalHeaderLabels(["歌曲", "艺术家", "专辑", "时长"])
                table.set_proportions([0.4, 0.2, 0.4, 2])

                for song in result:
                    table.insertRow(table.rowCount())
                    name = song['title'] + "(" + song["subtitle"] + ")" if song["subtitle"] != "" else song['title']

                    table.setItem(table.rowCount() - 1, 0, QTableWidgetItem(name))
                    table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(song["artist"]))
                    table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(song["album"]))
                    table.setItem(table.rowCount() - 1, 3, QTableWidgetItem('{:02d}:{:02d}'.format(*divmod(song['interval'], 60))))

                table.setProperty("result_type", (result_type[0], "songs"))

            case QMSearchType.ALBUM:
                table.setColumnCount(4)
                table.setHorizontalHeaderLabels(["专辑", "艺术家", "发行日期", "歌曲数量"])
                table.set_proportions([0.6, 0.4, 2, 2])
                for album in result:
                    table.insertRow(table.rowCount())
                    table.setItem(table.rowCount() - 1, 0, QTableWidgetItem(album["name"]))
                    table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(album["artist"]))
                    table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(album["time"]))
                    table.setItem(table.rowCount() - 1, 3, QTableWidgetItem(str(album["count"])))

                table.setProperty("result_type", (result_type[0], "album"))

            case QMSearchType.SONGLIST:
                table.setColumnCount(4)
                table.setHorizontalHeaderLabels(["歌单", "创建者", "创建时间", "歌曲数量"])
                table.set_proportions([0.6, 0.4, 2, 2])
                for songlist in result:
                    table.insertRow(table.rowCount())
                    table.setItem(table.rowCount() - 1, 0, QTableWidgetItem(songlist["name"]))
                    table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(songlist["creator"]))
                    table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(songlist["time"]))
                    table.setItem(table.rowCount() - 1, 3, QTableWidgetItem(str(songlist["count"])))

                table.setProperty("result_type", (result_type[0], "songlist"))

    def get_songlist_error(self, error: str) -> None:
        QMessageBox.warning(self, "警告", error)
        self.return_search_result()

    def show_songlist_result(self, result_type: str, result: list) -> None:
        """
        :param result_type: album或songlist
        """
        self.return_toolButton.setEnabled(True)
        if result_type == "album":
            self.update_result_table(("album", QMSearchType.SONG), result)
        elif result_type == "songlist":
            self.update_result_table(("songlist", QMSearchType.SONG), result)

        self.songlist_result = {"type": result_type, "result": result}

    def get_songlist_result(self, result_type: str, info: dict) -> None:
        """
        :param result_type: album或songlist
        """
        if result_type == "album":
            worker = GetSongListWorker(result_type, info['mid'])
        elif result_type == "songlist":
            worker = GetSongListWorker(result_type, info['id'])
        worker.signals.result.connect(self.show_songlist_result)
        worker.signals.error.connect(self.get_songlist_error)
        self.threadpool.start(worker)
        self.results_tableWidget.setRowCount(0)

    def select_results(self, index: QModelIndex) -> None:
        """结果表格元素被双击时调用"""
        row = index.row()  # 获取被双击的行
        table = self.results_tableWidget
        if table.property("result_type")[0] == "search":  # 如果结果表格显示的是搜索结果
            info = self.search_result["result"][row]
        elif table.property("result_type")[0] in ["album", "songlist"]:  # 如果结果表格显示的是专辑、歌单的列表
            info = self.songlist_result["result"][row]
        else:
            return

        if table.property("result_type")[1] == "songs":  # 如果结果表格显示的是歌曲
            self.update_preview_lyric(info)

        if table.property("result_type")[1] in ["album", "songlist"]:  # 如果结果表格显的是搜索结果的专辑、歌单
            self.get_songlist_result(table.property("result_type")[1], info)
