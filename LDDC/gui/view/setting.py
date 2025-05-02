# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os

from PySide6.QtCore import Qt, QUrl, Slot
from PySide6.QtGui import QDesktopServices, QFont, QFontDatabase, QGuiApplication
from PySide6.QtWidgets import QFileDialog, QListWidgetItem, QWidget

from LDDC.common.data.cache import cache
from LDDC.common.data.config import cfg
from LDDC.common.logger import logger
from LDDC.common.models import TranslateSource, TranslateTargetLanguage
from LDDC.common.paths import log_dir
from LDDC.common.translator import load_translation
from LDDC.gui.ui.settings_ui import Ui_settings


class SettingWidget(QWidget, Ui_settings):
    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.init_ui()
        self.connect_signals()

    def init_ui(self) -> None:
        # 保存设置
        self.lyrics_file_name_fmt_lineEdit.setText(cfg["lyrics_file_name_fmt"])
        self.default_save_path_lineEdit.setText(cfg["default_save_path"])
        self.id3_ver_comboBox.setCurrentText(cfg["ID3_version"])

        # 歌词设置
        self.langs_order_listWidget.clear()
        for o in cfg["langs_order"]:
            item = QListWidgetItem()
            item.setData(Qt.ItemDataRole.UserRole, o)
            match o:
                case "roma":
                    item.setText(self.tr("罗马音"))
                case "orig":
                    item.setText(self.tr("原文"))
                case "ts":
                    item.setText(self.tr("译文"))
            self.langs_order_listWidget.addItem(item)
        self.skip_inst_lyrics_checkBox.setChecked(cfg["skip_inst_lyrics"])
        self.auto_select_checkBox.setChecked(cfg["auto_select"])
        self.add_end_timestamp_line_checkBox.setChecked(cfg["add_end_timestamp_line"])
        self.lrc_ms_digit_count_spinBox.setValue(cfg["lrc_ms_digit_count"])
        self.last_ref_line_time_sty_comboBox.setCurrentIndex(cfg["last_ref_line_time_sty"])
        self.lrc_tag_info_src_comboBox.setCurrentIndex(cfg["lrc_tag_info_src"])

        # 桌面歌词部分
        self.played_color_list.set_colors(cfg["desktop_lyrics_played_colors"])
        self.unplayed_color_list.set_colors(cfg["desktop_lyrics_unplayed_colors"])

        self.lang_type_list.set_langs(cfg["desktop_lyrics_default_langs"], cfg["desktop_lyrics_langs_order"])
        self.source_list.set_soures(cfg["desktop_lyrics_sources"])

        self.font_comboBox.addItems(QFontDatabase.families())
        if cfg["desktop_lyrics_font_family"] in QFontDatabase.families():
            self.font_comboBox.setCurrentText(cfg["desktop_lyrics_font_family"])
        else:
            self.font_comboBox.setCurrentText(QFont().family())

        self.auto_frame_rate_checkBox.setChecked(bool(cfg["desktop_lyrics_refresh_rate"] == -1))
        self.frame_rate_spinBox.setDisabled(self.auto_frame_rate_checkBox.isChecked())
        if cfg["desktop_lyrics_refresh_rate"] >= 0:
            self.frame_rate_spinBox.setValue(cfg["desktop_lyrics_refresh_rate"])

        # 其他设置
        match cfg["language"]:
            case "auto":
                self.language_comboBox.setCurrentIndex(0)
            case "zh-Hans":
                self.language_comboBox.setCurrentIndex(1)
            case "zh-Hant":
                self.language_comboBox.setCurrentIndex(2)
            case "en":
                self.language_comboBox.setCurrentIndex(3)
            case "ja":
                self.language_comboBox.setCurrentIndex(4)

        self.color_scheme_mapping = {
            0: "auto",
            1: "dark",
            2: "light",
        }
        for i, v in self.color_scheme_mapping.items():
            if v == cfg["color_scheme"]:
                self.color_scheme_comboBox.setCurrentIndex(i)
                break

        self.log_level_comboBox.setCurrentText(cfg["log_level"])
        self.auto_check_update_checkBox.setChecked(cfg["auto_check_update"])

        # 翻译API设置
        self.translate_source_comboBox.setCurrentIndex(TranslateSource.__members__.get(cfg["translate_source"], TranslateSource(0)).value)
        self.translate_cfg_stackedWidget.setCurrentIndex(self.translate_source_comboBox.currentIndex())

        self.translate_target_lang_comboBox.setCurrentIndex(
            TranslateTargetLanguage.__members__.get(cfg["translate_target_lang"], TranslateTargetLanguage(0)).value,
        )
        self.oai_base_url_lineEdit.setText(cfg["openai_base_url"])
        self.oai_key_lineEdit.setText(cfg["openai_api_key"])
        self.oai_model_lineEdit.setText(cfg["openai_model"])

        # 搜索设置
        self.multi_search_source_list.set_soures(cfg["multi_search_sources"])

    @Slot()
    def select_default_save_path(self) -> None:
        @Slot(str)
        def file_selected(path: str) -> None:
            self.default_save_path_lineEdit.setText(os.path.normpath(path))

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("选择默认保存路径"))
        dialog.setFileMode(QFileDialog.FileMode.Directory)
        dialog.fileSelected.connect(file_selected)
        dialog.open()

    def connect_signals(self) -> None:
        # 保存设置
        self.lyrics_file_name_fmt_lineEdit.textChanged.connect(lambda: cfg.setitem("lyrics_file_name_fmt", self.lyrics_file_name_fmt_lineEdit.text()))

        self.default_save_path_lineEdit.textChanged.connect(lambda: cfg.setitem("default_save_path", self.default_save_path_lineEdit.text()))

        self.select_default_save_path_pushButton.clicked.connect(self.select_default_save_path)

        self.id3_ver_comboBox.currentIndexChanged.connect(lambda: cfg.setitem("ID3_version", self.id3_ver_comboBox.currentText()))

        # 歌词设置
        self.langs_order_listWidget.droped.connect(
            lambda: cfg.setitem(
                "langs_order",
                [self.langs_order_listWidget.item(i).data(Qt.ItemDataRole.UserRole) for i in range(self.langs_order_listWidget.count())],
            ),
        )

        self.skip_inst_lyrics_checkBox.stateChanged.connect(lambda: cfg.setitem("skip_inst_lyrics", self.skip_inst_lyrics_checkBox.isChecked()))

        self.auto_select_checkBox.stateChanged.connect(lambda: cfg.setitem("auto_select", self.auto_select_checkBox.isChecked()))

        self.add_end_timestamp_line_checkBox.stateChanged.connect(
            lambda: cfg.setitem("add_end_timestamp_line", self.add_end_timestamp_line_checkBox.isChecked()),
        )

        self.lrc_ms_digit_count_spinBox.valueChanged.connect(
            lambda: cfg.setitem("lrc_ms_digit_count", self.lrc_ms_digit_count_spinBox.value()),
        )

        self.last_ref_line_time_sty_comboBox.currentIndexChanged.connect(
            lambda: cfg.setitem("last_ref_line_time_sty", self.last_ref_line_time_sty_comboBox.currentIndex()),
        )

        self.lrc_tag_info_src_comboBox.currentIndexChanged.connect(
            lambda: cfg.setitem("lrc_tag_info_src", self.lrc_tag_info_src_comboBox.currentIndex()),
        )

        # 桌面歌词设置
        self.played_add_color_button.clicked.connect(lambda: self.played_color_list.open_color_dialog())
        self.played_del_color_button.clicked.connect(self.played_color_list.del_selected)
        self.played_color_list.color_changed.connect(
            lambda: cfg.setitem("desktop_lyrics_played_colors", self.played_color_list.get_colors()),
        )

        self.unplayed_add_color_button.clicked.connect(lambda: self.unplayed_color_list.open_color_dialog())
        self.unplayed_del_color_button.clicked.connect(self.unplayed_color_list.del_selected)
        self.unplayed_color_list.color_changed.connect(
            lambda: cfg.setitem("desktop_lyrics_unplayed_colors", self.unplayed_color_list.get_colors()),
        )

        self.lang_type_list.data_changed.connect(
            lambda: cfg.setitem("desktop_lyrics_default_langs", self.lang_type_list.get_data()),
        )
        self.lang_type_list.data_changed.connect(
            lambda: cfg.setitem("desktop_lyrics_langs_order", self.lang_type_list.get_order()),
        )
        self.source_list.data_changed.connect(
            lambda: cfg.setitem("desktop_lyrics_sources", self.source_list.get_data()),
        )

        self.font_comboBox.currentIndexChanged.connect(
            lambda: cfg.setitem("desktop_lyrics_font_family", self.font_comboBox.currentText()),
        )

        self.frame_rate_spinBox.valueChanged.connect(
            lambda: cfg.setitem("desktop_lyrics_refresh_rate", self.frame_rate_spinBox.value()),
        )

        self.auto_frame_rate_checkBox.stateChanged.connect(
            lambda: (
                cfg.setitem("desktop_lyrics_refresh_rate", -1 if self.auto_frame_rate_checkBox.isChecked() else self.frame_rate_spinBox.value()),
                self.frame_rate_spinBox.setDisabled(self.auto_frame_rate_checkBox.isChecked()),
            ),
        )

        from .local_song_lyrics_db_manager import local_song_lyrics_db_manager

        self.show_local_song_lyrics_db_manager_button.clicked.connect(local_song_lyrics_db_manager.show)

        # 其他设置
        self.language_comboBox.currentIndexChanged.connect(self.language_comboBox_changed)

        self.color_scheme_comboBox.currentIndexChanged.connect(self.color_scheme_changed)

        self.log_level_comboBox.currentTextChanged.connect(lambda: cfg.setitem("log_level", self.log_level_comboBox.currentText()))

        self.log_level_comboBox.currentTextChanged.connect(lambda: logger.set_level(self.log_level_comboBox.currentText()))

        self.restore2default_pushButton.clicked.connect(lambda: (cfg.reset(), self.init_ui()))

        self.open_log_dir_button.clicked.connect(lambda: QDesktopServices.openUrl(QUrl.fromLocalFile(log_dir)))

        self.auto_check_update_checkBox.stateChanged.connect(
            lambda: cfg.setitem("auto_check_update", self.auto_check_update_checkBox.isChecked()),
        )

        # 缓存设置
        self.clear_cache_pushButton.clicked.connect(self.clear_cache)

        # 翻译API设置
        self.translate_source_comboBox.currentIndexChanged.connect(
            lambda: cfg.setitem("translate_source", TranslateSource(self.translate_source_comboBox.currentIndex()).name),
        )
        self.translate_target_lang_comboBox.currentIndexChanged.connect(
            lambda: cfg.setitem("translate_target_lang", self.translate_target_lang_comboBox.currentText()),
        )

        self.oai_base_url_lineEdit.textChanged.connect(lambda: cfg.setitem("openai_base_url", self.oai_base_url_lineEdit.text()))
        self.oai_key_lineEdit.textChanged.connect(lambda: cfg.setitem("openai_api_key", self.oai_key_lineEdit.text()))
        self.oai_model_lineEdit.textChanged.connect(lambda: cfg.setitem("openai_model", self.oai_model_lineEdit.text()))

        # 搜索设置
        self.multi_search_source_list.data_changed.connect(lambda: cfg.setitem("multi_search_sources", self.multi_search_source_list.get_data()))

    @Slot(int)
    def color_scheme_changed(self, index: int) -> None:
        cfg["color_scheme"] = self.color_scheme_mapping[index]
        qapp = QGuiApplication.instance()
        if not isinstance(qapp, QGuiApplication):
            msg = "qapp is not a QGuiApplication"
            raise TypeError(msg)
        style_hints = qapp.styleHints()
        match index:
            case 0:
                style_hints.unsetColorScheme()
            case 1:
                style_hints.setColorScheme(Qt.ColorScheme.Light)
            case 2:
                style_hints.setColorScheme(Qt.ColorScheme.Dark)

    @Slot(int)
    def language_comboBox_changed(self, index: int) -> None:
        match index:
            case 0:
                cfg.setitem("language", "auto")
            case 1:
                cfg.setitem("language", "zh-Hans")
            case 2:
                cfg.setitem("language", "zh-Hant")
            case 3:
                cfg.setitem("language", "en")
            case 4:
                cfg.setitem("language", "ja")
        load_translation()
        self.init_ui()

    @Slot()
    def update_cache_size(self) -> None:
        self.cache_size_label.setText(self.tr("缓存大小:") + f" {cache.volume() / 1000000} MB")

    @Slot()
    def clear_cache(self) -> None:
        cache.clear()
        self.update_cache_size()
