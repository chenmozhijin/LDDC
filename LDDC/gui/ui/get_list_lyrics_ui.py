################################################################################
## Form generated from reading UI file 'get_list_lyrics.ui'
##
## Created by: Qt User Interface Compiler version 6.8.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, QSize
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QPlainTextEdit, QProgressBar, QPushButton, QVBoxLayout


class Ui_get_list_lyrics:
    def setupUi(self, get_list_lyrics):
        if not get_list_lyrics.objectName():
            get_list_lyrics.setObjectName("get_list_lyrics")
        get_list_lyrics.resize(600, 400)
        icon = QIcon()
        icon.addFile(":/LDDC/img/icon/logo.png", QSize(), QIcon.Mode.Normal, QIcon.State.Off)
        get_list_lyrics.setWindowIcon(icon)
        self.verticalLayout = QVBoxLayout(get_list_lyrics)
        self.verticalLayout.setObjectName("verticalLayout")
        self.plainTextEdit = QPlainTextEdit(get_list_lyrics)
        self.plainTextEdit.setObjectName("plainTextEdit")
        self.plainTextEdit.setReadOnly(True)

        self.verticalLayout.addWidget(self.plainTextEdit)

        self.progressBar = QProgressBar(get_list_lyrics)
        self.progressBar.setObjectName("progressBar")
        self.progressBar.setMaximum(0)
        self.progressBar.setValue(0)

        self.verticalLayout.addWidget(self.progressBar)

        self.pushButton = QPushButton(get_list_lyrics)
        self.pushButton.setObjectName("pushButton")

        self.verticalLayout.addWidget(self.pushButton)

        self.retranslateUi(get_list_lyrics)

        QMetaObject.connectSlotsByName(get_list_lyrics)

    # setupUi

    def retranslateUi(self, get_list_lyrics):
        get_list_lyrics.setWindowTitle(QCoreApplication.translate("get_list_lyrics", "\u83b7\u53d6\u4e13\u8f91/\u6b4c\u5355\u6b4c\u8bcd", None))
        self.pushButton.setText(QCoreApplication.translate("get_list_lyrics", "\u53d6\u6d88", None))

    # retranslateUi
