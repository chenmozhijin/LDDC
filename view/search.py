# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os
import re
from itertools import zip_longest
from typing import Any

from PySide6.QtCore import (
    QModelIndex,
    QSize,
    Qt,
    QTimer,
    Slot,
)
from PySide6.QtGui import (
    QDragEnterEvent,
    QDropEvent,
    QFont,
)
from PySide6.QtWidgets import QFileDialog, QHBoxLayout, QLabel, QLineEdit, QPushButton, QSizePolicy, QTableWidgetItem, QWidget

from backend.converter import convert2
from backend.lyrics import Lyrics
from backend.song_info import get_audio_file_infos, parse_cue_from_file
from backend.worker import AutoLyricsFetcher, GetSongListWorker, LyricProcessingWorker, SearchWorker
from ui.search_base_ui import Ui_search_base
from utils.data import cfg
from utils.enum import LyricsFormat, LyricsType, SearchType, Source
from utils.logger import logger
from utils.thread import threadpool
from utils.utils import get_artist_str, get_lyrics_format_ext, get_save_path, ms2formattime

from .get_list_lyrics import GetListLyrics
from .msg_box import MsgBox


class SearchWidgetBase(QWidget, Ui_search_base):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setupUi(self)
        self.connect_signals()
        self.search_type = SearchType.SONG

        self.songlist_result = None
        self.reset_page_status()
        self.search_info: dict[str, Any] | None = None  # 搜索的信息
        self.search_result = None
        self.search_lyrics_result = None
        self.preview_lyric_result = None

        self.result_path = []  # 值为"search": 搜索、"songlist":歌曲列表(歌单、专辑)、"lyrics": 歌词搜索结果

        self.taskid = {
            "results_table": 0,
            "update_preview_lyric": 0,
        }  # 用于防止旧任务的结果覆盖新任务的结果

    def connect_signals(self) -> None:
        self.search_keyword_lineEdit.returnPressed.connect(self.search)
        self.search_pushButton.clicked.connect(self.search)
        self.search_type_comboBox.currentIndexChanged.connect(self.search_type_changed)
        self.results_tableWidget.doubleClicked.connect(self.select_results)

        self.translate_checkBox.stateChanged.connect(self.update_preview_lyric)
        self.romanized_checkBox.stateChanged.connect(self.update_preview_lyric)
        self.original_checkBox.stateChanged.connect(self.update_preview_lyric)
        self.lyricsformat_comboBox.currentTextChanged.connect(self.update_preview_lyric)
        self.offset_spinBox.valueChanged.connect(self.update_preview_lyric)

        self.return_toolButton.clicked.connect(self.result_return)

        self.results_tableWidget.verticalScrollBar().valueChanged.connect(self.results_table_scroll_changed)
        self.results_tableWidget.verticalScrollBar().rangeChanged.connect(self.results_table_scroll_changed)

        cfg.lyrics_changed.connect(self.update_preview_lyric)

    def get_lyric_langs(self) -> list:
        """返回选择了的歌词类型的列表"""
        lyric_langs = []
        if self.original_checkBox.isChecked():
            lyric_langs.append('orig')
        if self.translate_checkBox.isChecked():
            lyric_langs.append('ts')
        if self.romanized_checkBox.isChecked():
            lyric_langs.append("roma")
        return lyric_langs

    def get_source(self) -> Source | list[Source]:
        """返回选择了的源"""
        match self.source_comboBox.currentIndex():
            case 0:
                return [Source.QM, Source.KG, Source.NE]
            case 1:
                return Source.QM
            case 2:
                return Source.KG
            case 3:
                return Source.NE
            case _:
                msg = "Invalid source"
                raise ValueError(msg)

    @Slot(str)
    def search_type_changed(self, index: int) -> None:
        """搜索类型改变"""
        match index:
            case 0:
                self.search_type = SearchType.SONG
            case 1:
                self.search_type = SearchType.ALBUM
            case 2:
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
        if not result:
            MsgBox.warning(self, self.tr("错误"), self.tr("没有搜索到相关结果"))
            return
        self.update_result_table(("search", search_type), result)

        self.search_result = {"type": search_type, "result": result}
        self.result_path = ["search"]
        QTimer.singleShot(100, self.results_table_scroll_changed)

    @Slot(str)
    def search_error_slot(self, error: str) -> None:
        """搜索错误时调用"""
        self.search_pushButton.setText(self.tr('搜索'))
        self.search_pushButton.setEnabled(True)
        MsgBox.critical(self, self.tr("错误"), error)

    @Slot()
    def search(self) -> None:
        """搜索按钮被点击"""
        self.reset_page_status()
        keyword = self.search_keyword_lineEdit.text()
        if keyword == "":
            MsgBox.warning(self, self.tr("错误"), self.tr("请输入搜索关键词"))
            return
        self.search_pushButton.setText(self.tr('正在搜索...'))
        self.search_pushButton.setEnabled(False)
        self.taskid["results_table"] += 1
        self.search_info = {'keyword': keyword, 'search_type': self.search_type, 'source': self.get_source(), 'page': 1}
        worker = SearchWorker(self.taskid["results_table"], keyword, self.search_type, self.get_source(), 1)
        worker.signals.result.connect(self.search_result_slot)
        worker.signals.error.connect(self.search_error_slot)
        threadpool.start(worker)
        self.results_tableWidget.setRowCount(0)
        self.results_tableWidget.setColumnCount(0)
        self.results_tableWidget.setProperty("result_type", (None, None))

    @Slot(str)
    def update_preview_lyric_error_slot(self, error: str) -> None:
        """更新预览歌词错误时调用"""
        MsgBox.critical(self, self.tr("获取预览歌词错误"), error)
        self.preview_plainTextEdit.setPlainText("")
        self.preview_lyric_result = None

    @Slot(int, dict)
    def update_preview_lyric_result_slot(self, taskid: int, result: dict) -> None:
        """更新预览歌词结果时调用"""
        def get_lrc_type(lrc: Lyrics, lrc_type: str) -> str:
            match lrc.types[lrc_type]:
                case LyricsType.PlainText:
                    return self.tr("纯文本")
                case LyricsType.VERBATIM:
                    return self.tr("逐字")
                case LyricsType.LINEBYLINE:
                    return self.tr("逐行")
                case _:
                    msg = f"Invalid LyricsType: {lrc.types[lrc_type]}"
                    raise ValueError(msg)

        if taskid != self.taskid["update_preview_lyric"]:
            return
        self.preview_lyric_result = {"info": result["info"], "lyrics": result["lyrics"]}
        lyric_langs_text = ""
        if "orig" in result['lyrics'].types:
            lyric_langs_text += self.tr("原文") + f"({get_lrc_type(result['lyrics'], 'orig')})"
        if "ts" in result['lyrics'].types:
            lyric_langs_text += self.tr("、译文") + f"({get_lrc_type(result['lyrics'], 'ts')})"
        if "roma" in result['lyrics'].types:
            lyric_langs_text += self.tr("、罗马音") + f"({get_lrc_type(result['lyrics'], 'roma')})"
        self.lyric_langs_lineEdit.setText(lyric_langs_text)
        if 'id' in result['info']:
            self.songid_lineEdit.setText(str(result['info']['id']))
        elif result["lyrics"].id is not None:
            self.songid_lineEdit.setText(str(result["lyrics"].id))
        else:
            self.songid_lineEdit.setText("")

        self.preview_plainTextEdit.setPlainText(result['converted_lyrics'])

    def update_preview_lyric(self, info: dict | None = None) -> None:
        """开始更新预览歌词"""
        if not isinstance(info, dict) and self.preview_lyric_result is not None:
            lyrics = self.preview_lyric_result["lyrics"]

            if isinstance(lyrics, Lyrics):
                # 直接在主线程更新还快一些
                self.taskid["update_preview_lyric"] += 1
                info = self.preview_lyric_result["info"]
                if info is not None:
                    info["lyrics_format"] = LyricsFormat(self.lyricsformat_comboBox.currentIndex())
                    result = {"info": self.preview_lyric_result["info"], 'lyrics': lyrics,
                              'converted_lyrics': convert2(lyrics,
                                                           self.get_lyric_langs(),
                                                           LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
                                                           self.offset_spinBox.value())}
                    self.update_preview_lyric_result_slot(self.taskid["update_preview_lyric"], result)
                    return
            info = self.preview_lyric_result["info"]
        elif not isinstance(info, dict) and self.preview_lyric_result is None:
            return

        self.taskid["update_preview_lyric"] += 1
        worker = LyricProcessingWorker(
            {"type": "get_converted_lyrics",
             "song_info": info,
             "lyric_langs": self.get_lyric_langs(),
             "lyrics_format": LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
             "id": self.taskid["update_preview_lyric"],
             "offset": self.offset_spinBox.value()})
        worker.signals.result.connect(self.update_preview_lyric_result_slot)
        worker.signals.error.connect(self.update_preview_lyric_error_slot)
        threadpool.start(worker)

        self.preview_lyric_result = None
        self.preview_plainTextEdit.setPlainText(self.tr("处理中..."))

    def update_result_table(self, result_type: tuple, result: list[dict], clear: bool = True) -> None:
        """更新结果表格

        :param result_type: 结果类型(结果类型, 搜索类型)
        :param result: 结果(列表)
        """
        table = self.results_tableWidget
        if clear:
            table.setRowCount(0)

        headers_proportions = {SearchType.SONG: ([self.tr("歌曲"), self.tr("艺术家"), self.tr("专辑"), self.tr("时长")], [0.4, 0.2, 0.4, 2]),
                               SearchType.ALBUM: ([self.tr("专辑"), self.tr("艺术家"), self.tr("发行日期"), self.tr("歌曲数量")], [0.6, 0.4, 2, 2]),
                               SearchType.SONGLIST: ([self.tr("歌单"), self.tr("创建者"), self.tr("歌曲数量"), self.tr("创建时间")], [0.6, 0.4, 2, 2]),
                               SearchType.LYRICS: ([self.tr("歌曲"), self.tr("艺术家"), self.tr("专辑"), self.tr("时长")], [0.4, 0.2, 0.4, 2])}

        show_source = bool(result_type[0] == "search" and self.search_info and isinstance(self.search_info["source"], list))

        headers = headers_proportions[result_type[1]][0] + ([self.tr("来源")] if show_source else [])
        table.setColumnCount(len(headers))
        table.setHorizontalHeaderLabels(headers)
        table.set_proportions(headers_proportions[result_type[1]][1] + ([2] if show_source else []))

        def add_items(texts: list[str]) -> None:
            table.insertRow(table.rowCount())
            for i, text in enumerate(texts):
                table.setItem(table.rowCount() - 1, i, QTableWidgetItem(text))
            if len(texts) != table.columnCount():
                msg = "texts length not equal to column count"
                raise ValueError(msg)

        match result_type[1]:
            case SearchType.SONG:

                for song in result:
                    name = song['title'] + "(" + song["subtitle"] + ")" if song["subtitle"] != "" else song['title']
                    artist = "/".join(song["artist"]) if isinstance(song["artist"], list) else song["artist"]

                    add_items([name, artist, song["album"], '{:02d}:{:02d}'.format(*divmod(song['duration'], 60))] +
                              ([str(song["source"])] if show_source else []))

                table.setProperty("result_type", (result_type[0], "songs"))

            case SearchType.ALBUM:
                for album in result:
                    add_items([album["name"], album["artist"], album["time"], str(album["count"])] + ([str(album["source"])] if show_source else []))

                table.setProperty("result_type", (result_type[0], "album"))

            case SearchType.SONGLIST:
                for songlist in result:
                    add_items([songlist["name"], songlist["creator"], songlist["time"], str(songlist["count"])] +
                              ([str(songlist["source"])] if show_source else []))

                table.setProperty("result_type", (result_type[0], "songlist"))

            case SearchType.LYRICS:
                for lyric in result:
                    add_items([str(lyric["id"]), lyric["creator"], ms2formattime(int(lyric["duration"])), str(lyric["score"])] +
                              ([str(lyric["source"])] if show_source else []))

                table.setProperty("result_type", (result_type[0], "lyrics"))

    @Slot(str)
    def get_songlist_error(self, error: str) -> None:
        """获取歌单、专辑中的歌曲错误时调用"""
        MsgBox.critical(self, self.tr("错误"), error)
        self.result_return()

    @Slot(int, str, list)
    def show_songlist_result(self, taskid: int, result_type: str, result: list) -> None:
        """显示歌单、专辑中的歌曲

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
        """获取歌单、专辑中的歌曲

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
                case _:
                    msg = "Unknown source"
                    raise ValueError(msg)
        elif result_type == "songlist":
            worker = GetSongListWorker(self.taskid["results_table"], result_type, info['id'], info['source'])
        else:
            msg = "Unknown result_type"
            raise ValueError(msg)
        worker.signals.result.connect(self.show_songlist_result)
        worker.signals.error.connect(self.get_songlist_error)
        threadpool.start(worker)
        self.results_tableWidget.setRowCount(0)
        self.results_tableWidget.setColumnCount(0)
        self.result_path.append("songlist")

    @Slot(str)
    def search_lyrics_error_slot(self, error: str) -> None:
        """搜索歌词错误时调用"""
        MsgBox.critical(self, self.tr("错误"), error)

    @Slot(int, SearchType, list)
    def search_lyrics_result_slot(self, taskid: int, _type: SearchType, result: list) -> None:
        if taskid != self.taskid["results_table"]:
            return
        if not result:
            # never
            MsgBox.information(self, self.tr("提示"), self.tr("没有找到歌词"))
        elif len(result) == 1:
            self.update_preview_lyric(result[0])
        else:
            auto_select = cfg['auto_select']
            if auto_select:
                self.update_preview_lyric(result[0])
            else:
                self.update_result_table(("lyrics", SearchType.LYRICS), result)
                self.search_lyrics_result = result
                self.result_path.append("lyrics")
                self.return_toolButton.setEnabled(True)

    def search_lyrics(self, info: dict) -> None:
        """搜索歌词(已经搜索了歌曲)"""
        self.reset_page_status()
        self.taskid["results_table"] += 1
        worker = SearchWorker(self.taskid["results_table"],
                              f"{get_artist_str(info.get('artist')), '、'} - {info['title'].strip()}",
                              SearchType.LYRICS, info['source'], 1, info)
        worker.signals.result.connect(self.search_lyrics_result_slot)
        worker.signals.error.connect(self.search_lyrics_error_slot)
        threadpool.start(worker)

    def select_results(self, index: QModelIndex) -> None:
        """结果表格元素被双击时调用"""
        row = index.row()  # 获取被双击的行
        table = self.results_tableWidget
        result_type = table.property("result_type")
        match result_type[0]:
            case "search":  # 如果结果表格显示的是搜索结果
                if not self.search_result:
                    return
                info = self.search_result["result"][row]
            case "album" | "songlist":  # 如果结果表格显示的是专辑、歌单的列表
                if not self.songlist_result:
                    return
                info = self.songlist_result["result"][row]
            case "lyrics":  # 如果结果表格显示的是歌词的搜索结果
                if not self.search_lyrics_result:
                    return
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
        if taskid != self.taskid["results_table"] or not self.search_info or not self.search_result:
            return
        self.get_next_page = False

        last_row = self.results_tableWidget.rowCount() - 1
        if not result:
            self.all_results_obtained = True

            # 创建"没有更多结果"的 QTableWidgetItem
            nomore_item = QTableWidgetItem(self.tr("没有更多结果"))
            nomore_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)  # 设置水平和垂直居中对齐
            self.results_tableWidget.setItem(last_row, 0, nomore_item)
        else:
            self.search_info['page'] += 1
            self.results_tableWidget.removeRow(last_row)

            self.update_result_table(("search", search_type), result, False)
            self.search_result["result"].extend(result)

    @Slot(str)
    def search_nextpage_error(self, error: str) -> None:
        self.get_next_page = False
        last_row = self.results_tableWidget.rowCount() - 1
        self.results_tableWidget.removeRow(last_row)
        MsgBox.critical(self, self.tr("错误"), error)

    def results_table_scroll_changed(self) -> None:
        # 判断是否已经滚动到了底部或消失
        results_table_scroll = self.results_tableWidget.verticalScrollBar()

        value = results_table_scroll.value()
        max_value = results_table_scroll.maximum()
        if value == max_value:

            # 更新列表(获取下一页)
            table = self.results_tableWidget
            result_type = table.property("result_type")
            if (result_type[0] == "search" and
                not self.get_next_page and
                self.search_result is not None and
                not self.all_results_obtained and
                self.search_info and
                    table.rowCount() > 0):
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
                worker = SearchWorker(self.taskid["results_table"],
                                      self.search_info['keyword'],
                                      self.search_info['search_type'],
                                      self.search_info['source'],
                                      self.search_info['page'] + 1)
                worker.signals.result.connect(self.search_nextpage_result_slot)
                worker.signals.error.connect(self.search_nextpage_error)
                threadpool.start(worker)


