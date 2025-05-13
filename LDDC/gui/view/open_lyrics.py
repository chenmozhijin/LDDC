# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from pathlib import Path

from PySide6.QtCore import Slot
from PySide6.QtWidgets import QFileDialog, QWidget

from LDDC.common.data.config import cfg
from LDDC.common.logger import logger
from LDDC.common.models import Lyrics, LyricsFormat, QrcType
from LDDC.common.utils import read_unknown_encoding_file
from LDDC.core.api.lyrics import get_lyrics
from LDDC.core.decryptor import krc_decrypt, qrc_decrypt
from LDDC.core.parser.krc import KRC_MAGICHEADER
from LDDC.core.parser.qrc import QRC_MAGICHEADER
from LDDC.gui.components.msg_box import MsgBox
from LDDC.gui.ui.open_lyrics_ui import Ui_open_lyrics


class OpenLyricsWidget(QWidget, Ui_open_lyrics):
    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.connect_signals()
        self.lyrics_type = None
        self.path: Path | None = None
        self.data: bytes | None = None

    def connect_signals(self) -> None:
        self.open_pushButton.clicked.connect(self.select_file)
        self.convert_pushButton.clicked.connect(self.convert)
        self.save_pushButton.clicked.connect(self.save)

        self.translate_checkBox.stateChanged.connect(self.update_lyrics)
        self.romanized_checkBox.stateChanged.connect(self.update_lyrics)
        self.original_checkBox.stateChanged.connect(self.update_lyrics)

        self.lyricsformat_comboBox.currentIndexChanged.connect(self.update_lyrics)
        self.offset_spinBox.valueChanged.connect(self.update_lyrics)

        cfg.lyrics_changed.connect(self.update_lyrics)

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

    @Slot(object)
    def open_file(self, path_str: str | Path) -> None:
        file_path = Path(path_str)
        if not file_path.exists():
            MsgBox.warning(self, self.tr("警告"), self.tr("文件不存在！"))
            return
        try:
            with file_path.open("rb") as f:
                data = f.read()
        except Exception as e:
            MsgBox.warning(self, self.tr("警告"), self.tr("读取文件失败：") + str(e))
            return
        try:
            if data.startswith(QRC_MAGICHEADER):
                self.lyrics_type = "qrc"
                lyrics_text = qrc_decrypt(data, QrcType.LOCAL)
            elif data.startswith(KRC_MAGICHEADER):
                self.lyrics_type = "krc"
                lyrics_text = krc_decrypt(data)
            elif file_path.suffix == ".lrc":
                self.lyrics_type = "lrc"
                lyrics_text = read_unknown_encoding_file(file_data=data, sign_word=("[", "]", ":"))
            elif file_path.suffix == ".ass":
                self.lyrics_type = "ass"
                lyrics_text = read_unknown_encoding_file(file_data=data)
            elif file_path.suffix == ".srt":
                self.lyrics_type = "srt"
                lyrics_text = read_unknown_encoding_file(file_data=data)
            else:
                MsgBox.warning(self, self.tr("警告"), self.tr("不支持的文件格式！"))
                return
            self.path = Path(file_path)
            self.data = data
        except Exception as e:
            logger.exception("打开失败")
            MsgBox.critical(self, self.tr("警告"), self.tr("打开失败：") + str(e))
            return
        if lyrics_text is None:
            self.lyrics_type = None
            msg = self.tr("打开失败")
            MsgBox.critical(self, self.tr("错误"), msg)
            return

        self.plainTextEdit.setPlainText(lyrics_text)

    @Slot()
    def select_file(self) -> None:
        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("打开本地歌词"))
        dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
        dialog.setNameFilter(self.tr("歌词文件(*.qrc *.krc *.lrc *.ass *.srt)"))
        dialog.fileSelected.connect(self.open_file)
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
            self.lyrics = get_lyrics(path=self.path, data=self.data)

            lyrics_text = self.lyrics.to(
                lyrics_format=LyricsFormat(self.lyricsformat_comboBox.currentIndex()),
                langs=self.langs,
                offset=self.offset_spinBox.value(),
            )
        except Exception as e:
            logger.exception("转换失败")
            MsgBox.critical(self, self.tr("错误"), self.tr("转换失败：") + str(e))
            return
        self.plainTextEdit.setPlainText(lyrics_text)
        self.lyrics_type = "converted"

    @Slot()
    def update_lyrics(self) -> None:
        if (
            self.lyrics_type == "converted"
            and isinstance(self.lyrics, Lyrics)
            and (lyrics_text := self.lyrics.to(LyricsFormat(self.lyricsformat_comboBox.currentIndex()), self.langs, self.offset_spinBox.value()))
            and lyrics_text != self.plainTextEdit.toPlainText()
        ):
            self.plainTextEdit.setPlainText(lyrics_text)

    @Slot()
    def save(self) -> None:
        if self.plainTextEdit.toPlainText() == "":
            MsgBox.warning(self, self.tr("警告"), self.tr("歌词内容不能为空！"))
            return

        @Slot(str)
        def file_selected(path_str: str) -> None:
            file_path = Path(path_str)
            if self.lyrics_type == "converted":
                ext = LyricsFormat(self.lyricsformat_comboBox.currentIndex()).ext
            if ext and not file_path.name.endswith(ext):
                file_path = Path(file_path.parent / (file_path.name + ext))
            try:
                with file_path.open("w", encoding="utf-8") as f:
                    f.write(self.plainTextEdit.toPlainText())
            except Exception as e:
                MsgBox.critical(self, self.tr("错误"), self.tr("保存失败：") + str(e))

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("保存歌词"))
        dialog.setFileMode(QFileDialog.FileMode.AnyFile)
        if self.lyrics_type == "converted":
            ext = f"(*{LyricsFormat(self.lyricsformat_comboBox.currentIndex()).ext})"
            dialog.setNameFilter(self.tr("歌词文件 ") + ext)
        else:
            dialog.setNameFilter(self.tr("全部文件") + "(*)")
        dialog.fileSelected.connect(file_selected)
        dialog.open()
