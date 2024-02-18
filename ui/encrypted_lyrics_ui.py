# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'encrypted_lyrics.ui'
##
## Created by: Qt User Interface Compiler version 6.6.1
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import (QCoreApplication, QDate, QDateTime, QLocale,
    QMetaObject, QObject, QPoint, QRect,
    QSize, QTime, QUrl, Qt)
from PySide6.QtGui import (QBrush, QColor, QConicalGradient, QCursor,
    QFont, QFontDatabase, QGradient, QIcon,
    QImage, QKeySequence, QLinearGradient, QPainter,
    QPalette, QPixmap, QRadialGradient, QTransform)
from PySide6.QtWidgets import (QApplication, QHBoxLayout, QPlainTextEdit, QPushButton,
    QSizePolicy, QVBoxLayout, QWidget)

class Ui_encrypted_lyrics(object):
    def setupUi(self, encrypted_lyrics):
        if not encrypted_lyrics.objectName():
            encrypted_lyrics.setObjectName(u"encrypted_lyrics")
        encrypted_lyrics.resize(802, 413)
        self.verticalLayout = QVBoxLayout(encrypted_lyrics)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.plainTextEdit = QPlainTextEdit(encrypted_lyrics)
        self.plainTextEdit.setObjectName(u"plainTextEdit")
        self.plainTextEdit.setLineWrapMode(QPlainTextEdit.NoWrap)

        self.verticalLayout.addWidget(self.plainTextEdit)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.open_pushButton = QPushButton(encrypted_lyrics)
        self.open_pushButton.setObjectName(u"open_pushButton")
        sizePolicy = QSizePolicy(QSizePolicy.Minimum, QSizePolicy.Preferred)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.open_pushButton.sizePolicy().hasHeightForWidth())
        self.open_pushButton.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.open_pushButton)

        self.convert_pushButton = QPushButton(encrypted_lyrics)
        self.convert_pushButton.setObjectName(u"convert_pushButton")

        self.horizontalLayout.addWidget(self.convert_pushButton)

        self.save_pushButton = QPushButton(encrypted_lyrics)
        self.save_pushButton.setObjectName(u"save_pushButton")
        sizePolicy.setHeightForWidth(self.save_pushButton.sizePolicy().hasHeightForWidth())
        self.save_pushButton.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.save_pushButton)


        self.verticalLayout.addLayout(self.horizontalLayout)


        self.retranslateUi(encrypted_lyrics)

        QMetaObject.connectSlotsByName(encrypted_lyrics)
    # setupUi

    def retranslateUi(self, encrypted_lyrics):
        encrypted_lyrics.setWindowTitle(QCoreApplication.translate("encrypted_lyrics", u"Form", None))
        self.open_pushButton.setText(QCoreApplication.translate("encrypted_lyrics", u"\u6253\u5f00\u52a0\u5bc6qrc\u6b4c\u8bcd", None))
        self.convert_pushButton.setText(QCoreApplication.translate("encrypted_lyrics", u"\u8f6c\u6362\u4e3alrc", None))
        self.save_pushButton.setText(QCoreApplication.translate("encrypted_lyrics", u"\u4fdd\u5b58\u6b4c\u8bcd", None))
    # retranslateUi

