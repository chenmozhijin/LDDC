# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'export_lyrics.ui'
##
## Created by: Qt User Interface Compiler version 6.8.1
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
from PySide6.QtWidgets import (QAbstractButton, QApplication, QCheckBox, QComboBox,
    QDialog, QDialogButtonBox, QGridLayout, QLabel,
    QLineEdit, QPushButton, QSizePolicy, QWidget)

class Ui_export_lyrics(object):
    def setupUi(self, export_lyrics):
        if not export_lyrics.objectName():
            export_lyrics.setObjectName(u"export_lyrics")
        export_lyrics.resize(409, 287)
        self.gridLayout = QGridLayout(export_lyrics)
        self.gridLayout.setObjectName(u"gridLayout")
        self.save_path_lineEdit = QLineEdit(export_lyrics)
        self.save_path_lineEdit.setObjectName(u"save_path_lineEdit")

        self.gridLayout.addWidget(self.save_path_lineEdit, 3, 0, 1, 4)

        self.lyricsformat_comboBox = QComboBox(export_lyrics)
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.setObjectName(u"lyricsformat_comboBox")

        self.gridLayout.addWidget(self.lyricsformat_comboBox, 0, 1, 1, 4)

        self.label_10 = QLabel(export_lyrics)
        self.label_10.setObjectName(u"label_10")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.label_10.sizePolicy().hasHeightForWidth())
        self.label_10.setSizePolicy(sizePolicy)

        self.gridLayout.addWidget(self.label_10, 0, 0, 1, 1)

        self.translate_checkBox = QCheckBox(export_lyrics)
        self.translate_checkBox.setObjectName(u"translate_checkBox")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.translate_checkBox.sizePolicy().hasHeightForWidth())
        self.translate_checkBox.setSizePolicy(sizePolicy1)
        self.translate_checkBox.setChecked(True)

        self.gridLayout.addWidget(self.translate_checkBox, 2, 2, 1, 1)

        self.filename_mode_comboBox = QComboBox(export_lyrics)
        self.filename_mode_comboBox.addItem("")
        self.filename_mode_comboBox.addItem("")
        self.filename_mode_comboBox.addItem("")
        self.filename_mode_comboBox.setObjectName(u"filename_mode_comboBox")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.filename_mode_comboBox.sizePolicy().hasHeightForWidth())
        self.filename_mode_comboBox.setSizePolicy(sizePolicy2)
        self.filename_mode_comboBox.setMinimumSize(QSize(133, 0))

        self.gridLayout.addWidget(self.filename_mode_comboBox, 1, 1, 1, 4)

        self.save_path_button = QPushButton(export_lyrics)
        self.save_path_button.setObjectName(u"save_path_button")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Preferred)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.save_path_button.sizePolicy().hasHeightForWidth())
        self.save_path_button.setSizePolicy(sizePolicy3)

        self.gridLayout.addWidget(self.save_path_button, 3, 4, 1, 1)

        self.label_8 = QLabel(export_lyrics)
        self.label_8.setObjectName(u"label_8")
        sizePolicy.setHeightForWidth(self.label_8.sizePolicy().hasHeightForWidth())
        self.label_8.setSizePolicy(sizePolicy)

        self.gridLayout.addWidget(self.label_8, 1, 0, 1, 1)

        self.label_9 = QLabel(export_lyrics)
        self.label_9.setObjectName(u"label_9")

        self.gridLayout.addWidget(self.label_9, 2, 0, 1, 1)

        self.original_checkBox = QCheckBox(export_lyrics)
        self.original_checkBox.setObjectName(u"original_checkBox")
        self.original_checkBox.setChecked(True)

        self.gridLayout.addWidget(self.original_checkBox, 2, 1, 1, 1)

        self.buttonBox = QDialogButtonBox(export_lyrics)
        self.buttonBox.setObjectName(u"buttonBox")
        self.buttonBox.setOrientation(Qt.Orientation.Horizontal)
        self.buttonBox.setStandardButtons(QDialogButtonBox.StandardButton.Cancel|QDialogButtonBox.StandardButton.Ok)

        self.gridLayout.addWidget(self.buttonBox, 4, 0, 1, 5)

        self.romanized_checkBox = QCheckBox(export_lyrics)
        self.romanized_checkBox.setObjectName(u"romanized_checkBox")
        sizePolicy1.setHeightForWidth(self.romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.romanized_checkBox.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.romanized_checkBox, 2, 3, 1, 2)


        self.retranslateUi(export_lyrics)
        self.buttonBox.accepted.connect(export_lyrics.accept)
        self.buttonBox.rejected.connect(export_lyrics.reject)

        QMetaObject.connectSlotsByName(export_lyrics)
    # setupUi

    def retranslateUi(self, export_lyrics):
        export_lyrics.setWindowTitle(QCoreApplication.translate("export_lyrics", u"\u5bfc\u51fa\u6b4c\u8bcd", None))
        self.lyricsformat_comboBox.setItemText(0, QCoreApplication.translate("export_lyrics", u"LRC(\u9010\u5b57)", None))
        self.lyricsformat_comboBox.setItemText(1, QCoreApplication.translate("export_lyrics", u"LRC(\u9010\u884c)", None))
        self.lyricsformat_comboBox.setItemText(2, QCoreApplication.translate("export_lyrics", u"\u589e\u5f3a\u578bLRC(ESLyric)", None))
        self.lyricsformat_comboBox.setItemText(3, QCoreApplication.translate("export_lyrics", u"SRT", None))
        self.lyricsformat_comboBox.setItemText(4, QCoreApplication.translate("export_lyrics", u"ASS", None))

        self.label_10.setText(QCoreApplication.translate("export_lyrics", u"\u6b4c\u8bcd\u683c\u5f0f:", None))
        self.translate_checkBox.setText(QCoreApplication.translate("export_lyrics", u"\u8bd1\u6587", None))
        self.filename_mode_comboBox.setItemText(0, QCoreApplication.translate("export_lyrics", u"\u4f9d\u7167\u683c\u5f0f(\u6839\u636e\u6b4c\u8bcd\u4e2d\u7684\u4fe1\u606f)", None))
        self.filename_mode_comboBox.setItemText(1, QCoreApplication.translate("export_lyrics", u"\u4f9d\u7167\u683c\u5f0f(\u6839\u636e\u6b4c\u66f2\u4e2d\u7684\u4fe1\u606f)", None))
        self.filename_mode_comboBox.setItemText(2, QCoreApplication.translate("export_lyrics", u"\u4e0e\u6b4c\u66f2\u6587\u4ef6\u540d\u76f8\u540c", None))

        self.save_path_button.setText(QCoreApplication.translate("export_lyrics", u"\u9009\u62e9\u4fdd\u5b58\u8def\u5f84", None))
        self.label_8.setText(QCoreApplication.translate("export_lyrics", u"\u6b4c\u8bcd\u6587\u4ef6\u540d:", None))
        self.label_9.setText(QCoreApplication.translate("export_lyrics", u"\u6b4c\u8bcd\u7c7b\u578b:", None))
        self.original_checkBox.setText(QCoreApplication.translate("export_lyrics", u"\u539f\u6587", None))
        self.romanized_checkBox.setText(QCoreApplication.translate("export_lyrics", u"\u7f57\u9a6c\u97f3", None))
    # retranslateUi

