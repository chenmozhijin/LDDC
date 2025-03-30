# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import time

from PySide6.QtCore import QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import QWidget

from LDDC.common.version import __version__
from LDDC.gui.ui.about_ui import Ui_about

from .update import check_update


class AboutWidget(QWidget, Ui_about):
    def __init__(self) -> None:
        super().__init__()
        self.setupUi(self)
        self.connect_signals()

    def init_ui(self) -> None:
        html = self.label.text()
        year = time.strftime("%Y", time.localtime())
        if year != "2024":
            year = "2024-" + year
        self.label.setText(html.replace("{year}", year))
        self.version_label.setText(self.version_label.text() + __version__)

    def connect_signals(self) -> None:
        self.github_pushButton.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/chenmozhijin/LDDC")))
        self.githubissues_pushButton.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/chenmozhijin/LDDC/issues")))
        self.checkupdate_pushButton.clicked.connect(lambda: check_update(False, self.tr("LDDC主程序"), "chenmozhijin/LDDC", __version__))

    def retranslateUi(self, about: QWidget) -> None:
        super().retranslateUi(about)
        self.init_ui()
