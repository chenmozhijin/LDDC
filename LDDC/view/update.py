# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QAbstractButton, QDialog, QDialogButtonBox

from LDDC.backend.worker import CheckUpdate
from LDDC.ui.update_ui import Ui_UpdateDialog
from LDDC.utils.thread import threadpool

dialogs = []


class UpdateQDialog(QDialog, Ui_UpdateDialog):

    def __init__(self, name: str, repo: str, new_version: str, body: str) -> None:
        super().__init__()
        self.setupUi(self)
        self.setWindowModality(Qt.WindowModality.NonModal)
        self.repo = repo
        self.label.setText(self.tr('{0}发现新版本{1}，是否前往GitHub下载更新?').format(name, new_version))
        body = re.sub(r'!\[[^\]]*?\]\([^\)]*\)\s*', "", body)  # 去除图片链接
        self.textBrowser.setMarkdown(body)
        self.buttonBox.clicked.connect(self.button_clicked)
        self.show()

    def button_clicked(self, button: QAbstractButton) -> None:
        if self.buttonBox.standardButton(button) == QDialogButtonBox.StandardButton.Yes:
            QDesktopServices.openUrl(QUrl(f"https://github.com/{self.repo}/releases/latest"))
        self.close()
        self.deleteLater()
        if self in dialogs:
            dialogs.remove(self)


def show_new_version_dialog(name: str, repo: str, new_version: str, body: str) -> None:
    dialog = UpdateQDialog(name, repo, new_version, body)
    dialog.show()
    dialogs.append(dialog)


def check_update(is_auto: bool, name: str, repo: str, version: str) -> None:
    worker = CheckUpdate(is_auto, name, repo, version)
    worker.signals.show_new_version_dialog.connect(show_new_version_dialog)
    threadpool.start(worker)
