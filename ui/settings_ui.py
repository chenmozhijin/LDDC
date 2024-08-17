################################################################################
## Form generated from reading UI file 'settings.ui'
##
## Created by: Qt User Interface Compiler version 6.7.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, QRect, QSize, Qt
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
    QScrollArea,
    QSizePolicy,
    QSpacerItem,
    QSpinBox,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from ui.custom_widgets import CheckBoxListWidget, ColorsListWidget, LyricOrderListWidget


class Ui_settings:
    def setupUi(self, settings):
        if not settings.objectName():
            settings.setObjectName("settings")
        settings.resize(1173, 870)
        self.verticalLayout = QVBoxLayout(settings)
        self.verticalLayout.setObjectName("verticalLayout")
        self.verticalLayout.setContentsMargins(0, 0, 0, 0)
        self.scrollArea = QScrollArea(settings)
        self.scrollArea.setObjectName("scrollArea")
        self.scrollArea.setFrameShape(QFrame.Shape.NoFrame)
        self.scrollArea.setFrameShadow(QFrame.Shadow.Plain)
        self.scrollArea.setLineWidth(0)
        self.scrollArea.setWidgetResizable(True)
        self.scrollAreaWidgetContents = QWidget()
        self.scrollAreaWidgetContents.setObjectName("scrollAreaWidgetContents")
        self.scrollAreaWidgetContents.setGeometry(QRect(0, 0, 1161, 980))
        self.verticalLayout_2 = QVBoxLayout(self.scrollAreaWidgetContents)
        self.verticalLayout_2.setObjectName("verticalLayout_2")
        self.label = QLabel(self.scrollAreaWidgetContents)
        self.label.setObjectName("label")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.label.sizePolicy().hasHeightForWidth())
        self.label.setSizePolicy(sizePolicy)
        font = QFont()
        font.setPointSize(18)
        self.label.setFont(font)

        self.verticalLayout_2.addWidget(self.label)

        self.groupBox = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox.setObjectName("groupBox")
        self.gridLayout = QGridLayout(self.groupBox)
        self.gridLayout.setObjectName("gridLayout")
        self.textBrowser = QTextBrowser(self.groupBox)
        self.textBrowser.setObjectName("textBrowser")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Minimum)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.textBrowser.sizePolicy().hasHeightForWidth())
        self.textBrowser.setSizePolicy(sizePolicy1)
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
        sizePolicy.setHeightForWidth(self.label_3.sizePolicy().hasHeightForWidth())
        self.label_3.setSizePolicy(sizePolicy)

        self.gridLayout.addWidget(self.label_3, 1, 1, 1, 1)

        self.lyrics_file_name_fmt_lineEdit = QLineEdit(self.groupBox)
        self.lyrics_file_name_fmt_lineEdit.setObjectName("lyrics_file_name_fmt_lineEdit")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.MinimumExpanding, QSizePolicy.Policy.Fixed)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.lyrics_file_name_fmt_lineEdit.sizePolicy().hasHeightForWidth())
        self.lyrics_file_name_fmt_lineEdit.setSizePolicy(sizePolicy2)

        self.gridLayout.addWidget(self.lyrics_file_name_fmt_lineEdit, 0, 2, 1, 1)

        self.label_2 = QLabel(self.groupBox)
        self.label_2.setObjectName("label_2")
        sizePolicy.setHeightForWidth(self.label_2.sizePolicy().hasHeightForWidth())
        self.label_2.setSizePolicy(sizePolicy)
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

        self.verticalLayout_2.addWidget(self.groupBox)

        self.groupBox_2 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_2.setObjectName("groupBox_2")
        self.horizontalLayout = QHBoxLayout(self.groupBox_2)
        self.horizontalLayout.setObjectName("horizontalLayout")
        self.verticalLayout_4 = QVBoxLayout()
        self.verticalLayout_4.setObjectName("verticalLayout_4")
        self.verticalLayout_4.setSizeConstraint(QLayout.SizeConstraint.SetDefaultConstraint)
        self.label_4 = QLabel(self.groupBox_2)
        self.label_4.setObjectName("label_4")
        sizePolicy.setHeightForWidth(self.label_4.sizePolicy().hasHeightForWidth())
        self.label_4.setSizePolicy(sizePolicy)

        self.verticalLayout_4.addWidget(self.label_4)

        self.langs_order_listWidget = LyricOrderListWidget(self.groupBox_2)
        QListWidgetItem(self.langs_order_listWidget)
        QListWidgetItem(self.langs_order_listWidget)
        QListWidgetItem(self.langs_order_listWidget)
        self.langs_order_listWidget.setObjectName("langs_order_listWidget")
        sizePolicy.setHeightForWidth(self.langs_order_listWidget.sizePolicy().hasHeightForWidth())
        self.langs_order_listWidget.setSizePolicy(sizePolicy)
        self.langs_order_listWidget.setMinimumSize(QSize(0, 0))
        self.langs_order_listWidget.setMaximumSize(QSize(118, 96))
        self.langs_order_listWidget.setFrameShape(QFrame.Shape.Box)
        self.langs_order_listWidget.setFrameShadow(QFrame.Shadow.Sunken)
        self.langs_order_listWidget.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.langs_order_listWidget.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.langs_order_listWidget.setAutoScroll(True)
        self.langs_order_listWidget.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.langs_order_listWidget.setDragEnabled(True)
        self.langs_order_listWidget.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)
        self.langs_order_listWidget.setDefaultDropAction(Qt.DropAction.MoveAction)
        self.langs_order_listWidget.setSelectionMode(QAbstractItemView.SelectionMode.SingleSelection)
        self.langs_order_listWidget.setMovement(QListView.Movement.Free)
        self.langs_order_listWidget.setSortingEnabled(False)

        self.verticalLayout_4.addWidget(self.langs_order_listWidget)

        self.verticalSpacer = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Preferred)

        self.verticalLayout_4.addItem(self.verticalSpacer)

        self.horizontalLayout.addLayout(self.verticalLayout_4)

        self.gridLayout_4 = QGridLayout()
        self.gridLayout_4.setObjectName("gridLayout_4")
        self.auto_select_checkBox = QCheckBox(self.groupBox_2)
        self.auto_select_checkBox.setObjectName("auto_select_checkBox")

        self.gridLayout_4.addWidget(self.auto_select_checkBox, 1, 0, 1, 1)

        self.gridLayout_8 = QGridLayout()
        self.gridLayout_8.setObjectName("gridLayout_8")
        self.lrc_ms_digit_count_spinBox = QSpinBox(self.groupBox_2)
        self.lrc_ms_digit_count_spinBox.setObjectName("lrc_ms_digit_count_spinBox")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Fixed)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.lrc_ms_digit_count_spinBox.sizePolicy().hasHeightForWidth())
        self.lrc_ms_digit_count_spinBox.setSizePolicy(sizePolicy3)
        self.lrc_ms_digit_count_spinBox.setMinimumSize(QSize(70, 0))
        self.lrc_ms_digit_count_spinBox.setMinimum(2)
        self.lrc_ms_digit_count_spinBox.setMaximum(3)
        self.lrc_ms_digit_count_spinBox.setValue(3)

        self.gridLayout_8.addWidget(self.lrc_ms_digit_count_spinBox, 0, 2, 1, 1)

        self.label_6 = QLabel(self.groupBox_2)
        self.label_6.setObjectName("label_6")
        sizePolicy.setHeightForWidth(self.label_6.sizePolicy().hasHeightForWidth())
        self.label_6.setSizePolicy(sizePolicy)

        self.gridLayout_8.addWidget(self.label_6, 0, 1, 1, 1)

        self.label_8 = QLabel(self.groupBox_2)
        self.label_8.setObjectName("label_8")

        self.gridLayout_8.addWidget(self.label_8, 1, 1, 1, 1)

        self.last_ref_line_time_sty_comboBox = QComboBox(self.groupBox_2)
        self.last_ref_line_time_sty_comboBox.addItem("")
        self.last_ref_line_time_sty_comboBox.addItem("")
        self.last_ref_line_time_sty_comboBox.setObjectName("last_ref_line_time_sty_comboBox")

        self.gridLayout_8.addWidget(self.last_ref_line_time_sty_comboBox, 1, 2, 1, 1)

        self.gridLayout_4.addLayout(self.gridLayout_8, 3, 0, 1, 1)

        self.skip_inst_lyrics_checkBox = QCheckBox(self.groupBox_2)
        self.skip_inst_lyrics_checkBox.setObjectName("skip_inst_lyrics_checkBox")

        self.gridLayout_4.addWidget(self.skip_inst_lyrics_checkBox, 0, 0, 1, 1)

        self.add_end_timestamp_line_checkBox = QCheckBox(self.groupBox_2)
        self.add_end_timestamp_line_checkBox.setObjectName("add_end_timestamp_line_checkBox")

        self.gridLayout_4.addWidget(self.add_end_timestamp_line_checkBox, 2, 0, 1, 1)

        self.horizontalLayout.addLayout(self.gridLayout_4)

        self.verticalLayout_2.addWidget(self.groupBox_2)

        self.groupBox_3 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_3.setObjectName("groupBox_3")
        self.verticalLayout_3 = QVBoxLayout(self.groupBox_3)
        self.verticalLayout_3.setObjectName("verticalLayout_3")
        self.horizontalLayout_2 = QHBoxLayout()
        self.horizontalLayout_2.setObjectName("horizontalLayout_2")
        self.gridLayout_3 = QGridLayout()
        self.gridLayout_3.setObjectName("gridLayout_3")
        self.played_del_color_button = QPushButton(self.groupBox_3)
        self.played_del_color_button.setObjectName("played_del_color_button")
        sizePolicy.setHeightForWidth(self.played_del_color_button.sizePolicy().hasHeightForWidth())
        self.played_del_color_button.setSizePolicy(sizePolicy)

        self.gridLayout_3.addWidget(self.played_del_color_button, 2, 0, 1, 1)

        self.label_11 = QLabel(self.groupBox_3)
        self.label_11.setObjectName("label_11")
        sizePolicy.setHeightForWidth(self.label_11.sizePolicy().hasHeightForWidth())
        self.label_11.setSizePolicy(sizePolicy)

        self.gridLayout_3.addWidget(self.label_11, 0, 0, 1, 1, Qt.AlignmentFlag.AlignLeft)

        self.played_add_color_button = QPushButton(self.groupBox_3)
        self.played_add_color_button.setObjectName("played_add_color_button")
        sizePolicy.setHeightForWidth(self.played_add_color_button.sizePolicy().hasHeightForWidth())
        self.played_add_color_button.setSizePolicy(sizePolicy)

        self.gridLayout_3.addWidget(self.played_add_color_button, 1, 0, 1, 1)

        self.horizontalLayout_2.addLayout(self.gridLayout_3)

        self.played_color_list = ColorsListWidget(self.groupBox_3)
        self.played_color_list.setObjectName("played_color_list")
        sizePolicy.setHeightForWidth(self.played_color_list.sizePolicy().hasHeightForWidth())
        self.played_color_list.setSizePolicy(sizePolicy)
        self.played_color_list.setMaximumSize(QSize(120, 16777215))

        self.horizontalLayout_2.addWidget(self.played_color_list)

        self.gridLayout_7 = QGridLayout()
        self.gridLayout_7.setObjectName("gridLayout_7")
        self.unplayed_del_color_button = QPushButton(self.groupBox_3)
        self.unplayed_del_color_button.setObjectName("unplayed_del_color_button")
        sizePolicy.setHeightForWidth(self.unplayed_del_color_button.sizePolicy().hasHeightForWidth())
        self.unplayed_del_color_button.setSizePolicy(sizePolicy)

        self.gridLayout_7.addWidget(self.unplayed_del_color_button, 2, 0, 1, 1)

        self.label_12 = QLabel(self.groupBox_3)
        self.label_12.setObjectName("label_12")
        sizePolicy.setHeightForWidth(self.label_12.sizePolicy().hasHeightForWidth())
        self.label_12.setSizePolicy(sizePolicy)

        self.gridLayout_7.addWidget(self.label_12, 0, 0, 1, 1)

        self.unplayed_add_color_button = QPushButton(self.groupBox_3)
        self.unplayed_add_color_button.setObjectName("unplayed_add_color_button")
        sizePolicy.setHeightForWidth(self.unplayed_add_color_button.sizePolicy().hasHeightForWidth())
        self.unplayed_add_color_button.setSizePolicy(sizePolicy)

        self.gridLayout_7.addWidget(self.unplayed_add_color_button, 1, 0, 1, 1)

        self.horizontalLayout_2.addLayout(self.gridLayout_7)

        self.unplayed_color_list = ColorsListWidget(self.groupBox_3)
        self.unplayed_color_list.setObjectName("unplayed_color_list")
        sizePolicy.setHeightForWidth(self.unplayed_color_list.sizePolicy().hasHeightForWidth())
        self.unplayed_color_list.setSizePolicy(sizePolicy)
        self.unplayed_color_list.setMaximumSize(QSize(120, 16777215))

        self.horizontalLayout_2.addWidget(self.unplayed_color_list)

        self.gridLayout_9 = QGridLayout()
        self.gridLayout_9.setObjectName("gridLayout_9")
        self.label_16 = QLabel(self.groupBox_3)
        self.label_16.setObjectName("label_16")
        sizePolicy4 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy4.setHorizontalStretch(0)
        sizePolicy4.setVerticalStretch(0)
        sizePolicy4.setHeightForWidth(self.label_16.sizePolicy().hasHeightForWidth())
        self.label_16.setSizePolicy(sizePolicy4)

        self.gridLayout_9.addWidget(self.label_16, 0, 1, 1, 1)

        self.lang_type_list = CheckBoxListWidget(self.groupBox_3)
        self.lang_type_list.setObjectName("lang_type_list")
        sizePolicy.setHeightForWidth(self.lang_type_list.sizePolicy().hasHeightForWidth())
        self.lang_type_list.setSizePolicy(sizePolicy)
        self.lang_type_list.setMaximumSize(QSize(100, 16777215))
        self.lang_type_list.setDragEnabled(True)
        self.lang_type_list.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)

        self.gridLayout_9.addWidget(self.lang_type_list, 1, 0, 1, 1)

        self.label_13 = QLabel(self.groupBox_3)
        self.label_13.setObjectName("label_13")
        sizePolicy4.setHeightForWidth(self.label_13.sizePolicy().hasHeightForWidth())
        self.label_13.setSizePolicy(sizePolicy4)

        self.gridLayout_9.addWidget(self.label_13, 0, 0, 1, 1)

        self.source_list = CheckBoxListWidget(self.groupBox_3)
        self.source_list.setObjectName("source_list")
        sizePolicy.setHeightForWidth(self.source_list.sizePolicy().hasHeightForWidth())
        self.source_list.setSizePolicy(sizePolicy)
        self.source_list.setMaximumSize(QSize(100, 16777215))
        self.source_list.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)

        self.gridLayout_9.addWidget(self.source_list, 1, 1, 1, 1)

        self.horizontalLayout_2.addLayout(self.gridLayout_9)

        self.gridLayout_10 = QGridLayout()
        self.gridLayout_10.setObjectName("gridLayout_10")
        self.font_comboBox = QComboBox(self.groupBox_3)
        self.font_comboBox.setObjectName("font_comboBox")

        self.gridLayout_10.addWidget(self.font_comboBox, 0, 1, 1, 1)

        self.auto_frame_rate_checkBox = QCheckBox(self.groupBox_3)
        self.auto_frame_rate_checkBox.setObjectName("auto_frame_rate_checkBox")

        self.gridLayout_10.addWidget(self.auto_frame_rate_checkBox, 2, 0, 1, 2)

        self.label_15 = QLabel(self.groupBox_3)
        self.label_15.setObjectName("label_15")

        self.gridLayout_10.addWidget(self.label_15, 3, 0, 1, 1)

        self.label_18 = QLabel(self.groupBox_3)
        self.label_18.setObjectName("label_18")
        sizePolicy5 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Fixed)
        sizePolicy5.setHorizontalStretch(0)
        sizePolicy5.setVerticalStretch(0)
        sizePolicy5.setHeightForWidth(self.label_18.sizePolicy().hasHeightForWidth())
        self.label_18.setSizePolicy(sizePolicy5)
        self.label_18.setWordWrap(True)

        self.gridLayout_10.addWidget(self.label_18, 1, 0, 1, 2)

        self.frame_rate_spinBox = QSpinBox(self.groupBox_3)
        self.frame_rate_spinBox.setObjectName("frame_rate_spinBox")
        self.frame_rate_spinBox.setMaximum(1000)
        self.frame_rate_spinBox.setValue(60)

        self.gridLayout_10.addWidget(self.frame_rate_spinBox, 3, 1, 1, 1)

        self.label_10 = QLabel(self.groupBox_3)
        self.label_10.setObjectName("label_10")
        sizePolicy4.setHeightForWidth(self.label_10.sizePolicy().hasHeightForWidth())
        self.label_10.setSizePolicy(sizePolicy4)

        self.gridLayout_10.addWidget(self.label_10, 0, 0, 1, 1)

        self.show_local_song_lyrics_db_manager_button = QPushButton(self.groupBox_3)
        self.show_local_song_lyrics_db_manager_button.setObjectName("show_local_song_lyrics_db_manager_button")

        self.gridLayout_10.addWidget(self.show_local_song_lyrics_db_manager_button, 4, 0, 1, 2)

        self.horizontalLayout_2.addLayout(self.gridLayout_10)

        self.verticalLayout_3.addLayout(self.horizontalLayout_2)

        self.verticalLayout_2.addWidget(self.groupBox_3)

        self.groupBox_6 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_6.setObjectName("groupBox_6")
        self.gridLayout_2 = QGridLayout(self.groupBox_6)
        self.gridLayout_2.setObjectName("gridLayout_2")
        self.log_level_comboBox = QComboBox(self.groupBox_6)
        self.log_level_comboBox.addItem("CRITICAL")
        self.log_level_comboBox.addItem("ERROR")
        self.log_level_comboBox.addItem("WARNING")
        self.log_level_comboBox.addItem("INFO")
        self.log_level_comboBox.addItem("DEBUG")
        self.log_level_comboBox.addItem("NOTSET")
        self.log_level_comboBox.setObjectName("log_level_comboBox")

        self.gridLayout_2.addWidget(self.log_level_comboBox, 1, 2, 1, 1)

        self.label_7 = QLabel(self.groupBox_6)
        self.label_7.setObjectName("label_7")
        sizePolicy4.setHeightForWidth(self.label_7.sizePolicy().hasHeightForWidth())
        self.label_7.setSizePolicy(sizePolicy4)

        self.gridLayout_2.addWidget(self.label_7, 0, 0, 1, 1)

        self.restore2default_pushButton = QPushButton(self.groupBox_6)
        self.restore2default_pushButton.setObjectName("restore2default_pushButton")

        self.gridLayout_2.addWidget(self.restore2default_pushButton, 2, 2, 1, 1)

        self.open_log_dir_button = QPushButton(self.groupBox_6)
        self.open_log_dir_button.setObjectName("open_log_dir_button")

        self.gridLayout_2.addWidget(self.open_log_dir_button, 3, 2, 1, 1)

        self.language_comboBox = QComboBox(self.groupBox_6)
        self.language_comboBox.addItem("")
        self.language_comboBox.addItem("")
        self.language_comboBox.addItem("")
        self.language_comboBox.setObjectName("language_comboBox")

        self.gridLayout_2.addWidget(self.language_comboBox, 0, 2, 1, 1)

        self.label_5 = QLabel(self.groupBox_6)
        self.label_5.setObjectName("label_5")
        sizePolicy.setHeightForWidth(self.label_5.sizePolicy().hasHeightForWidth())
        self.label_5.setSizePolicy(sizePolicy)

        self.gridLayout_2.addWidget(self.label_5, 1, 0, 1, 1)

        self.auto_check_update_checkBox = QCheckBox(self.groupBox_6)
        self.auto_check_update_checkBox.setObjectName("auto_check_update_checkBox")

        self.gridLayout_2.addWidget(self.auto_check_update_checkBox, 4, 2, 1, 1)

        self.verticalLayout_2.addWidget(self.groupBox_6)

        self.groupBox_5 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_5.setObjectName("groupBox_5")
        self.gridLayout_5 = QGridLayout(self.groupBox_5)
        self.gridLayout_5.setObjectName("gridLayout_5")
        self.clear_cache_pushButton = QPushButton(self.groupBox_5)
        self.clear_cache_pushButton.setObjectName("clear_cache_pushButton")

        self.gridLayout_5.addWidget(self.clear_cache_pushButton, 0, 1, 1, 1)

        self.cache_size_label = QLabel(self.groupBox_5)
        self.cache_size_label.setObjectName("cache_size_label")

        self.gridLayout_5.addWidget(self.cache_size_label, 0, 0, 1, 1)

        self.verticalLayout_2.addWidget(self.groupBox_5)

        self.verticalSpacer_2 = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Expanding)

        self.verticalLayout_2.addItem(self.verticalSpacer_2)

        self.scrollArea.setWidget(self.scrollAreaWidgetContents)

        self.verticalLayout.addWidget(self.scrollArea)

        self.retranslateUi(settings)

        self.log_level_comboBox.setCurrentIndex(0)

        QMetaObject.connectSlotsByName(settings)

    # setupUi

    def retranslateUi(self, settings):
        self.label.setText(QCoreApplication.translate("settings", "\u8bbe\u7f6e", None))
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
        self.groupBox_2.setTitle(QCoreApplication.translate("settings", "\u6b4c\u8bcd\u8bbe\u7f6e", None))
        self.label_4.setText(QCoreApplication.translate("settings", "\u987a\u5e8f", None))

        __sortingEnabled = self.langs_order_listWidget.isSortingEnabled()
        self.langs_order_listWidget.setSortingEnabled(False)
        ___qlistwidgetitem = self.langs_order_listWidget.item(0)
        ___qlistwidgetitem.setText(QCoreApplication.translate("settings", "\u7f57\u9a6c\u97f3", None))
        ___qlistwidgetitem1 = self.langs_order_listWidget.item(1)
        ___qlistwidgetitem1.setText(QCoreApplication.translate("settings", "\u539f\u6587", None))
        ___qlistwidgetitem2 = self.langs_order_listWidget.item(2)
        ___qlistwidgetitem2.setText(QCoreApplication.translate("settings", "\u8bd1\u6587", None))
        self.langs_order_listWidget.setSortingEnabled(__sortingEnabled)

        self.auto_select_checkBox.setText(
            QCoreApplication.translate("settings", "\u6b4c\u66f2\u641c\u7d22\u6b4c\u8bcd\u65f6\u81ea\u52a8\u9009\u62e9(\u9177\u72d7\u97f3\u4e50)", None)
        )
        self.lrc_ms_digit_count_spinBox.setSpecialValueText("")
        self.lrc_ms_digit_count_spinBox.setPrefix("")
        self.label_6.setText(QCoreApplication.translate("settings", "LRC\u6b4c\u8bcd\u6beb\u79d2\u4f4d\u6570", None))
        self.label_8.setText(QCoreApplication.translate("settings", "\u672b\u5c3e\u53c2\u7167\u884c\u65f6\u95f4\u6837\u5f0f(\u4ec5LRC):", None))
        self.last_ref_line_time_sty_comboBox.setItemText(
            0, QCoreApplication.translate("settings", "\u4e0e\u5f53\u524d\u539f\u6587\u8d77\u59cb\u65f6\u95f4\u76f8\u540c", None)
        )
        self.last_ref_line_time_sty_comboBox.setItemText(
            1, QCoreApplication.translate("settings", "\u4e0e\u4e0b\u4e00\u884c\u539f\u6587\u8d77\u59cb\u65f6\u95f4\u63a5\u8fd1", None)
        )

        self.skip_inst_lyrics_checkBox.setText(
            QCoreApplication.translate(
                "settings", "\u4fdd\u5b58\u4e13\u8f91/\u6b4c\u5355\u6b4c\u8bcd/\u672c\u5730\u5339\u914d\u65f6\u8df3\u8fc7\u7eaf\u97f3\u4e50", None
            )
        )
        self.add_end_timestamp_line_checkBox.setText(
            QCoreApplication.translate("settings", "\u4e3a\u9010\u884clrc\u6b4c\u8bcd\u6dfb\u52a0\u7ed3\u675f\u65f6\u95f4\u6233\u884c", None)
        )
        self.groupBox_3.setTitle(QCoreApplication.translate("settings", "\u684c\u9762\u6b4c\u8bcd\u8bbe\u7f6e", None))
        self.played_del_color_button.setText(QCoreApplication.translate("settings", "\u5220\u9664\u989c\u8272", None))
        self.label_11.setText(QCoreApplication.translate("settings", "\u5df2\u64ad\u653e\u989c\u8272:", None))
        self.played_add_color_button.setText(QCoreApplication.translate("settings", "\u6dfb\u52a0\u989c\u8272", None))
        self.unplayed_del_color_button.setText(QCoreApplication.translate("settings", "\u5220\u9664\u989c\u8272", None))
        self.label_12.setText(QCoreApplication.translate("settings", "\u672a\u64ad\u653e\u989c\u8272:", None))
        self.unplayed_add_color_button.setText(QCoreApplication.translate("settings", "\u6dfb\u52a0\u989c\u8272", None))
        self.label_16.setText(QCoreApplication.translate("settings", "\u81ea\u52a8\u641c\u7d22\u6b4c\u8bcd\u6e90\uff1a", None))
        self.label_13.setText(QCoreApplication.translate("settings", "\u9ed8\u8ba4\u8bed\u8a00\u7c7b\u578b\uff1a", None))
        self.auto_frame_rate_checkBox.setText(QCoreApplication.translate("settings", "\u81ea\u9002\u5e94\u5e27\u7387", None))
        self.label_15.setText(QCoreApplication.translate("settings", "\u5e27\u7387:", None))
        self.label_18.setText(
            QCoreApplication.translate("settings", "\u63d0\u793a\uff1a\u5b57\u4f53\u5927\u5c0f\u901a\u8fc7\u62c9\u4f38\u7a97\u53e3\u8c03\u8282", None)
        )
        self.label_10.setText(QCoreApplication.translate("settings", "\u5b57\u4f53:", None))
        self.show_local_song_lyrics_db_manager_button.setText(QCoreApplication.translate("settings", "\u6b4c\u8bcd\u5173\u8054\u7ba1\u7406", None))
        self.groupBox_6.setTitle(QCoreApplication.translate("settings", "\u5176\u4ed6", None))

        self.label_7.setText(QCoreApplication.translate("settings", "\u8bed\u8a00\uff1a", None))
        self.restore2default_pushButton.setText(QCoreApplication.translate("settings", "\u6062\u590d\u9ed8\u8ba4\u8bbe\u7f6e", None))
        self.open_log_dir_button.setText(QCoreApplication.translate("settings", "\u6253\u5f00\u65e5\u5fd7\u6587\u4ef6\u5939", None))
        self.language_comboBox.setItemText(0, QCoreApplication.translate("settings", "\u81ea\u52a8", None))
        self.language_comboBox.setItemText(1, QCoreApplication.translate("settings", "\u82f1\u6587", None))
        self.language_comboBox.setItemText(2, QCoreApplication.translate("settings", "\u4e2d\u6587", None))

        self.label_5.setText(QCoreApplication.translate("settings", "\u65e5\u5fd7\u7b49\u7ea7:", None))
        self.auto_check_update_checkBox.setText(QCoreApplication.translate("settings", "\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0", None))
        self.groupBox_5.setTitle(QCoreApplication.translate("settings", "\u7f13\u5b58\u8bbe\u7f6e", None))
        self.clear_cache_pushButton.setText(QCoreApplication.translate("settings", "\u6e05\u9664\u7f13\u5b58", None))
        self.cache_size_label.setText(QCoreApplication.translate("settings", "\u7f13\u5b58\u5927\u5c0f\uff1a", None))

    # retranslateUi
