import os

from PySide6.QtWidgets import QFileDialog, QMessageBox, QWidget

from decryptor import QrcType, qrc_decrypt
from lyrics import get_clear_lyric, qrc2lrc
from ui.encrypted_lyrics_ui import Ui_encrypted_lyrics


class EncryptedLyricsWidget(QWidget, Ui_encrypted_lyrics):
    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.connect_signals()
        self.is_lrc = False

    def connect_signals(self) -> None:
        self.open_pushButton.clicked.connect(self.open_file)
        self.convert_pushButton.clicked.connect(self.convert)
        self.save_pushButton.clicked.connect(self.save)

    def open_file(self) -> None:
        file_path = QFileDialog.getOpenFileName(self, "选取加密歌词", "", "QRC  Files(*.qrc)")[0]
        if file_path == "":
            return
        if not os.path.exists(file_path):
            QMessageBox.warning(self, "警告", "文件不存在！")
            return
        try:
            with open(file_path, "rb") as f:
                data = f.read()
        except Exception as e:
            QMessageBox.warning(self, "警告", f"读取文件失败：{e}")
            return
        magic_header = b'\x98%\xb0\xac\xe3\x02\x83h\xe8\xfc\x6c'
        if data[:len(magic_header)] != magic_header:
            QMessageBox.warning(self, "警告", "文件格式不正确！")
            return
        lyrics, error = qrc_decrypt(data, QrcType.LOCAL)
        if lyrics is None:
            msg = "解密失败" if error is None else f"解密失败：{error}"
            QMessageBox.critical(self, "错误", msg)
            return
        self.plainTextEdit.setPlainText(lyrics)
        self.is_lrc = False

    def convert(self) -> None:
        if self.is_lrc:
            QMessageBox.information(self, "提示", "当前歌词已经是lrc格式了！")
            return
        lyrics = self.plainTextEdit.toPlainText()
        if lyrics.strip() == "":
            QMessageBox.warning(self, "警告", "歌词内容不能为空！")
            return
        try:
            lrc = get_clear_lyric(qrc2lrc(lyrics))
        except Exception as e:
            QMessageBox.critical(self, "错误", f"转换失败：{e}")
            return
        self.plainTextEdit.setPlainText(lrc)
        self.is_lrc = True

    def save(self) -> None:
        file_path, _ = QFileDialog.getSaveFileName(self, "保存文件", "", "LRC文件 (*.lrc)")
        if file_path == "":
            return
        try:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(self.plainTextEdit.toPlainText())
        except Exception as e:
            QMessageBox.critical(self, "错误", f"保存失败：{e}")
