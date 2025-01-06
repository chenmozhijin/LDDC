# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import os

from PySide6.QtCore import QMimeData, Qt, QUrl, Signal, Slot
from PySide6.QtGui import QContextMenuEvent, QDesktopServices, QDragEnterEvent, QDropEvent, QKeyEvent
from PySide6.QtWidgets import QFileDialog, QMenu, QTableWidgetItem, QWidget

from LDDC.backend.worker import LocalMatchWorker
from LDDC.ui.local_match_ui import Ui_local_match
from LDDC.utils.data import cfg
from LDDC.utils.enum import LocalMatchFileNameMode, LocalMatchSave2TagMode, LocalMatchSaveMode, LyricsFormat, Source
from LDDC.utils.paths import default_save_lyrics_dir
from LDDC.utils.thread import threadpool
from LDDC.utils.utils import get_artist_str, get_local_match_save_path

from .msg_box import MsgBox


class LocalMatchWidget(QWidget, Ui_local_match):
    search_song = Signal(dict)

    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.setAcceptDrops(True)  # 启用拖放功能
        self.connect_signals()

        self.songs_table.set_proportions([0.2, 0.1, 0.1, 0.3, 2, 0.3, 2])  # 设置列宽比例
        self.source_listWidget.set_soures(["QM", "KG", "NE"])

        self.taskids: dict[str, int] = {
            "get_infos": 0,
            "match_lyrics": 0,
        }
        self.workers: dict[int, LocalMatchWorker] = {}  # 任务ID与工作线程的映射
        self.matching: bool = False  # 是否正在匹配
        self.save_root_path: str | None = None  # 保存根目录
        self.save_path_errors: set[str] = set()  # 保存路径错误

    def connect_signals(self) -> None:
        """连接信号与槽"""
        self.select_files_button.clicked.connect(self.select_files)
        self.select_dirs_button.clicked.connect(self.select_dirs)
        self.save_path_button.clicked.connect(self.select_save_root_path)
        self.start_cancel_pushButton.clicked.connect(self.start_cancel)

        self.save_mode_comboBox.currentIndexChanged.connect(self.update_save_paths)
        self.filename_mode_comboBox.currentIndexChanged.connect(self.update_save_paths)
        self.save2tag_mode_comboBox.currentIndexChanged.connect(self.update_save_paths)
        self.lyricsformat_comboBox.currentIndexChanged.connect(self.update_save_paths)

    @Slot()
    def start_cancel(self) -> None:
        """开始/取消按钮点击槽"""
        if self.workers:
            for worker in self.workers.values():
                worker.stop()
            self.start_cancel_pushButton.setEnabled(False)
            self.start_cancel_pushButton.setText(self.tr("取消中..."))
            return

        if (LocalMatchSave2TagMode(self.save2tag_mode_comboBox.currentIndex()) in (LocalMatchSave2TagMode.ONLY_TAG, LocalMatchSave2TagMode.BOTH) and
                LyricsFormat(self.lyricsformat_comboBox.currentIndex()) not in (LyricsFormat.VERBATIMLRC,
                                                                                LyricsFormat.LINEBYLINELRC,
                                                                                LyricsFormat.ENHANCEDLRC)):

            MsgBox.warning(self, self.tr("警告"), self.tr("歌曲标签中的歌词应为LRC格式"))
            return

        langs = self.get_langs()
        if not langs:
            MsgBox.warning(self, self.tr("警告"), self.tr("请选择要匹配的语言"))
            return

        if len(source := [Source[k] for k in self.source_listWidget.get_data()]) == 0:
            MsgBox.warning(self, self.tr("警告"), self.tr("请选择至少一个源！"))
            return

        if self.save_path_errors:
            MsgBox.warning(self, self.tr("警告"), "\n".join(self.save_path_errors))
            return

        if not (infos := self.get_table_infos()):
            MsgBox.warning(self, self.tr("警告"), self.tr("请选择要匹配的歌曲！"))
            return

        worker = LocalMatchWorker("match_lyrics",
                                  self.taskids["match_lyrics"],
                                  infos=infos,
                                  save_mode=LocalMatchSaveMode(self.save_mode_comboBox.currentIndex()),
                                  file_name_mode=LocalMatchFileNameMode(self.filename_mode_comboBox.currentIndex()),
                                  save2tag_mode=LocalMatchSave2TagMode(self.save2tag_mode_comboBox.currentIndex()),
                                  lyrics_format=LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
                                  langs=self.get_langs(),
                                  save_root_path=self.save_root_path,
                                  min_score=self.min_score_spinBox.value(),
                                  source=source)

        worker.signals.finished.connect(self.match_lyrics_result_slot, Qt.ConnectionType.BlockingQueuedConnection)
        worker.signals.progress.connect(self.update_progress_slot, Qt.ConnectionType.BlockingQueuedConnection)
        threadpool.start(worker)
        self.workers[self.taskids["match_lyrics"]] = worker
        self.taskids["match_lyrics"] += 1
        self.start_cancel_pushButton.setText(self.tr("取消(匹配歌词)"))

        for widget in self.control_bar.children():
            if isinstance(widget, QWidget) and widget != self.start_cancel_pushButton:
                widget.setEnabled(False)
        self.matching = True

        self.update_save_paths()
        for i in range(self.songs_table.rowCount()):
            self.songs_table.setItem(i, 6, QTableWidgetItem(self.tr("未匹配")))

    @Slot(list)
    @Slot(str)
    def get_infos(self, paths: list[str] | str | QMimeData) -> None:
        """获取文件信息,并添加到表格中"""
        if isinstance(paths, QMimeData):
            mime = paths

        if isinstance(paths, str):
            paths = [paths]

        if not paths:
            return

        if isinstance(paths, list) and paths:
            mime = QMimeData()
            mime.setUrls([QUrl.fromLocalFile(path) for path in paths])

        worker = LocalMatchWorker("get_infos",
                                  self.taskids["get_infos"],
                                  mime=mime)
        worker.signals.finished.connect(self.get_infos_result_slot, Qt.ConnectionType.BlockingQueuedConnection)
        worker.signals.progress.connect(self.update_progress_slot, Qt.ConnectionType.BlockingQueuedConnection)
        threadpool.start(worker)
        self.workers[self.taskids["get_infos"]] = worker
        self.taskids["get_infos"] += 1
        self.start_cancel_pushButton.setText(self.tr("取消(获取文件信息)"))

    @Slot()
    def select_files(self) -> None:
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择要匹配的文件"))
        dialog.setFileMode(QFileDialog.FileMode.ExistingFiles)
        dialog.filesSelected.connect(self.get_infos)
        dialog.open()

    @Slot()
    def select_dirs(self) -> None:
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择要遍历的文件夹"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.fileSelected.connect(self.get_infos)
        dialog.open()

    @Slot()
    def select_save_root_path(self) -> None:
        """选择保存根目录"""
        @Slot(str)
        def set_save_root_path(path: str) -> None:
            self.save_root_path = os.path.abspath(path)
            self.update_save_paths()
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择保存根目录"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.fileSelected.connect(set_save_root_path)
        dialog.setDirectory(default_save_lyrics_dir)
        dialog.open()

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        formats = event.mimeData().formats()
        if (event.mimeData().hasUrls() or
            'application/x-qt-windows-mime;value="foobar2000_playable_location_format"' in formats or
                'application/x-qt-windows-mime;value="ACL.FileURIs"' in formats) and not self.matching:
            event.acceptProposedAction()  # 接受拖动操作
        else:
            event.ignore()

    def dropEvent(self, event: QDropEvent) -> None:
        mime = QMimeData()

        # 复制一份数据以便在其他线程使用
        _mime = event.mimeData()
        for f in _mime.formats():
            mime.setData(f, _mime.data(f))
        self.get_infos(mime)

    @Slot(dict)
    def update_progress_slot(self, result: dict) -> None:
        """处理更新进度条的结果

        :param result: 更新进度条的结果
        """
        msg, progress, total = result["msg"], result["progress"], result["total"]
        self.progressBar.setMaximum(total)
        self.progressBar.setValue(progress)
        self.status_label.setText(msg)

        if "current" in result:
            info_item = self.songs_table.item(result["current"], 0)
            status_item = self.songs_table.item(result["current"], 6)
            if not status_item or not info_item:
                MsgBox.critical(self, self.tr("错误"), self.tr("对应的引索{}不存在").format(result["current"]))
                return
            match result["status"]:
                case "成功":
                    status_item.setForeground(Qt.GlobalColor.green)
                    status_item.setText(self.tr("成功"))
                    if "save_path" in result:
                        info = info_item.data(Qt.ItemDataRole.UserRole)
                        status_item.setData(Qt.ItemDataRole.UserRole, {"status": result["status"], "save_path": result["save_path"]})
                        if (LocalMatchSave2TagMode(self.save2tag_mode_comboBox.currentIndex()) in (LocalMatchSave2TagMode.ONLY_TAG,
                                                                                                   LocalMatchSave2TagMode.BOTH) and
                                info["type"] != "cue"):

                            self.songs_table.setItem(result["current"], 5, QTableWidgetItem(f"{self.tr("保存到标签")} + {result['save_path']}"))
                        else:
                            self.songs_table.setItem(result["current"], 5, QTableWidgetItem(result["save_path"]))
                    else:  # 只保存到标签
                        status_item.setData(Qt.ItemDataRole.UserRole, {"status": result["status"]})

                case "跳过纯音乐":
                    status_item.setForeground(Qt.GlobalColor.blue)
                    status_item.setText(self.tr("跳过"))
                    status_item.setData(Qt.ItemDataRole.UserRole, {"status": result["status"]})
                    status_item.setToolTip(self.tr("跳过纯音乐"))

                case _:
                    status_item.setForeground(Qt.GlobalColor.red)
                    status_item.setText(self.tr("失败"))
                    status_item.setData(Qt.ItemDataRole.UserRole, {"status": result["status"]})
                    match result["status"]:
                        case "没有找到符合要求的歌曲":
                            status_item.setToolTip(self.tr("错误：没有找到符合要求的歌曲"))
                        case "搜索结果处理失败":
                            status_item.setToolTip(self.tr("错误：搜索结果处理失败"))
                        case "没有足够的信息用于搜索":
                            status_item.setToolTip(self.tr("错误：没有足够的信息用于搜索"))
                        case "保存歌词失败":
                            status_item.setToolTip(self.tr("错误：保存歌词失败"))
                        case "超时":
                            status_item.setToolTip(self.tr("错误：超时"))

    def get_table_infos(self) -> list[dict]:
        """获取表格中的文件信息

        :return: 文件信息列表
        """
        infos: list[dict] = []
        for row in range(self.songs_table.rowCount()):
            item = self.songs_table.item(row, 0)
            if item is not None:
                infos.append(item.data(Qt.ItemDataRole.UserRole))
        return infos

    def get_langs(self) -> list[str]:
        """获取选择的的语言"""
        lyric_langs = []
        if self.original_checkBox.isChecked():
            lyric_langs.append("orig")
        if self.translate_checkBox.isChecked():
            lyric_langs.append("ts")
        if self.romanized_checkBox.isChecked():
            lyric_langs.append("roma")
        return [lang for lang in cfg["langs_order"] if lang in lyric_langs]

    @Slot()
    def update_save_paths(self) -> None:
        """更新保存路径"""
        save_mode = LocalMatchSaveMode(self.save_mode_comboBox.currentIndex())
        file_name_mode = LocalMatchFileNameMode(self.filename_mode_comboBox.currentIndex())
        save2tag_mode = LocalMatchSave2TagMode(self.save2tag_mode_comboBox.currentIndex())
        lyrics_format = LyricsFormat(self.lyricsformat_comboBox.currentIndex())
        langs = self.get_langs()
        file_name_format = cfg["lyrics_file_name_fmt"]

        self.save_path_errors.clear()

        for row in range(self.songs_table.rowCount()):
            info_item = self.songs_table.item(row, 0)
            if not info_item:
                MsgBox.critical(self, self.tr("错误"), self.tr("对应的引索{}不存在").format(row))
                continue
            info: dict = info_item.data(Qt.ItemDataRole.UserRole)
            save_path_text = ""

            if save2tag_mode in (LocalMatchSave2TagMode.ONLY_TAG, LocalMatchSave2TagMode.BOTH) and info["type"] != "cue":
                save_path_text += self.tr("保存到标签")

            if (info["type"] == "cue" or save2tag_mode != LocalMatchSave2TagMode.ONLY_TAG):
                save_path = get_local_match_save_path(save_mode=save_mode,
                                                      file_name_mode=file_name_mode,
                                                      song_info=info,
                                                      lyrics_format=lyrics_format,
                                                      file_name_format=file_name_format,
                                                      langs=langs,
                                                      save_root_path=self.save_root_path,
                                                      allow_placeholder=True)
                if isinstance(save_path, int):
                    match save_path:
                        case -1:
                            save_path = self.tr("需要指定保存路径")
                        case -2:
                            save_path = self.tr("错误(需要歌词信息)")
                        case -3:
                            save_path = self.tr("需要指定歌曲根目录")
                        case _:
                            save_path = self.tr("未知错误")
                    self.save_path_errors.add(save_path)
                save_path_text += f" + {save_path}" if save_path_text else save_path

            self.songs_table.setItem(row, 5, QTableWidgetItem(save_path_text))

    @Slot(str)
    def select_root_path(self, rows: list[int]) -> None:
        @Slot(str)
        def set_root_path(path: str) -> None:
            skips = []
            for row in rows:
                info_item = self.songs_table.item(row, 0)
                if not info_item:
                    MsgBox.critical(self, self.tr("错误"), self.tr("对应的引索{}不存在").format(row))
                    continue
                info: dict = info_item.data(Qt.ItemDataRole.UserRole)
                # 获取绝对路径
                file_path = os.path.abspath(info["file_path"])  # 歌曲文件路径
                path = os.path.abspath(path)  # 根目录路径

                # 检查驱动器是否相同(仅在 Windows 上适用)
                # 检查文件路径是否以目录路径为前缀
                if os.path.splitdrive(file_path)[0] == os.path.splitdrive(path)[0] and os.path.commonpath([file_path, path]) == path:
                    info["root_path"] = path
                    info_item.setData(Qt.ItemDataRole.UserRole, info)
                else:
                    skips.append(info["file_path"])

            if skips:
                MsgBox.warning(self, self.tr("警告"), self.tr("由于以下歌曲不在指定的根目录中,无法设置\n") + "\n".join(skips))

            self.update_save_paths()

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择歌曲根目录"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        info_item = self.songs_table.item(rows[0], 0)
        if not info_item:
            MsgBox.critical(self, self.tr("错误"), self.tr("对应的引索{}不存在").format(rows[0]))
            return
        dialog.setDirectory(os.path.dirname(info_item.data(Qt.ItemDataRole.UserRole)["file_path"]))
        dialog.fileSelected.connect(set_root_path)
        dialog.open()

    def contextMenuEvent(self, event: QContextMenuEvent) -> None:
        if not self.songs_table.geometry().contains(event.pos()):  # 判断否在表格内点击
            return
        selected_rows = self.songs_table.selectionModel().selectedRows()
        if not selected_rows:
            return
        menu = QMenu(self)
        if not self.matching:
            menu.addAction(self.tr("删除"), lambda rows=selected_rows: [self.songs_table.removeRow(row.row()) for row in reversed(rows)])
            #  反向删除,防止删除行后影响后续行号
            menu.addAction(self.tr("指定根目录"), lambda rows=selected_rows: self.select_root_path([row.row() for row in rows]))
        if len(selected_rows) == 1:
            info_item, status_item = self.songs_table.item(selected_rows[0].row(), 0), self.songs_table.item(selected_rows[0].row(), 6)
            if not info_item or not status_item:
                return
            menu.addAction(self.tr("打开歌曲目录"),
                           lambda info_item=info_item: QDesktopServices.openUrl(
                               QUrl.fromLocalFile(os.path.dirname(info_item.data(Qt.ItemDataRole.UserRole)["file_path"]))))
            menu.addAction(self.tr("在搜索中打开"),
                           lambda info_item=info_item: self.search_song.emit(info_item.data(Qt.ItemDataRole.UserRole)))
            if ((completion_status := status_item.data(Qt.ItemDataRole.UserRole)) and  # 获取完成状态
                isinstance(completion_status, dict) and  # 检查是否为字典
                    (save_path := completion_status.get("save_path"))):  # 获取保存路径
                menu.addAction(self.tr("打开保存目录"),
                               lambda save_path=save_path: QDesktopServices.openUrl(QUrl.fromLocalFile(os.path.dirname(save_path))))
                menu.addAction(self.tr("打开歌词"),
                               lambda save_path=save_path: QDesktopServices.openUrl(QUrl.fromLocalFile(save_path)))
        menu.exec_(event.globalPos())

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if event.key() == Qt.Key.Key_Delete and not self.matching:
            # 获取所有选中的行并删除
            selected_rows = {index.row() for index in self.songs_table.selectionModel().selectedRows()}
            for row in sorted(selected_rows, reverse=True):
                self.songs_table.removeRow(row)
        else:
            super().keyPressEvent(event)

    @Slot(dict)
    def get_infos_result_slot(self, result: dict) -> None:
        """处理获取文件信息的结果

        :param result: 获取文件信息的结果
        """
        del self.workers[result["taskid"]]
        if not self.workers:
            self.start_cancel_pushButton.setText(self.tr("开始"))
            self.start_cancel_pushButton.setEnabled(True)
        errors: list = result.get("errors", [])
        if errors:
            MsgBox.critical(self, self.tr("错误"), "\n".join(errors))

        if result["status"] == "success":
            infos: list[dict] = result["infos"]
            existing_infos = self.get_table_infos()
            for info in infos:
                if info in existing_infos:
                    continue
                i = self.songs_table.rowCount()
                self.songs_table.insertRow(i)
                item = QTableWidgetItem(info.get("title", ""))
                item.setData(Qt.ItemDataRole.UserRole, info)
                self.songs_table.setItem(i, 0, item)
                self.songs_table.setItem(i, 1, QTableWidgetItem(get_artist_str(info.get("artist"))))
                self.songs_table.setItem(i, 2, QTableWidgetItem(info.get("album", "")))
                self.songs_table.setItem(i, 3, QTableWidgetItem(info["file_path"]))
                if info["duration"] is not None:
                    self.songs_table.setItem(i, 4, QTableWidgetItem('{:02d}:{:02d}'.format(*divmod(info['duration'], 60))))
                self.songs_table.setItem(i, 6, QTableWidgetItem(self.tr("未匹配")))
            self.update_save_paths()

    @Slot(dict)
    def match_lyrics_result_slot(self, result: dict) -> None:
        """处理匹配歌词的结果

        :param result: 匹配歌词的结果
        """
        del self.workers[result["taskid"]]
        self.update_progress_slot({"msg": "", "progress": 0, "total": 0})
        self.start_cancel_pushButton.setText(self.tr("开始"))
        for widget in self.control_bar.children():
            if isinstance(widget, QWidget):
                widget.setEnabled(True)
        self.matching = False

        info_str = self.tr("总共{total}首歌曲，匹配成功{success}首，匹配失败{fail}首，跳过{skip}首。").format(total=result.get("total"),
                                                                                        success=result.get("success"),
                                                                                        fail=result.get("fail"),
                                                                                        skip=result.get("skip"))
        match result["status"]:
            case "success":
                MsgBox.information(self, self.tr("匹配完成"), self.tr("匹配完成") + "\n" + info_str)
            case "error":
                MsgBox.critical(self, self.tr("匹配错误"), self.tr("匹配错误") + "\n" + info_str)
            case "cancelled":
                MsgBox.information(self, self.tr("匹配取消"), self.tr("匹配取消") + "\n" + info_str)
