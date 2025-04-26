# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from pathlib import Path

from PySide6.QtCore import QMimeData, Qt, QUrl, Signal, Slot
from PySide6.QtGui import QContextMenuEvent, QDesktopServices, QDragEnterEvent, QDropEvent, QKeyEvent
from PySide6.QtWidgets import QFileDialog, QMenu, QTableWidgetItem, QWidget

from LDDC.common.data.config import cfg
from LDDC.common.models import LyricsFormat, SongInfo, Source
from LDDC.common.models._enums import FileNameMode, SaveMode
from LDDC.common.path_processor import get_local_match_save_path
from LDDC.common.paths import default_save_lyrics_dir
from LDDC.common.task_manager import TaskManager
from LDDC.gui.components.msg_box import MsgBox
from LDDC.gui.ui.local_match_ui import Ui_local_match
from LDDC.gui.workers.local_match import (
    GetInfosWorker,
    LocalMatchingStatus,
    LocalMatchingStatusType,
    LocalMatchSave2TagMode,
    LocalMatchWorker,
)


class LocalMatchWidget(QWidget, Ui_local_match):
    search_song = Signal(SongInfo)

    _get_infos_callback_signal = Signal(str, int, int, SongInfo)

    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.setAcceptDrops(True)  # 启用拖放功能
        self.connect_signals()

        self.songs_table.set_proportions([0.2, 0.1, 0.1, 0.3, 2, 0.3, 2])  # 设置列宽比例
        self.source_listWidget.set_soures(["QM", "KG", "NE"])

        def restore_start_cancel() -> None:
            if self.taskmanager.is_finished():
                self.start_cancel_pushButton.setText(self.tr("开始"))
                self.start_cancel_pushButton.setEnabled(True)

        def restore() -> None:
            restore_start_cancel()
            for widget in self.control_bar.children():
                if isinstance(widget, QWidget):
                    widget.setEnabled(True)

        self.taskmanager = TaskManager({"get_infos": [], "local_match": []}, {"get_infos": restore_start_cancel, "local_match": restore})
        self.save_root_path: Path | None = None  # 保存根目录
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

    @Slot(str, int, int)
    def update_progressbar(self, text: str, value: int, max_value: int) -> None:
        """更新进度条"""
        self.progressBar.setMaximum(max_value)
        self.progressBar.setValue(value)
        self.status_label.setText(text)

    @Slot()
    def start_cancel(self) -> None:
        if not self.taskmanager.is_finished():
            self.taskmanager.cancel()
            self.start_cancel_pushButton.setEnabled(False)
            self.start_cancel_pushButton.setText(self.tr("取消中..."))
            return

        if LocalMatchSave2TagMode(self.save2tag_mode_comboBox.currentIndex()) in (
            LocalMatchSave2TagMode.ONLY_TAG,
            LocalMatchSave2TagMode.BOTH,
        ) and LyricsFormat(self.lyricsformat_comboBox.currentIndex()) not in (LyricsFormat.VERBATIMLRC, LyricsFormat.LINEBYLINELRC, LyricsFormat.ENHANCEDLRC):
            MsgBox.warning(self, self.tr("警告"), self.tr("歌曲标签中的歌词应为LRC格式"))
            return

        if not self.langs:
            MsgBox.warning(self, self.tr("警告"), self.tr("请选择要匹配的语言"))
            return

        if len(sources := [Source[k] for k in self.source_listWidget.get_data()]) == 0:
            MsgBox.warning(self, self.tr("警告"), self.tr("请选择至少一个源！"))
            return

        if self.save_path_errors:
            MsgBox.warning(self, self.tr("警告"), "\n".join(self.save_path_errors))
            return

        if not (infos := self.get_table_infos()):
            MsgBox.warning(self, self.tr("警告"), self.tr("请选择要匹配的歌曲！"))
            return

        skip_existing_lyrics = self.skip_existing_lyrics_checkbox.isChecked()  # 获取跳过已存在歌词的选项状态
        save2tag_mode=LocalMatchSave2TagMode(self.save2tag_mode_comboBox.currentIndex())
        file_name_mode=FileNameMode(self.filename_mode_comboBox.currentIndex())
        if skip_existing_lyrics and (save2tag_mode != LocalMatchSave2TagMode.ONLY_TAG and file_name_mode == FileNameMode.FORMAT_BY_LYRICS):
            MsgBox.warning(self, self.tr("警告"), self.tr("跳过已存在歌词时,如果不仅保存到标签,则歌曲文件名模式不能为按歌词格式命名！"))
            return


        worker = LocalMatchWorker(
            infos_root_paths=infos,
            save_mode=SaveMode(self.save_mode_comboBox.currentIndex()),
            file_name_mode=file_name_mode,
            save2tag_mode=save2tag_mode,
            lyrics_format=LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
            langs=self.langs,
            save_root_path=self.save_root_path,
            min_score=self.min_score_spinBox.value(),
            sources=sources,
            skip_existing_lyrics=skip_existing_lyrics,
        )
        worker.progress.connect(
            lambda text, value, max_value, status: (self.update_progressbar(text, value, max_value), self.update_status(status) if status else None),
        )
        worker.finished.connect(
            lambda total, success_count, fail_count, skip_count: self.tr("总共{total}首歌曲，匹配成功{success}首，匹配失败{fail}首，跳过{skip}首。").format(
                total=total,
                success=success_count,
                fail=fail_count,
                skip=skip_count,
            ),
        )
        self.taskmanager.run_worker("local_match", worker)

        self.start_cancel_pushButton.setText(self.tr("取消(匹配歌词)"))

        for widget in self.control_bar.children():
            if isinstance(widget, QWidget) and widget != self.start_cancel_pushButton:
                widget.setEnabled(False)

    def add2table(self, infos: list[tuple[SongInfo, Path | None]]) -> None:
        """添加文件信息到表格中

        Args:
            infos: 文件信息
            root_path: 文件根路径, 注意传入infos为list[SongInfo]时, root_path应该为None

        """
        existing_infos = self.get_table_infos()
        for info, root_path in infos:
            if (info, root_path) in existing_infos:
                continue
            i = self.songs_table.rowCount()
            self.songs_table.insertRow(i)
            item = QTableWidgetItem(info.title or "")
            item.setData(Qt.ItemDataRole.UserRole, info)
            item.setData(Qt.ItemDataRole.UserRole + 1, root_path)
            self.songs_table.setItem(i, 0, item)
            self.songs_table.setItem(i, 1, QTableWidgetItem(info.str_artist))
            self.songs_table.setItem(i, 2, QTableWidgetItem(info.album or ""))
            self.songs_table.setItem(i, 3, QTableWidgetItem(str(info.path) if info.path else ""))
            if info.duration is not None:
                self.songs_table.setItem(i, 4, QTableWidgetItem(info.format_duration))
            self.songs_table.setItem(i, 6, QTableWidgetItem(self.tr("未匹配")))
        self.update_save_paths()

    def update_status(self, status: LocalMatchingStatus) -> None:
        status_item, info_item = self.songs_table.item(status.index, 6), self.songs_table.item(status.index, 0)
        if not status_item or not info_item:
            MsgBox.critical(self, self.tr("错误"), self.tr("对应的引索{}不存在").format(status.index))
            return
        info_item.setData(Qt.ItemDataRole.UserRole + 2, status)
        match status.status:
            case LocalMatchingStatusType.SUCCESS:
                status_item.setForeground(Qt.GlobalColor.green)
                status_item.setText(self.tr("成功"))
                if status.path:
                    info = info_item.data(Qt.ItemDataRole.UserRole)
                    if (
                        LocalMatchSave2TagMode(self.save2tag_mode_comboBox.currentIndex()) in (LocalMatchSave2TagMode.ONLY_TAG, LocalMatchSave2TagMode.BOTH)
                        and info["type"] != "cue"
                    ):
                        self.songs_table.setItem(status.index, 5, QTableWidgetItem(f"{self.tr('保存到标签')} + {status.path!s}"))
                    else:
                        self.songs_table.setItem(status.index, 5, QTableWidgetItem(str(status.path)))
            case LocalMatchingStatusType.SKIP_INST | LocalMatchingStatusType.SKIP_EXISTING:
                status_item.setForeground(Qt.GlobalColor.blue)
                status_item.setText(self.tr("跳过"))

            case _:
                status_item.setForeground(Qt.GlobalColor.red)
                status_item.setText(self.tr("失败"))
        status_item.setToolTip(status.text)

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

        worker = GetInfosWorker(self, mime)
        worker.progress.connect(self.update_progressbar)
        worker.finished.connect(
            lambda result, errors: (self.add2table(result) if result else None, MsgBox.critical(self, self.tr("错误"), "\n".join(errors)) if errors else None),
        )
        self.taskmanager.run_worker("get_infos", worker)
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

    def dragEnterEvent(self, event: QDragEnterEvent) -> None:
        formats = event.mimeData().formats()
        if (
            event.mimeData().hasUrls()
            or 'application/x-qt-windows-mime;value="foobar2000_playable_location_format"' in formats
            or 'application/x-qt-windows-mime;value="ACL.FileURIs"' in formats
        ) and self.taskmanager.is_finished("local_match"):
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

    @Slot()
    def select_save_root_path(self) -> None:
        """选择保存根目录"""

        @Slot(str)
        def set_save_root_path(path: str) -> None:
            self.save_root_path = Path(path).resolve()
            self.update_save_paths()

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择保存根目录"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.fileSelected.connect(set_save_root_path)
        dialog.setDirectory(str(default_save_lyrics_dir))
        dialog.open()

    @Slot(str)
    def select_root_path(self, rows: list[int]) -> None:
        @Slot(str)
        def set_root_path(path_str: str) -> None:
            path = Path(path_str)
            skips = []
            for row in rows:
                info_item = self.songs_table.item(row, 0)
                if not info_item:
                    MsgBox.critical(self, self.tr("错误"), self.tr("对应的引索{}不存在").format(row))
                    continue
                info: SongInfo = info_item.data(Qt.ItemDataRole.UserRole)
                if not info.path:
                    raise ValueError(self.tr("歌曲{}的路径为空").format(info.artist_title()))

                # 检查驱动器是否相同(仅在 Windows 上适用)
                # 检查文件路径是否以目录路径为前缀
                if info.path.is_relative_to(path):
                    info_item.setData(Qt.ItemDataRole.UserRole + 1, path)
                else:
                    skips.append(str(info.path))

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
        dialog.setDirectory(str(info_item.data(Qt.ItemDataRole.UserRole).path.parent))
        dialog.fileSelected.connect(set_root_path)
        dialog.open()

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

    def get_table_infos(self) -> list[tuple[SongInfo, Path | None]]:
        """获取表格中的文件信息

        :return: 文件信息列表
        """
        infos: list[tuple[SongInfo, Path | None]] = []
        for row in range(self.songs_table.rowCount()):
            item = self.songs_table.item(row, 0)
            if item is not None:
                infos.append((item.data(Qt.ItemDataRole.UserRole), item.data(Qt.ItemDataRole.UserRole + 1)))
        return infos

    @Slot()
    def update_save_paths(self) -> None:
        """更新保存路径"""
        save_mode = SaveMode(self.save_mode_comboBox.currentIndex())
        file_name_mode = FileNameMode(self.filename_mode_comboBox.currentIndex())
        save2tag_mode = LocalMatchSave2TagMode(self.save2tag_mode_comboBox.currentIndex())
        lyrics_format = LyricsFormat(self.lyricsformat_comboBox.currentIndex())
        langs = self.langs
        file_name_format = cfg["lyrics_file_name_fmt"]

        self.save_path_errors.clear()

        for row in range(self.songs_table.rowCount()):
            info_item = self.songs_table.item(row, 0)
            if not info_item:
                MsgBox.critical(self, self.tr("错误"), self.tr("对应的引索{}不存在").format(row))
                continue
            info: SongInfo = info_item.data(Qt.ItemDataRole.UserRole)
            song_root_path: Path | None = info_item.data(Qt.ItemDataRole.UserRole + 1)
            save_path_text = ""

            if save2tag_mode in (LocalMatchSave2TagMode.ONLY_TAG, LocalMatchSave2TagMode.BOTH) and info.from_cue is False:
                save_path_text += self.tr("保存到标签")

            if info.from_cue is True or save2tag_mode != LocalMatchSave2TagMode.ONLY_TAG:
                save_path = get_local_match_save_path(
                    save_mode=save_mode,
                    file_name_mode=file_name_mode,
                    local_info=info,
                    lyrics_format=lyrics_format,
                    file_name_format=file_name_format,
                    langs=langs,
                    save_root_path=self.save_root_path,
                    allow_placeholder=True,
                    song_root_path=song_root_path,
                )
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
                save_path_text += f" + {save_path!s}" if save_path_text else str(save_path)

            self.songs_table.setItem(row, 5, QTableWidgetItem(save_path_text))

    def contextMenuEvent(self, event: QContextMenuEvent) -> None:
        if not self.songs_table.geometry().contains(event.pos()):  # 判断否在表格内点击
            return
        selected_rows = self.songs_table.selectionModel().selectedRows()
        if not selected_rows:
            return
        menu = QMenu(self)
        if self.taskmanager.is_finished("local_match"):
            menu.addAction(self.tr("删除"), lambda rows=selected_rows: [self.songs_table.removeRow(row.row()) for row in reversed(rows)])
            #  反向删除,防止删除行后影响后续行号
            menu.addAction(self.tr("指定根目录"), lambda rows=selected_rows: self.select_root_path([row.row() for row in rows]))
        if len(selected_rows) == 1:
            info_item = self.songs_table.item(selected_rows[0].row(), 0)
            if not info_item:
                return
            menu.addAction(
                self.tr("打开歌曲目录"),
                lambda info_item=info_item: QDesktopServices.openUrl(QUrl.fromLocalFile(str(info_item.data(Qt.ItemDataRole.UserRole).path.parent))),
            )
            menu.addAction(self.tr("在搜索中打开"), lambda info_item=info_item: self.search_song.emit(info_item.data(Qt.ItemDataRole.UserRole)))
            if (
                (completion_status := info_item.data(Qt.ItemDataRole.UserRole + 2))  # 获取完成状态
                and isinstance(completion_status, LocalMatchingStatus)  # 检查是否为字典
                and (save_path := completion_status.path)
            ):  # 获取保存路径
                menu.addAction(self.tr("打开保存目录"), lambda save_path=save_path: QDesktopServices.openUrl(QUrl.fromLocalFile(save_path.parent)))
                menu.addAction(self.tr("打开歌词"), lambda save_path=save_path: QDesktopServices.openUrl(QUrl.fromLocalFile(save_path)))
        menu.exec_(event.globalPos())

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if event.key() == Qt.Key.Key_Delete and self.taskmanager.is_finished("local_match"):
            # 获取所有选中的行并删除
            selected_rows = {index.row() for index in self.songs_table.selectionModel().selectedRows()}
            for row in sorted(selected_rows, reverse=True):
                self.songs_table.removeRow(row)
        else:
            super().keyPressEvent(event)
