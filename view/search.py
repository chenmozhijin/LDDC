# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import os

from PySide6.QtCore import (
    QModelIndex,
    QThreadPool,
    Slot,
)
from PySide6.QtWidgets import (
    QFileDialog,
    QMessageBox,
    QTableWidgetItem,
    QWidget,
)

from ui.search_ui import Ui_search
from utils.data import data
from utils.enum import LyricsFormat, LyricsType, SearchType, Source
from utils.lyrics import Lyrics
from utils.utils import get_lyrics_format_ext, get_save_path, ms2formattime
from utils.worker import GetSongListWorker, LyricProcessingWorker, SearchWorker
from view.get_list_lyrics import GetListLyrics


class SearchWidget(QWidget, Ui_search):
    def __init__(self, main_window: QWidget, threadpool: QThreadPool) -> None:
        super().__init__()
        self.setupUi(self)
        self.return_toolButton.setEnabled(False)
        self.main_window = main_window
        self.data = data
        self.data_mutex = data.mutex
        self.threadpool = threadpool
        self.connect_signals()
        self.search_type = SearchType.SONG

        self.songlist_result = None
        self.reset_page_status()
        self.search_info = {'keyword': None, 'search_type': None, 'source': None, 'page': None}  # 搜索的信息
        self.search_result = None
        self.search_lyrics_result = None
        self.preview_info = None

        self.result_path = []  # 值为"search": 搜索、"songlist":歌曲列表(歌单、专辑)、"lyrics": 歌词搜索结果

        self.save_path_lineEdit.setText(self.data.cfg["default_save_path"])

        self.get_list_lyrics_box = GetListLyrics(self)

        self.taskid = {
            "results_table": 0,
            "update_preview_lyric": 0,
        }  # 用于防止旧任务的结果覆盖新任务的结果

    def connect_signals(self) -> None:
        self.select_path_pushButton.clicked.connect(self.select_savepath)
        self.save_preview_lyric_pushButton.clicked.connect(self.save_preview_lyric)
        self.save_list_lyrics_pushButton.clicked.connect(self.save_list_lyrics)

        self.search_pushButton.clicked.connect(self.search_button_clicked)
        self.search_type_comboBox.currentIndexChanged.connect(self.search_type_changed)
        self.results_tableWidget.doubleClicked.connect(self.select_results)

        self.translate_checkBox.stateChanged.connect(self.update_preview_lyric)
        self.romanized_checkBox.stateChanged.connect(self.update_preview_lyric)
        self.original_checkBox.stateChanged.connect(self.update_preview_lyric)
        self.lyricsformat_comboBox.currentTextChanged.connect(self.update_preview_lyric)

        self.return_toolButton.clicked.connect(self.result_return)

        self.results_tableWidget.verticalScrollBar().valueChanged.connect(self.results_table_scroll_changed)

    def get_lyric_type(self) -> list:
        """返回选择了的歌词类型的列表"""
        lyric_type = []
        if self.original_checkBox.isChecked():
            lyric_type.append('orig')
        if self.translate_checkBox.isChecked():
            lyric_type.append('ts')
        if self.romanized_checkBox.isChecked():
            lyric_type.append("roma")
        return lyric_type

    def get_source(self) -> Source:
        """返回选择了的源"""
        match self.source_comboBox.currentIndex():
            case 0:
                return Source.QM
            case 1:
                return Source.KG
            case 2:
                return Source.NE

    def save_list_lyrics(self) -> None:
        """保存专辑、歌单中的所有歌词"""
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
                self.get_list_lyrics_box.plainTextEdit.appendPlainText(error)
            else:
                save_path = result['save_path']
                save_folder = os.path.dirname(save_path)
                text += f"获取 {result['info']['title']} - {result['info']['artist']} 歌词成功"
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
                self.get_list_lyrics_box.pushButton.setText(self.tr("关闭"))
                self.get_list_lyrics_box.closed.connect(None)
                self.get_list_lyrics_box.pushButton.clicked.connect(self.get_list_lyrics_box.close)
                QMessageBox.information(self.main_window, self.tr("提示"), self.tr("获取歌词完成"))
                self.main_window.setDisabled(False)

        self.main_window.setDisabled(True)
        self.get_list_lyrics_box.ask_to_close = True
        self.get_list_lyrics_box.progressBar.setValue(0)
        self.get_list_lyrics_box.pushButton.setText(self.tr("取消"))
        self.get_list_lyrics_box.progressBar.setMaximum(len(self.songlist_result["result"]))
        self.get_list_lyrics_box.plainTextEdit.setPlainText("")
        self.get_list_lyrics_box.show()
        self.get_list_lyrics_box.setEnabled(True)

        worker = LyricProcessingWorker({"type": "get_list_lyrics",
                                        "song_info_list": self.songlist_result["result"],
                                        "lyric_type": self.get_lyric_type(),
                                        "lyrics_format": LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
                                        "save_folder": save_folder,
                                        "lyrics_file_name_format": lyrics_file_name_format,
                                        },
                                       self.data)
        worker.signals.result.connect(get_list_lyrics_update)
        worker.signals.error.connect(get_list_lyrics_update)
        self.threadpool.start(worker)

        def cancel_get_list_lyrics() -> None:
            self.get_list_lyrics_box.ask_to_close = False
            self.get_list_lyrics_box.pushButton.setText(self.tr("关闭"))
            self.get_list_lyrics_box.closed.connect(None)
            self.get_list_lyrics_box.pushButton.clicked.connect(self.get_list_lyrics_box.close)
            self.main_window.setDisabled(False)
            worker.stop()

        self.get_list_lyrics_box.pushButton.clicked.connect(cancel_get_list_lyrics)
        self.get_list_lyrics_box.closed.connect(cancel_get_list_lyrics)

    @Slot()
    def save_preview_lyric(self) -> None:
        """保存预览的歌词"""
        if self.preview_info is None or self.save_path_lineEdit.text() == "":
            QMessageBox.warning(self, '警告', '请先下载并预览歌词并选择保存路径')
            return

        if self.preview_plainTextEdit.toPlainText() == "":
            QMessageBox.warning(self, '警告', '歌词内容为空')
            return

        self.data_mutex.lock()
        type_mapping = {"原文": "orig", "译文": "ts", "罗马音": "roma"}
        lyrics_types = [type_mapping[type_] for type_ in self.data.cfg["lyrics_order"] if type_mapping[type_] in self.get_lyric_type()]
        # 获取已选择的歌词(用于替换占位符)
        save_folder, file_name = get_save_path(
            self.save_path_lineEdit.text(),
            self.data.cfg["lyrics_file_name_format"] + get_lyrics_format_ext(self.preview_info["info"]["lyrics_format"]),
            self.preview_info["info"],
            lyrics_types)

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

    @Slot(str)
    def search_type_changed(self, index: int) -> None:
        """搜索类型改变"""
        match index:
            case 0:
                self.search_type = SearchType.SONG
            case 1:
                self.search_type = SearchType.ALBUM
            case 2:
                self.search_type = SearchType.ARTIST
            case 3:
                self.search_type = SearchType.SONGLIST

    def result_return(self) -> None:
        """返回"""
        if self.search_result is not None and len(self.result_path) == 2 and self.result_path[0] == "search":
            self.taskid["results_table"] += 1
            self.result_path = self.result_path[:-2]  # 删两个,因为还要加一个
            search_type, result = self.search_result.values()
            self.search_result_slot(self.taskid["results_table"], search_type, result)
        elif self.songlist_result is not None and len(self.result_path) == 3 and self.result_path[1] == "songlist":
            self.taskid["results_table"] += 1
            self.result_path = self.result_path[:-1]  # 删一个
            result_type, result = self.songlist_result.values()
            self.show_songlist_result(self.taskid["results_table"], result_type, result)

        if len(self.result_path) <= 1:
            self.return_toolButton.setEnabled(False)
        else:
            self.return_toolButton.setEnabled(True)

    @Slot(int, SearchType, list)
    def search_result_slot(self, taskid: int, search_type: SearchType, result: list) -> None:
        """搜索结果槽函数"""
        if taskid != self.taskid["results_table"]:
            return
        self.search_pushButton.setText(self.tr('搜索'))
        self.search_pushButton.setEnabled(True)
        self.return_toolButton.setEnabled(False)
        self.update_result_table(("search", search_type), result)

        self.search_result = {"type": search_type, "result": result}
        self.result_path = ["search"]

    @Slot(str)
    def search_error_slot(self, error: str) -> None:
        """搜索错误时调用"""
        self.search_pushButton.setText(self.tr('搜索'))
        self.search_pushButton.setEnabled(True)
        QMessageBox.critical(self, self.tr("搜索错误"), error)

    @Slot()
    def search_button_clicked(self) -> None:
        """搜索按钮被点击"""
        self.reset_page_status()
        keyword = self.search_keyword_lineEdit.text()
        if keyword == "":
            QMessageBox.warning(self, self.tr("搜索错误"), self.tr("请输入搜索关键字"))
            return
        self.search_pushButton.setText('正在搜索...')
        self.search_pushButton.setEnabled(False)
        self.taskid["results_table"] += 1
        self.search_info = {'keyword': keyword, 'search_type': self.search_type, 'source': self.get_source(), 'page': 1}
        worker = SearchWorker(self.taskid["results_table"], keyword, self.search_type, self.get_source(), 1)
        worker.signals.result.connect(self.search_result_slot)
        worker.signals.error.connect(self.search_error_slot)
        self.threadpool.start(worker)
        self.results_tableWidget.setRowCount(0)
        self.results_tableWidget.setProperty("result_type", (None, None))

    @Slot(str)
    def update_preview_lyric_error_slot(self, error: str) -> None:
        """更新预览歌词错误时调用"""
        QMessageBox.critical(self, self.tr("获取预览歌词错误"), error)
        self.preview_plainTextEdit.setPlainText("")

    @Slot(int, dict)
    def update_preview_lyric_result_slot(self, taskid: int, result: dict) -> None:
        """更新预览歌词结果时调用"""
        def get_lrc_type(lrc: Lyrics, lrc_type: str) -> str:
            if lrc.lrc_types[lrc_type] == LyricsType.PlainText:
                return self.tr("纯文本")
            if lrc.lrc_isverbatim[lrc_type] is True:
                return self.tr("逐字")
            return self.tr("逐行")
        if taskid != self.taskid["update_preview_lyric"]:
            return
        self.preview_info = {"info": result["info"]}
        lyric_types_text = ""
        if "orig" in result['lrc'].lrc_types:
            lyric_types_text += self.tr("原文") + f"({get_lrc_type(result['lrc'], 'orig')})"
        if "ts" in result['lrc'].lrc_types:
            lyric_types_text += self.tr("、译文") + f"({get_lrc_type(result['lrc'], 'ts')})"
        if "roma" in result['lrc'].lrc_types:
            lyric_types_text += self.tr("、罗马音") + f"({get_lrc_type(result['lrc'], 'roma')})"
        self.lyric_types_lineEdit.setText(lyric_types_text)
        self.songid_lineEdit.setText(str(result['info']['id']))

        self.preview_plainTextEdit.setPlainText(result['merged_lyric'])

    def update_preview_lyric(self, info: dict | None = None) -> None:
        """开始更新预览歌词"""
        if not isinstance(info, dict) and self.preview_info is not None:
            info = self.preview_info["info"]
        elif not isinstance(info, dict) and self.preview_info is None:
            return

        self.taskid["update_preview_lyric"] += 1
        worker = LyricProcessingWorker(
            {"type": "get_merged_lyric",
             "song_info": info,
             "lyric_type": self.get_lyric_type(),
             "lyrics_format": LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
             "id": self.taskid["update_preview_lyric"]},
            self.data)
        worker.signals.result.connect(self.update_preview_lyric_result_slot)
        worker.signals.error.connect(self.update_preview_lyric_error_slot)
        self.threadpool.start(worker)

        self.preview_info = None
        self.preview_plainTextEdit.setPlainText(self.tr("处理中..."))

    def update_result_table(self, result_type: tuple, result: list, clear: bool = True) -> None:
        """
        更新结果表格
        :param result_type: 结果类型(结果类型, 搜索类型)
        :param result: 结果(列表)
        """
        table = self.results_tableWidget
        if clear:
            table.setRowCount(0)

        match result_type[1]:
            case SearchType.SONG:
                table.setColumnCount(4)
                table.setHorizontalHeaderLabels([self.tr("歌曲"), self.tr("艺术家"), self.tr("专辑"), self.tr("时长")])
                table.set_proportions([0.4, 0.2, 0.4, 2])

                for song in result:
                    table.insertRow(table.rowCount())
                    name = song['title'] + "(" + song["subtitle"] + ")" if song["subtitle"] != "" else song['title']

                    table.setItem(table.rowCount() - 1, 0, QTableWidgetItem(name))
                    table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(song["artist"]))
                    table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(song["album"]))
                    table.setItem(table.rowCount() - 1, 3, QTableWidgetItem('{:02d}:{:02d}'.format(*divmod(song['duration'], 60))))

                table.setProperty("result_type", (result_type[0], "songs"))

            case SearchType.ALBUM:
                table.setColumnCount(4)
                table.setHorizontalHeaderLabels([self.tr("专辑"), self.tr("艺术家"), self.tr("发行日期"), self.tr("歌曲数量")])
                table.set_proportions([0.6, 0.4, 2, 2])
                for album in result:
                    table.insertRow(table.rowCount())
                    table.setItem(table.rowCount() - 1, 0, QTableWidgetItem(album["name"]))
                    table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(album["artist"]))
                    table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(album["time"]))
                    table.setItem(table.rowCount() - 1, 3, QTableWidgetItem(str(album["count"])))

                table.setProperty("result_type", (result_type[0], "album"))

            case SearchType.SONGLIST:
                table.setColumnCount(4)
                table.setHorizontalHeaderLabels([self.tr("歌单"), self.tr("创建者"), self.tr("创建时间"), self.tr("歌曲数量")])
                table.set_proportions([0.6, 0.4, 2, 2])
                for songlist in result:
                    table.insertRow(table.rowCount())
                    table.setItem(table.rowCount() - 1, 0, QTableWidgetItem(songlist["name"]))
                    table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(songlist["creator"]))
                    table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(songlist["time"]))
                    table.setItem(table.rowCount() - 1, 3, QTableWidgetItem(str(songlist["count"])))

                table.setProperty("result_type", (result_type[0], "songlist"))

            case SearchType.LYRICS:
                table.setColumnCount(4)
                table.setHorizontalHeaderLabels(["id", self.tr("上传者"), self.tr("时长"), self.tr("分数")])
                table.set_proportions([2, 1, 2, 2])
                for lyric in result:
                    table.insertRow(table.rowCount())
                    table.setItem(table.rowCount() - 1, 0, QTableWidgetItem(str(lyric["id"])))
                    table.setItem(table.rowCount() - 1, 1, QTableWidgetItem(lyric["creator"]))
                    table.setItem(table.rowCount() - 1, 2, QTableWidgetItem(ms2formattime(int(lyric["duration"]))))
                    table.setItem(table.rowCount() - 1, 3, QTableWidgetItem(str(lyric["score"])))

                table.setProperty("result_type", (result_type[0], "lyrics"))

    @Slot(str)
    def get_songlist_error(self, error: str) -> None:
        """获取歌单、专辑中的歌曲错误时调用"""
        QMessageBox.critical(self, self.tr("错误"), error)
        self.result_return()

    @Slot(int, str, list)
    def show_songlist_result(self, taskid: int, result_type: str, result: list) -> None:
        """
        :param result_type: album或songlist
        """
        if taskid != self.taskid["results_table"]:
            return
        if result_type == "album":
            self.update_result_table(("album", SearchType.SONG), result)
        elif result_type == "songlist":
            self.update_result_table(("songlist", SearchType.SONG), result)

        self.songlist_result = {"type": result_type, "result": result}

    def get_songlist_result(self, result_type: str, info: dict) -> None:
        """
        获取歌单、专辑中的歌曲
        :param result_type: album或songlist
        """
        self.reset_page_status()
        self.results_tableWidget.setProperty("result_type", (None, None))  # 修复搜索结果翻页覆盖歌单、专辑结果
        self.return_toolButton.setEnabled(True)
        self.taskid["results_table"] += 1
        if result_type == "album":
            match info['source']:
                case Source.QM:
                    worker = GetSongListWorker(self.taskid["results_table"], result_type, info['mid'], info['source'])
                case Source.KG | Source.NE:
                    worker = GetSongListWorker(self.taskid["results_table"], result_type, info['id'], info['source'])
        elif result_type == "songlist":
            worker = GetSongListWorker(self.taskid["results_table"], result_type, info['id'], info['source'])
        worker.signals.result.connect(self.show_songlist_result)
        worker.signals.error.connect(self.get_songlist_error)
        self.threadpool.start(worker)
        self.results_tableWidget.setRowCount(0)
        self.result_path.append("songlist")

    @Slot(str)
    def search_lyrics_error_slot(self, error: str) -> None:
        """搜索歌词错误时调用"""
        QMessageBox.critical(self, self.tr("错误"), error)

    @Slot(int, SearchType, list)
    def search_lyrics_result_slot(self, taskid: int, _type: SearchType, result: list) -> None:
        if taskid != self.taskid["results_table"]:
            return
        if not result:
            # never
            QMessageBox.information(self, self.tr("提示"), self.tr("没有找到歌词"))
        elif len(result) == 1:
            self.update_preview_lyric(result[0])
        else:
            self.data_mutex.lock()
            auto_select = self.data.cfg['auto_select']
            self.data_mutex.unlock()
            if auto_select:
                self.update_preview_lyric(result[0])
            else:
                self.update_result_table(("lyrics", SearchType.LYRICS), result)
                self.search_lyrics_result = result
                self.result_path.append("lyrics")
                self.return_toolButton.setEnabled(True)

    def search_lyrics(self, info: dict) -> None:
        """搜索歌词(已经搜索了歌曲)"""
        if (info['source'] == Source.KG and info['language'] in ["纯音乐", '伴奏'] and
           QMessageBox.question(self, self.tr("提示"), self.tr("是否为纯音乐搜索歌词"), QMessageBox.Yes | QMessageBox.No, QMessageBox.No)) == QMessageBox.No:
            return
        self.reset_page_status()
        self.taskid["results_table"] += 1
        worker = SearchWorker(self.taskid["results_table"],
                              info,
                              SearchType.LYRICS, info['source'], 1)
        worker.signals.result.connect(self.search_lyrics_result_slot)
        worker.signals.error.connect(self.search_lyrics_error_slot)
        self.threadpool.start(worker)

    def select_results(self, index: QModelIndex) -> None:
        """结果表格元素被双击时调用"""
        row = index.row()  # 获取被双击的行
        table = self.results_tableWidget
        result_type = table.property("result_type")
        match result_type[0]:
            case "search":  # 如果结果表格显示的是搜索结果
                info = self.search_result["result"][row]
            case "album" | "songlist":  # 如果结果表格显示的是专辑、歌单的列表
                info = self.songlist_result["result"][row]
            case "lyrics":  # 如果结果表格显示的是歌词的搜索结果
                info = self.search_lyrics_result[row]
            case _:
                return

        match result_type[1]:
            case "songs":  # 如果结果表格显示的是歌曲
                match info["source"]:
                    case Source.QM | Source.NE:
                        self.update_preview_lyric(info)
                    case Source.KG:
                        self.search_lyrics(info)

            case "lyrics":
                self.update_preview_lyric(info)

            case "album" | "songlist":  # 如果结果表格显的是搜索结果的专辑、歌单
                self.get_songlist_result(result_type[1], info)

    def reset_page_status(self) -> None:
        """重置有关页码的状态(正在获取下一页、已获取所有页)"""
        self.get_next_page = False
        self.all_results_obtained = False

    @Slot(int, SearchType, list)
    def search_nextpage_result_slot(self, taskid: int, search_type: SearchType, result: list) -> None:
        if taskid != self.taskid["results_table"]:
            return
        self.get_next_page = False

        self.search_info['page'] += 1
        last_row = self.results_tableWidget.rowCount() - 1
        self.results_tableWidget.removeRow(last_row)

        self.update_result_table(("search", search_type), result, False)
        self.search_result["result"].extend(result)

    @Slot(str)
    def search_nextpage_error(self, error: str) -> None:
        self.get_next_page = False
        last_row = self.results_tableWidget.rowCount() - 1
        if error == "没有任何结果":
            self.all_results_obtained = True

            # 创建"没有更多结果"的 QTableWidgetItem
            nomore_item = QTableWidgetItem(self.tr("没有更多结果"))
            nomore_item.setTextAlignment(0x0004 | 0x0080)  # 设置水平和垂直居中对齐
            self.results_tableWidget.setItem(last_row, 0, nomore_item)
        else:
            self.results_tableWidget.removeRow(last_row)
            QMessageBox.critical(self, self.tr("错误"), error)

    def results_table_scroll_changed(self, value: int) -> None:
        # 判断是否已经滚动到了底部
        if value != self.results_tableWidget.verticalScrollBar().maximum():
            return

        # 更新列表(获取下一页)
        table = self.results_tableWidget
        result_type = table.property("result_type")
        if (result_type[0] == "search" and
            not self.get_next_page and
            self.search_result is not None and
                not self.all_results_obtained):
            self.get_next_page = True

            # 创建加载中的 QTableWidgetItem
            loading_item = QTableWidgetItem(self.tr("加载中..."))
            loading_item.setTextAlignment(0x0004 | 0x0080)  # 设置水平和垂直居中对齐

            # 设置合并单元格
            table.insertRow(table.rowCount())
            last_row = table.rowCount() - 1
            table.setSpan(last_row, 0, 1, table.columnCount())
            table.setItem(last_row, 0, loading_item)

            self.taskid["results_table"] += 1
            worker = SearchWorker(self.taskid["results_table"], self.search_info['keyword'], self.search_info['search_type'], self.search_info['source'], self.search_info['page'] + 1)
            worker.signals.result.connect(self.search_nextpage_result_slot)
            worker.signals.error.connect(self.search_nextpage_error)
            self.threadpool.start(worker)
