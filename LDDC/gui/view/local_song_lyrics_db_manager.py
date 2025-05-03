# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import json
import os
from collections.abc import Callable
from dataclasses import replace
from pathlib import Path

from PySide6.QtCore import QCoreApplication, Qt, Signal, Slot
from PySide6.QtGui import QCloseEvent, QShowEvent
from PySide6.QtWidgets import QDialog, QFileDialog, QLineEdit, QTableWidgetItem, QWidget

from LDDC.common.data.config import cfg
from LDDC.common.data.local_song_lyrics_db import local_song_lyrics
from LDDC.common.logger import logger
from LDDC.common.models import (
    FileNameMode,
    LyricInfo,
    LyricsFormat,
    SaveMode,
)
from LDDC.common.path_processor import get_local_match_save_path
from LDDC.common.thread import cross_thread_func, in_main_thread, in_other_thread
from LDDC.common.time import ms2formattime
from LDDC.core.api.lyrics import get_lyrics
from LDDC.gui.components.msg_box import MsgBox
from LDDC.gui.exit_manager import exit_manager
from LDDC.gui.ui.local_song_lyrics_db_manager.dir_selector_ui import Ui_DirSelectorDialog
from LDDC.gui.ui.local_song_lyrics_db_manager.export_lyrics_ui import Ui_export_lyrics
from LDDC.gui.ui.local_song_lyrics_db_manager.local_song_lyrics_db_manager_ui import Ui_LocalSongLyricsDBManager
from LDDC.gui.ui.progres_ui import Ui_progressDialog


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
        old_path = Path(self.old_lineEdit.text())
        new_path = Path(self.new_lineEdit.text())
        if not new_path.exists():
            MsgBox.critical(self, self.tr("错误"), self.tr("新路径不存在"))
            return
        if old_path == new_path:
            MsgBox.warning(self, self.tr("警告"), self.tr("新旧路径相同"))
            return
        if not old_path:
            MsgBox.critical(self, self.tr("错误"), self.tr("旧路径为空"))
            return
        in_other_thread(
            self.change_dir,
            lambda count: MsgBox.information(self._parent, self.tr("成功"), self.tr("修改成功, 共修改了 {0} 条数据").format(count)),
            MsgBox.get_error_slot(self._parent, self.tr("失败"), self.tr("修改失败")),
            old_path,
            new_path,
            self.del_old_checkBox.isChecked(),
        )
        self.close()

    def change_dir(self, old_dir: Path, new_dir: Path, del_old: bool) -> int:
        def migrate_path(original_path: Path | None) -> Path | None:
            if not original_path or not original_path.is_relative_to(old_dir):
                return None
            new_path = new_dir / original_path.relative_to(old_dir)
            return new_path if new_path.is_file() else None

        progress_dialog = in_main_thread(self._parent.get_progress_dialog)
        all_data = local_song_lyrics.get_all_songinfo()
        new_songs = []
        total = len(all_data)
        frequency = max(total // 20, 1) if total else 1  # 进度更新频率
        success_count = 0
        for i, (k, song_info, lyrics_path, config) in enumerate(all_data):
            new_song_path, new_lyrics_path = migrate_path(song_info.path), migrate_path(lyrics_path)
            if new_song_path or new_lyrics_path:  # 检查路径是否需要迁移
                if del_old:
                    local_song_lyrics.del_item(k)
                updated_song = (
                    replace(song_info, path=new_song_path) if new_song_path else song_info,
                    new_lyrics_path if new_lyrics_path else lyrics_path,
                    config,
                )  # 构建更新后的歌曲信息元组

                if not any(d[1:4] == updated_song for d in all_data):  # 避免添加重复记录并计数成功迁移
                    new_songs.append(updated_song)
                    success_count += 1
                if i % frequency == 0:
                    progress_dialog.set_progress_signal.emit(i, total)
        local_song_lyrics.set_songs(new_songs)  # 批量写入新数据
        progress_dialog.close()
        return success_count


class ExportLyricsDialog(QDialog, Ui_export_lyrics):
    def __init__(self, parent: "LocalSongLyricsDBManager") -> None:
        super().__init__(parent)
        self.setupUi(self)
        self.setWindowModality(Qt.WindowModality.WindowModal)

        self.save_path_button.clicked.connect(self.select_path)
        self.accepted.connect(self.to_export)
        self._parent = parent

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
    def select_path(self) -> None:
        @Slot(str)
        def file_selected(save_path: str) -> None:
            self.save_path_lineEdit.setText(os.path.normpath(save_path))

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择文件夹"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.fileSelected.connect(file_selected)
        dialog.open()

    @Slot()
    def to_export(self) -> None:
        progress_dialog = in_main_thread(self._parent.get_progress_dialog)
        in_other_thread(
            self.export,
            lambda result: MsgBox.information(self._parent, self.tr("成功"), self.tr("导出成功, 共导出了 {0}/{1} 条数据").format(result[0], result[1])),
            (MsgBox.get_error_slot(self._parent, self.tr("失败"), self.tr("导出失败")), lambda _: progress_dialog.close()),
            SaveMode.SPECIFY,
            LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
            self.get_langs(),
            FileNameMode(self.filename_mode_comboBox.currentIndex()),
            Path(self.save_path_lineEdit.text()),
            progress_dialog,
        )
        self.close()

    def export(
        self,
        save_mode: SaveMode,
        lyrics_format: LyricsFormat,
        langs: list[str],
        file_name_mode: FileNameMode,
        save_root_path: Path,
        progress_dialog: "ProgresDialog",
    ) -> tuple[int, int]:
        all_data = local_song_lyrics.get_all_songinfo()
        total = len(all_data)
        frequency = max(total // 20, 1) if total else 1  # 进度更新频率
        file_name_format = cfg["lyrics_file_name_fmt"]
        success_count = 0
        skip_count = 0
        for i, (_id, song_info, lyrics_path, config) in enumerate(all_data):
            if config.get("inst") is True or not lyrics_path:
                skip_count += 1
                continue
            try:
                lyrics = get_lyrics(path=lyrics_path)
            except Exception:
                logger.exception("获取歌词失败: %s", lyrics_path)
                continue
            if cfg["lrc_tag_info_src"] == 1:
                # 从歌曲文件获取标签信息
                lyrics.info = LyricInfo(source=song_info.source, songinfo=song_info)
            converted_lyrics = lyrics.to(lyrics_format=lyrics_format, langs=langs)
            save_path = get_local_match_save_path(
                save_mode=save_mode,
                file_name_mode=file_name_mode,
                local_info=song_info,
                lyrics_format=lyrics_format,
                langs=langs,
                save_root_path=save_root_path,
                cloud_info=lyrics.info.songinfo,
                file_name_format=file_name_format,
            )
            if isinstance(save_path, int):
                logger.error("获取歌词保存路径失败，错误码: %s", save_path)
                continue
            if "? - ?" in save_path.stem:
                pass
            try:
                save_path.parent.mkdir(parents=True, exist_ok=True)

                with save_path.open("w", encoding="utf-8") as f:
                    f.write(converted_lyrics)
            except Exception:
                logger.exception("保存歌词失败")
                continue
            success_count += 1

            if i % frequency == 0:
                progress_dialog.set_progress_signal.emit(i, total)

        progress_dialog.close()
        return success_count, total - skip_count


class ProgresDialog(QDialog, Ui_progressDialog):
    set_progress_signal = Signal(int, int)

    def __init__(self, parent: QWidget, text: str) -> None:
        super().__init__(parent)
        self.setupUi(self)
        self.label.setText(text)
        self.setWindowModality(Qt.WindowModality.WindowModal)
        self.set_progress_signal.connect(self.set_progress)

        self.closeable = False

    @Slot(int, int)
    def set_progress(self, progress: int, total: int) -> None:
        self.progressBar.setMaximum(total)
        self.progressBar.setValue(progress)

    def closeEvent(self, event: QCloseEvent) -> None:
        if not self.closeable:
            event.ignore()
        super().closeEvent(event)
        self.closeable = False

    @cross_thread_func
    def show(self) -> None:
        return super().show()

    @cross_thread_func
    def close(self) -> bool:
        self.reset()
        self.closeable = True
        return super().close()

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
        self.delete_all_button.clicked.connect(
            lambda: in_other_thread(
                local_song_lyrics.del_all,
                lambda _: MsgBox.information(self, self.tr("成功"), self.tr("删除成功")),
                MsgBox.get_error_slot(self, self.tr("失败"), self.tr("删除失败")),
            ),
        )
        self.clear_button.clicked.connect(
            lambda: in_other_thread(
                self.clear,
                lambda count: MsgBox.information(self, self.tr("成功"), self.tr("清理成功, 共清理了 {0} 条数据").format(count)),
                MsgBox.get_error_slot(self, self.tr("失败"), self.tr("清理成功,")),
            ),
        )
        self.change_dir_button.clicked.connect(self.change_dir)
        self.backup_button.clicked.connect(lambda: self.run_select_path_task(self.backup))
        self.restore_button.clicked.connect(lambda: self.run_select_path_task(self.restore))
        self.export_lyrics_button.clicked.connect(self.export_lyrics)

    @Slot()
    def reset_table(self) -> None:
        data = local_song_lyrics.get_all()
        self.id_map = {i: item[0] for i, item in enumerate(data)}
        self.data_table.setRowCount(0)
        self.data_table.setColumnCount(8)
        self.data_table.setHorizontalHeaderLabels(
            [
                self.tr("歌曲名"),
                self.tr("艺术家"),
                self.tr("专辑"),
                self.tr("时长"),
                self.tr("歌曲路径"),
                self.tr("音轨号"),
                self.tr("歌词路径"),
                self.tr("配置"),
            ],
        )
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

    @Slot()
    def export_lyrics(self) -> None:
        self.export_lyrics_dialog = ExportLyricsDialog(self)
        self.export_lyrics_dialog.show()

    def run_select_path_task(self, task: Callable) -> None:
        @Slot(str)
        def file_selected(path_str: str) -> None:
            path = Path(path_str)
            in_other_thread(
                task,
                lambda _: MsgBox.information(self, self.tr("成功"), self.tr("操作成功")),
                MsgBox.get_error_slot(self, self.tr("失败"), self.tr("操作失败")),
                path,
            )


        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择文件"))
        match task:
            case self.backup:
                dialog.setFileMode(QFileDialog.FileMode.AnyFile)
            case self.restore:
                dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
        dialog.fileSelected.connect(file_selected)
        dialog.setNameFilter(self.tr("备份文件(*.json)"))
        dialog.open()

    def get_progress_dialog(self) -> ProgresDialog:
        self.progress_dialog = ProgresDialog(self, self.tr("正在处理中，请稍候..."))
        self.progress_dialog.show()
        return self.progress_dialog

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

    def backup(self, path: Path) -> None:
        path = path.with_suffix(".json")
        with Path(path).open("w", encoding="UTF-8") as f:
            json.dump(
                [
                    {
                        "title": item[1] if item[1] != "" else None,
                        "artist": item[2] if item[2] != "" else None,
                        "album": item[3] if item[3] != "" else None,
                        "duration": item[4] if item[4] != -1 else None,
                        "song_path": item[5] if item[5] != "" else None,
                        "track_number": item[6] if item[6] != "" else None,
                        "lyrics_path": item[7] if item[7] != "" else None,
                        "config": json.loads(item[8]),
                    }
                    for item in local_song_lyrics.get_all()
                ],
                f,
                ensure_ascii=False,
            )

    def restore(self, path: Path) -> None:
        with path.open(encoding="UTF-8") as f:
            json_data = json.load(f)
        if not isinstance(json_data, list):
            msg = "数据格式错误, 应为列表"
            raise TypeError(msg)

        local_song_lyrics.del_all()
        local_song_lyrics.set_items(
            [
                (
                    d["title"],
                    d["artist"],
                    d["album"],
                    d["duration"],
                    d["song_path"],
                    d["track_number"],
                    d["lyrics_path"],
                    d["config"],
                )
                for d in json_data
            ],
        )

    def clear(self) -> int:
        """清理无效数据"""
        items2del = [
            k
            for k, song_info, lyrics_path, config in local_song_lyrics.get_all_songinfo()
            if (song_info.path and not song_info.path.is_file()) or (lyrics_path and not lyrics_path.is_file())
        ]
        local_song_lyrics.del_items(items2del)
        return len(items2del)

    def del_all(self) -> str:
        local_song_lyrics.del_all()
        return QCoreApplication.translate("LocalSongLyricsDB", "删除成功")


local_song_lyrics_db_manager = LocalSongLyricsDBManager()
