# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import os
from logging import Logger

from PySide6.QtCore import SignalInstance
from PySide6.QtWidgets import QFileDialog, QWidget

from ui.settings_ui import Ui_settings
from utils.cache import cache
from utils.data import data
from utils.translator import load_translation
from utils.utils import str2log_level


class SettingWidget(QWidget, Ui_settings):

    def __init__(self, logger: Logger, widget_changed_signal: SignalInstance) -> None:
        super().__init__()
        self.logger = logger
        self.setupUi(self)
        self.init_ui()
        self.widget_changed_signal = widget_changed_signal
        self.widget_changed_signal.connect(self.update_cache_size)
        self.connect_signals()

    def init_ui(self) -> None:
        self.lyrics_order_listWidget.clear()
        self.lyrics_order_listWidget.addItems(data.cfg["lyrics_order"])
        self.lyrics_file_name_format_lineEdit.setText(data.cfg["lyrics_file_name_format"])
        self.default_save_path_lineEdit.setText(data.cfg["default_save_path"])
        self.log_level_comboBox.setCurrentText(data.cfg["log_level"])
        self.skip_inst_lyrics_checkBox.setChecked(data.cfg["skip_inst_lyrics"])
        self.auto_select_checkBox.setChecked(data.cfg["auto_select"])
        match data.cfg["language"]:
            case "auto":
                self.language_comboBox.setCurrentIndex(0)
            case "en":
                self.language_comboBox.setCurrentIndex(1)
            case "zh-Hans":
                self.language_comboBox.setCurrentIndex(2)
        self.lrc_ms_digit_count_spinBox.setValue(data.cfg["lrc_ms_digit_count"])

    def select_default_save_path(self) -> None:
        path = QFileDialog.getExistingDirectory(self, self.tr("选择默认保存路径"))
        if path:
            self.default_save_path_lineEdit.setText(os.path.normpath(path))

    def update_cache_size(self) -> None:
        self.cache_size_label.setText(self.tr("缓存大小:") + f" {cache.volume() / 1000000 } MB")

    def clear_cache(self) -> None:
        cache.clear()
        self.update_cache_size()

    def connect_signals(self) -> None:
        self.lyrics_order_listWidget.droped.connect(self.lyrics_order_changed)

        self.lyrics_file_name_format_lineEdit.textChanged.connect(
            lambda: data.write_config("lyrics_file_name_format", self.lyrics_file_name_format_lineEdit.text()))

        self.default_save_path_lineEdit.textChanged.connect(
            lambda: data.write_config("default_save_path", self.default_save_path_lineEdit.text()))

        self.log_level_comboBox.currentTextChanged.connect(
            lambda: data.write_config("log_level", self.log_level_comboBox.currentText()))
        self.log_level_comboBox.currentTextChanged.connect(
            lambda: self.logger.setLevel(str2log_level(self.log_level_comboBox.currentText())))

        self.select_default_save_path_pushButton.clicked.connect(self.select_default_save_path)

        self.skip_inst_lyrics_checkBox.stateChanged.connect(
            lambda: data.write_config("skip_inst_lyrics", self.skip_inst_lyrics_checkBox.isChecked()))

        self.auto_select_checkBox.stateChanged.connect(
            lambda: data.write_config("auto_select", self.auto_select_checkBox.isChecked()))

        self.language_comboBox.currentIndexChanged.connect(self.language_comboBox_changed)

        self.lrc_ms_digit_count_spinBox.valueChanged.connect(
            lambda: data.write_config("lrc_ms_digit_count", self.lrc_ms_digit_count_spinBox.value()),
        )

        self.clear_cache_pushButton.clicked.connect(self.clear_cache)

    def language_comboBox_changed(self, index: int) -> None:
        match index:
            case 0:
                data.write_config("language", "auto")
            case 1:
                data.write_config("language", "en")
            case 2:
                data.write_config("language", "zh-Hans")
        load_translation()

    def lyrics_order_changed(self) -> None:
        lyrics_order = []
        for type_ in [self.lyrics_order_listWidget.item(i).text()
                      for i in range(self.lyrics_order_listWidget.count())]:
            if type_ == self.tr("罗马音"):
                lyrics_order.append("罗马音")
            elif type_ == self.tr("原文"):
                lyrics_order.append("原文")
            elif type_ == self.tr("译文"):
                lyrics_order.append("译文")
            else:
                msg = "Unknown lyrics type"
                raise ValueError(msg)

        data.write_config("lyrics_order", lyrics_order)
