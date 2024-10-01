################################################################################
## Form generated from reading UI file 'local_match.ui'
##
## Created by: Qt User Interface Compiler version 6.7.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, QSize, Qt
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QComboBox,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPlainTextEdit,
    QProgressBar,
    QPushButton,
    QSizePolicy,
    QSpacerItem,
    QSpinBox,
    QSplitter,
    QVBoxLayout,
    QWidget,
)

from LDDC.ui.custom_widgets import CheckBoxListWidget


class Ui_local_match:
    def setupUi(self, local_match):
        if not local_match.objectName():
            local_match.setObjectName("local_match")
        local_match.resize(1050, 600)
        self.horizontalLayout_6 = QHBoxLayout(local_match)
        self.horizontalLayout_6.setObjectName("horizontalLayout_6")
        self.splitter = QSplitter(local_match)
        self.splitter.setObjectName("splitter")
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
        self.layoutWidget_2.setObjectName("layoutWidget_2")
        self.verticalLayout_3 = QVBoxLayout(self.layoutWidget_2)
        self.verticalLayout_3.setObjectName("verticalLayout_3")
        self.verticalLayout_3.setContentsMargins(0, 0, 0, 0)
        self.verticalLayout = QVBoxLayout()
        self.verticalLayout.setObjectName("verticalLayout")
        self.label = QLabel(self.layoutWidget_2)
        self.label.setObjectName("label")
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
        self.label_4.setObjectName("label_4")

        self.verticalLayout.addWidget(self.label_4)

        self.horizontalLayout_7 = QHBoxLayout()
        self.horizontalLayout_7.setObjectName("horizontalLayout_7")
        self.song_path_lineEdit = QLineEdit(self.layoutWidget_2)
        self.song_path_lineEdit.setObjectName("song_path_lineEdit")

        self.horizontalLayout_7.addWidget(self.song_path_lineEdit)

        self.song_path_pushButton = QPushButton(self.layoutWidget_2)
        self.song_path_pushButton.setObjectName("song_path_pushButton")

        self.horizontalLayout_7.addWidget(self.song_path_pushButton)

        self.verticalLayout.addLayout(self.horizontalLayout_7)

        self.groupBox = QGroupBox(self.layoutWidget_2)
        self.groupBox.setObjectName("groupBox")
        self.gridLayout = QGridLayout(self.groupBox)
        self.gridLayout.setObjectName("gridLayout")
        self.save_path_lineEdit = QLineEdit(self.groupBox)
        self.save_path_lineEdit.setObjectName("save_path_lineEdit")

        self.gridLayout.addWidget(self.save_path_lineEdit, 1, 0, 1, 1)

        self.save_path_pushButton = QPushButton(self.groupBox)
        self.save_path_pushButton.setObjectName("save_path_pushButton")
        sizePolicy1.setHeightForWidth(self.save_path_pushButton.sizePolicy().hasHeightForWidth())
        self.save_path_pushButton.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.save_path_pushButton, 1, 1, 1, 1)

        self.gridLayout_7 = QGridLayout()
        self.gridLayout_7.setObjectName("gridLayout_7")
        self.label_8 = QLabel(self.groupBox)
        self.label_8.setObjectName("label_8")

        self.gridLayout_7.addWidget(self.label_8, 1, 0, 1, 1)

        self.label_11 = QLabel(self.groupBox)
        self.label_11.setObjectName("label_11")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.label_11.sizePolicy().hasHeightForWidth())
        self.label_11.setSizePolicy(sizePolicy2)

        self.gridLayout_7.addWidget(self.label_11, 0, 0, 1, 1)

        self.save_mode_comboBox = QComboBox(self.groupBox)
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.setObjectName("save_mode_comboBox")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.save_mode_comboBox.sizePolicy().hasHeightForWidth())
        self.save_mode_comboBox.setSizePolicy(sizePolicy3)
        self.save_mode_comboBox.setMinimumSize(QSize(194, 0))

        self.gridLayout_7.addWidget(self.save_mode_comboBox, 0, 1, 1, 1)

        self.lyrics_filename_mode_comboBox = QComboBox(self.groupBox)
        self.lyrics_filename_mode_comboBox.addItem("")
        self.lyrics_filename_mode_comboBox.addItem("")
        self.lyrics_filename_mode_comboBox.setObjectName("lyrics_filename_mode_comboBox")
        sizePolicy3.setHeightForWidth(self.lyrics_filename_mode_comboBox.sizePolicy().hasHeightForWidth())
        self.lyrics_filename_mode_comboBox.setSizePolicy(sizePolicy3)
        self.lyrics_filename_mode_comboBox.setMinimumSize(QSize(133, 0))

        self.gridLayout_7.addWidget(self.lyrics_filename_mode_comboBox, 1, 1, 1, 1)

        self.gridLayout.addLayout(self.gridLayout_7, 0, 0, 1, 1)

        self.verticalLayout.addWidget(self.groupBox)

        self.groupBox_2 = QGroupBox(self.layoutWidget_2)
        self.groupBox_2.setObjectName("groupBox_2")
        self.gridLayout_2 = QGridLayout(self.groupBox_2)
        self.gridLayout_2.setObjectName("gridLayout_2")
        self.horizontalLayout_5 = QHBoxLayout()
        self.horizontalLayout_5.setObjectName("horizontalLayout_5")
        self.gridLayout_4 = QGridLayout()
        self.gridLayout_4.setObjectName("gridLayout_4")
        self.min_score_spinBox = QSpinBox(self.groupBox_2)
        self.min_score_spinBox.setObjectName("min_score_spinBox")
        self.min_score_spinBox.setMinimumSize(QSize(70, 0))
        self.min_score_spinBox.setMaximum(100)
        self.min_score_spinBox.setValue(60)

        self.gridLayout_4.addWidget(self.min_score_spinBox, 0, 3, 1, 1, Qt.AlignmentFlag.AlignTop)

        self.label_3 = QLabel(self.groupBox_2)
        self.label_3.setObjectName("label_3")
        sizePolicy2.setHeightForWidth(self.label_3.sizePolicy().hasHeightForWidth())
        self.label_3.setSizePolicy(sizePolicy2)

        self.gridLayout_4.addWidget(self.label_3, 0, 2, 1, 1, Qt.AlignmentFlag.AlignTop)

        self.label_2 = QLabel(self.groupBox_2)
        self.label_2.setObjectName("label_2")
        sizePolicy2.setHeightForWidth(self.label_2.sizePolicy().hasHeightForWidth())
        self.label_2.setSizePolicy(sizePolicy2)

        self.gridLayout_4.addWidget(self.label_2, 0, 0, 1, 1, Qt.AlignmentFlag.AlignTop)

        self.source_listWidget = CheckBoxListWidget(self.groupBox_2)
        self.source_listWidget.setObjectName("source_listWidget")
        sizePolicy3.setHeightForWidth(self.source_listWidget.sizePolicy().hasHeightForWidth())
        self.source_listWidget.setSizePolicy(sizePolicy3)
        self.source_listWidget.setMinimumSize(QSize(0, 0))
        self.source_listWidget.setMaximumSize(QSize(96, 64))
        self.source_listWidget.setDragDropMode(QAbstractItemView.DragDropMode.DragDrop)
        self.source_listWidget.setDefaultDropAction(Qt.DropAction.MoveAction)

        self.gridLayout_4.addWidget(self.source_listWidget, 0, 1, 1, 1)

        self.horizontalLayout_5.addLayout(self.gridLayout_4)

        self.gridLayout_2.addLayout(self.horizontalLayout_5, 0, 0, 1, 1)

        self.gridLayout_5 = QGridLayout()
        self.gridLayout_5.setObjectName("gridLayout_5")
        self.label_9 = QLabel(self.groupBox_2)
        self.label_9.setObjectName("label_9")

        self.gridLayout_5.addWidget(self.label_9, 0, 0, 1, 1)

        self.horizontalLayout_3 = QHBoxLayout()
        self.horizontalLayout_3.setObjectName("horizontalLayout_3")
        self.original_checkBox = QCheckBox(self.groupBox_2)
        self.original_checkBox.setObjectName("original_checkBox")
        self.original_checkBox.setChecked(True)

        self.horizontalLayout_3.addWidget(self.original_checkBox)

        self.translate_checkBox = QCheckBox(self.groupBox_2)
        self.translate_checkBox.setObjectName("translate_checkBox")
        sizePolicy1.setHeightForWidth(self.translate_checkBox.sizePolicy().hasHeightForWidth())
        self.translate_checkBox.setSizePolicy(sizePolicy1)
        self.translate_checkBox.setChecked(True)

        self.horizontalLayout_3.addWidget(self.translate_checkBox, 0, Qt.AlignmentFlag.AlignLeft)

        self.romanized_checkBox = QCheckBox(self.groupBox_2)
        self.romanized_checkBox.setObjectName("romanized_checkBox")
        sizePolicy1.setHeightForWidth(self.romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.romanized_checkBox.setSizePolicy(sizePolicy1)

        self.horizontalLayout_3.addWidget(self.romanized_checkBox, 0, Qt.AlignmentFlag.AlignLeft)

        self.gridLayout_5.addLayout(self.horizontalLayout_3, 0, 1, 1, 1)

        self.label_10 = QLabel(self.groupBox_2)
        self.label_10.setObjectName("label_10")
        sizePolicy2.setHeightForWidth(self.label_10.sizePolicy().hasHeightForWidth())
        self.label_10.setSizePolicy(sizePolicy2)

        self.gridLayout_5.addWidget(self.label_10, 1, 0, 1, 1)

        self.lyricsformat_comboBox = QComboBox(self.groupBox_2)
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.setObjectName("lyricsformat_comboBox")

        self.gridLayout_5.addWidget(self.lyricsformat_comboBox, 1, 1, 1, 1)

        self.gridLayout_2.addLayout(self.gridLayout_5, 1, 0, 1, 1)

        self.verticalLayout.addWidget(self.groupBox_2)

        self.start_cancel_pushButton = QPushButton(self.layoutWidget_2)
        self.start_cancel_pushButton.setObjectName("start_cancel_pushButton")

        self.verticalLayout.addWidget(self.start_cancel_pushButton)

        self.verticalSpacer = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Expanding)

        self.verticalLayout.addItem(self.verticalSpacer)

        self.verticalLayout_3.addLayout(self.verticalLayout)

        self.splitter.addWidget(self.layoutWidget_2)
        self.layoutWidget_3 = QWidget(self.splitter)
        self.layoutWidget_3.setObjectName("layoutWidget_3")
        self.verticalLayout_8 = QVBoxLayout(self.layoutWidget_3)
        self.verticalLayout_8.setObjectName("verticalLayout_8")
        self.verticalLayout_8.setContentsMargins(0, 0, 0, 0)
        self.plainTextEdit = QPlainTextEdit(self.layoutWidget_3)
        self.plainTextEdit.setObjectName("plainTextEdit")
        sizePolicy.setHeightForWidth(self.plainTextEdit.sizePolicy().hasHeightForWidth())
        self.plainTextEdit.setSizePolicy(sizePolicy)
        self.plainTextEdit.setReadOnly(True)

        self.verticalLayout_8.addWidget(self.plainTextEdit)

        self.progressBar = QProgressBar(self.layoutWidget_3)
        self.progressBar.setObjectName("progressBar")
        self.progressBar.setMaximum(0)
        self.progressBar.setValue(0)
        self.progressBar.setOrientation(Qt.Orientation.Horizontal)
        self.progressBar.setInvertedAppearance(False)

        self.verticalLayout_8.addWidget(self.progressBar)

        self.splitter.addWidget(self.layoutWidget_3)

        self.horizontalLayout_6.addWidget(self.splitter)

        self.retranslateUi(local_match)

        QMetaObject.connectSlotsByName(local_match)

    # setupUi

    def retranslateUi(self, local_match):
        self.label.setText(QCoreApplication.translate("local_match", "\u672c\u5730\u5339\u914d", None))
        self.label_4.setText(QCoreApplication.translate("local_match", "\u4e3a\u672c\u5730\u6b4c\u66f2\u6587\u4ef6\u5339\u914d\u6b4c\u8bcd", None))
        self.song_path_pushButton.setText(QCoreApplication.translate("local_match", "\u9009\u62e9\u8981\u904d\u5386\u7684\u6587\u4ef6\u5939", None))
        self.groupBox.setTitle(QCoreApplication.translate("local_match", "\u4fdd\u5b58", None))
        self.save_path_pushButton.setText(QCoreApplication.translate("local_match", "\u9009\u62e9\u6587\u4ef6\u5939\u8def\u5f84", None))
        self.label_8.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u6587\u4ef6\u540d:", None))
        self.label_11.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u4fdd\u5b58\u6a21\u5f0f:", None))
        self.save_mode_comboBox.setItemText(
            0, QCoreApplication.translate("local_match", "\u4fdd\u5b58\u5230\u6b4c\u66f2\u6587\u4ef6\u5939\u7684\u955c\u50cf\u6587\u4ef6\u5939", None)
        )
        self.save_mode_comboBox.setItemText(1, QCoreApplication.translate("local_match", "\u4fdd\u5b58\u5230\u6b4c\u66f2\u6587\u4ef6\u5939", None))
        self.save_mode_comboBox.setItemText(2, QCoreApplication.translate("local_match", "\u4fdd\u5b58\u5230\u6307\u5b9a\u6587\u4ef6\u5939", None))

        self.lyrics_filename_mode_comboBox.setItemText(
            0, QCoreApplication.translate("local_match", "\u4e0e\u8bbe\u7f6e\u4e2d\u7684\u683c\u5f0f\u76f8\u540c", None)
        )
        self.lyrics_filename_mode_comboBox.setItemText(1, QCoreApplication.translate("local_match", "\u4e0e\u6b4c\u66f2\u6587\u4ef6\u540d\u76f8\u540c", None))

        self.groupBox_2.setTitle(QCoreApplication.translate("local_match", "\u6b4c\u8bcd", None))
        self.label_3.setText(QCoreApplication.translate("local_match", "\u6700\u4f4e\u5339\u914d\u5ea6(0~100):", None))
        self.label_2.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u6765\u6e90:", None))
        self.label_9.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u7c7b\u578b:", None))
        self.original_checkBox.setText(QCoreApplication.translate("local_match", "\u539f\u6587", None))
        self.translate_checkBox.setText(QCoreApplication.translate("local_match", "\u8bd1\u6587", None))
        self.romanized_checkBox.setText(QCoreApplication.translate("local_match", "\u7f57\u9a6c\u97f3", None))
        self.label_10.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u683c\u5f0f:", None))
        self.lyricsformat_comboBox.setItemText(0, QCoreApplication.translate("local_match", "LRC(\u9010\u5b57)", None))
        self.lyricsformat_comboBox.setItemText(1, QCoreApplication.translate("local_match", "LRC(\u9010\u884c)", None))
        self.lyricsformat_comboBox.setItemText(2, QCoreApplication.translate("local_match", "\u589e\u5f3a\u578bLRC(ESLyric)", None))
        self.lyricsformat_comboBox.setItemText(3, QCoreApplication.translate("local_match", "SRT", None))
        self.lyricsformat_comboBox.setItemText(4, QCoreApplication.translate("local_match", "ASS", None))

        self.start_cancel_pushButton.setText(QCoreApplication.translate("local_match", "\u5f00\u59cb\u5339\u914d", None))

    # retranslateUi
