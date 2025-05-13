# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os
from pathlib import Path
from typing import Literal

from PySide6.QtCore import QModelIndex, QSize, Qt, QTimer, Slot
from PySide6.QtGui import QDragEnterEvent, QDropEvent, QFont
from PySide6.QtWidgets import QFileDialog, QHBoxLayout, QLabel, QLineEdit, QPushButton, QSizePolicy, QTableWidgetItem, QWidget

from LDDC.common.data.config import cfg
from LDDC.common.models import (
    APIResultList,
    Language,
    LyricInfo,
    Lyrics,
    LyricsData,
    LyricsFormat,
    LyricsType,
    SearchInfo,
    SearchType,
    SongInfo,
    SongListInfo,
    SongListType,
    Source,
)
from LDDC.common.task_manager import TaskManager, create_collecting_callbacks
from LDDC.common.utils import save2fomat_path
from LDDC.core.api.lyrics import get_lyrics, get_lyricslist, get_songlist, search
from LDDC.core.api.translate import translate_lyrics
from LDDC.core.auto_fetch import auto_fetch
from LDDC.core.song_info import audio_formats, parse_drop_infos, write_lyrics
from LDDC.gui.components.msg_box import MsgBox
from LDDC.gui.ui.search_base_ui import Ui_search_base
from LDDC.gui.view.get_list_lyrics import GetListLyrics


