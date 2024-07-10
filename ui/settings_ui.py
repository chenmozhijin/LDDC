################################################################################
## Form generated from reading UI file 'settings.ui'
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
    QFrame,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLayout,
    QLineEdit,
    QListView,
    QListWidgetItem,
    QPushButton,
    QSizePolicy,
    QSpacerItem,
    QSpinBox,
    QTextBrowser,
    QVBoxLayout,
)

from ui.custom_widgets import LyricOrderListWidget


class Ui_settings:
    def setupUi(self, settings):
        if not settings.objectName():
            settings.setObjectName("settings")
        settings.resize(1050, 600)
        self.gridLayout_2 = QGridLayout(settings)
        self.gridLayout_2.setObjectName("gridLayout_2")
        self.groupBox = QGroupBox(settings)
        self.groupBox.setObjectName("groupBox")
        self.gridLayout = QGridLayout(self.groupBox)
        self.gridLayout.setObjectName("gridLayout")
        self.textBrowser = QTextBrowser(self.groupBox)
        self.textBrowser.setObjectName("textBrowser")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Minimum)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.textBrowser.sizePolicy().hasHeightForWidth())
        self.textBrowser.setSizePolicy(sizePolicy)
        self.textBrowser.setMinimumSize(QSize(200, 106))
        self.textBrowser.setMaximumSize(QSize(234, 78))
        self.textBrowser.setFrameShape(QFrame.Shape.Box)
        self.textBrowser.setFrameShadow(QFrame.Shadow.Sunken)
        self.textBrowser.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.textBrowser.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.textBrowser.setOpenLinks(False)

        self.gridLayout.addWidget(self.textBrowser, 0, 0, 1, 1)

        self.label_3 = QLabel(self.groupBox)
        self.label_3.setObjectName("label_3")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.label_3.sizePolicy().hasHeightForWidth())
        self.label_3.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.label_3, 1, 1, 1, 1)

        self.lyrics_file_name_format_lineEdit = QLineEdit(self.groupBox)
        self.lyrics_file_name_format_lineEdit.setObjectName("lyrics_file_name_format_lineEdit")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.MinimumExpanding, QSizePolicy.Policy.Fixed)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.lyrics_file_name_format_lineEdit.sizePolicy().hasHeightForWidth())
        self.lyrics_file_name_format_lineEdit.setSizePolicy(sizePolicy2)

        self.gridLayout.addWidget(self.lyrics_file_name_format_lineEdit, 0, 2, 1, 1)

        self.label_2 = QLabel(self.groupBox)
        self.label_2.setObjectName("label_2")
        sizePolicy1.setHeightForWidth(self.label_2.sizePolicy().hasHeightForWidth())
        self.label_2.setSizePolicy(sizePolicy1)
        self.label_2.setTextFormat(Qt.TextFormat.AutoText)

        self.gridLayout.addWidget(self.label_2, 0, 1, 1, 1)

        self.horizontalLayout_5 = QHBoxLayout()
        self.horizontalLayout_5.setObjectName("horizontalLayout_5")
        self.default_save_path_lineEdit = QLineEdit(self.groupBox)
        self.default_save_path_lineEdit.setObjectName("default_save_path_lineEdit")

        self.horizontalLayout_5.addWidget(self.default_save_path_lineEdit)

        self.select_default_save_path_pushButton = QPushButton(self.groupBox)
        self.select_default_save_path_pushButton.setObjectName("select_default_save_path_pushButton")

        self.horizontalLayout_5.addWidget(self.select_default_save_path_pushButton)

        self.gridLayout.addLayout(self.horizontalLayout_5, 1, 2, 1, 1)

        self.gridLayout_2.addWidget(self.groupBox, 1, 0, 1, 1)

        self.groupBox_4 = QGroupBox(settings)
        self.groupBox_4.setObjectName("groupBox_4")
        self.verticalLayout_7 = QVBoxLayout(self.groupBox_4)
        self.verticalLayout_7.setObjectName("verticalLayout_7")
        self.language_comboBox = QComboBox(self.groupBox_4)
        self.language_comboBox.addItem("")
        self.language_comboBox.addItem("")
        self.language_comboBox.addItem("")
        self.language_comboBox.setObjectName("language_comboBox")

        self.verticalLayout_7.addWidget(self.language_comboBox)

        self.gridLayout_2.addWidget(self.groupBox_4, 3, 0, 1, 1)

        self.groupBox_2 = QGroupBox(settings)
        self.groupBox_2.setObjectName("groupBox_2")
        self.horizontalLayout = QHBoxLayout(self.groupBox_2)
        self.horizontalLayout.setObjectName("horizontalLayout")
        self.verticalLayout_4 = QVBoxLayout()
        self.verticalLayout_4.setObjectName("verticalLayout_4")
        self.verticalLayout_4.setSizeConstraint(QLayout.SizeConstraint.SetDefaultConstraint)
        self.label_4 = QLabel(self.groupBox_2)
        self.label_4.setObjectName("label_4")
        sizePolicy1.setHeightForWidth(self.label_4.sizePolicy().hasHeightForWidth())
        self.label_4.setSizePolicy(sizePolicy1)

        self.verticalLayout_4.addWidget(self.label_4)

        self.lyrics_order_listWidget = LyricOrderListWidget(self.groupBox_2)
        QListWidgetItem(self.lyrics_order_listWidget)
        QListWidgetItem(self.lyrics_order_listWidget)
        QListWidgetItem(self.lyrics_order_listWidget)
        self.lyrics_order_listWidget.setObjectName("lyrics_order_listWidget")
        sizePolicy1.setHeightForWidth(self.lyrics_order_listWidget.sizePolicy().hasHeightForWidth())
        self.lyrics_order_listWidget.setSizePolicy(sizePolicy1)
        self.lyrics_order_listWidget.setMinimumSize(QSize(0, 0))
        self.lyrics_order_listWidget.setMaximumSize(QSize(118, 96))
        self.lyrics_order_listWidget.setFrameShape(QFrame.Shape.Box)
        self.lyrics_order_listWidget.setFrameShadow(QFrame.Shadow.Sunken)
        self.lyrics_order_listWidget.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.lyrics_order_listWidget.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.lyrics_order_listWidget.setAutoScroll(True)
        self.lyrics_order_listWidget.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.lyrics_order_listWidget.setDragEnabled(True)
        self.lyrics_order_listWidget.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)
        self.lyrics_order_listWidget.setDefaultDropAction(Qt.DropAction.MoveAction)
        self.lyrics_order_listWidget.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.lyrics_order_listWidget.setMovement(QListView.Movement.Free)
        self.lyrics_order_listWidget.setSortingEnabled(False)

        self.verticalLayout_4.addWidget(self.lyrics_order_listWidget)

        self.verticalSpacer = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Preferred)

        self.verticalLayout_4.addItem(self.verticalSpacer)

        self.horizontalLayout.addLayout(self.verticalLayout_4)

        self.gridLayout_4 = QGridLayout()
        self.gridLayout_4.setObjectName("gridLayout_4")
        self.auto_select_checkBox = QCheckBox(self.groupBox_2)
        self.auto_select_checkBox.setObjectName("auto_select_checkBox")

        self.gridLayout_4.addWidget(self.auto_select_checkBox, 1, 0, 1, 1)

        self.horizontalLayout_7 = QHBoxLayout()
        self.horizontalLayout_7.setObjectName("horizontalLayout_7")
        self.label_6 = QLabel(self.groupBox_2)
        self.label_6.setObjectName("label_6")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Fixed)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.label_6.sizePolicy().hasHeightForWidth())
        self.label_6.setSizePolicy(sizePolicy3)

        self.horizontalLayout_7.addWidget(self.label_6)

        self.lrc_ms_digit_count_spinBox = QSpinBox(self.groupBox_2)
        self.lrc_ms_digit_count_spinBox.setObjectName("lrc_ms_digit_count_spinBox")
        sizePolicy4 = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Fixed)
        sizePolicy4.setHorizontalStretch(0)
        sizePolicy4.setVerticalStretch(0)
        sizePolicy4.setHeightForWidth(self.lrc_ms_digit_count_spinBox.sizePolicy().hasHeightForWidth())
        self.lrc_ms_digit_count_spinBox.setSizePolicy(sizePolicy4)
        self.lrc_ms_digit_count_spinBox.setMinimumSize(QSize(70, 0))
        self.lrc_ms_digit_count_spinBox.setMinimum(2)
        self.lrc_ms_digit_count_spinBox.setMaximum(3)
        self.lrc_ms_digit_count_spinBox.setValue(3)

        self.horizontalLayout_7.addWidget(self.lrc_ms_digit_count_spinBox)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout_7.addItem(self.horizontalSpacer)

        self.gridLayout_4.addLayout(self.horizontalLayout_7, 3, 0, 1, 1)

        self.skip_inst_lyrics_checkBox = QCheckBox(self.groupBox_2)
        self.skip_inst_lyrics_checkBox.setObjectName("skip_inst_lyrics_checkBox")

        self.gridLayout_4.addWidget(self.skip_inst_lyrics_checkBox, 0, 0, 1, 1)

        self.add_end_timestamp_line_checkBox = QCheckBox(self.groupBox_2)
        self.add_end_timestamp_line_checkBox.setObjectName("add_end_timestamp_line_checkBox")

        self.gridLayout_4.addWidget(self.add_end_timestamp_line_checkBox, 2, 0, 1, 1)

        self.horizontalLayout.addLayout(self.gridLayout_4)

        self.gridLayout_2.addWidget(self.groupBox_2, 2, 0, 1, 1)

        self.label = QLabel(settings)
        self.label.setObjectName("label")
        sizePolicy1.setHeightForWidth(self.label.sizePolicy().hasHeightForWidth())
        self.label.setSizePolicy(sizePolicy1)
        font = QFont()
        font.setPointSize(18)
        self.label.setFont(font)

        self.gridLayout_2.addWidget(self.label, 0, 0, 1, 1)

        self.groupBox_3 = QGroupBox(settings)
        self.groupBox_3.setObjectName("groupBox_3")
        self.gridLayout_3 = QGridLayout(self.groupBox_3)
        self.gridLayout_3.setObjectName("gridLayout_3")
        self.log_level_comboBox = QComboBox(self.groupBox_3)
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.setObjectName("log_level_comboBox")

        self.gridLayout_3.addWidget(self.log_level_comboBox, 0, 1, 1, 1)

        self.label_5 = QLabel(self.groupBox_3)
        self.label_5.setObjectName("label_5")
        sizePolicy1.setHeightForWidth(self.label_5.sizePolicy().hasHeightForWidth())
        self.label_5.setSizePolicy(sizePolicy1)

        self.gridLayout_3.addWidget(self.label_5, 0, 0, 1, 1)

        self.gridLayout_2.addWidget(self.groupBox_3, 4, 0, 1, 1)

        self.groupBox_5 = QGroupBox(settings)
        self.groupBox_5.setObjectName("groupBox_5")
        self.gridLayout_5 = QGridLayout(self.groupBox_5)
        self.gridLayout_5.setObjectName("gridLayout_5")
        self.clear_cache_pushButton = QPushButton(self.groupBox_5)
        self.clear_cache_pushButton.setObjectName("clear_cache_pushButton")

        self.gridLayout_5.addWidget(self.clear_cache_pushButton, 0, 1, 1, 1)

        self.cache_size_label = QLabel(self.groupBox_5)
        self.cache_size_label.setObjectName("cache_size_label")

        self.gridLayout_5.addWidget(self.cache_size_label, 0, 0, 1, 1)

        self.gridLayout_2.addWidget(self.groupBox_5, 5, 0, 1, 1)

        self.retranslateUi(settings)

        self.log_level_comboBox.setCurrentIndex(1)

        QMetaObject.connectSlotsByName(settings)

    # setupUi

    def retranslateUi(self, settings):
        settings.setWindowTitle(QCoreApplication.translate("settings", "Form", None))
        self.groupBox.setTitle(QCoreApplication.translate("settings", "\u4fdd\u5b58\u8bbe\u7f6e", None))
        self.textBrowser.setHtml(
            QCoreApplication.translate(
                "settings",
                '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN" "http://www.w3.org/TR/REC-html40/strict.dtd">\n'
                '<html><head><meta name="qrichtext" content="1" /><meta charset="utf-8" /><style type="text/css">\n'
                "p, li { white-space: pre-wrap; }\n"
                "hr { height: 1px; border-width: 0; }\n"
                'li.unchecked::marker { content: "\\2610"; }\n'
                'li.checked::marker { content: "\\2612"; }\n'
                "</style></head><body style=\" font-family:'Microsoft YaHei UI'; font-size:9pt; font-weight:400; font-style:normal;\">\n"
                '<p style=" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;">\u4ee5\u4e0b\u5360\u4f4d\u7b26\u53ef\u7528</p>\n'
                '<p style=" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;"><span style=" font-size:8pt;">\u6b4c\u540d: %&lt;title&gt; \u827a\u672f\u5bb6: %&lt;artist&gt;</span></p>\n'
                '<p style=" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; te'
                'xt-indent:0px;"><span style=" font-size:8pt;">\u4e13\u8f91\u540d: %&lt;album&gt; \u6b4c\u66f2/\u6b4c\u8bcdid: %&lt;id&gt;</span></p>\n'
                '<p style=" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;"><span style=" font-size:8pt;">\u8bed\u8a00\u7c7b\u578b: %&lt;langs&gt;</span></p></body></html>',
                None,
            )
        )
        self.label_3.setText(QCoreApplication.translate("settings", "\u9ed8\u8ba4\u4fdd\u5b58\u8def\u5f84", None))
        # if QT_CONFIG(whatsthis)
        self.label_2.setWhatsThis("")
        # endif // QT_CONFIG(whatsthis)
        # if QT_CONFIG(accessibility)
        self.label_2.setAccessibleDescription("")
        # endif // QT_CONFIG(accessibility)
        self.label_2.setText(QCoreApplication.translate("settings", "\u6b4c\u8bcd\u6587\u4ef6\u540d\u683c\u5f0f", None))
        self.select_default_save_path_pushButton.setText(QCoreApplication.translate("settings", "\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.groupBox_4.setTitle(QCoreApplication.translate("settings", "\u8bed\u8a00\u8bbe\u7f6e", None))
        self.language_comboBox.setItemText(0, QCoreApplication.translate("settings", "\u81ea\u52a8", None))
        self.language_comboBox.setItemText(1, QCoreApplication.translate("settings", "\u82f1\u6587", None))
        self.language_comboBox.setItemText(2, QCoreApplication.translate("settings", "\u4e2d\u6587", None))

        self.groupBox_2.setTitle(QCoreApplication.translate("settings", "\u6b4c\u8bcd\u8bbe\u7f6e", None))
        self.label_4.setText(QCoreApplication.translate("settings", "\u987a\u5e8f", None))

        __sortingEnabled = self.lyrics_order_listWidget.isSortingEnabled()
        self.lyrics_order_listWidget.setSortingEnabled(False)
        ___qlistwidgetitem = self.lyrics_order_listWidget.item(0)
        ___qlistwidgetitem.setText(QCoreApplication.translate("settings", "\u7f57\u9a6c\u97f3", None))
        ___qlistwidgetitem1 = self.lyrics_order_listWidget.item(1)
        ___qlistwidgetitem1.setText(QCoreApplication.translate("settings", "\u539f\u6587", None))
        ___qlistwidgetitem2 = self.lyrics_order_listWidget.item(2)
        ___qlistwidgetitem2.setText(QCoreApplication.translate("settings", "\u8bd1\u6587", None))
        self.lyrics_order_listWidget.setSortingEnabled(__sortingEnabled)

        self.auto_select_checkBox.setText(
            QCoreApplication.translate("settings", "\u6b4c\u66f2\u641c\u7d22\u6b4c\u8bcd\u65f6\u81ea\u52a8\u9009\u62e9(\u9177\u72d7\u97f3\u4e50)", None)
        )
        self.label_6.setText(QCoreApplication.translate("settings", "LRC\u6b4c\u8bcd\u6beb\u79d2\u4f4d\u6570", None))
        self.lrc_ms_digit_count_spinBox.setSpecialValueText("")
        self.lrc_ms_digit_count_spinBox.setPrefix("")
        self.skip_inst_lyrics_checkBox.setText(
            QCoreApplication.translate(
                "settings", "\u4fdd\u5b58\u4e13\u8f91/\u6b4c\u5355\u6b4c\u8bcd/\u672c\u5730\u5339\u914d\u65f6\u8df3\u8fc7\u7eaf\u97f3\u4e50", None
            )
        )
        self.add_end_timestamp_line_checkBox.setText(
            QCoreApplication.translate("settings", "\u4e3a\u9010\u884clrc\u6b4c\u8bcd\u6dfb\u52a0\u7ed3\u675f\u65f6\u95f4\u6233\u884c", None)
        )
        self.label.setText(QCoreApplication.translate("settings", "\u8bbe\u7f6e", None))
        self.groupBox_3.setTitle(QCoreApplication.translate("settings", "\u65e5\u5fd7\u8bbe\u7f6e", None))
        self.log_level_comboBox.setItemText(0, QCoreApplication.translate("settings", "CRITICAL", None))
        self.log_level_comboBox.setItemText(1, QCoreApplication.translate("settings", "ERROR", None))
        self.log_level_comboBox.setItemText(2, QCoreApplication.translate("settings", "WARNING", None))
        self.log_level_comboBox.setItemText(3, QCoreApplication.translate("settings", "INFO", None))
        self.log_level_comboBox.setItemText(4, QCoreApplication.translate("settings", "DEBUG", None))
        self.log_level_comboBox.setItemText(5, QCoreApplication.translate("settings", "NOTSET", None))

        self.label_5.setText(QCoreApplication.translate("settings", "\u65e5\u5fd7\u7b49\u7ea7:", None))
        self.groupBox_5.setTitle(QCoreApplication.translate("settings", "\u7f13\u5b58\u8bbe\u7f6e", None))
        self.clear_cache_pushButton.setText(QCoreApplication.translate("settings", "\u6e05\u9664\u7f13\u5b58", None))
        self.cache_size_label.setText(QCoreApplication.translate("settings", "\u7f13\u5b58\u5927\u5c0f\uff1a", None))

    # retranslateUi
