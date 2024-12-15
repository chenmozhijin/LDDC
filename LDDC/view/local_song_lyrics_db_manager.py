# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os
from typing import Any, Literal

from PySide6.QtCore import Qt, Slot
from PySide6.QtGui import QCloseEvent, QShowEvent
from PySide6.QtWidgets import QDialog, QFileDialog, QLineEdit, QTableWidgetItem, QWidget

from LDDC.backend.worker import LocalSongLyricsDBWorker
from LDDC.ui.local_song_lyrics_db_manager.dir_selector_ui import Ui_DirSelectorDialog
from LDDC.ui.local_song_lyrics_db_manager.local_song_lyrics_db_manager_ui import Ui_LocalSongLyricsDBManager
from LDDC.ui.progres_ui import Ui_progressDialog
from LDDC.utils.data import local_song_lyrics
from LDDC.utils.exit_manager import exit_manager
from LDDC.utils.thread import threadpool
from LDDC.utils.utils import ms2formattime

from .msg_box import MsgBox


class DirSelectorDialog(QDialog, Ui_DirSelectorDialog):
    def __init__(self, parent: "LocalSongLyricsDBManager") -> None:
        super().__init__(parent)
        self.setupUi(self)
        self.setWindowModality(Qt.WindowModality.WindowModal)

        self.old_pushButton.clicked.connect(lambda: self.select_path(self.old_lineEdit))
        self.new_pushButton.clicked.connect(lambda: self.select_path(self.new_lineEdit))
        self.accepted.connect(self.to_change)
        self._parent = parent

    def select_path(self, path_line_edit: QLineEdit) -> None:
        @Slot(str)
        def file_selected(save_path: str) -> None:
            path_line_edit.setText(os.path.normpath(save_path))
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择文件夹"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.fileSelected.connect(file_selected)
        dialog.open()

    @Slot()
    def to_change(self) -> None:
        old_path = self.old_lineEdit.text()
        new_path = self.new_lineEdit.text()
        if not os.path.exists(new_path):
            MsgBox.critical(self, self.tr("错误"), self.tr("新路径不存在"))
            return
        if old_path == new_path:
            MsgBox.warning(self, self.tr("警告"), self.tr("新旧路径相同"))
            return
        if not old_path:
            MsgBox.critical(self, self.tr("错误"), self.tr("旧路径为空"))
            return
        self._parent.run_task("change_dir", old_path, new_path, self.del_old_checkBox.isChecked())
        self.close()


class ProgresDialog(QDialog, Ui_progressDialog):
    def __init__(self, parent: QWidget, text: str) -> None:
        super().__init__(parent)
        self.setupUi(self)
        self.label.setText(text)
        self.setWindowModality(Qt.WindowModality.WindowModal)

    @Slot(int, int)
    def set_progress(self, progress: int, total: int) -> None:
        self.progressBar.setMaximum(total)
        self.progressBar.setValue(progress)

    def reset(self) -> None:
        self.progressBar.setMaximum(0)
        self.progressBar.setValue(0)
        self.label.setText("")


class LocalSongLyricsDBManager(QWidget, Ui_LocalSongLyricsDBManager):
    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        exit_manager.windows.append(self)

        self.data_table.set_proportions([0.3, 0.2, 0.1, 2, 0.2, 2, 0.1, 0.1])
        self.id_map = {}

        self.delete_button.clicked.connect(self.del_item)
        self.delete_all_button.clicked.connect(lambda: self.run_task("del_all"))
        self.clear_button.clicked.connect(lambda: self.run_task("clear"))
        self.change_dir_button.clicked.connect(self.change_dir)
        self.backup_button.clicked.connect(lambda: self.run_select_path_task("backup"))
        self.restore_button.clicked.connect(lambda: self.run_select_path_task("restore"))

    @Slot()
    def reset_table(self) -> None:
        data = local_song_lyrics.get_all()
        self.id_map = {i: item[0] for i, item in enumerate(data)}
        self.data_table.setRowCount(0)
        self.data_table.setColumnCount(8)
        self.data_table.setHorizontalHeaderLabels([self.tr('歌曲名'), self.tr('艺术家'), self.tr('专辑'), self.tr("时长"), self.tr("歌曲路径"),
                                                   self.tr("音轨号"), self.tr("歌词路径"), self.tr("配置")])
        for i, (_id, title, artist, album, duration, song_path, track_number, lyrics_path, config) in enumerate(data, self.data_table.rowCount()):
            self.data_table.insertRow(i)
            self.data_table.setItem(i, 0, QTableWidgetItem(title))
            self.data_table.setItem(i, 1, QTableWidgetItem(artist))
            self.data_table.setItem(i, 2, QTableWidgetItem(album))
            self.data_table.setItem(i, 3, QTableWidgetItem(ms2formattime(duration) if duration > 0 else ""))
            self.data_table.setItem(i, 4, QTableWidgetItem(song_path))
            self.data_table.setItem(i, 5, QTableWidgetItem(track_number))
            self.data_table.setItem(i, 6, QTableWidgetItem(lyrics_path))
            self.data_table.setItem(i, 7, QTableWidgetItem(str(config)))

    @Slot()
    def del_item(self) -> None:
        if not self.data_table.selectionModel().hasSelection():
            MsgBox.information(self, self.tr("提示"), self.tr("请先选择要删除的项"))
        for i in self.data_table.selectionModel().selectedRows():
            local_song_lyrics.del_item(self.id_map[i.row()])
        self.reset_table()

    @Slot()
    def change_dir(self) -> None:
        self.dir_selector = DirSelectorDialog(self)
        self.dir_selector.show()

    def run_select_path_task(self, task: Literal["backup", "restore"]) -> None:
        @Slot(str)
        def file_selected(save_path: str) -> None:
            self.run_task(task, save_path)
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择文件"))
        match task:
            case "backup":
                dialog.setFileMode(QFileDialog.FileMode.AnyFile)
            case "restore":
                dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
        dialog.fileSelected.connect(file_selected)
        dialog.setNameFilter(self.tr("备份文件(*.json)"))
        dialog.open()

    def run_task(self, task: Literal["backup", "restore", "clear", "change_dir", "del_all"], *args: Any, **kwargs: Any) -> None:
        worker = LocalSongLyricsDBWorker(task, *args, **kwargs)
        worker.signals.finished.connect(self.task_finished)
        self.progress_dialog = ProgresDialog(self, self.tr("正在处理中，请稍候..."))
        worker.signals.progress.connect(self.progress_dialog.set_progress)
        self.progress_dialog.show()
        local_song_lyrics.changed.disconnect(self.reset_table)
        threadpool.start(worker)

    @Slot()
    def task_finished(self, result: bool, msg: str) -> None:
        if result:
            MsgBox.information(self, self.tr("提示"), msg)
        else:
            MsgBox.critical(self, self.tr("错误"), msg)
        self.progress_dialog.close()
        self.reset_table()
        local_song_lyrics.changed.connect(self.reset_table)

    def showEvent(self, event: QShowEvent) -> None:
        local_song_lyrics.changed.connect(self.reset_table)
        self.reset_table()
        self.raise_()
        return super().showEvent(event)

    def closeEvent(self, event: QCloseEvent) -> None:
        if exit_manager.window_close_event(self):
            super().closeEvent(event)
        else:
            event.ignore()
            self.hide()


local_song_lyrics_db_manager = LocalSongLyricsDBManager()
