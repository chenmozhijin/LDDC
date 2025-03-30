################################################################################
## Form generated from reading UI file 'open_lyrics.ui'
##
## Created by: Qt User Interface Compiler version 6.8.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, Qt
from PySide6.QtWidgets import (
    QAbstractSpinBox,
    QCheckBox,
    QComboBox,
    QHBoxLayout,
    QLabel,
    QPlainTextEdit,
    QPushButton,
    QSizePolicy,
    QSpinBox,
    QVBoxLayout,
)


class Ui_open_lyrics:
    def setupUi(self, open_lyrics):
        if not open_lyrics.objectName():
            open_lyrics.setObjectName("open_lyrics")
        self.verticalLayout = QVBoxLayout(open_lyrics)
        self.verticalLayout.setObjectName("verticalLayout")
        self.plainTextEdit = QPlainTextEdit(open_lyrics)
        self.plainTextEdit.setObjectName("plainTextEdit")
        self.plainTextEdit.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        self.plainTextEdit.setReadOnly(True)

        self.verticalLayout.addWidget(self.plainTextEdit)

        self.horizontalLayout_2 = QHBoxLayout()
        self.horizontalLayout_2.setObjectName("horizontalLayout_2")
        self.label = QLabel(open_lyrics)
        self.label.setObjectName("label")

        self.horizontalLayout_2.addWidget(self.label)

        self.original_checkBox = QCheckBox(open_lyrics)
        self.original_checkBox.setObjectName("original_checkBox")
        self.original_checkBox.setChecked(True)

        self.horizontalLayout_2.addWidget(self.original_checkBox)

        self.translate_checkBox = QCheckBox(open_lyrics)
        self.translate_checkBox.setObjectName("translate_checkBox")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.translate_checkBox.sizePolicy().hasHeightForWidth())
        self.translate_checkBox.setSizePolicy(sizePolicy)
        self.translate_checkBox.setChecked(True)

        self.horizontalLayout_2.addWidget(self.translate_checkBox, 0, Qt.AlignmentFlag.AlignLeft)

        self.romanized_checkBox = QCheckBox(open_lyrics)
        self.romanized_checkBox.setObjectName("romanized_checkBox")
        sizePolicy.setHeightForWidth(self.romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.romanized_checkBox.setSizePolicy(sizePolicy)

        self.horizontalLayout_2.addWidget(self.romanized_checkBox, 0, Qt.AlignmentFlag.AlignLeft)

        self.label_5 = QLabel(open_lyrics)
        self.label_5.setObjectName("label_5")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.label_5.sizePolicy().hasHeightForWidth())
        self.label_5.setSizePolicy(sizePolicy1)

        self.horizontalLayout_2.addWidget(self.label_5)

        self.offset_spinBox = QSpinBox(open_lyrics)
        self.offset_spinBox.setObjectName("offset_spinBox")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Fixed)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.offset_spinBox.sizePolicy().hasHeightForWidth())
        self.offset_spinBox.setSizePolicy(sizePolicy2)
        self.offset_spinBox.setWrapping(False)
        self.offset_spinBox.setButtonSymbols(QAbstractSpinBox.ButtonSymbols.UpDownArrows)
        self.offset_spinBox.setAccelerated(False)
        self.offset_spinBox.setProperty("showGroupSeparator", False)
        self.offset_spinBox.setMinimum(-999999999)
        self.offset_spinBox.setMaximum(999999999)
        self.offset_spinBox.setSingleStep(100)

        self.horizontalLayout_2.addWidget(self.offset_spinBox)

        self.label_2 = QLabel(open_lyrics)
        self.label_2.setObjectName("label_2")

        self.horizontalLayout_2.addWidget(self.label_2)

        self.lyricsformat_comboBox = QComboBox(open_lyrics)
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.setObjectName("lyricsformat_comboBox")

        self.horizontalLayout_2.addWidget(self.lyricsformat_comboBox)

        self.verticalLayout.addLayout(self.horizontalLayout_2)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName("horizontalLayout")
        self.open_pushButton = QPushButton(open_lyrics)
        self.open_pushButton.setObjectName("open_pushButton")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Preferred)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.open_pushButton.sizePolicy().hasHeightForWidth())
        self.open_pushButton.setSizePolicy(sizePolicy3)

        self.horizontalLayout.addWidget(self.open_pushButton)

        self.convert_pushButton = QPushButton(open_lyrics)
        self.convert_pushButton.setObjectName("convert_pushButton")

        self.horizontalLayout.addWidget(self.convert_pushButton)

        self.save_pushButton = QPushButton(open_lyrics)
        self.save_pushButton.setObjectName("save_pushButton")
        sizePolicy3.setHeightForWidth(self.save_pushButton.sizePolicy().hasHeightForWidth())
        self.save_pushButton.setSizePolicy(sizePolicy3)

        self.horizontalLayout.addWidget(self.save_pushButton)

        self.verticalLayout.addLayout(self.horizontalLayout)

        self.retranslateUi(open_lyrics)

        QMetaObject.connectSlotsByName(open_lyrics)

    # setupUi

    def retranslateUi(self, open_lyrics):
        self.label.setText(QCoreApplication.translate("open_lyrics", "\u6b4c\u8bcd\u8bed\u8a00:", None))
        self.original_checkBox.setText(QCoreApplication.translate("open_lyrics", "\u539f\u6587", None))
        self.translate_checkBox.setText(QCoreApplication.translate("open_lyrics", "\u8bd1\u6587", None))
        self.romanized_checkBox.setText(QCoreApplication.translate("open_lyrics", "\u7f57\u9a6c\u97f3", None))
        self.label_5.setText(QCoreApplication.translate("open_lyrics", "\u504f\u79fb\u91cf:", None))
        self.label_2.setText(QCoreApplication.translate("open_lyrics", "\u8f6c\u6362\u7684\u683c\u5f0f\uff1a", None))
        self.lyricsformat_comboBox.setItemText(0, QCoreApplication.translate("open_lyrics", "LRC(\u9010\u5b57)", None))
        self.lyricsformat_comboBox.setItemText(1, QCoreApplication.translate("open_lyrics", "LRC(\u9010\u884c)", None))
        self.lyricsformat_comboBox.setItemText(2, QCoreApplication.translate("open_lyrics", "\u589e\u5f3a\u578bLRC(ESLyric)", None))
        self.lyricsformat_comboBox.setItemText(3, QCoreApplication.translate("open_lyrics", "SRT", None))
        self.lyricsformat_comboBox.setItemText(4, QCoreApplication.translate("open_lyrics", "ASS", None))

        self.open_pushButton.setText(QCoreApplication.translate("open_lyrics", "\u6253\u5f00\u6b4c\u8bcd\u6587\u4ef6", None))
        self.convert_pushButton.setText(QCoreApplication.translate("open_lyrics", "\u8f6c\u6362\u683c\u5f0f", None))
        self.save_pushButton.setText(QCoreApplication.translate("open_lyrics", "\u4fdd\u5b58\u6b4c\u8bcd", None))

    # retranslateUi
