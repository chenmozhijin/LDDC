# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'get_list_lyrics.ui'
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
from PySide6.QtWidgets import (QApplication, QPlainTextEdit, QProgressBar, QPushButton,
    QSizePolicy, QVBoxLayout, QWidget)

class Ui_get_list_lyrics(object):
    def setupUi(self, get_list_lyrics):
        if not get_list_lyrics.objectName():
            get_list_lyrics.setObjectName(u"get_list_lyrics")
        get_list_lyrics.resize(900, 450)
        self.verticalLayout = QVBoxLayout(get_list_lyrics)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.plainTextEdit = QPlainTextEdit(get_list_lyrics)
        self.plainTextEdit.setObjectName(u"plainTextEdit")
        self.plainTextEdit.setReadOnly(True)

        self.verticalLayout.addWidget(self.plainTextEdit)

        self.progressBar = QProgressBar(get_list_lyrics)
        self.progressBar.setObjectName(u"progressBar")
        self.progressBar.setMaximum(0)
        self.progressBar.setValue(0)

        self.verticalLayout.addWidget(self.progressBar)

        self.pushButton = QPushButton(get_list_lyrics)
        self.pushButton.setObjectName(u"pushButton")

        self.verticalLayout.addWidget(self.pushButton)


        self.retranslateUi(get_list_lyrics)

        QMetaObject.connectSlotsByName(get_list_lyrics)
    # setupUi

    def retranslateUi(self, get_list_lyrics):
        get_list_lyrics.setWindowTitle(QCoreApplication.translate("get_list_lyrics", u"\u83b7\u53d6\u4e13\u8f91/\u6b4c\u5355\u6b4c\u8bcd", None))
        self.pushButton.setText(QCoreApplication.translate("get_list_lyrics", u"\u53d6\u6d88", None))
    # retranslateUi

