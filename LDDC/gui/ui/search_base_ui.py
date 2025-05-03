################################################################################
## Form generated from reading UI file 'search_base.ui'
##
## Created by: Qt User Interface Compiler version 6.9.0
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, Qt
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

from LDDC.gui.components.custom_widgets import ProportionallyStretchedTableWidget


class Ui_search_base:
    def setupUi(self, search_base):
        if not search_base.objectName():
            search_base.setObjectName("search_base")
        self.verticalLayout = QVBoxLayout(search_base)
        self.verticalLayout.setObjectName("verticalLayout")
        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName("horizontalLayout")
        self.source_comboBox = QComboBox(search_base)
        self.source_comboBox.addItem("")
        self.source_comboBox.addItem("")
        self.source_comboBox.addItem("")
        self.source_comboBox.addItem("")
        self.source_comboBox.addItem("")
        self.source_comboBox.setObjectName("source_comboBox")
        self.source_comboBox.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToContents)

        self.horizontalLayout.addWidget(self.source_comboBox)

        self.search_type_comboBox = QComboBox(search_base)
        self.search_type_comboBox.setObjectName("search_type_comboBox")
        self.search_type_comboBox.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToContents)

        self.horizontalLayout.addWidget(self.search_type_comboBox)

        self.search_keyword_lineEdit = QLineEdit(search_base)
        self.search_keyword_lineEdit.setObjectName("search_keyword_lineEdit")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.search_keyword_lineEdit.sizePolicy().hasHeightForWidth())
        self.search_keyword_lineEdit.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.search_keyword_lineEdit)

        self.horizontalSpacer_2 = QSpacerItem(20, 20, QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer_2)

        self.search_pushButton = QPushButton(search_base)
        self.search_pushButton.setObjectName("search_pushButton")

        self.horizontalLayout.addWidget(self.search_pushButton)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)

        self.verticalLayout.addLayout(self.horizontalLayout)

        self.splitter = QSplitter(search_base)
        self.splitter.setObjectName("splitter")
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
        self.layoutWidget_2.setObjectName("layoutWidget_2")
        self.verticalLayout_3 = QVBoxLayout(self.layoutWidget_2)
        self.verticalLayout_3.setObjectName("verticalLayout_3")
        self.verticalLayout_3.setContentsMargins(0, 0, 0, 0)
        self.result_label = QLabel(self.layoutWidget_2)
        self.result_label.setObjectName("result_label")
        sizePolicy.setHeightForWidth(self.result_label.sizePolicy().hasHeightForWidth())
        self.result_label.setSizePolicy(sizePolicy)
        font = QFont()
        font.setPointSize(14)
        self.result_label.setFont(font)

        self.verticalLayout_3.addWidget(self.result_label)

        self.return_toolButton = QToolButton(self.layoutWidget_2)
        self.return_toolButton.setObjectName("return_toolButton")
        self.return_toolButton.setEnabled(False)
        self.return_toolButton.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        self.return_toolButton.setAutoRaise(False)
        self.return_toolButton.setArrowType(Qt.ArrowType.LeftArrow)

        self.verticalLayout_3.addWidget(self.return_toolButton)

        self.results_tableWidget = ProportionallyStretchedTableWidget(self.layoutWidget_2)
        self.results_tableWidget.setObjectName("results_tableWidget")
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
        self.layoutWidget_3.setObjectName("layoutWidget_3")
        self.verticalLayout_8 = QVBoxLayout(self.layoutWidget_3)
        self.verticalLayout_8.setObjectName("verticalLayout_8")
        self.verticalLayout_8.setContentsMargins(0, 0, 0, 0)
        self.label_8 = QLabel(self.layoutWidget_3)
        self.label_8.setObjectName("label_8")
        sizePolicy.setHeightForWidth(self.label_8.sizePolicy().hasHeightForWidth())
        self.label_8.setSizePolicy(sizePolicy)
        self.label_8.setFont(font)

        self.verticalLayout_8.addWidget(self.label_8)

        self.horizontalLayout_5 = QHBoxLayout()
        self.horizontalLayout_5.setObjectName("horizontalLayout_5")
        self.label_2 = QLabel(self.layoutWidget_3)
        self.label_2.setObjectName("label_2")

        self.horizontalLayout_5.addWidget(self.label_2)

        self.lyric_langs_lineEdit = QLineEdit(self.layoutWidget_3)
        self.lyric_langs_lineEdit.setObjectName("lyric_langs_lineEdit")
        self.lyric_langs_lineEdit.setReadOnly(True)

        self.horizontalLayout_5.addWidget(self.lyric_langs_lineEdit)

        self.label_3 = QLabel(self.layoutWidget_3)
        self.label_3.setObjectName("label_3")

        self.horizontalLayout_5.addWidget(self.label_3)

        self.songid_lineEdit = QLineEdit(self.layoutWidget_3)
        self.songid_lineEdit.setObjectName("songid_lineEdit")
        sizePolicy.setHeightForWidth(self.songid_lineEdit.sizePolicy().hasHeightForWidth())
        self.songid_lineEdit.setSizePolicy(sizePolicy)
        self.songid_lineEdit.setReadOnly(True)

        self.horizontalLayout_5.addWidget(self.songid_lineEdit)

        self.verticalLayout_8.addLayout(self.horizontalLayout_5)

        self.preview_plainTextEdit = QPlainTextEdit(self.layoutWidget_3)
        self.preview_plainTextEdit.setObjectName("preview_plainTextEdit")
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

        self.bottom_horizontalLayout = QHBoxLayout()
        self.bottom_horizontalLayout.setObjectName("bottom_horizontalLayout")
        self.control_verticalLayout = QVBoxLayout()
        self.control_verticalLayout.setObjectName("control_verticalLayout")
        self.horizontalLayout_7 = QHBoxLayout()
        self.horizontalLayout_7.setObjectName("horizontalLayout_7")

        self.control_verticalLayout.addLayout(self.horizontalLayout_7)

        self.horizontalLayout_8 = QHBoxLayout()
        self.horizontalLayout_8.setObjectName("horizontalLayout_8")
        self.original_checkBox = QCheckBox(search_base)
        self.original_checkBox.setObjectName("original_checkBox")
        sizePolicy.setHeightForWidth(self.original_checkBox.sizePolicy().hasHeightForWidth())
        self.original_checkBox.setSizePolicy(sizePolicy)
        self.original_checkBox.setChecked(True)

        self.horizontalLayout_8.addWidget(self.original_checkBox)

        self.translate_checkBox = QCheckBox(search_base)
        self.translate_checkBox.setObjectName("translate_checkBox")
        sizePolicy.setHeightForWidth(self.translate_checkBox.sizePolicy().hasHeightForWidth())
        self.translate_checkBox.setSizePolicy(sizePolicy)
        self.translate_checkBox.setChecked(True)

        self.horizontalLayout_8.addWidget(self.translate_checkBox)

        self.romanized_checkBox = QCheckBox(search_base)
        self.romanized_checkBox.setObjectName("romanized_checkBox")
        sizePolicy.setHeightForWidth(self.romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.romanized_checkBox.setSizePolicy(sizePolicy)

        self.horizontalLayout_8.addWidget(self.romanized_checkBox)

        self.label_5 = QLabel(search_base)
        self.label_5.setObjectName("label_5")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.label_5.sizePolicy().hasHeightForWidth())
        self.label_5.setSizePolicy(sizePolicy3)

        self.horizontalLayout_8.addWidget(self.label_5)

        self.offset_spinBox = QSpinBox(search_base)
        self.offset_spinBox.setObjectName("offset_spinBox")
        sizePolicy4 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Fixed)
        sizePolicy4.setHorizontalStretch(0)
        sizePolicy4.setVerticalStretch(0)
        sizePolicy4.setHeightForWidth(self.offset_spinBox.sizePolicy().hasHeightForWidth())
        self.offset_spinBox.setSizePolicy(sizePolicy4)
        self.offset_spinBox.setMinimum(-999999999)
        self.offset_spinBox.setMaximum(999999999)
        self.offset_spinBox.setSingleStep(100)

        self.horizontalLayout_8.addWidget(self.offset_spinBox)

        self.control_verticalLayout.addLayout(self.horizontalLayout_8)

        self.horizontalLayout_9 = QHBoxLayout()
        self.horizontalLayout_9.setObjectName("horizontalLayout_9")
        self.label_9 = QLabel(search_base)
        self.label_9.setObjectName("label_9")
        sizePolicy3.setHeightForWidth(self.label_9.sizePolicy().hasHeightForWidth())
        self.label_9.setSizePolicy(sizePolicy3)

        self.horizontalLayout_9.addWidget(self.label_9)

        self.lyricsformat_comboBox = QComboBox(search_base)
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.setObjectName("lyricsformat_comboBox")

        self.horizontalLayout_9.addWidget(self.lyricsformat_comboBox)

        self.translate_pushButton = QPushButton(search_base)
        self.translate_pushButton.setObjectName("translate_pushButton")

        self.horizontalLayout_9.addWidget(self.translate_pushButton)

        self.control_verticalLayout.addLayout(self.horizontalLayout_9)

        self.control_verticalSpacer = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Preferred)

        self.control_verticalLayout.addItem(self.control_verticalSpacer)

        self.bottom_horizontalLayout.addLayout(self.control_verticalLayout)

        self.horizontalSpacer_3 = QSpacerItem(97, 20, QSizePolicy.Policy.Maximum, QSizePolicy.Policy.Minimum)

        self.bottom_horizontalLayout.addItem(self.horizontalSpacer_3)

        self.verticalLayout.addLayout(self.bottom_horizontalLayout)

        self.retranslateUi(search_base)

        QMetaObject.connectSlotsByName(search_base)

    # setupUi

    def retranslateUi(self, search_base):
        self.source_comboBox.setItemText(0, QCoreApplication.translate("search_base", "\u805a\u5408", None))
        self.source_comboBox.setItemText(1, QCoreApplication.translate("search_base", "QQ\u97f3\u4e50", None))
        self.source_comboBox.setItemText(2, QCoreApplication.translate("search_base", "\u9177\u72d7\u97f3\u4e50", None))
        self.source_comboBox.setItemText(3, QCoreApplication.translate("search_base", "\u7f51\u6613\u4e91\u97f3\u4e50", None))
        self.source_comboBox.setItemText(4, QCoreApplication.translate("search_base", "Lrclib", None))

        self.search_keyword_lineEdit.setInputMask("")
        self.search_keyword_lineEdit.setText("")
        self.search_keyword_lineEdit.setPlaceholderText(QCoreApplication.translate("search_base", "\u8f93\u5165\u5173\u952e\u8bcd", None))
        self.search_pushButton.setText(QCoreApplication.translate("search_base", "\u641c\u7d22", None))
        self.result_label.setText(QCoreApplication.translate("search_base", "\u641c\u7d22\u7ed3\u679c", None))
        self.return_toolButton.setText(QCoreApplication.translate("search_base", "\u8fd4\u56de", None))
        self.label_8.setText(QCoreApplication.translate("search_base", "\u6b4c\u8bcd\u9884\u89c8", None))
        self.label_2.setText(QCoreApplication.translate("search_base", "\u6b4c\u8bcd\u8bed\u8a00", None))
        self.lyric_langs_lineEdit.setText("")
        self.label_3.setText(QCoreApplication.translate("search_base", "\u6b4c\u66f2/\u6b4c\u8bcdid", None))
        self.original_checkBox.setText(QCoreApplication.translate("search_base", "\u539f\u6587", None))
        self.translate_checkBox.setText(QCoreApplication.translate("search_base", "\u8bd1\u6587", None))
        self.romanized_checkBox.setText(QCoreApplication.translate("search_base", "\u7f57\u9a6c\u97f3", None))
        self.label_5.setText(QCoreApplication.translate("search_base", "\u504f\u79fb\u91cf:", None))
        self.label_9.setText(QCoreApplication.translate("search_base", "\u6b4c\u8bcd\u683c\u5f0f:", None))
        self.lyricsformat_comboBox.setItemText(0, QCoreApplication.translate("search_base", "LRC(\u9010\u5b57)", None))
        self.lyricsformat_comboBox.setItemText(1, QCoreApplication.translate("search_base", "LRC(\u9010\u884c)", None))
        self.lyricsformat_comboBox.setItemText(2, QCoreApplication.translate("search_base", "\u589e\u5f3a\u578bLRC(ESLyric)", None))
        self.lyricsformat_comboBox.setItemText(3, QCoreApplication.translate("search_base", "SRT", None))
        self.lyricsformat_comboBox.setItemText(4, QCoreApplication.translate("search_base", "ASS", None))

        self.translate_pushButton.setText(QCoreApplication.translate("search_base", "\u7ffb\u8bd1\u6b4c\u8bcd", None))

    # retranslateUi
