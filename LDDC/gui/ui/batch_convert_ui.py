################################################################################
## Form generated from reading UI file 'batch_convert.ui'
##
## Created by: Qt User Interface Compiler version 6.9.0
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject
from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QComboBox,
    QGridLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QSizePolicy,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from LDDC.gui.components.custom_widgets import ProportionallyStretchedTableWidget


class Ui_batch_convert:
    def setupUi(self, batch_convert):
        if not batch_convert.objectName():
            batch_convert.setObjectName("batch_convert")
        batch_convert.resize(720, 442)
        self.verticalLayout = QVBoxLayout(batch_convert)
        self.verticalLayout.setObjectName("verticalLayout")
        self.control_bar = QWidget(batch_convert)
        self.control_bar.setObjectName("control_bar")
        self.gridLayout = QGridLayout(self.control_bar)
        self.gridLayout.setObjectName("gridLayout")
        self.select_files_button = QPushButton(self.control_bar)
        self.select_files_button.setObjectName("select_files_button")

        self.gridLayout.addWidget(self.select_files_button, 0, 0, 1, 1)

        self.save_path_button = QPushButton(self.control_bar)
        self.save_path_button.setObjectName("save_path_button")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Expanding)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.save_path_button.sizePolicy().hasHeightForWidth())
        self.save_path_button.setSizePolicy(sizePolicy)

        self.gridLayout.addWidget(self.save_path_button, 0, 1, 2, 1)

        self.label = QLabel(self.control_bar)
        self.label.setObjectName("label")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.label.sizePolicy().hasHeightForWidth())
        self.label.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.label, 0, 2, 1, 1)

        self.format_comboBox = QComboBox(self.control_bar)
        self.format_comboBox.addItem("")
        self.format_comboBox.addItem("")
        self.format_comboBox.addItem("")
        self.format_comboBox.addItem("")
        self.format_comboBox.addItem("")
        self.format_comboBox.setObjectName("format_comboBox")

        self.gridLayout.addWidget(self.format_comboBox, 0, 3, 1, 1)

        self.start_button = QPushButton(self.control_bar)
        self.start_button.setObjectName("start_button")
        sizePolicy.setHeightForWidth(self.start_button.sizePolicy().hasHeightForWidth())
        self.start_button.setSizePolicy(sizePolicy)

        self.gridLayout.addWidget(self.start_button, 0, 4, 2, 1)

        self.select_dirs_button = QPushButton(self.control_bar)
        self.select_dirs_button.setObjectName("select_dirs_button")

        self.gridLayout.addWidget(self.select_dirs_button, 1, 0, 1, 1)

        self.recursive_checkBox = QCheckBox(self.control_bar)
        self.recursive_checkBox.setObjectName("recursive_checkBox")
        self.recursive_checkBox.setChecked(False)

        self.gridLayout.addWidget(self.recursive_checkBox, 1, 2, 1, 2)

        self.verticalLayout.addWidget(self.control_bar)

        self.label_2 = QLabel(batch_convert)
        self.label_2.setObjectName("label_2")

        self.verticalLayout.addWidget(self.label_2)

        self.files_table = ProportionallyStretchedTableWidget(batch_convert)
        if self.files_table.columnCount() < 3:
            self.files_table.setColumnCount(3)
        __qtablewidgetitem = QTableWidgetItem()
        self.files_table.setHorizontalHeaderItem(0, __qtablewidgetitem)
        __qtablewidgetitem1 = QTableWidgetItem()
        self.files_table.setHorizontalHeaderItem(1, __qtablewidgetitem1)
        __qtablewidgetitem2 = QTableWidgetItem()
        self.files_table.setHorizontalHeaderItem(2, __qtablewidgetitem2)
        self.files_table.setObjectName("files_table")
        self.files_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.files_table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
        self.files_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)

        self.verticalLayout.addWidget(self.files_table)

        self.status_label = QLabel(batch_convert)
        self.status_label.setObjectName("status_label")

        self.verticalLayout.addWidget(self.status_label)

        self.progressBar = QProgressBar(batch_convert)
        self.progressBar.setObjectName("progressBar")
        self.progressBar.setFormat("%v/%m %p%")

        self.verticalLayout.addWidget(self.progressBar)

        self.retranslateUi(batch_convert)

        QMetaObject.connectSlotsByName(batch_convert)

    # setupUi

    def retranslateUi(self, batch_convert):
        batch_convert.setWindowTitle("")
        self.select_files_button.setText(QCoreApplication.translate("batch_convert", "\u9009\u62e9\u6587\u4ef6", None))
        self.save_path_button.setText(QCoreApplication.translate("batch_convert", "\u9009\u62e9\u4fdd\u5b58\u8def\u5f84", None))
        self.label.setText(QCoreApplication.translate("batch_convert", "\u76ee\u6807\u683c\u5f0f:", None))
        self.format_comboBox.setItemText(0, QCoreApplication.translate("batch_convert", "LRC(\u9010\u5b57)", None))
        self.format_comboBox.setItemText(1, QCoreApplication.translate("batch_convert", "LRC(\u9010\u884c)", None))
        self.format_comboBox.setItemText(2, QCoreApplication.translate("batch_convert", "\u589e\u5f3a\u578bLRC(ESLyric)", None))
        self.format_comboBox.setItemText(3, QCoreApplication.translate("batch_convert", "SRT", None))
        self.format_comboBox.setItemText(4, QCoreApplication.translate("batch_convert", "ASS", None))

        self.start_button.setText(QCoreApplication.translate("batch_convert", "\u5f00\u59cb\u8f6c\u6362", None))
        self.select_dirs_button.setText(QCoreApplication.translate("batch_convert", "\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.recursive_checkBox.setText(QCoreApplication.translate("batch_convert", "\u904d\u5386\u5b50\u6587\u4ef6\u5939", None))
        self.label_2.setText(
            QCoreApplication.translate("batch_convert", "\u6ce8\u610f:\u6279\u91cf\u8f6c\u6362\u4e0d\u4f1a\u63a8\u6d4b\u8bed\u8a00\u7c7b\u578b", None),
        )
        ___qtablewidgetitem = self.files_table.horizontalHeaderItem(0)
        ___qtablewidgetitem.setText(QCoreApplication.translate("batch_convert", "\u6587\u4ef6\u540d", None))
        ___qtablewidgetitem1 = self.files_table.horizontalHeaderItem(1)
        ___qtablewidgetitem1.setText(QCoreApplication.translate("batch_convert", "\u4fdd\u5b58\u8def\u5f84", None))
        ___qtablewidgetitem2 = self.files_table.horizontalHeaderItem(2)
        ___qtablewidgetitem2.setText(QCoreApplication.translate("batch_convert", "\u72b6\u6001", None))

    # retranslateUi
