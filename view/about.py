# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import time

from PySide6.QtCore import QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QWidget

from ui.about_ui import Ui_about


class AboutWidget(QWidget, Ui_about):
    def __init__(self, version: str) -> None:
        super().__init__()
        self.version = version
        self.setupUi(self)
        self.init_ui()
        self.connect_signals()

    def init_ui(self) -> None:
        html = self.label.text()
        year = time.strftime("%Y", time.localtime())
        if year != "2024":
            year = "2024-" + year
        self.label.setText(html.replace("{year}", year))
        self.version_label.setText(self.version_label.text() + self.version)

    def connect_signals(self) -> None:
        self.github_pushButton.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/chenmozhijin/LDDC")))
        self.githubissues_pushButton.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/chenmozhijin/LDDC/issues")))

    def retranslateUi(self, about: QWidget) -> None:
        super().retranslateUi(about)
        self.init_ui()