class SearchWidgetBase(QWidget, Ui_search_base):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setupUi(self)

        self._init_task_manager()
        self._connect_signals()

        self.path: list[APIResultList | None] = []  # 页面路径
        self.lyrics: None | Lyrics = None

        self.update_search_types()


    def _init_task_manager(self) -> None:
        def restore_search() -> None:
            self.search_pushButton.setText(self.tr("搜索"))
            self.search_pushButton.setEnabled(True)

            if self.results_tableWidget.rowCount() == 0 and self.path and self.path[-1] is not None:
                MsgBox.warning(self, self.tr("错误"), self.tr("没有搜索到相关结果"))
            elif self.path and self.path[-1] is not None:
                QTimer.singleShot(100, self._check_search_more)

        self.task_manager = TaskManager(
            parent_childs={
                "table": ["search", "search_more", "get_lyricslist", "get_songlist"],
                "search": [],
                "search_more": [],
                "get_lyrics": ["translate"],
                "get_songlist": [],
                "get_lyricslist": [],
                "translate": [],
            },
            task_callback={
                "search": restore_search,
            },
        )

    def _connect_signals(self) -> None:
        self.search_keyword_lineEdit.returnPressed.connect(self.search)
        self.search_pushButton.clicked.connect(self.search)

        self.translate_checkBox.stateChanged.connect(lambda: self.set_lyrics())
        self.romanized_checkBox.stateChanged.connect(lambda: self.set_lyrics())
        self.original_checkBox.stateChanged.connect(lambda: self.set_lyrics())
        self.lyricsformat_comboBox.currentTextChanged.connect(lambda: self.set_lyrics())
        self.offset_spinBox.valueChanged.connect(lambda: self.set_lyrics())
        cfg.lyrics_changed.connect(lambda: self.set_lyrics())

        self.results_tableWidget.verticalScrollBar().valueChanged.connect(self._check_search_more)
        self.results_tableWidget.verticalScrollBar().rangeChanged.connect(self._check_search_more)

        self.results_tableWidget.doubleClicked.connect(self.open_table_item)

        self.return_toolButton.clicked.connect(self.table_return)

        self.translate_pushButton.clicked.connect(self.translate_lyrics)

        self.source_comboBox.currentIndexChanged.connect(self.update_search_types)

    @Slot()
    def update_search_types(self) -> None:
        """更新搜索类型"""
        type_str_map = {
            SearchType.SONG: self.tr("单曲"),
            SearchType.ALBUM: self.tr("专辑"),
            SearchType.SONGLIST: self.tr("歌单"),
            SearchType.ARTIST: self.tr("歌手"),
            SearchType.LYRICS: self.tr("歌词"),
        }
        self.search_type_comboBox.clear()
        for seatch_type in Source(self.source_comboBox.currentIndex()).supported_search_types:
            self.search_type_comboBox.addItem(type_str_map[seatch_type])

        self.search_type_comboBox.setCurrentIndex(0)

    @property
    def langs(self) -> list[str]:
        """返回选择了的歌词类型的列表"""
        return [
            lang
            for checkbox, lang in [
                (self.original_checkBox, "orig"),
                (self.translate_checkBox, "ts"),
                (self.romanized_checkBox, "roma"),
            ]
            if checkbox.isChecked()
        ]

    def get_source(self) -> list[Source]:
        """返回选择了的源"""
        index = self.source_comboBox.currentIndex()
        return [Source[source] for source in cfg["multi_search_sources"]] if index == 0 else [Source(index)]

    @Slot()
    def search(self) -> None:
        """搜索"""
        keyword = self.search_keyword_lineEdit.text()
        if keyword == "":
            MsgBox.warning(self, self.tr("提示"), self.tr("请输入搜索关键词"))
            return
        # 获取搜索源
        orig_sources = self.get_source()
        if not orig_sources:
            MsgBox.critical(self, self.tr("错误"), self.tr("请选择搜索源"))
            return
        # 获取选择的搜索类型
        search_type = SearchType(self.search_type_comboBox.currentIndex())
        sources = [source for source in orig_sources if search_type in source.supported_search_types]
        if not sources:
            if len(orig_sources) == 1:
                MsgBox.critical(self, self.tr("错误"), self.tr(f"{orig_sources[0].name} 不支持 {search_type.name} 搜索"))
            else:
                MsgBox.critical(self, self.tr("错误"), self.tr(f"所选源都不支持 {search_type.name} 搜索"))
            return
        # 设置搜索按钮文本为“正在搜索...”并禁用按钮
        self.search_pushButton.setText(self.tr("正在搜索..."))
        self.search_pushButton.setEnabled(False)

        callback, error_handling = create_collecting_callbacks(len(sources), self.add2table, MsgBox.get_error_slot(self, msg=self.tr("搜索失败")))
        self.task_manager.clear_task("table")
        # 对每个搜索源执行搜索操作
        for source in sources:
            self.task_manager.new_multithreaded_task(
                "search",  # 当前任务类型
                search,  # 搜索函数
                callback,  # 成功回调函数
                error_handling,  # 错误回调函数
                source,  # 当前搜索源
                keyword,  # 搜索关键词
                search_type,  # 搜索类型
            )
        self.path = [None]  # 初始化路径
        self.check_return()
        # 清除表格
        self.results_tableWidget.setRowCount(0)
        self.results_tableWidget.setColumnCount(0)

    def add2table(self, result: APIResultList) -> None:
        """将搜索结果添加到表格中"""
        if self.path[-1] is not None:
            self.path[-1] = self.path[-1] + result
        else:
            self.path[-1] = result

        table = self.results_tableWidget

        headers_proportions = {
            "song": ([self.tr("歌曲"), self.tr("艺术家"), self.tr("专辑"), self.tr("时长")], [0.4, 0.2, 0.4, 2]),
            "album": ([self.tr("专辑"), self.tr("艺术家"), self.tr("发行日期"), self.tr("歌曲数量")], [0.6, 0.4, 2, 2]),
            "songlist": ([self.tr("歌单"), self.tr("创建者"), self.tr("歌曲数量"), self.tr("创建时间")], [0.6, 0.4, 2, 2]),
            "lyric": ([self.tr("id"), self.tr("创建者"), self.tr("时长"), self.tr("评分")], [0.4, 0.2, 0.4, 2]),
        }
        header_type = "song"
        show_source = False
        if isinstance(result.info, SearchInfo):
            match result.info.search_type:
                case SearchType.ALBUM:
                    header_type = "album"
                case SearchType.SONGLIST:
                    header_type = "songlist"
            if len(self.path[-1].sources) > 1:
                show_source = True
        if isinstance(result.info, LyricInfo):
            header_type = "lyric"

        headers = headers_proportions[header_type][0] + ([self.tr("来源")] if show_source else [])
        table.setColumnCount(len(headers))
        table.setHorizontalHeaderLabels(headers)
        table.set_proportions(headers_proportions[header_type][1] + ([2] if show_source else []))

        if len(result) == 0:
            return

        def add_items(*texts: str, source: Source | None = None) -> None:
            table.insertRow(table.rowCount())
            if show_source:
                table.setItem(table.rowCount() - 1, table.columnCount() - 1, QTableWidgetItem(str(source)))
            for i, text in enumerate(texts):
                table.setItem(table.rowCount() - 1, i, QTableWidgetItem(text))
            if (len(texts) + 1 if show_source else len(texts)) != table.columnCount():
                msg = "文本数量与列数不匹配"
                raise ValueError(msg)

        if isinstance(result[0], SongInfo):
            for song in result:
                song: SongInfo
                add_items(song.full_title, str(song.artist), song.album if song.album else "", song.format_duration, source=song.source)
        elif isinstance(result[0], SongListInfo):
            if result[0].type == SongListType.ALBUM:
                # 专辑
                for songlist in result:
                    songlist: SongListInfo
                    add_items(
                        songlist.title,
                        songlist.author,
                        songlist.format_publishtime,
                        str(songlist.songcount) if songlist.songcount else "",
                        source=songlist.source,
                    )
            else:
                # 歌单
                for songlist in result:
                    songlist: SongListInfo
                    add_items(
                        songlist.title,
                        songlist.author,
                        str(songlist.songcount) if songlist.songcount else "",
                        songlist.format_publishtime,
                        source=songlist.source,
                    )

        elif isinstance(result[0], LyricInfo):
            for lyric in result:
                lyric: LyricInfo
                add_items(
                    lyric.id if lyric.id else "",
                    lyric.creator if lyric.creator else "",
                    lyric.format_duration,
                    str(lyric.score) if lyric.score else "",
                    source=lyric.source,
                )
        else:
            msg = "未知类型"
            raise TypeError(msg)

    def set_lyrics(self, lyrics: Lyrics | None = None) -> None:
        if lyrics is not None:
            self.lyrics = lyrics
        if not self.lyrics:
            return

        lyric_type_mapping = {
            LyricsType.PlainText: self.tr("纯文本"),
            LyricsType.VERBATIM: self.tr("逐字"),
            LyricsType.LINEBYLINE: self.tr("逐行"),
        }
        lyric_types_order = [
            ("orig", self.tr("原文")),
            ("ts", self.tr("译文")),
            ("roma", self.tr("罗马音")),
        ]

        # 构建歌词语言类型文本
        lyric_parts = []
        for key, label in lyric_types_order:
            if key in self.lyrics.types:
                try:
                    type_name = lyric_type_mapping[self.lyrics.types[key]]
                except KeyError as e:
                    msg = f"无效的歌词类型: {e}"
                    raise ValueError(msg) from None
                lyric_parts.append(f"{label}({type_name})")

        self.lyric_langs_lineEdit.setText(self.tr("、").join(lyric_parts))
        self.songid_lineEdit.setText(str(self.lyrics.id) if self.lyrics.id is not None else "")
        if (
            lyrics_text := self.lyrics.to(LyricsFormat(self.lyricsformat_comboBox.currentIndex()), self.langs, self.offset_spinBox.value())
        ) and lyrics_text != self.preview_plainTextEdit.toPlainText():
            self.preview_plainTextEdit.setPlainText(lyrics_text)

        self.update_translate_button_state()

    def check_return(self) -> bool:
        if len(self.path) > 1:
            self.return_toolButton.setEnabled(True)
            return True
        self.return_toolButton.setEnabled(False)
        return False

    @Slot()
    def table_return(self) -> None:
        if not self.check_return():
            return

        if self.path[-2] is None:
            msg = self.tr("无法返回")
            MsgBox.critical(self, "错误", msg)
            return
        result = self.path[-2]
        self.path.pop()
        self.path[-1] = None
        self.results_tableWidget.setRowCount(0)
        self.results_tableWidget.setColumnCount(0)
        self.add2table(result)
        self.check_return()

        self.task_manager.clear_task("table")

    @Slot(QModelIndex)
    def open_table_item(self, index: QModelIndex) -> None:
        """结果表格元素被双击时调用"""
        row = index.row()  # 获取被双击的行
        items = self.path[-1]
        if not items or len(items) <= row:
            return

        item = items[row]

        if not cfg["auto_select"] and isinstance(item, SongInfo) and item.source == Source.KG:
            self.task_manager.clear_task("table")
            self.task_manager.new_multithreaded_task(
                "get_lyricslist",
                get_lyricslist,
                self.add2table,
                (MsgBox.get_error_slot(self, msg=self.tr("获取歌词列表失败")), lambda _: self.table_return()),
                item,
            )
            self.path.append(None)
            self.results_tableWidget.setRowCount(0)
            self.results_tableWidget.setColumnCount(0)
            self.check_return()

        elif isinstance(item, SongListInfo):
            self.task_manager.clear_task("table")
            self.task_manager.new_multithreaded_task(
                "get_songlist",
                get_songlist,
                self.add2table,
                (MsgBox.get_error_slot(self, msg=self.tr("获取歌曲列表失败")), lambda _: self.table_return()),
                item,
            )
            self.path.append(None)
            self.results_tableWidget.setRowCount(0)
            self.results_tableWidget.setColumnCount(0)
            self.check_return()

        elif isinstance(item, SongInfo | LyricInfo):
            self.task_manager.clear_task("get_lyrics")
            self.lyrics = None
            self.preview_plainTextEdit.setPlainText(self.tr("处理中..."))
            self.task_manager.new_multithreaded_task(
                "get_lyrics",
                get_lyrics,
                self.set_lyrics,
                (
                    MsgBox.get_error_slot(
                        self,
                        msg=self.tr("获取纯音乐{}的歌词失败").format(
                            (item.artist_title(replace=True) if isinstance(item, SongInfo) else item.songinfo.artist_title(replace=True)),
                        )
                        if (item.language if isinstance(item, SongInfo) else item.songinfo.language) == Language.INSTRUMENTAL
                        else self.tr("获取歌词失败"),
                    ),
                    lambda _: self.preview_plainTextEdit.setPlainText(""),
                ),
                item,
            )

    @Slot()
    def _check_search_more(self) -> None:
        table_scroll = self.results_tableWidget.verticalScrollBar()
        pre_result = self.path[-1]
        if (
            table_scroll.value() == table_scroll.maximum()  # 判断是否已经滚动到了底部或消失
            and pre_result
            and isinstance(pre_result.info, SearchInfo)
            and pre_result.more
            and self.task_manager.is_finished("search_more")
        ):

            def _callback(result: APIResultList | Exception) -> None:
                if isinstance(result, Exception):
                    MsgBox.error(self, result, msg=self.tr("搜索更多结果时错误"))
                    return

                if len(result) == 0:
                    nomore_item = QTableWidgetItem(self.tr("没有更多结果"))
                    nomore_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)  # 设置水平和垂直居中对齐
                    self.results_tableWidget.setItem(self.results_tableWidget.rowCount() - 1, 0, nomore_item)
                    return

                self.results_tableWidget.removeRow(self.results_tableWidget.rowCount() - 1)
                self.add2table(result)

            callback, error_handling = create_collecting_callbacks(len(pre_result.more), _callback)
            for source in pre_result.more:
                start, end, _ = pre_result.source_ranges[source]
                self.task_manager.new_multithreaded_task(
                    "search_more",
                    search,
                    callback,
                    error_handling,
                    source,
                    pre_result.info.keyword,
                    pre_result.info.search_type,
                    ((end - start + 1) // 20) + 1,
                )

            # 创建加载中的 QTableWidgetItem
            loading_item = QTableWidgetItem(self.tr("加载中..."))
            loading_item.setTextAlignment(Qt.AlignmentFlag.AlignCenter)  # 设置水平和垂直居中对齐

            table = self.results_tableWidget
            # 设置合并单元格
            table.insertRow(table.rowCount())
            last_row = table.rowCount() - 1
            table.setSpan(last_row, 0, 1, table.columnCount())
            table.setItem(last_row, 0, loading_item)

    @Slot()
    def translate_lyrics(self) -> None:
        if not self.lyrics:
            MsgBox.warning(self, self.tr("警告"), self.tr("请先获取歌词"))
            return
        lyrics = self.lyrics
        if "LDDC_ts" in lyrics:
            self.lyrics.pop("LDDC_ts")
            self.set_lyrics()
            self.update_translate_button_state()
            return

        def callback(ts_data: LyricsData) -> None:
            if self.lyrics:
                self.lyrics["LDDC_ts"] = ts_data
                self.set_lyrics()

            self.update_translate_button_state()

        self.task_manager.new_multithreaded_task(
            "translate",
            translate_lyrics,
            callback,
            (
                MsgBox.get_error_slot(self, self.tr("翻译歌词失败")),
                lambda _: (self.translate_pushButton.setText(self.tr("翻译歌词")), self.translate_pushButton.setEnabled(True)),
            ),
            lyrics,
        )

        self.translate_pushButton.setEnabled(False)
        self.translate_pushButton.setText(self.tr("翻译中..."))

    def update_translate_button_state(self) -> None:
        if self.lyrics and self.lyrics.get("LDDC_ts"):
            self.translate_pushButton.setText(self.tr("取消翻译"))
        else:
            self.translate_pushButton.setText(self.tr("翻译歌词"))
        self.translate_pushButton.setEnabled(True)

    def retranslateUi(self, _search_base: "SearchWidgetBase | None" = None) -> None:
        self.update_search_types()
        super().retranslateUi(self)


class SearchWidget(SearchWidgetBase):
    def __init__(self) -> None:
        super().__init__()
        self.setup_ui()
        self.resize(1050, 600)
        self.select_path_pushButton.clicked.connect(self.select_savepath)
        self.save_preview_lyric_pushButton.clicked.connect(lambda: self.save_lyric("dir"))
        self.save_to_tag_pushButton.clicked.connect(lambda: self.save_lyric("tag"))
        self.save_list_lyrics_pushButton.clicked.connect(self.save_list_lyrics)
        self.setAcceptDrops(True)  # 启用拖放功能

        self.auto_fetch_file_path: Path | None = None

        self.task_manager.set_task("auto_fetch")
        self.task_manager.parent_childs["get_lyrics"].append("auto_fetch")

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
        self.save_to_tag_pushButton = QPushButton(self)
        save_button_size_policy = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        save_button_size_policy.setHorizontalStretch(0)
        save_button_size_policy.setVerticalStretch(0)
        save_button_size_policy.setHeightForWidth(self.save_preview_lyric_pushButton.sizePolicy().hasHeightForWidth())
        self.save_preview_lyric_pushButton.setSizePolicy(save_button_size_policy)
        self.save_to_tag_pushButton.setSizePolicy(save_button_size_policy)
        self.save_list_lyrics_pushButton.setSizePolicy(save_button_size_policy)

        but_h = self.control_verticalLayout.sizeHint().height() - self.control_verticalSpacer.sizeHint().height() * 0.8

        self.save_preview_lyric_pushButton.setMinimumSize(QSize(0, int(but_h)))
        self.save_to_tag_pushButton.setMinimumSize(QSize(0, int(but_h)))
        self.save_list_lyrics_pushButton.setMinimumSize(QSize(0, int(but_h)))

        self.bottom_horizontalLayout.addWidget(self.save_list_lyrics_pushButton)
        self.bottom_horizontalLayout.addWidget(self.save_preview_lyric_pushButton)
        self.bottom_horizontalLayout.addWidget(self.save_to_tag_pushButton)

        self.retranslateUi()

    def retranslateUi(self, search_base: SearchWidgetBase | None = None) -> None:
        super().retranslateUi(self)
        if search_base is not None:
            return
        self.label_title.setText(self.tr("搜索"))
        self.label_sub_title.setText(self.tr("从云端搜索并下载歌词"))

        self.select_path_label.setText(self.tr("保存到:"))
        self.select_path_pushButton.setText(self.tr("选择保存路径"))

        self.save_preview_lyric_pushButton.setText(self.tr("保存歌词到目录"))
        self.save_to_tag_pushButton.setText(self.tr("保存到歌曲标签"))
        self.save_list_lyrics_pushButton.setText(self.tr("保存专辑/歌单的歌词"))

    @Slot()
    def save_lyric(self, location: Literal["dir", "tag"]) -> None:
        """保存预览的歌词"""
        if self.lyrics is None:
            MsgBox.warning(self, self.tr("警告"), self.tr("请先下载并预览歌词"))
            return

        if not self.lyrics or self.preview_plainTextEdit.toPlainText() == "":
            MsgBox.warning(self, self.tr("警告"), self.tr("歌词内容为空"))
            return

        if location == "dir":
            if self.save_path_lineEdit.text() == "":
                MsgBox.warning(self, self.tr("警告"), self.tr("请先选择保存路径"))
                return
            lyric_langs = [lang for lang in cfg["langs_order"] if lang in self.langs]
            # 获取已选择的歌词(用于替换占位符)
            try:
                save2fomat_path(
                    self.preview_plainTextEdit.toPlainText(),
                    Path(self.save_path_lineEdit.text()),
                    cfg["lyrics_file_name_fmt"] + LyricsFormat(self.lyricsformat_comboBox.currentIndex()).ext,
                    self.lyrics.info.songinfo,
                    lyric_langs,
                )
                MsgBox.information(self, self.tr("提示"), self.tr("歌词保存成功"))
            except Exception as e:
                MsgBox.warning(self, self.tr("警告"), self.tr("歌词保存失败：") + str(e))

        if location == "tag":
            if LyricsFormat(self.lyricsformat_comboBox.currentIndex()) not in (LyricsFormat.VERBATIMLRC, LyricsFormat.LINEBYLINELRC, LyricsFormat.ENHANCEDLRC):
                MsgBox.warning(self, self.tr("警告"), self.tr("歌曲标签中的歌词应为LRC格式"))
                return

            @Slot()
            def file_selected(save_path: str) -> None:
                try:
                    if self.lyrics:
                        write_lyrics(save_path, self.preview_plainTextEdit.toPlainText(), self.lyrics)
                    else:
                        write_lyrics(save_path, self.preview_plainTextEdit.toPlainText())
                    MsgBox.information(self, self.tr("提示"), self.tr("歌词保存成功"))
                except Exception as e:
                    MsgBox.warning(self, self.tr("警告"), self.tr("歌词保存失败：") + str(e))

            dialog = QFileDialog(self)
            dialog.setWindowTitle(self.tr("选择歌曲文件"))
            dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
            dialog.setNameFilter(self.tr("歌曲文件") + "*." + " *.".join(audio_formats))
            dialog.fileSelected.connect(file_selected)
            if self.auto_fetch_file_path:
                dialog.setDirectory(str(self.auto_fetch_file_path.parent))
                dialog.selectFile(str(self.auto_fetch_file_path.name))
            dialog.open()

    @Slot()
    def save_list_lyrics(self) -> None:
        if not self.path or not self.path[-1] or not isinstance(self.path[-1].info, SongListInfo):
            MsgBox.warning(self, self.tr("警告"), self.tr("请先选择一个专辑或歌单"))
            return
        dialog = GetListLyrics(
            self,
            self.path[-1],
            self.langs,
            LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
            Path(self.save_path_lineEdit.text()),
        )
        dialog.open()

    @Slot()
    def select_savepath(self) -> None:
        @Slot(str)
        def file_selected(save_path: str) -> None:
            self.save_path_lineEdit.setText(os.path.normpath(save_path))

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择保存路径"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.fileSelected.connect(file_selected)
        dialog.open()

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        formats = event.mimeData().formats()
        if (
            event.mimeData().hasUrls()
            or 'application/x-qt-windows-mime;value="foobar2000_playable_location_format"' in formats
            or 'application/x-qt-windows-mime;value="ACL.FileURIs"' in formats
        ):
            event.acceptProposedAction()  # 接受拖动操作
        else:
            event.ignore()

    def search(self) -> None:
        self.auto_fetch_file_path = None
        super().search()

    def dropEvent(self, event: QDropEvent) -> None:
        try:
            # 获取拖入的文件信息
            song = parse_drop_infos(event.mimeData(), first=True)
        except Exception as e:
            MsgBox.critical(self, self.tr("错误"), self.tr("拖动文件解析失败：") + str(e))
            return

        self.auto_fetch(song)

    @Slot(SongInfo)
    def auto_fetch(self, song: SongInfo) -> None:
        self.task_manager.clear_task("table")
        self.task_manager.clear_task("get_lyrics")

        self.auto_fetch_file_path = song.path
        self.preview_plainTextEdit.setPlainText(self.tr("正在自动获取 {0} 的歌词...").format(song.artist_title(replace=True)))

        self.path = [None]
        self.check_return()
        self.task_manager.new_multithreaded_task(
            "auto_fetch",
            auto_fetch,
            lambda result: (
                self.set_lyrics(result[0]),
                self.add2table(result[1]),
                self.results_tableWidget.selectRow(0),
                self.search_keyword_lineEdit.setText(result[1].info.keyword),
            ),
            (MsgBox.get_error_slot(self, None, self.tr("自动获取歌词失败：")), lambda _: self.preview_plainTextEdit.setPlainText("")),
            song,
            return_search_results=True,
        )
        # 清除表格
        self.results_tableWidget.setRowCount(0)
        self.results_tableWidget.setColumnCount(0)
