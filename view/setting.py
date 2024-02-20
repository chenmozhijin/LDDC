# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import os
from logging import Logger

from PySide6.QtWidgets import QFileDialog, QWidget

from data import Data
from ui.settings_ui import Ui_settings
from utils import str2log_level


class SettingWidget(QWidget, Ui_settings):

    def __init__(self, data: Data, logger: Logger) -> None:
        super().__init__()
        self.data = data
        self.logger = logger
        self.setupUi(self)
        self.init_ui()
        self.connect_signals()

    def init_ui(self) -> None:
        self.lyrics_order_listWidget.clear()
        self.lyrics_order_listWidget.addItems(self.data.cfg["lyrics_order"])
        self.lyrics_file_name_format_lineEdit.setText(self.data.cfg["lyrics_file_name_format"])
        self.default_save_path_lineEdit.setText(self.data.cfg["default_save_path"])
        self.log_level_comboBox.setCurrentText(self.data.cfg["log_level"])
        self.skip_inst_lyrics_checkBox.setChecked(self.data.cfg["skip_inst_lyrics"])
        self.get_normal_lyrics_checkBox.setChecked(self.data.cfg["get_normal_lyrics"])
        self.auto_select_checkBox.setChecked(self.data.cfg["auto_select"])

    def select_default_save_path(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "选择默认保存路径")
        if path:
            self.default_save_path_lineEdit.setText(os.path.normpath(path))

    def connect_signals(self) -> None:
        self.lyrics_order_listWidget.droped.connect(lambda: self.data.write_config(
                                                    "lyrics_order",
                                                    [self.lyrics_order_listWidget.item(i).text()
                                                     for i in range(self.lyrics_order_listWidget.count())]))

        self.lyrics_file_name_format_lineEdit.textChanged.connect(
            lambda: self.data.write_config("lyrics_file_name_format", self.lyrics_file_name_format_lineEdit.text()))

        self.default_save_path_lineEdit.textChanged.connect(
            lambda: self.data.write_config("default_save_path", self.default_save_path_lineEdit.text()))

        self.log_level_comboBox.currentTextChanged.connect(
            lambda: self.data.write_config("log_level", self.log_level_comboBox.currentText()))
        self.log_level_comboBox.currentTextChanged.connect(
            lambda: self.logger.setLevel(str2log_level(self.log_level_comboBox.currentText())))

        self.select_default_save_path_pushButton.clicked.connect(self.select_default_save_path)

        self.skip_inst_lyrics_checkBox.stateChanged.connect(
            lambda: self.data.write_config("skip_inst_lyrics", self.skip_inst_lyrics_checkBox.isChecked()))

        self.get_normal_lyrics_checkBox.stateChanged.connect(
            lambda: self.data.write_config("get_normal_lyrics", self.get_normal_lyrics_checkBox.isChecked()))

        self.auto_select_checkBox.stateChanged.connect(
            lambda: self.data.write_config("auto_select", self.auto_select_checkBox.isChecked()))
