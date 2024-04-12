# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'local_match.ui'
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
    QCheckBox,
    QComboBox,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QPlainTextEdit,
    QPushButton,
    QSizePolicy,
    QSpacerItem,
    QSplitter,
    QVBoxLayout,
    QWidget,
)


class Ui_local_match(object):
    def setupUi(self, local_match):
        if not local_match.objectName():
            local_match.setObjectName(u"local_match")
        local_match.resize(1050, 600)
        self.horizontalLayout_6 = QHBoxLayout(local_match)
        self.horizontalLayout_6.setObjectName(u"horizontalLayout_6")
        self.splitter = QSplitter(local_match)
        self.splitter.setObjectName(u"splitter")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.splitter.sizePolicy().hasHeightForWidth())
        self.splitter.setSizePolicy(sizePolicy)
        self.splitter.setOrientation(Qt.Orientation.Horizontal)
        self.splitter.setOpaqueResize(True)
        self.splitter.setHandleWidth(5)
        self.splitter.setChildrenCollapsible(False)
        self.layoutWidget_2 = QWidget(self.splitter)
        self.layoutWidget_2.setObjectName(u"layoutWidget_2")
        self.verticalLayout_3 = QVBoxLayout(self.layoutWidget_2)
        self.verticalLayout_3.setObjectName(u"verticalLayout_3")
        self.verticalLayout_3.setContentsMargins(0, 0, 0, 0)
        self.verticalLayout = QVBoxLayout()
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.label = QLabel(self.layoutWidget_2)
        self.label.setObjectName(u"label")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.label.sizePolicy().hasHeightForWidth())
        self.label.setSizePolicy(sizePolicy1)
        self.label.setMaximumSize(QSize(16777215, 16777215))
        font = QFont()
        font.setPointSize(18)
        self.label.setFont(font)

        self.verticalLayout.addWidget(self.label)

        self.label_4 = QLabel(self.layoutWidget_2)
        self.label_4.setObjectName(u"label_4")

        self.verticalLayout.addWidget(self.label_4)

        self.horizontalLayout_7 = QHBoxLayout()
        self.horizontalLayout_7.setObjectName(u"horizontalLayout_7")
        self.song_path_lineEdit = QLineEdit(self.layoutWidget_2)
        self.song_path_lineEdit.setObjectName(u"song_path_lineEdit")

        self.horizontalLayout_7.addWidget(self.song_path_lineEdit)

        self.song_path_pushButton = QPushButton(self.layoutWidget_2)
        self.song_path_pushButton.setObjectName(u"song_path_pushButton")

        self.horizontalLayout_7.addWidget(self.song_path_pushButton)


        self.verticalLayout.addLayout(self.horizontalLayout_7)

        self.groupBox = QGroupBox(self.layoutWidget_2)
        self.groupBox.setObjectName(u"groupBox")
        self.gridLayout = QGridLayout(self.groupBox)
        self.gridLayout.setObjectName(u"gridLayout")
        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.label_5 = QLabel(self.groupBox)
        self.label_5.setObjectName(u"label_5")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.label_5.sizePolicy().hasHeightForWidth())
        self.label_5.setSizePolicy(sizePolicy2)

        self.horizontalLayout.addWidget(self.label_5)

        self.save_mode_comboBox = QComboBox(self.groupBox)
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.setObjectName(u"save_mode_comboBox")
        sizePolicy1.setHeightForWidth(self.save_mode_comboBox.sizePolicy().hasHeightForWidth())
        self.save_mode_comboBox.setSizePolicy(sizePolicy1)
        self.save_mode_comboBox.setMinimumSize(QSize(194, 0))

        self.horizontalLayout.addWidget(self.save_mode_comboBox)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)


        self.gridLayout.addLayout(self.horizontalLayout, 0, 0, 1, 1)

        self.save_path_lineEdit = QLineEdit(self.groupBox)
        self.save_path_lineEdit.setObjectName(u"save_path_lineEdit")

        self.gridLayout.addWidget(self.save_path_lineEdit, 2, 0, 1, 1)

        self.save_path_pushButton = QPushButton(self.groupBox)
        self.save_path_pushButton.setObjectName(u"save_path_pushButton")
        sizePolicy1.setHeightForWidth(self.save_path_pushButton.sizePolicy().hasHeightForWidth())
        self.save_path_pushButton.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.save_path_pushButton, 2, 1, 1, 1)

        self.horizontalLayout_2 = QHBoxLayout()
        self.horizontalLayout_2.setObjectName(u"horizontalLayout_2")
        self.label_6 = QLabel(self.groupBox)
        self.label_6.setObjectName(u"label_6")

        self.horizontalLayout_2.addWidget(self.label_6)

        self.lyrics_filename_mode_comboBox = QComboBox(self.groupBox)
        self.lyrics_filename_mode_comboBox.addItem("")
        self.lyrics_filename_mode_comboBox.addItem("")
        self.lyrics_filename_mode_comboBox.setObjectName(u"lyrics_filename_mode_comboBox")
        sizePolicy1.setHeightForWidth(self.lyrics_filename_mode_comboBox.sizePolicy().hasHeightForWidth())
        self.lyrics_filename_mode_comboBox.setSizePolicy(sizePolicy1)
        self.lyrics_filename_mode_comboBox.setMinimumSize(QSize(133, 0))

        self.horizontalLayout_2.addWidget(self.lyrics_filename_mode_comboBox)

        self.horizontalSpacer_2 = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout_2.addItem(self.horizontalSpacer_2)


        self.gridLayout.addLayout(self.horizontalLayout_2, 1, 0, 1, 1)


        self.verticalLayout.addWidget(self.groupBox)

        self.groupBox_2 = QGroupBox(self.layoutWidget_2)
        self.groupBox_2.setObjectName(u"groupBox_2")
        self.gridLayout_2 = QGridLayout(self.groupBox_2)
        self.gridLayout_2.setObjectName(u"gridLayout_2")
        self.horizontalLayout_3 = QHBoxLayout()
        self.horizontalLayout_3.setObjectName(u"horizontalLayout_3")
        self.label_9 = QLabel(self.groupBox_2)
        self.label_9.setObjectName(u"label_9")

        self.horizontalLayout_3.addWidget(self.label_9)

        self.original_checkBox = QCheckBox(self.groupBox_2)
        self.original_checkBox.setObjectName(u"original_checkBox")
        self.original_checkBox.setChecked(True)

        self.horizontalLayout_3.addWidget(self.original_checkBox)

        self.translate_checkBox = QCheckBox(self.groupBox_2)
        self.translate_checkBox.setObjectName(u"translate_checkBox")
        sizePolicy1.setHeightForWidth(self.translate_checkBox.sizePolicy().hasHeightForWidth())
        self.translate_checkBox.setSizePolicy(sizePolicy1)
        self.translate_checkBox.setChecked(True)

        self.horizontalLayout_3.addWidget(self.translate_checkBox, 0, Qt.AlignmentFlag.AlignLeft)

        self.romanized_checkBox = QCheckBox(self.groupBox_2)
        self.romanized_checkBox.setObjectName(u"romanized_checkBox")
        sizePolicy1.setHeightForWidth(self.romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.romanized_checkBox.setSizePolicy(sizePolicy1)

        self.horizontalLayout_3.addWidget(self.romanized_checkBox, 0, Qt.AlignmentFlag.AlignLeft)


        self.gridLayout_2.addLayout(self.horizontalLayout_3, 0, 0, 1, 1)

        self.horizontalLayout_4 = QHBoxLayout()
        self.horizontalLayout_4.setObjectName(u"horizontalLayout_4")
        self.verticalLayout_2 = QVBoxLayout()
        self.verticalLayout_2.setObjectName(u"verticalLayout_2")
        self.horizontalLayout_5 = QHBoxLayout()
        self.horizontalLayout_5.setObjectName(u"horizontalLayout_5")
        self.label_7 = QLabel(self.groupBox_2)
        self.label_7.setObjectName(u"label_7")

        self.horizontalLayout_5.addWidget(self.label_7, 0, Qt.AlignmentFlag.AlignTop)

        self.verticalLayout_4 = QVBoxLayout()
        self.verticalLayout_4.setObjectName(u"verticalLayout_4")
        self.qm_checkBox = QCheckBox(self.groupBox_2)
        self.qm_checkBox.setObjectName(u"qm_checkBox")
        self.qm_checkBox.setChecked(True)

        self.verticalLayout_4.addWidget(self.qm_checkBox)

        self.ne_checkBox = QCheckBox(self.groupBox_2)
        self.ne_checkBox.setObjectName(u"ne_checkBox")

        self.verticalLayout_4.addWidget(self.ne_checkBox)

        self.kg_checkBox = QCheckBox(self.groupBox_2)
        self.kg_checkBox.setObjectName(u"kg_checkBox")

        self.verticalLayout_4.addWidget(self.kg_checkBox)


        self.horizontalLayout_5.addLayout(self.verticalLayout_4)

        self.label_2 = QLabel(self.groupBox_2)
        self.label_2.setObjectName(u"label_2")

        self.horizontalLayout_5.addWidget(self.label_2, 0, Qt.AlignmentFlag.AlignTop)


        self.verticalLayout_2.addLayout(self.horizontalLayout_5)


        self.horizontalLayout_4.addLayout(self.verticalLayout_2)

        self.source_listWidget = QListWidget(self.groupBox_2)
        QListWidgetItem(self.source_listWidget)
        QListWidgetItem(self.source_listWidget)
        QListWidgetItem(self.source_listWidget)
        self.source_listWidget.setObjectName(u"source_listWidget")
        sizePolicy1.setHeightForWidth(self.source_listWidget.sizePolicy().hasHeightForWidth())
        self.source_listWidget.setSizePolicy(sizePolicy1)
        self.source_listWidget.setMinimumSize(QSize(0, 0))
        self.source_listWidget.setMaximumSize(QSize(96, 64))
        self.source_listWidget.setDragDropMode(QAbstractItemView.DragDropMode.DragDrop)
        self.source_listWidget.setDefaultDropAction(Qt.DropAction.MoveAction)

        self.horizontalLayout_4.addWidget(self.source_listWidget)

        self.horizontalSpacer_4 = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout_4.addItem(self.horizontalSpacer_4)


        self.gridLayout_2.addLayout(self.horizontalLayout_4, 2, 0, 1, 1)

        self.horizontalLayout_9 = QHBoxLayout()
        self.horizontalLayout_9.setObjectName(u"horizontalLayout_9")
        self.label_10 = QLabel(self.groupBox_2)
        self.label_10.setObjectName(u"label_10")
        sizePolicy2.setHeightForWidth(self.label_10.sizePolicy().hasHeightForWidth())
        self.label_10.setSizePolicy(sizePolicy2)

        self.horizontalLayout_9.addWidget(self.label_10)

        self.lyricsformat_comboBox = QComboBox(self.groupBox_2)
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.setObjectName(u"lyricsformat_comboBox")

        self.horizontalLayout_9.addWidget(self.lyricsformat_comboBox)


        self.gridLayout_2.addLayout(self.horizontalLayout_9, 1, 0, 1, 1)


        self.verticalLayout.addWidget(self.groupBox_2)

        self.start_cancel_pushButton = QPushButton(self.layoutWidget_2)
        self.start_cancel_pushButton.setObjectName(u"start_cancel_pushButton")

        self.verticalLayout.addWidget(self.start_cancel_pushButton)

        self.verticalSpacer = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Expanding)

        self.verticalLayout.addItem(self.verticalSpacer)


        self.verticalLayout_3.addLayout(self.verticalLayout)

        self.splitter.addWidget(self.layoutWidget_2)
        self.layoutWidget_3 = QWidget(self.splitter)
        self.layoutWidget_3.setObjectName(u"layoutWidget_3")
        self.verticalLayout_8 = QVBoxLayout(self.layoutWidget_3)
        self.verticalLayout_8.setObjectName(u"verticalLayout_8")
        self.verticalLayout_8.setContentsMargins(0, 0, 0, 0)
        self.plainTextEdit = QPlainTextEdit(self.layoutWidget_3)
        self.plainTextEdit.setObjectName(u"plainTextEdit")
        sizePolicy.setHeightForWidth(self.plainTextEdit.sizePolicy().hasHeightForWidth())
        self.plainTextEdit.setSizePolicy(sizePolicy)
        self.plainTextEdit.setReadOnly(True)

        self.verticalLayout_8.addWidget(self.plainTextEdit)

        self.splitter.addWidget(self.layoutWidget_3)

        self.horizontalLayout_6.addWidget(self.splitter)


        self.retranslateUi(local_match)

        QMetaObject.connectSlotsByName(local_match)
    # setupUi

    def retranslateUi(self, local_match):
        local_match.setWindowTitle(QCoreApplication.translate("local_match", u"Form", None))
        self.label.setText(QCoreApplication.translate("local_match", u"\u672c\u5730\u5339\u914d", None))
        self.label_4.setText(QCoreApplication.translate("local_match", u"\u4e3a\u672c\u5730\u6b4c\u66f2\u6587\u4ef6\u5339\u914d\u6b4c\u8bcd", None))
        self.song_path_pushButton.setText(QCoreApplication.translate("local_match", u"\u9009\u62e9\u8981\u904d\u5386\u7684\u6587\u4ef6\u5939", None))
        self.groupBox.setTitle(QCoreApplication.translate("local_match", u"\u4fdd\u5b58", None))
        self.label_5.setText(QCoreApplication.translate("local_match", u"\u6b4c\u8bcd\u4fdd\u5b58\u6a21\u5f0f:", None))
        self.save_mode_comboBox.setItemText(0, QCoreApplication.translate("local_match", u"\u4fdd\u5b58\u5230\u6b4c\u66f2\u6587\u4ef6\u5939\u7684\u955c\u50cf\u6587\u4ef6\u5939", None))
        self.save_mode_comboBox.setItemText(1, QCoreApplication.translate("local_match", u"\u4fdd\u5b58\u5230\u6b4c\u66f2\u6587\u4ef6\u5939", None))
        self.save_mode_comboBox.setItemText(2, QCoreApplication.translate("local_match", u"\u4fdd\u5b58\u5230\u6307\u5b9a\u6587\u4ef6\u5939", None))

        self.save_path_pushButton.setText(QCoreApplication.translate("local_match", u"\u9009\u62e9\u6587\u4ef6\u5939\u8def\u5f84", None))
        self.label_6.setText(QCoreApplication.translate("local_match", u"\u6b4c\u8bcd\u6587\u4ef6\u540d:", None))
        self.lyrics_filename_mode_comboBox.setItemText(0, QCoreApplication.translate("local_match", u"\u4e0e\u8bbe\u7f6e\u4e2d\u7684\u683c\u5f0f\u76f8\u540c", None))
        self.lyrics_filename_mode_comboBox.setItemText(1, QCoreApplication.translate("local_match", u"\u4e0e\u6b4c\u66f2\u6587\u4ef6\u540d\u76f8\u540c", None))

        self.groupBox_2.setTitle(QCoreApplication.translate("local_match", u"\u6b4c\u8bcd", None))
        self.label_9.setText(QCoreApplication.translate("local_match", u"\u6b4c\u8bcd\u7c7b\u578b:", None))
        self.original_checkBox.setText(QCoreApplication.translate("local_match", u"\u539f\u6587", None))
        self.translate_checkBox.setText(QCoreApplication.translate("local_match", u"\u8bd1\u6587", None))
        self.romanized_checkBox.setText(QCoreApplication.translate("local_match", u"\u7f57\u9a6c\u97f3", None))
        self.label_7.setText(QCoreApplication.translate("local_match", u"\u6b4c\u8bcd\u6765\u6e90:", None))
        self.qm_checkBox.setText(QCoreApplication.translate("local_match", u"QQ\u97f3\u4e50", None))
        self.ne_checkBox.setText(QCoreApplication.translate("local_match", u"\u7f51\u6613\u4e91\u97f3\u4e50", None))
        self.kg_checkBox.setText(QCoreApplication.translate("local_match", u"\u9177\u72d7\u97f3\u4e50", None))
        self.label_2.setText(QCoreApplication.translate("local_match", u"\u4f18\u5148\u987a\u5e8f:", None))

        __sortingEnabled = self.source_listWidget.isSortingEnabled()
        self.source_listWidget.setSortingEnabled(False)
        ___qlistwidgetitem = self.source_listWidget.item(0)
        ___qlistwidgetitem.setText(QCoreApplication.translate("local_match", u"QQ\u97f3\u4e50", None));
        ___qlistwidgetitem1 = self.source_listWidget.item(1)
        ___qlistwidgetitem1.setText(QCoreApplication.translate("local_match", u"\u9177\u72d7\u97f3\u4e50", None));
        ___qlistwidgetitem2 = self.source_listWidget.item(2)
        ___qlistwidgetitem2.setText(QCoreApplication.translate("local_match", u"\u7f51\u6613\u4e91\u97f3\u4e50", None));
        self.source_listWidget.setSortingEnabled(__sortingEnabled)

        self.label_10.setText(QCoreApplication.translate("local_match", u"\u6b4c\u8bcd\u683c\u5f0f:", None))
        self.lyricsformat_comboBox.setItemText(0, QCoreApplication.translate("local_match", u"LRC(\u9010\u5b57)", None))
        self.lyricsformat_comboBox.setItemText(1, QCoreApplication.translate("local_match", u"LRC(\u9010\u884c)", None))
        self.lyricsformat_comboBox.setItemText(2, QCoreApplication.translate("local_match", u"SRT", None))
        self.lyricsformat_comboBox.setItemText(3, QCoreApplication.translate("local_match", u"ASS", None))

        self.start_cancel_pushButton.setText(QCoreApplication.translate("local_match", u"\u5f00\u59cb\u5339\u914d", None))
    # retranslateUi

