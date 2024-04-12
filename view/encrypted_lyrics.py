import logging
import os

from PySide6.QtWidgets import QFileDialog, QMessageBox, QWidget

from decryptor import krc_decrypt, qrc_decrypt
from ui.encrypted_lyrics_ui import Ui_encrypted_lyrics
from utils.data import data
from utils.enum import LyricsFormat, LyricsType, QrcType, Source
from utils.lyrics import Lyrics, krc2dict, qrc2list


class EncryptedLyricsWidget(QWidget, Ui_encrypted_lyrics):
    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.connect_signals()
        self.lyrics_type = None
        self.lyrics = None
        self.data = data
        self.data_mutex = data.mutex

    def connect_signals(self) -> None:
        self.open_pushButton.clicked.connect(self.open_file)
        self.convert_pushButton.clicked.connect(self.convert)
        self.save_pushButton.clicked.connect(self.save)

        self.translate_checkBox.stateChanged.connect(self.change_lyrics_type)
        self.romanized_checkBox.stateChanged.connect(self.change_lyrics_type)
        self.original_checkBox.stateChanged.connect(self.change_lyrics_type)

        self.lyricsformat_comboBox.currentIndexChanged.connect(self.change_lyrics_format)

    def get_lyric_type(self) -> list:
        lyric_type = []
        if self.original_checkBox.isChecked():
            lyric_type.append('orig')
        if self.translate_checkBox.isChecked():
            lyric_type.append('ts')
        if self.romanized_checkBox.isChecked():
            lyric_type.append("roma")
        return lyric_type

    def open_file(self) -> None:
        file_path = QFileDialog.getOpenFileName(self, self.tr("选取加密歌词"), "", self.tr("加密歌词(*.qrc *.krc)"))[0]
        if file_path == "":
            return
        if not os.path.exists(file_path):
            QMessageBox.warning(self, self.tr("警告"), self.tr("文件不存在！"))
            return
        try:
            with open(file_path, "rb") as f:
                data = f.read()
        except Exception as e:
            QMessageBox.warning(self, self.tr("警告"), self.tr("读取文件失败：") + str(e))
            return
        qrc_magicheader = bytes.fromhex("98 25 B0 AC E3 02 83 68 E8 FC 6C")
        krc_magicheader = bytes.fromhex("6B 72 63 31 38")
        if data[:len(qrc_magicheader)] == qrc_magicheader:
            self.lyrics_type = "qrc"
            lyrics, error = qrc_decrypt(data, QrcType.LOCAL)
        elif data[:len(krc_magicheader)] == krc_magicheader:
            self.lyrics_type = "krc"
            lyrics, error = krc_decrypt(data)
        else:
            QMessageBox.warning(self, self.tr("警告"), self.tr("文件格式不正确！"))
            return

        if lyrics is None:
            self.lyrics_type = None
            msg = self.tr("解密失败") if error is None else self.tr("解密失败：") + error
            QMessageBox.critical(self, self.tr("错误"), msg)
            return

        self.plainTextEdit.setPlainText(lyrics)

    def convert(self) -> None:
        if self.lyrics_type == "converted":
            QMessageBox.information(self, self.tr("提示"), self.tr("当前歌词已经转换过了！"))
            return
        lyrics = self.plainTextEdit.toPlainText()
        if lyrics.strip() == "":
            QMessageBox.warning(self, self.tr("警告"), self.tr("歌词内容不能为空！"))
            return
        try:
            if self.lyrics_type == "qrc":
                self.lyrics = Lyrics({"source": Source.QM})
                self.lyrics.tags, lyric = qrc2list(lyrics)
                self.lyrics["orig"] = lyric
                self.lyrics.lrc_types["orig"] = LyricsType.QRC
                lrc = self.lyrics.get_merge_lrc(["orig"], LyricsFormat(self.lyricsformat_comboBox.currentIndex()))
            elif self.lyrics_type == "krc":
                self.data_mutex.lock()
                type_mapping = {"原文": "orig", "译文": "ts", "罗马音": "roma"}
                lyrics_order = [type_mapping[type_] for type_ in self.data.cfg["lyrics_order"] if type_mapping[type_] in self.get_lyric_type()]
                self.data_mutex.unlock()
                self.lyrics = Lyrics({"source": Source.KG})

                self.lyrics.tags, lyric = krc2dict(lyrics)
                self.lyrics.update(lyric)
                self.lyrics.lrc_types["orig"] = LyricsType.KRC
                self.lyrics.lrc_types["ts"] = LyricsType.JSONLINE
                self.lyrics.lrc_types["roma"] = LyricsType.JSONVERBATIM
                lrc = self.lyrics.get_merge_lrc(lyrics_order, LyricsFormat(self.lyricsformat_comboBox.currentIndex()))
        except Exception as e:
            logging.exception("转换失败")
            QMessageBox.critical(self, self.tr("错误"), self.tr("转换失败：") + str(e))
            return
        self.plainTextEdit.setPlainText(lrc)
        self.lyrics_type = "converted"

    def update_lyrics(self) -> None:
        type_mapping = {"原文": "orig", "译文": "ts", "罗马音": "roma"}
        self.data_mutex.lock()
        lyrics_order = [type_mapping[type_] for type_ in self.data.cfg["lyrics_order"] if type_mapping[type_] in self.get_lyric_type()]
        self.data_mutex.unlock()
        self.plainTextEdit.setPlainText(self.lyrics.get_merge_lrc(lyrics_order, LyricsFormat(self.lyricsformat_comboBox.currentIndex())))

    def change_lyrics_type(self) -> None:
        if self.lyrics_type == "converted" and isinstance(self.lyrics, Lyrics) and self.lyrics.source == Source.KG:
            self.update_lyrics()

    def change_lyrics_format(self) -> None:
        if self.lyrics_type == "converted" and isinstance(self.lyrics, Lyrics):
            self.update_lyrics()

    def save(self) -> None:
        file_path, _ = QFileDialog.getSaveFileName(self, self.tr("保存文件"), "", self.tr("歌词文件 (*.lrc *.srt *.ass)"))
        if file_path == "":
            return
        try:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(self.plainTextEdit.toPlainText())
        except Exception as e:
            QMessageBox.critical(self, self.tr("错误"), self.tr("保存失败：") + str(e))
