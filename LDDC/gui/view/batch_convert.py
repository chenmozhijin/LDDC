# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

from pathlib import Path
from typing import Optional

from PySide6.QtCore import Qt, QUrl, Signal, Slot
from PySide6.QtGui import QContextMenuEvent, QDesktopServices, QDragEnterEvent, QDropEvent, QKeyEvent
from PySide6.QtWidgets import QFileDialog, QMenu, QTableWidgetItem, QWidget

from LDDC.common.models import LyricsFormat
from LDDC.common.paths import default_save_lyrics_dir
from LDDC.common.task_manager import TaskManager
from LDDC.gui.components.msg_box import MsgBox
from LDDC.gui.ui.batch_convert_ui import Ui_batch_convert
from LDDC.gui.workers.batch_convert import BatchConvertWorker, ConverStatus, ConverStatusType


class BatchConvertWidget(QWidget, Ui_batch_convert):
    open_lyrics = Signal(Path)  # 用于打开歌词文件的信号

    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.setAcceptDrops(True)
        self.connect_signals()

        self.files_table.set_proportions([0.3, 0.6, 0.1])  # 设置列宽比例

        def restore() -> None:
            self.start_button.setEnabled(True)
            self.start_button.setText(self.tr("开始转换"))
            for widget in self.control_bar.children():
                if isinstance(widget, QWidget):
                    widget.setEnabled(True)

        self.taskmanager = TaskManager({"batch_convert": []}, {"batch_convert": restore})
        self.save_root_path: Optional[Path] = None  # 保存根目录

    def connect_signals(self) -> None:
        """连接信号与槽"""
        self.select_files_button.clicked.connect(self.select_files)
        self.select_dirs_button.clicked.connect(self.select_dirs)
        self.save_path_button.clicked.connect(self.select_save_root_path)
        self.start_button.clicked.connect(self.start_convert)
        self.format_comboBox.currentIndexChanged.connect(lambda: self.update_save_paths())

    @Slot(str, int, int)
    def update_progressbar(self, text: str, value: int, max_value: int, status: ConverStatus | None = None) -> None:
        """更新进度条"""
        self.progressBar.setMaximum(max_value)
        self.progressBar.setValue(value)
        self.status_label.setText(text)

        # 更新当前处理文件的状态
        if status:
            self.update_file_status(status)

    def update_file_status(self, status: ConverStatus) -> None:
        """更新文件状态"""
        status_item = self.files_table.item(status.index, 2)
        if status_item:
            status_item.setText(self.tr("转换成功") if status.type == ConverStatusType.SUCCESS else self.tr("转换失败"))
            status_item.setForeground(Qt.GlobalColor.green if status.type == ConverStatusType.SUCCESS else Qt.GlobalColor.red)
            status_item.setData(Qt.ItemDataRole.UserRole, status)  # 保存状态类型到UserRole

    @Slot()
    def start_convert(self) -> None:
        if not self.taskmanager.is_finished():
            self.taskmanager.cancel()
            self.start_button.setEnabled(False)
            self.start_button.setText(self.tr("取消中..."))
            return

        file_path_save_paths = [
            (file_path, save_path)
            for row in range(self.files_table.rowCount())
            if (item := self.files_table.item(row, 0))
            and (file_path := item.data(Qt.ItemDataRole.UserRole))
            and (save_path := item.data(Qt.ItemDataRole.UserRole + 1))
        ]
        if not file_path_save_paths:
            MsgBox.warning(self, self.tr("警告"), self.tr("请选择要转换的文件！"))
            return

        target_format = LyricsFormat(self.format_comboBox.currentIndex())
        worker = BatchConvertWorker(file_path_save_paths=file_path_save_paths, save_root_path=self.save_root_path, target_format=target_format)

        worker.progress.connect(self.update_progressbar)

        def on_finished(success: int, fail: int) -> None:
            MsgBox.information(self, self.tr("转换完成"), self.tr(f"成功转换 {success} 个文件, 失败 {fail} 个"))

        worker.finished.connect(on_finished)
        self.taskmanager.run_worker("batch_convert", worker)

        for widget in self.control_bar.children():
            if isinstance(widget, QWidget) and widget != self.start_button:
                widget.setEnabled(False)

    def add_to_table(self, files: list[Path]) -> None:
        """添加文件到表格中"""
        existing_files = {item.data(Qt.ItemDataRole.UserRole) for row in range(self.files_table.rowCount()) if (item := self.files_table.item(row, 0))}

        for file in files:
            if file in existing_files:
                continue

            row = self.files_table.rowCount()
            self.files_table.insertRow(row)

            item = QTableWidgetItem(file.name)
            item.setData(Qt.ItemDataRole.UserRole, file)
            self.files_table.setItem(row, 0, item)

            # 设置保存路径
            self.update_save_paths(row)

            # 设置初始状态
            self.files_table.setItem(row, 2, QTableWidgetItem(self.tr("等待转换")))

    @Slot()
    def select_files(self) -> None:
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择要转换的文件"))
        dialog.setFileMode(QFileDialog.FileMode.ExistingFiles)
        dialog.setNameFilter(self.tr("歌词文件 (*.lrc *.txt *.srt *.ass)"))
        dialog.filesSelected.connect(lambda files: self.add_to_table([Path(f) for f in files]))
        dialog.open()

    @Slot()
    def select_dirs(self) -> None:
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择要遍历的文件夹"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.setOption(QFileDialog.Option.ShowDirsOnly)

        @Slot(str)
        def handle_dir_selected(path: str) -> None:
            dir_path = Path(path)
            extensions = {f"*{lyric_format.ext}" for lyric_format in LyricsFormat.__members__.values()}
            search_method = dir_path.rglob if self.recursive_checkBox.isChecked() else dir_path.glob
            files = []
            for ext in extensions:
                files.extend(search_method(ext))

            if files:
                self.add_to_table(files)
            else:
                MsgBox.information(self, self.tr("提示"), self.tr("所选文件夹中没有找到支持的歌词文件"))

        dialog.fileSelected.connect(handle_dir_selected)
        dialog.open()

    @Slot()
    def select_save_root_path(self) -> None:
        """选择保存目录"""
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择保存目录"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.setDirectory(str(default_save_lyrics_dir))

        @Slot(str)
        def set_save_root_path(path: str) -> None:
            self.save_root_path = Path(path).resolve()
            self.update_save_paths()

        dialog.fileSelected.connect(set_save_root_path)
        dialog.open()

    def update_save_paths(self, index: int | None = None) -> None:
        """更新保存路径"""
        for row in range(self.files_table.rowCount()) if index is None else [index]:
            main_item = self.files_table.item(row, 0)
            target_format = LyricsFormat(self.format_comboBox.currentIndex())
            if not main_item:
                continue

            file_path: Path = main_item.data(Qt.ItemDataRole.UserRole)

            # 保持原文件结构
            relative_path = file_path.relative_to(file_path.parent)
            new_path = (file_path.parent if self.save_root_path is None else self.save_root_path) / relative_path

            # 修改扩展名
            save_path = new_path.with_suffix(target_format.ext)

            self.files_table.setItem(row, 1, QTableWidgetItem(str(save_path)))
            main_item.setData(Qt.ItemDataRole.UserRole + 1, save_path)

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        if event.mimeData().hasUrls() and self.taskmanager.is_finished():
            event.acceptProposedAction()
        else:
            event.ignore()

    def dropEvent(self, event: QDropEvent) -> None:
        mime = event.mimeData()
        if not mime.hasUrls():
            return

        extensions = {lyric_format.ext.lower() for lyric_format in LyricsFormat.__members__.values()}
        search_method = Path.rglob if self.recursive_checkBox.isChecked() else Path.glob
        files = []

        for url in mime.urls():
            path = Path(url.toLocalFile())
            if path.is_file() and path.suffix.lower() in extensions:
                files.append(path)
            elif path.is_dir():
                files.extend(file for ext in extensions for file in search_method(path, f"*{ext}"))

        if files:
            self.add_to_table(files)
        else:
            MsgBox.information(self, self.tr("提示"), self.tr("未找到支持的歌词文件"))

    def contextMenuEvent(self, event: QContextMenuEvent) -> None:
        if not self.files_table.geometry().contains(event.pos()):  # 判断是否在表格内点击
            return
        selected_rows = self.files_table.selectionModel().selectedRows()
        if not selected_rows:
            return
        menu = QMenu(self)
        if self.taskmanager.is_finished():
            menu.addAction(self.tr("删除"), lambda rows=selected_rows: [self.files_table.removeRow(row.row()) for row in reversed(rows)])
        if len(selected_rows) == 1:
            file_item = self.files_table.item(selected_rows[0].row(), 0)
            save_path_item = self.files_table.item(selected_rows[0].row(), 1)
            if not file_item or not save_path_item:
                return
            file_path: Path = file_item.data(Qt.ItemDataRole.UserRole)
            save_path: Path = file_item.data(Qt.ItemDataRole.UserRole + 1)

            menu.addAction(self.tr("打开原歌词目录"), lambda path=file_path: QDesktopServices.openUrl(QUrl.fromLocalFile(path.parent)))
            menu.addAction(self.tr("打开保存目录"), lambda path=save_path: QDesktopServices.openUrl(QUrl.fromLocalFile(path.parent)))
            if save_path.is_file():
                menu.addAction(self.tr("打开歌词文件"), lambda path=save_path: QDesktopServices.openUrl(QUrl.fromLocalFile(path)))
                menu.addAction(self.tr("在打开歌词界面中打开"), lambda path=save_path: self.open_lyrics.emit(path))
        menu.exec_(event.globalPos())

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if event.key() == Qt.Key.Key_Delete and self.taskmanager.is_finished():
            # 获取所有选中的行并删除
            selected_rows = {index.row() for index in self.files_table.selectionModel().selectedRows()}
            for row in sorted(selected_rows, reverse=True):
                self.files_table.removeRow(row)
        else:
            super().keyPressEvent(event)
