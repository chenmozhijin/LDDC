################################################################################
## Form generated from reading UI file 'local_match.ui'
##
## Created by: Qt User Interface Compiler version 6.9.0
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, QSize, Qt
from PySide6.QtWidgets import (
    QAbstractItemView,
    QAbstractScrollArea,
    QCheckBox,
    QComboBox,
    QGridLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QSizePolicy,
    QSpinBox,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from LDDC.gui.components.custom_widgets import CheckBoxListWidget, ProportionallyStretchedTableWidget


class Ui_local_match:
    def setupUi(self, local_match):
        if not local_match.objectName():
            local_match.setObjectName("local_match")
        self.verticalLayout = QVBoxLayout(local_match)
        self.verticalLayout.setObjectName("verticalLayout")
        self.control_bar = QWidget(local_match)
        self.control_bar.setObjectName("control_bar")
        self.gridLayout = QGridLayout(self.control_bar)
        self.gridLayout.setObjectName("gridLayout")
        self.original_checkBox = QCheckBox(self.control_bar)
        self.original_checkBox.setObjectName("original_checkBox")
        self.original_checkBox.setChecked(True)

        self.gridLayout.addWidget(self.original_checkBox, 1, 9, 1, 1)

        self.select_dirs_button = QPushButton(self.control_bar)
        self.select_dirs_button.setObjectName("select_dirs_button")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Preferred)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.select_dirs_button.sizePolicy().hasHeightForWidth())
        self.select_dirs_button.setSizePolicy(sizePolicy)

        self.gridLayout.addWidget(self.select_dirs_button, 3, 0, 2, 1)

        self.save_path_button = QPushButton(self.control_bar)
        self.save_path_button.setObjectName("save_path_button")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Preferred)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.save_path_button.sizePolicy().hasHeightForWidth())
        self.save_path_button.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.save_path_button, 0, 1, 5, 1)

        self.romanized_checkBox = QCheckBox(self.control_bar)
        self.romanized_checkBox.setObjectName("romanized_checkBox")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.romanized_checkBox.setSizePolicy(sizePolicy2)

        self.gridLayout.addWidget(self.romanized_checkBox, 1, 11, 1, 1)

        self.label_8 = QLabel(self.control_bar)
        self.label_8.setObjectName("label_8")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.label_8.sizePolicy().hasHeightForWidth())
        self.label_8.setSizePolicy(sizePolicy3)

        self.gridLayout.addWidget(self.label_8, 3, 3, 1, 1)

        self.lyricsformat_comboBox = QComboBox(self.control_bar)
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.addItem("")
        self.lyricsformat_comboBox.setObjectName("lyricsformat_comboBox")

        self.gridLayout.addWidget(self.lyricsformat_comboBox, 4, 4, 1, 1)

        self.source_listWidget = CheckBoxListWidget(self.control_bar)
        self.source_listWidget.setObjectName("source_listWidget")
        sizePolicy3.setHeightForWidth(self.source_listWidget.sizePolicy().hasHeightForWidth())
        self.source_listWidget.setSizePolicy(sizePolicy3)
        self.source_listWidget.setMinimumSize(QSize(0, 0))
        self.source_listWidget.setMaximumSize(QSize(96, 78))
        self.source_listWidget.setDragEnabled(False)
        self.source_listWidget.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)
        self.source_listWidget.setDefaultDropAction(Qt.DropAction.TargetMoveAction)

        self.gridLayout.addWidget(self.source_listWidget, 1, 2, 4, 1)

        self.label = QLabel(self.control_bar)
        self.label.setObjectName("label")

        self.gridLayout.addWidget(self.label, 1, 3, 1, 1)

        self.label_11 = QLabel(self.control_bar)
        self.label_11.setObjectName("label_11")
        sizePolicy1.setHeightForWidth(self.label_11.sizePolicy().hasHeightForWidth())
        self.label_11.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.label_11, 0, 3, 1, 1)

        self.label_2 = QLabel(self.control_bar)
        self.label_2.setObjectName("label_2")
        sizePolicy3.setHeightForWidth(self.label_2.sizePolicy().hasHeightForWidth())
        self.label_2.setSizePolicy(sizePolicy3)

        self.gridLayout.addWidget(self.label_2, 0, 2, 1, 1)

        self.min_score_spinBox = QSpinBox(self.control_bar)
        self.min_score_spinBox.setObjectName("min_score_spinBox")
        self.min_score_spinBox.setMinimumSize(QSize(70, 0))
        self.min_score_spinBox.setMaximum(100)
        self.min_score_spinBox.setValue(60)

        self.gridLayout.addWidget(self.min_score_spinBox, 0, 9, 1, 2)

        self.save_mode_comboBox = QComboBox(self.control_bar)
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.addItem("")
        self.save_mode_comboBox.setObjectName("save_mode_comboBox")
        sizePolicy4 = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        sizePolicy4.setHorizontalStretch(0)
        sizePolicy4.setVerticalStretch(0)
        sizePolicy4.setHeightForWidth(self.save_mode_comboBox.sizePolicy().hasHeightForWidth())
        self.save_mode_comboBox.setSizePolicy(sizePolicy4)
        self.save_mode_comboBox.setMinimumSize(QSize(194, 0))
        self.save_mode_comboBox.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToContents)

        self.gridLayout.addWidget(self.save_mode_comboBox, 0, 4, 1, 2)

        self.start_cancel_pushButton = QPushButton(self.control_bar)
        self.start_cancel_pushButton.setObjectName("start_cancel_pushButton")
        sizePolicy1.setHeightForWidth(self.start_cancel_pushButton.sizePolicy().hasHeightForWidth())
        self.start_cancel_pushButton.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.start_cancel_pushButton, 3, 7, 2, 5)

        self.label_3 = QLabel(self.control_bar)
        self.label_3.setObjectName("label_3")
        sizePolicy3.setHeightForWidth(self.label_3.sizePolicy().hasHeightForWidth())
        self.label_3.setSizePolicy(sizePolicy3)

        self.gridLayout.addWidget(self.label_3, 0, 7, 1, 2)

        self.select_files_button = QPushButton(self.control_bar)
        self.select_files_button.setObjectName("select_files_button")
        sizePolicy1.setHeightForWidth(self.select_files_button.sizePolicy().hasHeightForWidth())
        self.select_files_button.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.select_files_button, 0, 0, 3, 1)

        self.label_9 = QLabel(self.control_bar)
        self.label_9.setObjectName("label_9")

        self.gridLayout.addWidget(self.label_9, 1, 7, 1, 2)

        self.label_10 = QLabel(self.control_bar)
        self.label_10.setObjectName("label_10")
        sizePolicy3.setHeightForWidth(self.label_10.sizePolicy().hasHeightForWidth())
        self.label_10.setSizePolicy(sizePolicy3)

        self.gridLayout.addWidget(self.label_10, 4, 3, 1, 1)

        self.filename_mode_comboBox = QComboBox(self.control_bar)
        self.filename_mode_comboBox.addItem("")
        self.filename_mode_comboBox.addItem("")
        self.filename_mode_comboBox.addItem("")
        self.filename_mode_comboBox.setObjectName("filename_mode_comboBox")
        sizePolicy4.setHeightForWidth(self.filename_mode_comboBox.sizePolicy().hasHeightForWidth())
        self.filename_mode_comboBox.setSizePolicy(sizePolicy4)
        self.filename_mode_comboBox.setMinimumSize(QSize(133, 0))

        self.gridLayout.addWidget(self.filename_mode_comboBox, 3, 4, 1, 1)

        self.save2tag_mode_comboBox = QComboBox(self.control_bar)
        self.save2tag_mode_comboBox.addItem("")
        self.save2tag_mode_comboBox.addItem("")
        self.save2tag_mode_comboBox.addItem("")
        self.save2tag_mode_comboBox.setObjectName("save2tag_mode_comboBox")
        self.save2tag_mode_comboBox.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToContents)

        self.gridLayout.addWidget(self.save2tag_mode_comboBox, 1, 4, 1, 1)

        self.translate_checkBox = QCheckBox(self.control_bar)
        self.translate_checkBox.setObjectName("translate_checkBox")
        sizePolicy2.setHeightForWidth(self.translate_checkBox.sizePolicy().hasHeightForWidth())
        self.translate_checkBox.setSizePolicy(sizePolicy2)
        self.translate_checkBox.setChecked(True)

        self.gridLayout.addWidget(self.translate_checkBox, 1, 10, 1, 1)

        self.skip_existing_lyrics_checkbox = QCheckBox(self.control_bar)
        self.skip_existing_lyrics_checkbox.setObjectName("skip_existing_lyrics_checkbox")

        self.gridLayout.addWidget(self.skip_existing_lyrics_checkbox, 0, 11, 1, 1)

        self.verticalLayout.addWidget(self.control_bar)

        self.songs_table = ProportionallyStretchedTableWidget(local_match)
        if self.songs_table.columnCount() < 7:
            self.songs_table.setColumnCount(7)
        __qtablewidgetitem = QTableWidgetItem()
        self.songs_table.setHorizontalHeaderItem(0, __qtablewidgetitem)
        __qtablewidgetitem1 = QTableWidgetItem()
        self.songs_table.setHorizontalHeaderItem(1, __qtablewidgetitem1)
        __qtablewidgetitem2 = QTableWidgetItem()
        self.songs_table.setHorizontalHeaderItem(2, __qtablewidgetitem2)
        __qtablewidgetitem3 = QTableWidgetItem()
        self.songs_table.setHorizontalHeaderItem(3, __qtablewidgetitem3)
        __qtablewidgetitem4 = QTableWidgetItem()
        self.songs_table.setHorizontalHeaderItem(4, __qtablewidgetitem4)
        __qtablewidgetitem5 = QTableWidgetItem()
        self.songs_table.setHorizontalHeaderItem(5, __qtablewidgetitem5)
        __qtablewidgetitem6 = QTableWidgetItem()
        self.songs_table.setHorizontalHeaderItem(6, __qtablewidgetitem6)
        self.songs_table.setObjectName("songs_table")
        sizePolicy5 = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        sizePolicy5.setHorizontalStretch(0)
        sizePolicy5.setVerticalStretch(0)
        sizePolicy5.setHeightForWidth(self.songs_table.sizePolicy().hasHeightForWidth())
        self.songs_table.setSizePolicy(sizePolicy5)
        self.songs_table.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.songs_table.setSizeAdjustPolicy(QAbstractScrollArea.SizeAdjustPolicy.AdjustIgnored)
        self.songs_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.songs_table.setDragDropOverwriteMode(False)
        self.songs_table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.songs_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.songs_table.setShowGrid(False)
        self.songs_table.setRowCount(0)
        self.songs_table.horizontalHeader().setVisible(True)
        self.songs_table.horizontalHeader().setCascadingSectionResizes(False)
        self.songs_table.horizontalHeader().setDefaultSectionSize(100)
        self.songs_table.horizontalHeader().setHighlightSections(True)
        self.songs_table.horizontalHeader().setProperty("showSortIndicator", False)
        self.songs_table.horizontalHeader().setStretchLastSection(False)
        self.songs_table.verticalHeader().setVisible(True)

        self.verticalLayout.addWidget(self.songs_table)

        self.status_label = QLabel(local_match)
        self.status_label.setObjectName("status_label")
        sizePolicy6 = QSizePolicy(QSizePolicy.Policy.Ignored, QSizePolicy.Policy.Preferred)
        sizePolicy6.setHorizontalStretch(0)
        sizePolicy6.setVerticalStretch(0)
        sizePolicy6.setHeightForWidth(self.status_label.sizePolicy().hasHeightForWidth())
        self.status_label.setSizePolicy(sizePolicy6)

        self.verticalLayout.addWidget(self.status_label)

        self.progressBar = QProgressBar(local_match)
        self.progressBar.setObjectName("progressBar")
        self.progressBar.setOrientation(Qt.Orientation.Horizontal)
        self.progressBar.setInvertedAppearance(False)
        self.progressBar.setFormat("%v/%m %p%")

        self.verticalLayout.addWidget(self.progressBar)

        self.retranslateUi(local_match)

        QMetaObject.connectSlotsByName(local_match)

    # setupUi

    def retranslateUi(self, local_match):
        local_match.setWindowTitle("")
        self.original_checkBox.setText(QCoreApplication.translate("local_match", "\u539f\u6587", None))
        self.select_dirs_button.setText(QCoreApplication.translate("local_match", "\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.save_path_button.setText(QCoreApplication.translate("local_match", "\u9009\u62e9\u4fdd\u5b58\u8def\u5f84", None))
        self.romanized_checkBox.setText(QCoreApplication.translate("local_match", "\u7f57\u9a6c\u97f3", None))
        self.label_8.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u6587\u4ef6\u540d:", None))
        self.lyricsformat_comboBox.setItemText(0, QCoreApplication.translate("local_match", "LRC(\u9010\u5b57)", None))
        self.lyricsformat_comboBox.setItemText(1, QCoreApplication.translate("local_match", "LRC(\u9010\u884c)", None))
        self.lyricsformat_comboBox.setItemText(2, QCoreApplication.translate("local_match", "\u589e\u5f3a\u578bLRC(ESLyric)", None))
        self.lyricsformat_comboBox.setItemText(3, QCoreApplication.translate("local_match", "SRT", None))
        self.lyricsformat_comboBox.setItemText(4, QCoreApplication.translate("local_match", "ASS", None))

        self.label.setText(QCoreApplication.translate("local_match", "\u4fdd\u5b58\u5230\u6b4c\u8bcd\u6807\u7b7e:", None))
        self.label_11.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u6587\u4ef6\u4fdd\u5b58\u6a21\u5f0f:", None))
        self.label_2.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u6765\u6e90:", None))
        self.save_mode_comboBox.setItemText(
            0, QCoreApplication.translate("local_match", "\u4fdd\u5b58\u5230\u6b4c\u66f2\u6587\u4ef6\u5939\u7684\u955c\u50cf\u6587\u4ef6\u5939", None)
        )
        self.save_mode_comboBox.setItemText(1, QCoreApplication.translate("local_match", "\u4fdd\u5b58\u5230\u6b4c\u66f2\u6587\u4ef6\u5939", None))
        self.save_mode_comboBox.setItemText(2, QCoreApplication.translate("local_match", "\u4fdd\u5b58\u5230\u6307\u5b9a\u6587\u4ef6\u5939", None))

        self.start_cancel_pushButton.setText(QCoreApplication.translate("local_match", "\u5f00\u59cb\u5339\u914d", None))
        self.label_3.setText(QCoreApplication.translate("local_match", "\u6700\u4f4e\u5339\u914d\u5ea6(0~100):", None))
        self.select_files_button.setText(QCoreApplication.translate("local_match", "\u9009\u62e9\u6587\u4ef6", None))
        self.label_9.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u7c7b\u578b:", None))
        self.label_10.setText(QCoreApplication.translate("local_match", "\u6b4c\u8bcd\u683c\u5f0f:", None))
        self.filename_mode_comboBox.setItemText(
            0, QCoreApplication.translate("local_match", "\u4f9d\u7167\u683c\u5f0f(\u6839\u636e\u6b4c\u8bcd\u4e2d\u7684\u4fe1\u606f)", None)
        )
        self.filename_mode_comboBox.setItemText(
            1, QCoreApplication.translate("local_match", "\u4f9d\u7167\u683c\u5f0f(\u6839\u636e\u6b4c\u66f2\u4e2d\u7684\u4fe1\u606f)", None)
        )
        self.filename_mode_comboBox.setItemText(2, QCoreApplication.translate("local_match", "\u4e0e\u6b4c\u66f2\u6587\u4ef6\u540d\u76f8\u540c", None))

        self.save2tag_mode_comboBox.setItemText(0, QCoreApplication.translate("local_match", "\u53ea\u4fdd\u5b58\u5230\u6587\u4ef6", None))
        self.save2tag_mode_comboBox.setItemText(
            1, QCoreApplication.translate("local_match", "\u53ea\u4fdd\u5b58\u5230\u6b4c\u8bcd\u6807\u7b7e(\u975ecue)", None)
        )
        self.save2tag_mode_comboBox.setItemText(
            2, QCoreApplication.translate("local_match", "\u4fdd\u5b58\u5230\u6b4c\u8bcd\u6807\u7b7e(\u975ecue)\u4e0e\u6587\u4ef6", None)
        )

        self.translate_checkBox.setText(QCoreApplication.translate("local_match", "\u8bd1\u6587", None))
        self.skip_existing_lyrics_checkbox.setText(QCoreApplication.translate("local_match", "\u8df3\u8fc7\u5df2\u7ecf\u6709\u6b4c\u8bcd", None))
        ___qtablewidgetitem = self.songs_table.horizontalHeaderItem(0)
        ___qtablewidgetitem.setText(QCoreApplication.translate("local_match", "\u6b4c\u66f2\u540d", None))
        ___qtablewidgetitem1 = self.songs_table.horizontalHeaderItem(1)
        ___qtablewidgetitem1.setText(QCoreApplication.translate("local_match", "\u827a\u672f\u5bb6", None))
        ___qtablewidgetitem2 = self.songs_table.horizontalHeaderItem(2)
        ___qtablewidgetitem2.setText(QCoreApplication.translate("local_match", "\u4e13\u8f91", None))
        ___qtablewidgetitem3 = self.songs_table.horizontalHeaderItem(3)
        ___qtablewidgetitem3.setText(QCoreApplication.translate("local_match", "\u6b4c\u66f2\u8def\u5f84", None))
        ___qtablewidgetitem4 = self.songs_table.horizontalHeaderItem(4)
        ___qtablewidgetitem4.setText(QCoreApplication.translate("local_match", "\u65f6\u957f", None))
        ___qtablewidgetitem5 = self.songs_table.horizontalHeaderItem(5)
        ___qtablewidgetitem5.setText(QCoreApplication.translate("local_match", "\u4fdd\u5b58\u8def\u5f84", None))
        ___qtablewidgetitem6 = self.songs_table.horizontalHeaderItem(6)
        ___qtablewidgetitem6.setText(QCoreApplication.translate("local_match", "\u72b6\u6001", None))

    # retranslateUi
