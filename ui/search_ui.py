# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'search.ui'
##
## Created by: Qt User Interface Compiler version 6.7.0
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import (
    QCoreApplication,
    QMetaObject,
    QSize,
    Qt,
)
from PySide6.QtGui import (
    QFont,
)
from PySide6.QtWidgets import (
    QAbstractItemView,
    QAbstractScrollArea,
    QCheckBox,
    QComboBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPlainTextEdit,
    QPushButton,
    QSizePolicy,
    QSpacerItem,
    QSpinBox,
    QSplitter,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

from ui.custom_widgets import ProportionallyStretchedTableWidget


class Ui_search(object):
    def setupUi(self, search):
        if not search.objectName():
            search.setObjectName(u"search")
        search.resize(1050, 600)
        self.verticalLayout = QVBoxLayout(search)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.label = QLabel(search)
        self.label.setObjectName(u"label")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.label.sizePolicy().hasHeightForWidth())
        self.label.setSizePolicy(sizePolicy)
        self.label.setMaximumSize(QSize(16777215, 16777215))
        font = QFont()
        font.setPointSize(18)
        self.label.setFont(font)

        self.verticalLayout.addWidget(self.label)

        self.label_4 = QLabel(search)
        self.label_4.setObjectName(u"label_4")

        self.verticalLayout.addWidget(self.label_4)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.source_comboBox = QComboBox(search)
        self.source_comboBox.addItem("")
        self.source_comboBox.addItem("")
        self.source_comboBox.addItem("")
        self.source_comboBox.setObjectName(u"source_comboBox")

        self.horizontalLayout.addWidget(self.source_comboBox)

        self.search_type_comboBox = QComboBox(search)
        self.search_type_comboBox.addItem("")
        self.search_type_comboBox.addItem("")
        self.search_type_comboBox.addItem("")
        self.search_type_comboBox.setObjectName(u"search_type_comboBox")

        self.horizontalLayout.addWidget(self.search_type_comboBox)

        self.search_keyword_lineEdit = QLineEdit(search)
        self.search_keyword_lineEdit.setObjectName(u"search_keyword_lineEdit")
        sizePolicy.setHeightForWidth(self.search_keyword_lineEdit.sizePolicy().hasHeightForWidth())
        self.search_keyword_lineEdit.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.search_keyword_lineEdit)

        self.horizontalSpacer_2 = QSpacerItem(20, 20, QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer_2)

        self.search_pushButton = QPushButton(search)
        self.search_pushButton.setObjectName(u"search_pushButton")

        self.horizontalLayout.addWidget(self.search_pushButton)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)


        self.verticalLayout.addLayout(self.horizontalLayout)

        self.splitter = QSplitter(search)
        self.splitter.setObjectName(u"splitter")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.splitter.sizePolicy().hasHeightForWidth())
        self.splitter.setSizePolicy(sizePolicy1)
        self.splitter.setOrientation(Qt.Orientation.Horizontal)
        self.splitter.setOpaqueResize(True)
        self.splitter.setHandleWidth(5)
        self.splitter.setChildrenCollapsible(False)
        self.layoutWidget_2 = QWidget(self.splitter)
        self.layoutWidget_2.setObjectName(u"layoutWidget_2")
        self.verticalLayout_3 = QVBoxLayout(self.layoutWidget_2)
        self.verticalLayout_3.setObjectName(u"verticalLayout_3")
        self.verticalLayout_3.setContentsMargins(0, 0, 0, 0)
        self.result_label = QLabel(self.layoutWidget_2)
        self.result_label.setObjectName(u"result_label")
        sizePolicy.setHeightForWidth(self.result_label.sizePolicy().hasHeightForWidth())
        self.result_label.setSizePolicy(sizePolicy)
        font1 = QFont()
        font1.setPointSize(14)
        self.result_label.setFont(font1)

        self.verticalLayout_3.addWidget(self.result_label)

        self.return_toolButton = QToolButton(self.layoutWidget_2)
        self.return_toolButton.setObjectName(u"return_toolButton")
        self.return_toolButton.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self.return_toolButton.setAutoRaise(False)
        self.return_toolButton.setArrowType(Qt.ArrowType.LeftArrow)

        self.verticalLayout_3.addWidget(self.return_toolButton)

        self.results_tableWidget = ProportionallyStretchedTableWidget(self.layoutWidget_2)
        self.results_tableWidget.setObjectName(u"results_tableWidget")
        sizePolicy1.setHeightForWidth(self.results_tableWidget.sizePolicy().hasHeightForWidth())
        self.results_tableWidget.setSizePolicy(sizePolicy1)
        self.results_tableWidget.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.results_tableWidget.setSizeAdjustPolicy(QAbstractScrollArea.SizeAdjustPolicy.AdjustIgnored)
        self.results_tableWidget.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.results_tableWidget.setProperty("showDropIndicator", False)
        self.results_tableWidget.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.results_tableWidget.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.results_tableWidget.setShowGrid(False)
        self.results_tableWidget.setGridStyle(Qt.PenStyle.SolidLine)
        self.results_tableWidget.horizontalHeader().setVisible(True)
        self.results_tableWidget.horizontalHeader().setCascadingSectionResizes(False)
        self.results_tableWidget.horizontalHeader().setDefaultSectionSize(100)
        self.results_tableWidget.horizontalHeader().setHighlightSections(True)
        self.results_tableWidget.horizontalHeader().setProperty("showSortIndicator", False)
        self.results_tableWidget.horizontalHeader().setStretchLastSection(False)
        self.results_tableWidget.verticalHeader().setVisible(False)

        self.verticalLayout_3.addWidget(self.results_tableWidget)

        self.splitter.addWidget(self.layoutWidget_2)
        self.layoutWidget_3 = QWidget(self.splitter)
        self.layoutWidget_3.setObjectName(u"layoutWidget_3")
        self.verticalLayout_8 = QVBoxLayout(self.layoutWidget_3)
        self.verticalLayout_8.setObjectName(u"verticalLayout_8")
        self.verticalLayout_8.setContentsMargins(0, 0, 0, 0)
        self.label_8 = QLabel(self.layoutWidget_3)
        self.label_8.setObjectName(u"label_8")
        sizePolicy.setHeightForWidth(self.label_8.sizePolicy().hasHeightForWidth())
        self.label_8.setSizePolicy(sizePolicy)
        self.label_8.setFont(font1)

        self.verticalLayout_8.addWidget(self.label_8)

        self.horizontalLayout_5 = QHBoxLayout()
        self.horizontalLayout_5.setObjectName(u"horizontalLayout_5")
        self.label_2 = QLabel(self.layoutWidget_3)
        self.label_2.setObjectName(u"label_2")

        self.horizontalLayout_5.addWidget(self.label_2)

        self.lyric_types_lineEdit = QLineEdit(self.layoutWidget_3)
        self.lyric_types_lineEdit.setObjectName(u"lyric_types_lineEdit")
        self.lyric_types_lineEdit.setReadOnly(True)

        self.horizontalLayout_5.addWidget(self.lyric_types_lineEdit)

        self.label_3 = QLabel(self.layoutWidget_3)
        self.label_3.setObjectName(u"label_3")

        self.horizontalLayout_5.addWidget(self.label_3)

        self.songid_lineEdit = QLineEdit(self.layoutWidget_3)
        self.songid_lineEdit.setObjectName(u"songid_lineEdit")
        sizePolicy.setHeightForWidth(self.songid_lineEdit.sizePolicy().hasHeightForWidth())
        self.songid_lineEdit.setSizePolicy(sizePolicy)
        self.songid_lineEdit.setReadOnly(True)

        self.horizontalLayout_5.addWidget(self.songid_lineEdit)


        self.verticalLayout_8.addLayout(self.horizontalLayout_5)

        self.preview_plainTextEdit = QPlainTextEdit(self.layoutWidget_3)
        self.preview_plainTextEdit.setObjectName(u"preview_plainTextEdit")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.MinimumExpanding, QSizePolicy.Policy.Expanding)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.preview_plainTextEdit.sizePolicy().hasHeightForWidth())
        self.preview_plainTextEdit.setSizePolicy(sizePolicy2)
        self.preview_plainTextEdit.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        self.preview_plainTextEdit.setReadOnly(True)

        self.verticalLayout_8.addWidget(self.preview_plainTextEdit)

        self.splitter.addWidget(self.layoutWidget_3)

        self.verticalLayout.addWidget(self.splitter)

        self.horizontalLayout_3 = QHBoxLayout()
        self.horizontalLayout_3.setObjectName(u"horizontalLayout_3")
        self.verticalLayout_9 = QVBoxLayout()
        self.verticalLayout_9.setObjectName(u"verticalLayout_9")
        self.horizontalLayout_7 = QHBoxLayout()
        self.horizontalLayout_7.setObjectName(u"horizontalLayout_7")
        self.label_7 = QLabel(search)
        self.label_7.setObjectName(u"label_7")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.label_7.sizePolicy().hasHeightForWidth())
        self.label_7.setSizePolicy(sizePolicy3)

        self.horizontalLayout_7.addWidget(self.label_7)

        self.save_path_lineEdit = QLineEdit(search)
        self.save_path_lineEdit.setObjectName(u"save_path_lineEdit")
        sizePolicy4 = QSizePolicy(QSizePolicy.Policy.MinimumExpanding, QSizePolicy.Policy.Fixed)
        sizePolicy4.setHorizontalStretch(0)
        sizePolicy4.setVerticalStretch(0)
        sizePolicy4.setHeightForWidth(self.save_path_lineEdit.sizePolicy().hasHeightForWidth())
        self.save_path_lineEdit.setSizePolicy(sizePolicy4)

        self.horizontalLayout_7.addWidget(self.save_path_lineEdit)

        self.select_path_pushButton = QPushButton(search)
        self.select_path_pushButton.setObjectName(u"select_path_pushButton")
        sizePolicy.setHeightForWidth(self.select_path_pushButton.sizePolicy().hasHeightForWidth())
        self.select_path_pushButton.setSizePolicy(sizePolicy)

        self.horizontalLayout_7.addWidget(self.select_path_pushButton)


        self.verticalLayout_9.addLayout(self.horizontalLayout_7)

        self.horizontalLayout_8 = QHBoxLayout()
        self.horizontalLayout_8.setObjectName(u"horizontalLayout_8")
        self.original_checkBox = QCheckBox(search)
        self.original_checkBox.setObjectName(u"original_checkBox")
        sizePolicy.setHeightForWidth(self.original_checkBox.sizePolicy().hasHeightForWidth())
        self.original_checkBox.setSizePolicy(sizePolicy)
        self.original_checkBox.setChecked(True)

        self.horizontalLayout_8.addWidget(self.original_checkBox)

        self.translate_checkBox = QCheckBox(search)
        self.translate_checkBox.setObjectName(u"translate_checkBox")
        sizePolicy.setHeightForWidth(self.translate_checkBox.sizePolicy().hasHeightForWidth())
        self.translate_checkBox.setSizePolicy(sizePolicy)
        self.translate_checkBox.setChecked(True)

        self.horizontalLayout_8.addWidget(self.translate_checkBox)

        self.romanized_checkBox = QCheckBox(search)
        self.romanized_checkBox.setObjectName(u"romanized_checkBox")
        sizePolicy.setHeightForWidth(self.romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.romanized_checkBox.setSizePolicy(sizePolicy)

        self.horizontalLayout_8.addWidget(self.romanized_checkBox)

        self.label_5 = QLabel(search)
        self.label_5.setObjectName(u"label_5")
        sizePolicy3.setHeightForWidth(self.label_5.sizePolicy().hasHeightForWidth())
        self.label_5.setSizePolicy(sizePolicy3)

        self.horizontalLayout_8.addWidget(self.label_5)

        self.offset_spinBox = QSpinBox(search)
        self.offset_spinBox.setObjectName(u"offset_spinBox")
        sizePolicy5 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Fixed)
        sizePolicy5.setHorizontalStretch(0)
        sizePolicy5.setVerticalStretch(0)
        sizePolicy5.setHeightForWidth(self.offset_spinBox.sizePolicy().hasHeightForWidth())
        self.offset_spinBox.setSizePolicy(sizePolicy5)
        self.offset_spinBox.setMinimum(-999999999)
        self.offset_spinBox.setMaximum(999999999)
        self.offset_spinBox.setSingleStep(100)

        self.horizontalLayout_8.addWidget(self.offset_spinBox)


        self.verticalLayout_9.addLayout(self.horizontalLayout_8)

        self.horizontalLayout_9 = QHBoxLayout()
        self.horizontalLayout_9.setObjectName(u"horizontalLayout_9")
        self.label_9 = QLabel(search)
        self.label_9.setObjectName(u"label_9")
        sizePolicy3.setHeightForWidth(self.label_9.sizePolicy().hasHeightForWidth())
        self.label_9.setSizePolicy(sizePolicy3)

        self.horizontalLayout_9.addWidget(self.label_9)

        self.lyricsformat_comboBox = QComboBox(search)
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.setObjectName(u"lyricsformat_comboBox")

        self.horizontalLayout_9.addWidget(self.lyricsformat_comboBox)


        self.verticalLayout_9.addLayout(self.horizontalLayout_9)

        self.verticalSpacer_2 = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Preferred)

        self.verticalLayout_9.addItem(self.verticalSpacer_2)


        self.horizontalLayout_3.addLayout(self.verticalLayout_9)

        self.horizontalSpacer_3 = QSpacerItem(97, 20, QSizePolicy.Policy.Maximum, QSizePolicy.Policy.Minimum)

        self.horizontalLayout_3.addItem(self.horizontalSpacer_3)

        self.save_list_lyrics_pushButton = QPushButton(search)
        self.save_list_lyrics_pushButton.setObjectName(u"save_list_lyrics_pushButton")
        sizePolicy6 = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Preferred)
        sizePolicy6.setHorizontalStretch(0)
        sizePolicy6.setVerticalStretch(0)
        sizePolicy6.setHeightForWidth(self.save_list_lyrics_pushButton.sizePolicy().hasHeightForWidth())
        self.save_list_lyrics_pushButton.setSizePolicy(sizePolicy6)

        self.horizontalLayout_3.addWidget(self.save_list_lyrics_pushButton)

        self.save_preview_lyric_pushButton = QPushButton(search)
        self.save_preview_lyric_pushButton.setObjectName(u"save_preview_lyric_pushButton")
        sizePolicy7 = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Maximum)
        sizePolicy7.setHorizontalStretch(0)
        sizePolicy7.setVerticalStretch(0)
        sizePolicy7.setHeightForWidth(self.save_preview_lyric_pushButton.sizePolicy().hasHeightForWidth())
        self.save_preview_lyric_pushButton.setSizePolicy(sizePolicy7)
        self.save_preview_lyric_pushButton.setMinimumSize(QSize(92, 85))

        self.horizontalLayout_3.addWidget(self.save_preview_lyric_pushButton)


        self.verticalLayout.addLayout(self.horizontalLayout_3)


        self.retranslateUi(search)

        QMetaObject.connectSlotsByName(search)
    # setupUi

    def retranslateUi(self, search):
        search.setWindowTitle(QCoreApplication.translate("search", u"Form", None))
        self.label.setText(QCoreApplication.translate("search", u"\u641c\u7d22", None))
        self.label_4.setText(QCoreApplication.translate("search", u"\u4ece\u4e91\u7aef\u641c\u7d22\u5e76\u4e0b\u8f7d\u6b4c\u8bcd", None))
        self.source_comboBox.setItemText(0, QCoreApplication.translate("search", u"QQ\u97f3\u4e50", None))
        self.source_comboBox.setItemText(1, QCoreApplication.translate("search", u"\u9177\u72d7\u97f3\u4e50", None))
        self.source_comboBox.setItemText(2, QCoreApplication.translate("search", u"\u7f51\u6613\u4e91\u97f3\u4e50", None))

        self.search_type_comboBox.setItemText(0, QCoreApplication.translate("search", u"\u5355\u66f2", None))
        self.search_type_comboBox.setItemText(1, QCoreApplication.translate("search", u"\u4e13\u8f91", None))
        self.search_type_comboBox.setItemText(2, QCoreApplication.translate("search", u"\u6b4c\u5355", None))

        self.search_pushButton.setText(QCoreApplication.translate("search", u"\u641c\u7d22", None))
        self.result_label.setText(QCoreApplication.translate("search", u"\u641c\u7d22\u7ed3\u679c", None))
        self.return_toolButton.setText(QCoreApplication.translate("search", u"\u8fd4\u56de", None))
        self.label_8.setText(QCoreApplication.translate("search", u"\u6b4c\u8bcd\u9884\u89c8", None))
        self.label_2.setText(QCoreApplication.translate("search", u"\u6b4c\u8bcd\u7c7b\u578b", None))
        self.lyric_types_lineEdit.setText("")
        self.label_3.setText(QCoreApplication.translate("search", u"\u6b4c\u66f2/\u6b4c\u8bcdid", None))
        self.label_7.setText(QCoreApplication.translate("search", u"\u4fdd\u5b58\u5230:", None))
        self.select_path_pushButton.setText(QCoreApplication.translate("search", u"\u9009\u62e9\u4fdd\u5b58\u8def\u5f84", None))
        self.original_checkBox.setText(QCoreApplication.translate("search", u"\u539f\u6587", None))
        self.translate_checkBox.setText(QCoreApplication.translate("search", u"\u8bd1\u6587", None))
        self.romanized_checkBox.setText(QCoreApplication.translate("search", u"\u7f57\u9a6c\u97f3", None))
        self.label_5.setText(QCoreApplication.translate("search", u"\u504f\u79fb\u91cf:", None))
        self.label_9.setText(QCoreApplication.translate("search", u"\u6b4c\u8bcd\u683c\u5f0f:", None))
        self.lyricsformat_comboBox.setItemText(0, QCoreApplication.translate("search", u"LRC(\u9010\u5b57)", None))
        self.lyricsformat_comboBox.setItemText(1, QCoreApplication.translate("search", u"LRC(\u9010\u884c)", None))
        self.lyricsformat_comboBox.setItemText(2, QCoreApplication.translate("search", u"\u589e\u5f3a\u578bLRC(ESLyric)", None))
        self.lyricsformat_comboBox.setItemText(3, QCoreApplication.translate("search", u"SRT", None))
        self.lyricsformat_comboBox.setItemText(4, QCoreApplication.translate("search", u"ASS", None))

        self.save_list_lyrics_pushButton.setText(QCoreApplication.translate("search", u"\u4fdd\u5b58\u4e13\u8f91/\u6b4c\u5355\u7684\u6b4c\u8bcd", None))
        self.save_preview_lyric_pushButton.setText(QCoreApplication.translate("search", u"\u4fdd\u5b58\u9884\u89c8\u7684\u6b4c\u8bcd", None))
    # retranslateUi