class SearchWidget(SearchWidgetBase):
    def __init__(self, main_window: QWidget) -> None:
        super().__init__()
        self.setup_ui()
        self.resize(1050, 600)
        self.select_path_pushButton.clicked.connect(self.select_savepath)
        self.save_preview_lyric_pushButton.clicked.connect(self.save_preview_lyric)
        self.save_list_lyrics_pushButton.clicked.connect(self.save_list_lyrics)
        self.main_window = main_window
        self.setAcceptDrops(True)  # 启用拖放功能

    def setup_ui(self) -> None:

        # 设置标题
        title_font = QFont()
        title_font.setPointSize(18)
        self.label_title = QLabel(self)
        self.label_sub_title = QLabel(self)
        self.label_title.setFont(title_font)

        self.verticalLayout.insertWidget(0, self.label_title)
        self.verticalLayout.insertWidget(1, self.label_sub_title)

        # 设置选择保存路径
        self.select_path_lhorizontalLayout = QHBoxLayout()
        self.select_path_label = QLabel(self)
        self.save_path_lineEdit = QLineEdit(self)
        self.save_path_lineEdit.setText(cfg["default_save_path"])
        self.select_path_pushButton = QPushButton(self)

        self.select_path_lhorizontalLayout.addWidget(self.select_path_label)
        self.select_path_lhorizontalLayout.addWidget(self.save_path_lineEdit)
        self.select_path_lhorizontalLayout.addWidget(self.select_path_pushButton)
        self.control_verticalLayout.insertLayout(0, self.select_path_lhorizontalLayout)

        # 设置保存按钮
        self.save_preview_lyric_pushButton = QPushButton(self)
        self.save_list_lyrics_pushButton = QPushButton(self)
        save_button_size_policy = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        save_button_size_policy.setHorizontalStretch(0)
        save_button_size_policy.setVerticalStretch(0)
        save_button_size_policy.setHeightForWidth(self.save_preview_lyric_pushButton.sizePolicy().hasHeightForWidth())
        self.save_preview_lyric_pushButton.setSizePolicy(save_button_size_policy)
        self.save_list_lyrics_pushButton.setSizePolicy(save_button_size_policy)

        but_h = self.control_verticalLayout.sizeHint().height() - self.control_verticalSpacer.sizeHint().height() * 0.8

        self.save_preview_lyric_pushButton.setMinimumSize(QSize(0, int(but_h)))
        self.save_list_lyrics_pushButton.setMinimumSize(QSize(0, int(but_h)))

        self.bottom_horizontalLayout.addWidget(self.save_list_lyrics_pushButton)
        self.bottom_horizontalLayout.addWidget(self.save_preview_lyric_pushButton)

        self.retranslateUi()

    def retranslateUi(self, search_base: SearchWidgetBase | None = None) -> None:
        super().retranslateUi(self)
        if search_base is not None:
            return
        self.label_title.setText(self.tr("搜索"))
        self.label_sub_title.setText(self.tr("从云端搜索并下载歌词"))

        self.select_path_label.setText(self.tr("保存到:"))
        self.select_path_pushButton.setText(self.tr("选择保存路径"))

        self.save_preview_lyric_pushButton.setText(self.tr("保存预览歌词"))
        self.save_list_lyrics_pushButton.setText(self.tr("保存专辑/歌单的歌词"))

    def save_list_lyrics(self) -> None:
        """保存专辑、歌单中的所有歌词"""
        result_type = self.results_tableWidget.property("result_type")
        if (result_type is None or
            result_type[0] not in ["album", "songlist"] or
                not self.songlist_result):
            MsgBox.warning(self, self.tr('警告'), self.tr('请先选择一个专辑或歌单'))
            return

        lyrics_file_name_fmt = cfg["lyrics_file_name_fmt"]
        save_folder = self.save_path_lineEdit.text()

        worker = LyricProcessingWorker({"type": "get_list_lyrics",
                                        "song_info_list": self.songlist_result["result"],
                                        "lyric_langs": self.get_lyric_langs(),
                                        "lyrics_format": LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
                                        "save_folder": save_folder,
                                        "lyrics_file_name_fmt": lyrics_file_name_fmt,
                                        })

        def pushButton_clicked_slot() -> None:
            if worker.is_running:
                worker.stop()
                set_no_running()
            else:
                self.get_list_lyrics_box.close()

        def set_no_running() -> None:
            self.get_list_lyrics_box.pushButton.setText(self.tr("关闭"))
            self.get_list_lyrics_box.ask_to_close = False

        def get_list_lyrics_update(count: int | str, result: dict | None = None) -> None:
            text = ""
            if result is None or isinstance(count, str):
                error = count[:] if isinstance(count, str) else ""
                count = self.get_list_lyrics_box.progressBar.value() + 1
                self.get_list_lyrics_box.plainTextEdit.appendPlainText(error)
            elif result:
                save_path = result['save_path']
                save_folder = os.path.dirname(save_path)
                text += self.tr("获取 {0} 歌词成功").format(f"{result['info']['title']} - {get_artist_str(result['info']['artist'])}")
                if result['inst']:  # 检查是否为纯音乐,并且设置跳过纯音乐
                    text += self.tr("但歌曲为纯音乐,已跳过")
                else:
                    # 保存
                    try:
                        if not os.path.exists(save_folder):
                            os.makedirs(save_folder)
                        with open(save_path, 'w', encoding='utf-8') as f:
                            f.write(result['converted_lyrics'])
                    except Exception as e:
                        text += self.tr("但保存歌词失败,原因:") + str(e)
                    else:
                        text += self.tr(",保存到") + save_path
                self.get_list_lyrics_box.plainTextEdit.appendPlainText(text)

            self.get_list_lyrics_box.progressBar.setValue(count)

            if count == self.get_list_lyrics_box.progressBar.maximum():
                set_no_running()
                MsgBox.information(self.main_window, self.tr("提示"), self.tr("获取歌词完成"))

        self.get_list_lyrics_box = GetListLyrics(self)
        self.main_window.setEnabled(False)
        self.get_list_lyrics_box.ask_to_close = True
        self.get_list_lyrics_box.progressBar.setValue(0)
        self.get_list_lyrics_box.pushButton.setText(self.tr("取消"))
        self.get_list_lyrics_box.pushButton.clicked.connect(pushButton_clicked_slot)
        self.get_list_lyrics_box.closed.connect(lambda: self.main_window.setEnabled(True))
        self.get_list_lyrics_box.progressBar.setMaximum(len(self.songlist_result["result"]))
        self.get_list_lyrics_box.plainTextEdit.setPlainText("")
        self.get_list_lyrics_box.show()
        self.get_list_lyrics_box.setEnabled(True)

        worker.signals.result.connect(get_list_lyrics_update)
        worker.signals.error.connect(get_list_lyrics_update)
        threadpool.start(worker)

    @Slot()
    def save_preview_lyric(self) -> None:
        """保存预览的歌词"""
        if self.preview_lyric_result is None or self.save_path_lineEdit.text() == "":
            MsgBox.warning(self, self.tr('警告'), self.tr('请先下载并预览歌词并选择保存路径'))
            return

        if self.preview_plainTextEdit.toPlainText() == "":
            MsgBox.warning(self, self.tr('警告'), self.tr('歌词内容为空'))
            return

        lyric_langs = [lang for lang in cfg["langs_order"] if lang in self.get_lyric_langs()]
        # 获取已选择的歌词(用于替换占位符)
        save_folder, file_name = get_save_path(
            self.save_path_lineEdit.text(),
            cfg["lyrics_file_name_fmt"] + get_lyrics_format_ext(self.preview_lyric_result["info"]["lyrics_format"]),
            self.preview_lyric_result["info"],
            lyric_langs)

        save_path = os.path.join(save_folder, file_name)
        try:
            if not os.path.exists(save_folder):
                os.makedirs(save_folder)
            with open(save_path, 'w', encoding='utf-8') as f:
                f.write(self.preview_plainTextEdit.toPlainText())
            MsgBox.information(self, self.tr('提示'), self.tr('歌词保存成功'))
        except Exception as e:
            MsgBox.warning(self, self.tr('警告'), self.tr('歌词保存失败：') + str(e))

    @Slot()
    def select_savepath(self) -> None:
        def file_selected(save_path: str) -> None:
            self.save_path_lineEdit.setText(os.path.normpath(save_path))
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择保存路径"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.fileSelected.connect(file_selected)
        dialog.open()

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        if event.mimeData().hasUrls():
            event.acceptProposedAction()  # 接受拖动操作
        else:
            event.ignore()

    def dropEvent(self, event: QDropEvent) -> None:
        # 获取拖动的文件信息
        mime = event.mimeData()

        path, track, index = None, None, None
        # 特殊适配
        if 'application/x-qt-windows-mime;value="ACL.FileURIs"' in mime.formats():
            # AIMP
            data = mime.data('application/x-qt-windows-mime;value="ACL.FileURIs"')
            path = bytearray(data.data()[20:-4]).decode('UTF-16')
            if path.split(":")[-1].isdigit():
                index = path.split(":")[-1]
                path = ":".join(path.split(":")[:-1])
        elif ('text/plain' in mime.formats() and
              # foobar2000
              (matched := re.fullmatch(r"(?:(?P<artist>.*?) - )?\[(?P<album>.*?) (?:CD\d+/\d+ )?#(?P<track>\d+)\] (?P<title>.*)", mime.text())) is not None):
            track = matched.group('track')

        if not path:
            try:
                path = mime.urls()[0].toLocalFile()
            except Exception as e:
                logger.exception(e)
                MsgBox.critical(self, "错误", "无法获取文件路径")
                return
        if path.lower().endswith('.cue') and (isinstance(track, str | int) or index is not None):
            try:
                songs, _audio_file_paths = parse_cue_from_file(path)
            except Exception as e:
                MsgBox.critical(self, "错误", f"解析文件 {path} 失败: {e}")
                return
            if index is not None:
                if int(index) + 1 >= len(songs):
                    MsgBox.critical(self, "错误", f"文件 {path} 中没有找到第 {index} 轨歌曲")
                    return
                song = songs[int(index)]
            elif isinstance(track, str | int):
                for song in songs:
                    if song["track"] is not None and int(song["track"]) == int(track):
                        break
                else:
                    MsgBox.critical(self, "错误", f"文件 {path} 中没有找到第 {track} 轨歌曲")
                    return
        else:
            try:
                songs = get_audio_file_infos(path)
                if len(songs) == 1:
                    song = songs[0]
                elif isinstance(track, str | int):
                    for song in songs:
                        if song["track"] is not None and int(song["track"]) == int(track):
                            break
                    else:
                        MsgBox.critical(self, "错误", f"文件 {path} 中没有找到第 {track} 轨歌曲")
                        return
                else:
                    MsgBox.critical(self, "错误", f"文件 {path} 中包含多个歌曲")
            except Exception as e:
                logger.exception(e)
                MsgBox.critical(self, "错误", f"解析文件 {path} 失败: {e}")
                return

        if not song['title']:
            MsgBox.warning(self, "警告", "没有获取到歌曲标题,无法自动搜索")

        worker = AutoLyricsFetcher(song, taskid=tuple(self.taskid.values()), return_search_result=True)
        worker.signals.result.connect(self.auto_fetch_slot)
        threadpool.start(worker)
        self.preview_lyric_result = None
        self.preview_plainTextEdit.setPlainText(self.tr("正在自动获取 {0} 的歌词...").format(
            f"{song['artist']} - {song['title']}" if song['artist'] and len(song['title']) * 2 > len(song['artist']) else song['title']))

    def auto_fetch_slot(self, result: dict) -> None:
        if result.get("taskid") != tuple(self.taskid.values()):
            if result.get("taskid", (0, -1))[1] == self.taskid["update_preview_lyric"]:
                self.preview_plainTextEdit.setPlainText("")
            return

        if result.get("status") == "成功":
            self.preview_lyric_result = {"info": result["result_info"], "lyrics": result["lyrics"]}
            self.update_preview_lyric()

            self.reset_page_status()
            self.source_comboBox.setCurrentIndex(0)
            self.search_type_comboBox.setCurrentIndex(0)
            search_result: dict[Source, tuple[str, list[dict]]] = result["search_result"]
            keyword = search_result[result["result_info"]["source"]][0]
            self.search_info = {'keyword': keyword, 'search_type': SearchType.SONG, 'source': list(search_result.keys()), 'page': 1}
            self.search_keyword_lineEdit.setText(keyword)
            self.search_result_slot(self.taskid["results_table"], SearchType.SONG,
                                    [result["result_info"],
                                     *[item for group in zip_longest(*(k_i[1] for k_i in search_result.values())) for item in group
                                       if item is not None and item != result["result_info"]]])
            self.results_tableWidget.selectRow(0)

        else:
            MsgBox.critical(self, "错误", result["status"])
