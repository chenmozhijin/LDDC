# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import re

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QAbstractButton, QDialog, QDialogButtonBox, QWidget

from ui.update_ui import Ui_UpdateDialog


class UpdateQDialog(QDialog, Ui_UpdateDialog):

    def __init__(self, parent: QWidget, last_version: str, body: str) -> None:
        super().__init__(parent)
        self.setupUi(self)
        self.setWindowModality(Qt.WindowModality.NonModal)
        self.setWindowTitle(self.tr("发现新版本"))
        self.label.setText(self.tr('发现新版本{}，是否前往GitHub下载更新?').format(last_version))
        body = re.sub(r'!\[[^\]]*?\]\([^\)]*\)\s*', "", body)  # 去除图片链接
        self.textBrowser.setMarkdown(body)
        self.buttonBox.clicked.connect(self.button_clicked)
        self.show()

    def button_clicked(self, button: QAbstractButton) -> None:
        if self.buttonBox.standardButton(button) == QDialogButtonBox.StandardButton.Yes:
            QDesktopServices.openUrl(QUrl("https://github.com/chenmozhijin/LDDC/releases/latest"))
        self.close()
