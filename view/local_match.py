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
from utils.api import Source
from utils.data import Data
from utils.worker import LocalMatchFileNameMode, LocalMatchSaveMode, LocalMatchWorker


class LocalMatchWidget(QWidget, Ui_local_match):
    def __init__(self, data: Data, threadpool: QThreadPool) -> None:
        super().__init__()

        self.data = data
        self.data_mutex = data.mutex
        self.threadpool = threadpool

        self.running = False

        self.setupUi(self)
        self.connect_signals()

        self.worker = None

    def connect_signals(self) -> None:
        self.song_path_pushButton.clicked.connect(lambda: self.select_path(self.song_path_lineEdit))
        self.save_path_pushButton.clicked.connect(lambda: self.select_path(self.save_path_lineEdit))

        self.save_mode_comboBox.currentIndexChanged.connect(self.save_mode_changed)
        self.source_comboBox.currentIndexChanged.connect(self.source_mode_changed)

        self.start_cancel_pushButton.clicked.connect(self.start_cancel_button_clicked)

    def select_path(self, path_line_edit: QLineEdit) -> None:
        path = QFileDialog.getExistingDirectory(self, "选择文件夹", dir=path_line_edit.text())
        if path:
            path_line_edit.setText(os.path.normpath(path))

    def save_mode_changed(self, index: int) -> None:
        match index:
            case 0:
                self.save_path_lineEdit.setEnabled(True)
                self.save_path_pushButton.setEnabled(True)
                self.save_path_pushButton.setText("选择镜像文件夹")
            case 1:
                self.save_path_lineEdit.setEnabled(False)
                self.save_path_pushButton.setEnabled(False)
                self.save_path_pushButton.setText("选择文件夹")
            case 2:
                self.save_path_lineEdit.setEnabled(True)
                self.save_path_pushButton.setEnabled(True)
                self.save_path_pushButton.setText("选择文件夹")

    def source_mode_changed(self, index: int) -> None:
        if index == 1:
            self.source_listWidget.setEnabled(True)
        else:
            self.source_listWidget.setEnabled(False)

    def start_cancel_button_clicked(self) -> None:
        if self.running:
            # 取消
            if self.worker is not None:
                self.worker.stop()
            self.worker_finished()
            return

        if self.save_mode_comboBox.currentIndex() != 1 and not os.path.exists(self.save_path_lineEdit.text()):
            QMessageBox.warning(self, "警告", "保存路径不存在！")
            return

        if not os.path.exists(self.song_path_lineEdit.text()):
            QMessageBox.warning(self, "警告", "歌曲文件夹不存在！")
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
            QMessageBox.warning(self, "警告", "请选择至少一种歌词类型！")

        match self.save_mode_comboBox.currentIndex():
            case 0:
                save_mode = LocalMatchSaveMode.MIRROR
            case 1:
                save_mode = LocalMatchSaveMode.SONG
            case 2:
                save_mode = LocalMatchSaveMode.SPECIFY

        match self.lyrics_filename_mode_comboBox.currentIndex():
            case 0:
                flienmae_mode = LocalMatchFileNameMode.FORMAT
            case 1:
                flienmae_mode = LocalMatchFileNameMode.SONG

        source = []
        match self.source_comboBox.currentIndex():
            case 0:
                source.append(Source.QM)
            case 1:
                source_mapping = {"QQ音乐": Source.QM, "酷狗音乐": Source.KG}
                source = [source_mapping[type_] for type_ in
                          [self.source_listWidget.item(i).text() for i in range(self.source_listWidget.count())]]
            case 2:
                source.append(Source.KG)

        self.running = True
        self.plainTextEdit.setPlainText("")
        self.start_cancel_pushButton.setText("取消匹配")
        for item in self.findChildren(QWidget):
            if isinstance(item, QLineEdit | QPushButton | QComboBox | QCheckBox | QListWidget) and item != self.start_cancel_pushButton:
                item.setEnabled(False)

        self.worker = LocalMatchWorker(
            self.song_path_lineEdit.text(),
            self.save_path_lineEdit.text(),
            save_mode,
            flienmae_mode,
            lyrics_order,
            source,
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
        self.start_cancel_pushButton.setText("开始匹配")
        self.running = False
        for item in self.findChildren(QWidget):
            if isinstance(item, QLineEdit | QPushButton | QComboBox | QCheckBox | QListWidget):
                item.setEnabled(True)
        self.save_mode_changed(self.save_mode_comboBox.currentIndex())
        self.source_mode_changed(self.source_comboBox.currentIndex())

    def worker_error(self, error: str, level: int) -> None:
        if level == 0:
            self.plainTextEdit.appendPlainText(error)
        else:
            QMessageBox.critical(self, "错误", error)
            self.worker_finished()
