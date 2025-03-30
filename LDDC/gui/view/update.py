# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import re

from PySide6.QtCore import QCoreApplication, Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QAbstractButton, QDialog, QDialogButtonBox

from LDDC.common.thread import in_other_thread
from LDDC.common.version import compare_versions
from LDDC.core.api import get_last_release
from LDDC.gui.components.msg_box import MsgBox
from LDDC.gui.ui.update_ui import Ui_UpdateDialog

dialogs = []


class UpdateQDialog(QDialog, Ui_UpdateDialog):
    def __init__(self, name: str, repo: str, new_version: str, body: str) -> None:
        super().__init__()
        self.setupUi(self)
        self.setWindowModality(Qt.WindowModality.NonModal)
        self.repo = repo
        self.label.setText(self.tr("{0}发现新版本{1}，是否前往GitHub下载更新?").format(name, new_version))
        body = re.sub(r"!\[[^\]]*?\]\([^\)]*\)\s*", "", body)  # 去除图片链接
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
    def callback(info: tuple[str, str]) -> None:
        latest_version, body = info
        if compare_versions(version, latest_version) == -1:
            show_new_version_dialog(name, repo, latest_version, body)
        elif not is_auto:
            MsgBox.information(None, QCoreApplication.translate("CheckUpdate", "检查更新"), QCoreApplication.translate("CheckUpdate", "当前已是最新版本"))

    in_other_thread(
        get_last_release,
        callback,
        MsgBox.get_error_slot(
            None,
            QCoreApplication.translate("CheckUpdate", "检查更新失败"),
            QCoreApplication.translate("CheckUpdate", "检查更新失败，请检查网络连接"),
        )
        if not is_auto
        else None,
        repo,
    )
