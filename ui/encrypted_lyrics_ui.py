# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'encrypted_lyrics.ui'
##
## Created by: Qt User Interface Compiler version 6.6.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import (
    QCoreApplication,
    QMetaObject,
    Qt,
)
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QHBoxLayout,
    QLabel,
    QPlainTextEdit,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
)


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

        self.horizontalLayout_2 = QHBoxLayout()
        self.horizontalLayout_2.setObjectName(u"horizontalLayout_2")
        self.label = QLabel(encrypted_lyrics)
        self.label.setObjectName(u"label")

        self.horizontalLayout_2.addWidget(self.label)

        self.original_checkBox = QCheckBox(encrypted_lyrics)
        self.original_checkBox.setObjectName(u"original_checkBox")
        self.original_checkBox.setChecked(True)

        self.horizontalLayout_2.addWidget(self.original_checkBox)

        self.translate_checkBox = QCheckBox(encrypted_lyrics)
        self.translate_checkBox.setObjectName(u"translate_checkBox")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.translate_checkBox.sizePolicy().hasHeightForWidth())
        self.translate_checkBox.setSizePolicy(sizePolicy)
        self.translate_checkBox.setChecked(True)

        self.horizontalLayout_2.addWidget(self.translate_checkBox, 0, Qt.AlignLeft)

        self.romanized_checkBox = QCheckBox(encrypted_lyrics)
        self.romanized_checkBox.setObjectName(u"romanized_checkBox")
        sizePolicy.setHeightForWidth(self.romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.romanized_checkBox.setSizePolicy(sizePolicy)

        self.horizontalLayout_2.addWidget(self.romanized_checkBox, 0, Qt.AlignLeft)

        self.label_2 = QLabel(encrypted_lyrics)
        self.label_2.setObjectName(u"label_2")

        self.horizontalLayout_2.addWidget(self.label_2)

        self.lyricsformat_comboBox = QComboBox(encrypted_lyrics)
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.setObjectName(u"lyricsformat_comboBox")

        self.horizontalLayout_2.addWidget(self.lyricsformat_comboBox)


        self.verticalLayout.addLayout(self.horizontalLayout_2)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.open_pushButton = QPushButton(encrypted_lyrics)
        self.open_pushButton.setObjectName(u"open_pushButton")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Preferred)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.open_pushButton.sizePolicy().hasHeightForWidth())
        self.open_pushButton.setSizePolicy(sizePolicy1)

        self.horizontalLayout.addWidget(self.open_pushButton)

        self.convert_pushButton = QPushButton(encrypted_lyrics)
        self.convert_pushButton.setObjectName(u"convert_pushButton")

        self.horizontalLayout.addWidget(self.convert_pushButton)

        self.save_pushButton = QPushButton(encrypted_lyrics)
        self.save_pushButton.setObjectName(u"save_pushButton")
        sizePolicy1.setHeightForWidth(self.save_pushButton.sizePolicy().hasHeightForWidth())
        self.save_pushButton.setSizePolicy(sizePolicy1)

        self.horizontalLayout.addWidget(self.save_pushButton)


        self.verticalLayout.addLayout(self.horizontalLayout)


        self.retranslateUi(encrypted_lyrics)

        QMetaObject.connectSlotsByName(encrypted_lyrics)
    # setupUi

    def retranslateUi(self, encrypted_lyrics):
        encrypted_lyrics.setWindowTitle(QCoreApplication.translate("encrypted_lyrics", u"Form", None))
        self.label.setText(QCoreApplication.translate("encrypted_lyrics", u"\u6b4c\u8bcd\u7c7b\u578b(\u4ec5krc):", None))
        self.original_checkBox.setText(QCoreApplication.translate("encrypted_lyrics", u"\u539f\u6587", None))
        self.translate_checkBox.setText(QCoreApplication.translate("encrypted_lyrics", u"\u8bd1\u6587", None))
        self.romanized_checkBox.setText(QCoreApplication.translate("encrypted_lyrics", u"\u7f57\u9a6c\u97f3", None))
        self.label_2.setText(QCoreApplication.translate("encrypted_lyrics", u"\u8f6c\u6362\u7684\u683c\u5f0f\uff1a", None))
        self.lyricsformat_comboBox.setItemText(0, QCoreApplication.translate("encrypted_lyrics", u"LRC(\u9010\u5b57)", None))
        self.lyricsformat_comboBox.setItemText(1, QCoreApplication.translate("encrypted_lyrics", u"LRC(\u9010\u884c)", None))
        self.lyricsformat_comboBox.setItemText(2, QCoreApplication.translate("encrypted_lyrics", u"SRT", None))
        self.lyricsformat_comboBox.setItemText(3, QCoreApplication.translate("encrypted_lyrics", u"ASS", None))

        self.open_pushButton.setText(QCoreApplication.translate("encrypted_lyrics", u"\u6253\u5f00\u52a0\u5bc6\u6b4c\u8bcd", None))
        self.convert_pushButton.setText(QCoreApplication.translate("encrypted_lyrics", u"\u8f6c\u6362\u683c\u5f0f", None))
        self.save_pushButton.setText(QCoreApplication.translate("encrypted_lyrics", u"\u4fdd\u5b58\u6b4c\u8bcd", None))
    # retranslateUi

