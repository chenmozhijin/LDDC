# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import os

from PySide6.QtCore import Slot
from PySide6.QtWidgets import QFileDialog, QWidget

from LDDC.backend.converter import convert2
from LDDC.backend.decryptor import krc_decrypt, qrc_decrypt
from LDDC.backend.fetcher import get_lyrics
from LDDC.backend.fetcher.local import KRC_MAGICHEADER, QRC_MAGICHEADER
from LDDC.backend.lyrics import Lyrics
from LDDC.ui.open_lyrics_ui import Ui_open_lyrics
from LDDC.utils.data import cfg
from LDDC.utils.enum import LyricsFormat, QrcType, Source
from LDDC.utils.logger import logger
from LDDC.utils.utils import get_lyrics_format_ext, read_unknown_encoding_file

from .msg_box import MsgBox


class OpenLyricsWidget(QWidget, Ui_open_lyrics):
    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.connect_signals()
        self.lyrics_type = None
        self.path: str | None = None
        self.data: bytes | None = None

    def connect_signals(self) -> None:
        self.open_pushButton.clicked.connect(self.open_file)
        self.convert_pushButton.clicked.connect(self.convert)
        self.save_pushButton.clicked.connect(self.save)

        self.translate_checkBox.stateChanged.connect(self.change_lyrics_type)
        self.romanized_checkBox.stateChanged.connect(self.change_lyrics_type)
        self.original_checkBox.stateChanged.connect(self.change_lyrics_type)

        self.lyricsformat_comboBox.currentIndexChanged.connect(self.update_lyrics)
        self.offset_spinBox.valueChanged.connect(self.update_lyrics)

        cfg.lyrics_changed.connect(self.update_lyrics)

    def get_lyric_langs(self) -> list:
        lyric_langs = []
        if self.original_checkBox.isChecked():
            lyric_langs.append('orig')
        if self.translate_checkBox.isChecked():
            lyric_langs.append('ts')
        if self.romanized_checkBox.isChecked():
            lyric_langs.append("roma")
        return lyric_langs

    @Slot()
    def open_file(self) -> None:
        @Slot(str)
        def file_selected(file_path: str) -> None:
            if not os.path.exists(file_path):
                MsgBox.warning(self, self.tr("警告"), self.tr("文件不存在！"))
                return
            try:
                with open(file_path, "rb") as f:
                    data = f.read()
            except Exception as e:
                MsgBox.warning(self, self.tr("警告"), self.tr("读取文件失败：") + str(e))
                return
            try:
                if data.startswith(QRC_MAGICHEADER):
                    self.lyrics_type = "qrc"
                    lyrics = qrc_decrypt(data, QrcType.LOCAL)
                    self.path = file_path
                    self.data = data
                elif data.startswith(KRC_MAGICHEADER):
                    self.lyrics_type = "krc"
                    lyrics = krc_decrypt(data)
                    self.path = file_path
                    self.data = data
                elif file_path.lower().endswith(".lrc"):
                    self.lyrics_type = "lrc"
                    lyrics = read_unknown_encoding_file(file_data=data, sign_word=("[", "]", ":"))
                    self.path = file_path
                    self.data = data
                else:
                    MsgBox.warning(self, self.tr("警告"), self.tr("不支持的文件格式！"))
                    return
            except Exception as e:
                logger.exception("打开失败")
                MsgBox.critical(self, self.tr("警告"), self.tr("打开失败：") + str(e))
                return
            if lyrics is None:
                self.lyrics_type = None
                msg = self.tr("打开失败")
                MsgBox.critical(self, self.tr("错误"), msg)
                return

            self.plainTextEdit.setPlainText(lyrics)

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("打开本地歌词"))
        dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
        dialog.setNameFilter(self.tr("歌词文件(*.qrc *.krc *.lrc)"))
        dialog.fileSelected.connect(file_selected)
        dialog.open()

    @Slot()
    def convert(self) -> None:
        if self.lyrics_type == "converted":
            MsgBox.information(self, self.tr("提示"), self.tr("当前歌词已经转换过了！"))
            return
        lyrics = self.plainTextEdit.toPlainText()
        if lyrics.strip() == "":
            MsgBox.warning(self, self.tr("警告"), self.tr("歌词内容不能为空！"))
            return
        try:
            self.lyrics, _from_cache = get_lyrics(Source.Local, use_cache=False, path=self.path, data=self.data)

            langs_order = [lang for lang in cfg["langs_order"] if lang in self.get_lyric_langs()]
            lrc = convert2(self.lyrics, langs_order, LyricsFormat(self.lyricsformat_comboBox.currentIndex()), offset=self.offset_spinBox.value())
        except Exception as e:
            logger.exception("转换失败")
            MsgBox.critical(self, self.tr("错误"), self.tr("转换失败：") + str(e))
            return
        self.plainTextEdit.setPlainText(lrc)
        self.lyrics_type = "converted"

    @Slot()
    def update_lyrics(self) -> None:
        if not (self.lyrics_type == "converted" and isinstance(self.lyrics, Lyrics)):
            return

        langs_order = [lang for lang in cfg["langs_order"] if lang in self.get_lyric_langs()]
        self.plainTextEdit.setPlainText(convert2(self.lyrics, langs_order, LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
                                        offset=self.offset_spinBox.value()))

    @Slot()
    def change_lyrics_type(self) -> None:
        if self.lyrics_type == "converted" and isinstance(self.lyrics, Lyrics):
            self.update_lyrics()

    @Slot()
    def save(self) -> None:
        if self.plainTextEdit.toPlainText() == "":
            MsgBox.warning(self, self.tr("警告"), self.tr("歌词内容不能为空！"))
            return

        @Slot(str)
        def file_selected(file_path: str) -> None:
            if self.lyrics_type == 'converted':
                ext = get_lyrics_format_ext(LyricsFormat(self.lyricsformat_comboBox.currentIndex()))
            if ext and not file_path.endswith(ext):
                file_path += ext
            try:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(self.plainTextEdit.toPlainText())
            except Exception as e:
                MsgBox.critical(self, self.tr("错误"), self.tr("保存失败：") + str(e))

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("保存歌词"))
        dialog.setFileMode(QFileDialog.FileMode.AnyFile)
        if self.lyrics_type == 'converted':
            ext = f'(*{get_lyrics_format_ext(LyricsFormat(self.lyricsformat_comboBox.currentIndex()))})'
            dialog.setNameFilter(self.tr("歌词文件 ") + ext)
        else:
            dialog.setNameFilter(self.tr("全部文件") + "(*)")
        dialog.fileSelected.connect(file_selected)
        dialog.open()
