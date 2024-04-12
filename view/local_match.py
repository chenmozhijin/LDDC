import os

from PySide6.QtCore import QThreadPool
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFileDialog,
    QLineEdit,
    QListWidget,
    QMessageBox,
    QPushButton,
    QWidget,
)

from ui.local_match_ui import Ui_local_match
from utils.data import data
from utils.enum import LocalMatchFileNameMode, LocalMatchSaveMode, LyricsFormat, Source
from utils.worker import LocalMatchWorker


class LocalMatchWidget(QWidget, Ui_local_match):
    def __init__(self, threadpool: QThreadPool) -> None:
        super().__init__()

        self.data = data
        self.data_mutex = data.mutex
        self.threadpool = threadpool

        self.running = False

        self.setupUi(self)
        self.connect_signals()

        self.worker = None

        self.save_mode_changed(self.save_mode_comboBox.currentIndex())

        self.data_mutex.lock()
        self.save_path_lineEdit.setText(self.data.cfg["default_save_path"])
        self.data_mutex.unlock()

    def connect_signals(self) -> None:
        self.song_path_pushButton.clicked.connect(lambda: self.select_path(self.song_path_lineEdit))
        self.save_path_pushButton.clicked.connect(lambda: self.select_path(self.save_path_lineEdit))

        self.save_mode_comboBox.currentIndexChanged.connect(self.save_mode_changed)

        self.start_cancel_pushButton.clicked.connect(self.start_cancel_button_clicked)

    def select_path(self, path_line_edit: QLineEdit) -> None:
        path = QFileDialog.getExistingDirectory(self, self.tr("选择文件夹"), dir=path_line_edit.text())
        if path:
            path_line_edit.setText(os.path.normpath(path))

    def save_mode_changed(self, index: int) -> None:
        match index:
            case 0:
                self.save_path_lineEdit.setEnabled(True)
                self.save_path_pushButton.setEnabled(True)
                self.save_path_pushButton.setText(self.tr("选择镜像文件夹"))
            case 1:
                self.save_path_lineEdit.setEnabled(False)
                self.save_path_pushButton.setEnabled(False)
                self.save_path_pushButton.setText(self.tr("选择文件夹"))
            case 2:
                self.save_path_lineEdit.setEnabled(True)
                self.save_path_pushButton.setEnabled(True)
                self.save_path_pushButton.setText(self.tr("选择文件夹"))

    def start_cancel_button_clicked(self) -> None:
        if self.running:
            # 取消
            if self.worker is not None:
                self.worker.stop()
            self.worker_finished()
            return

        if not os.path.exists(self.song_path_lineEdit.text()):
            QMessageBox.warning(self, self.tr("警告"), self.tr("歌曲文件夹不存在！"))
            return

        lyric_types = []
        if self.original_checkBox.isChecked():
            lyric_types.append("orig")
        if self.translate_checkBox.isChecked():
            lyric_types.append("ts")
        if self.romanized_checkBox.isChecked():
            lyric_types.append("roma")
        type_mapping = {"原文": "orig", "译文": "ts", "罗马音": "roma"}
        self.data_mutex.lock()
        lyrics_order = [type_mapping[type_] for type_ in self.data.cfg["lyrics_order"] if type_mapping[type_] in lyric_types]
        self.data_mutex.unlock()

        if len(lyric_types) == 0:
            QMessageBox.warning(self, self.tr("警告"), self.tr("请选择至少一种歌词类型！"))

        match self.save_mode_comboBox.currentIndex():
            case 0:
                save_mode = LocalMatchSaveMode.MIRROR
            case 1:
                save_mode = LocalMatchSaveMode.SONG
            case 2:
                save_mode = LocalMatchSaveMode.SPECIFY
            case _:
                QMessageBox.critical(self, self.tr("错误"), self.tr("保存模式选择错误！"))
                return

        match self.lyrics_filename_mode_comboBox.currentIndex():
            case 0:
                flienmae_mode = LocalMatchFileNameMode.FORMAT
            case 1:
                flienmae_mode = LocalMatchFileNameMode.SONG
            case _:
                QMessageBox.critical(self, self.tr("错误"), self.tr("歌词文件名错误！"))
                return

        source = []
        for source_type in [self.source_listWidget.item(i).text() for i in range(self.source_listWidget.count())]:
            if source_type == self.tr("QQ音乐") and self.qm_checkBox.isChecked():
                source.append(Source.QM)
            elif source_type == self.tr("酷狗音乐") and self.kg_checkBox.isChecked():
                source.append(Source.KG)
            elif source_type == self.tr("网易云音乐") and self.ne_checkBox.isChecked():
                source.append(Source.NE)
        if len(source) == 0:
            QMessageBox.warning(self, self.tr("警告"), self.tr("请选择至少一个源！"))
            return

        self.running = True
        self.plainTextEdit.setPlainText("")
        self.start_cancel_pushButton.setText(self.tr("取消匹配"))
        for item in self.findChildren(QWidget):
            if isinstance(item, QLineEdit | QPushButton | QComboBox | QCheckBox | QListWidget) and item != self.start_cancel_pushButton:
                item.setEnabled(False)

        self.worker = LocalMatchWorker(
            {
                "song_path": self.song_path_lineEdit.text(),
                "save_path": self.save_path_lineEdit.text(),
                "save_mode": save_mode,
                "flienmae_mode": flienmae_mode,
                "lyrics_order": lyrics_order,
                "lyrics_format": LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
                "sources": source,
            },
            self.threadpool,
            self.data,
        )
        self.worker.signals.error.connect(self.worker_error)
        self.worker.signals.finished.connect(self.worker_finished)
        self.worker.signals.massage.connect(self.worker_massage)
        self.threadpool.start(self.worker)

    def worker_massage(self, massage: str) -> None:
        self.plainTextEdit.appendPlainText(massage)

    def worker_finished(self) -> None:
        self.start_cancel_pushButton.setText(self.tr("开始匹配"))
        self.running = False
        for item in self.findChildren(QWidget):
            if isinstance(item, QLineEdit | QPushButton | QComboBox | QCheckBox | QListWidget):
                item.setEnabled(True)
        self.save_mode_changed(self.save_mode_comboBox.currentIndex())

    def worker_error(self, error: str, level: int) -> None:
        if level == 0:
            self.plainTextEdit.appendPlainText(error)
        else:
            QMessageBox.critical(self, self.tr("错误"), error)
            self.worker_finished()
