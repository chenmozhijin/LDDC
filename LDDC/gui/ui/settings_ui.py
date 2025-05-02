################################################################################
## Form generated from reading UI file 'settings.ui'
##
## Created by: Qt User Interface Compiler version 6.9.0
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
    QLabel,
    QLineEdit,
    QListView,
    QListWidgetItem,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSpinBox,
    QStackedWidget,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from LDDC.gui.components.custom_widgets import CheckBoxListWidget, ColorsListWidget, LyricOrderListWidget


class Ui_settings:
    def setupUi(self, settings):
        if not settings.objectName():
            settings.setObjectName("settings")
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
        self.scrollAreaWidgetContents.setGeometry(QRect(0, 0, 910, 1044))
        self.gridLayout_6 = QGridLayout(self.scrollAreaWidgetContents)
        self.gridLayout_6.setObjectName("gridLayout_6")
        self.groupBox = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox.setObjectName("groupBox")
        self.gridLayout_4 = QGridLayout(self.groupBox)
        self.gridLayout_4.setObjectName("gridLayout_4")
        self.gridLayout_4.setContentsMargins(-1, -1, -1, 40)
        self.textBrowser_5 = QTextBrowser(self.groupBox)
        self.textBrowser_5.setObjectName("textBrowser_5")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Minimum)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.textBrowser_5.sizePolicy().hasHeightForWidth())
        self.textBrowser_5.setSizePolicy(sizePolicy)
        self.textBrowser_5.setMinimumSize(QSize(200, 106))
        self.textBrowser_5.setMaximumSize(QSize(234, 78))
        self.textBrowser_5.setFrameShape(QFrame.Shape.Box)
        self.textBrowser_5.setFrameShadow(QFrame.Shadow.Sunken)
        self.textBrowser_5.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.textBrowser_5.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.textBrowser_5.setOpenLinks(False)

        self.gridLayout_4.addWidget(self.textBrowser_5, 0, 0, 3, 1)

        self.label_26 = QLabel(self.groupBox)
        self.label_26.setObjectName("label_26")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.label_26.sizePolicy().hasHeightForWidth())
        self.label_26.setSizePolicy(sizePolicy1)
        self.label_26.setTextFormat(Qt.TextFormat.AutoText)

        self.gridLayout_4.addWidget(self.label_26, 0, 1, 1, 1)

        self.lyrics_file_name_fmt_lineEdit = QLineEdit(self.groupBox)
        self.lyrics_file_name_fmt_lineEdit.setObjectName("lyrics_file_name_fmt_lineEdit")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.MinimumExpanding, QSizePolicy.Policy.Fixed)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.lyrics_file_name_fmt_lineEdit.sizePolicy().hasHeightForWidth())
        self.lyrics_file_name_fmt_lineEdit.setSizePolicy(sizePolicy2)

        self.gridLayout_4.addWidget(self.lyrics_file_name_fmt_lineEdit, 0, 2, 1, 1)

        self.label_27 = QLabel(self.groupBox)
        self.label_27.setObjectName("label_27")
        sizePolicy1.setHeightForWidth(self.label_27.sizePolicy().hasHeightForWidth())
        self.label_27.setSizePolicy(sizePolicy1)

        self.gridLayout_4.addWidget(self.label_27, 1, 1, 1, 1)

        self.default_save_path_lineEdit = QLineEdit(self.groupBox)
        self.default_save_path_lineEdit.setObjectName("default_save_path_lineEdit")

        self.gridLayout_4.addWidget(self.default_save_path_lineEdit, 1, 2, 1, 1)

        self.select_default_save_path_pushButton = QPushButton(self.groupBox)
        self.select_default_save_path_pushButton.setObjectName("select_default_save_path_pushButton")

        self.gridLayout_4.addWidget(self.select_default_save_path_pushButton, 1, 3, 1, 1)

        self.label_28 = QLabel(self.groupBox)
        self.label_28.setObjectName("label_28")

        self.gridLayout_4.addWidget(self.label_28, 2, 1, 1, 1)

        self.id3_ver_comboBox = QComboBox(self.groupBox)
        self.id3_ver_comboBox.addItem("")
        self.id3_ver_comboBox.addItem("")
        self.id3_ver_comboBox.setObjectName("id3_ver_comboBox")

        self.gridLayout_4.addWidget(self.id3_ver_comboBox, 2, 2, 1, 1)

        self.gridLayout_6.addWidget(self.groupBox, 1, 0, 1, 1)

        self.label = QLabel(self.scrollAreaWidgetContents)
        self.label.setObjectName("label")
        sizePolicy1.setHeightForWidth(self.label.sizePolicy().hasHeightForWidth())
        self.label.setSizePolicy(sizePolicy1)
        font = QFont()
        font.setPointSize(18)
        self.label.setFont(font)

        self.gridLayout_6.addWidget(self.label, 0, 0, 1, 1)

        self.groupBox_4 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_4.setObjectName("groupBox_4")
        self.verticalLayout_2 = QVBoxLayout(self.groupBox_4)
        self.verticalLayout_2.setObjectName("verticalLayout_2")
        self.label_19 = QLabel(self.groupBox_4)
        self.label_19.setObjectName("label_19")
        sizePolicy3 = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Preferred)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.label_19.sizePolicy().hasHeightForWidth())
        self.label_19.setSizePolicy(sizePolicy3)

        self.verticalLayout_2.addWidget(self.label_19)

        self.multi_search_source_list = CheckBoxListWidget(self.groupBox_4)
        self.multi_search_source_list.setObjectName("multi_search_source_list")
        sizePolicy4 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Fixed)
        sizePolicy4.setHorizontalStretch(0)
        sizePolicy4.setVerticalStretch(0)
        sizePolicy4.setHeightForWidth(self.multi_search_source_list.sizePolicy().hasHeightForWidth())
        self.multi_search_source_list.setSizePolicy(sizePolicy4)
        self.multi_search_source_list.setMaximumSize(QSize(100, 16777215))
        self.multi_search_source_list.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)

        self.verticalLayout_2.addWidget(self.multi_search_source_list)

        self.gridLayout_6.addWidget(self.groupBox_4, 1, 1, 1, 1)

        self.groupBox_3 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_3.setObjectName("groupBox_3")
        self.gridLayout_3 = QGridLayout(self.groupBox_3)
        self.gridLayout_3.setObjectName("gridLayout_3")
        self.label_11 = QLabel(self.groupBox_3)
        self.label_11.setObjectName("label_11")
        sizePolicy1.setHeightForWidth(self.label_11.sizePolicy().hasHeightForWidth())
        self.label_11.setSizePolicy(sizePolicy1)

        self.gridLayout_3.addWidget(self.label_11, 0, 0, 1, 2)

        self.label_12 = QLabel(self.groupBox_3)
        self.label_12.setObjectName("label_12")
        sizePolicy1.setHeightForWidth(self.label_12.sizePolicy().hasHeightForWidth())
        self.label_12.setSizePolicy(sizePolicy1)

        self.gridLayout_3.addWidget(self.label_12, 0, 2, 1, 2)

        self.label_13 = QLabel(self.groupBox_3)
        self.label_13.setObjectName("label_13")
        sizePolicy3.setHeightForWidth(self.label_13.sizePolicy().hasHeightForWidth())
        self.label_13.setSizePolicy(sizePolicy3)

        self.gridLayout_3.addWidget(self.label_13, 0, 4, 1, 1)

        self.label_16 = QLabel(self.groupBox_3)
        self.label_16.setObjectName("label_16")
        sizePolicy3.setHeightForWidth(self.label_16.sizePolicy().hasHeightForWidth())
        self.label_16.setSizePolicy(sizePolicy3)

        self.gridLayout_3.addWidget(self.label_16, 0, 5, 1, 1)

        self.label_10 = QLabel(self.groupBox_3)
        self.label_10.setObjectName("label_10")
        sizePolicy3.setHeightForWidth(self.label_10.sizePolicy().hasHeightForWidth())
        self.label_10.setSizePolicy(sizePolicy3)

        self.gridLayout_3.addWidget(self.label_10, 0, 6, 1, 1)

        self.font_comboBox = QComboBox(self.groupBox_3)
        self.font_comboBox.setObjectName("font_comboBox")

        self.gridLayout_3.addWidget(self.font_comboBox, 0, 7, 1, 1)

        self.played_add_color_button = QPushButton(self.groupBox_3)
        self.played_add_color_button.setObjectName("played_add_color_button")
        sizePolicy1.setHeightForWidth(self.played_add_color_button.sizePolicy().hasHeightForWidth())
        self.played_add_color_button.setSizePolicy(sizePolicy1)

        self.gridLayout_3.addWidget(self.played_add_color_button, 1, 0, 2, 1)

        self.played_color_list = ColorsListWidget(self.groupBox_3)
        self.played_color_list.setObjectName("played_color_list")
        sizePolicy1.setHeightForWidth(self.played_color_list.sizePolicy().hasHeightForWidth())
        self.played_color_list.setSizePolicy(sizePolicy1)
        self.played_color_list.setMaximumSize(QSize(120, 16777215))

        self.gridLayout_3.addWidget(self.played_color_list, 1, 1, 4, 1)

        self.unplayed_add_color_button = QPushButton(self.groupBox_3)
        self.unplayed_add_color_button.setObjectName("unplayed_add_color_button")
        sizePolicy1.setHeightForWidth(self.unplayed_add_color_button.sizePolicy().hasHeightForWidth())
        self.unplayed_add_color_button.setSizePolicy(sizePolicy1)

        self.gridLayout_3.addWidget(self.unplayed_add_color_button, 1, 2, 2, 1)

        self.unplayed_color_list = ColorsListWidget(self.groupBox_3)
        self.unplayed_color_list.setObjectName("unplayed_color_list")
        sizePolicy1.setHeightForWidth(self.unplayed_color_list.sizePolicy().hasHeightForWidth())
        self.unplayed_color_list.setSizePolicy(sizePolicy1)
        self.unplayed_color_list.setMaximumSize(QSize(120, 16777215))

        self.gridLayout_3.addWidget(self.unplayed_color_list, 1, 3, 4, 1)

        self.lang_type_list = CheckBoxListWidget(self.groupBox_3)
        self.lang_type_list.setObjectName("lang_type_list")
        sizePolicy1.setHeightForWidth(self.lang_type_list.sizePolicy().hasHeightForWidth())
        self.lang_type_list.setSizePolicy(sizePolicy1)
        self.lang_type_list.setMaximumSize(QSize(100, 16777215))
        self.lang_type_list.setDragEnabled(True)
        self.lang_type_list.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)

        self.gridLayout_3.addWidget(self.lang_type_list, 1, 4, 4, 1)

        self.source_list = CheckBoxListWidget(self.groupBox_3)
        self.source_list.setObjectName("source_list")
        sizePolicy1.setHeightForWidth(self.source_list.sizePolicy().hasHeightForWidth())
        self.source_list.setSizePolicy(sizePolicy1)
        self.source_list.setMaximumSize(QSize(100, 16777215))
        self.source_list.setDragDropMode(QAbstractItemView.DragDropMode.InternalMove)

        self.gridLayout_3.addWidget(self.source_list, 1, 5, 4, 1)

        self.label_18 = QLabel(self.groupBox_3)
        self.label_18.setObjectName("label_18")
        sizePolicy4.setHeightForWidth(self.label_18.sizePolicy().hasHeightForWidth())
        self.label_18.setSizePolicy(sizePolicy4)
        self.label_18.setWordWrap(True)

        self.gridLayout_3.addWidget(self.label_18, 1, 6, 1, 2)

        self.label_15 = QLabel(self.groupBox_3)
        self.label_15.setObjectName("label_15")

        self.gridLayout_3.addWidget(self.label_15, 2, 6, 1, 1)

        self.frame_rate_spinBox = QSpinBox(self.groupBox_3)
        self.frame_rate_spinBox.setObjectName("frame_rate_spinBox")
        self.frame_rate_spinBox.setMaximum(1000)
        self.frame_rate_spinBox.setValue(60)

        self.gridLayout_3.addWidget(self.frame_rate_spinBox, 2, 7, 1, 1)

        self.played_del_color_button = QPushButton(self.groupBox_3)
        self.played_del_color_button.setObjectName("played_del_color_button")
        sizePolicy1.setHeightForWidth(self.played_del_color_button.sizePolicy().hasHeightForWidth())
        self.played_del_color_button.setSizePolicy(sizePolicy1)

        self.gridLayout_3.addWidget(self.played_del_color_button, 3, 0, 2, 1)

        self.unplayed_del_color_button = QPushButton(self.groupBox_3)
        self.unplayed_del_color_button.setObjectName("unplayed_del_color_button")
        sizePolicy1.setHeightForWidth(self.unplayed_del_color_button.sizePolicy().hasHeightForWidth())
        self.unplayed_del_color_button.setSizePolicy(sizePolicy1)

        self.gridLayout_3.addWidget(self.unplayed_del_color_button, 3, 2, 2, 1)

        self.auto_frame_rate_checkBox = QCheckBox(self.groupBox_3)
        self.auto_frame_rate_checkBox.setObjectName("auto_frame_rate_checkBox")

        self.gridLayout_3.addWidget(self.auto_frame_rate_checkBox, 3, 6, 1, 2)

        self.show_local_song_lyrics_db_manager_button = QPushButton(self.groupBox_3)
        self.show_local_song_lyrics_db_manager_button.setObjectName("show_local_song_lyrics_db_manager_button")

        self.gridLayout_3.addWidget(self.show_local_song_lyrics_db_manager_button, 4, 6, 1, 2)

        self.gridLayout_6.addWidget(self.groupBox_3, 3, 0, 1, 2)

        self.groupBox_6 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_6.setObjectName("groupBox_6")
        self.gridLayout_2 = QGridLayout(self.groupBox_6)
        self.gridLayout_2.setObjectName("gridLayout_2")
        self.auto_check_update_checkBox = QCheckBox(self.groupBox_6)
        self.auto_check_update_checkBox.setObjectName("auto_check_update_checkBox")

        self.gridLayout_2.addWidget(self.auto_check_update_checkBox, 5, 2, 1, 1)

        self.restore2default_pushButton = QPushButton(self.groupBox_6)
        self.restore2default_pushButton.setObjectName("restore2default_pushButton")

        self.gridLayout_2.addWidget(self.restore2default_pushButton, 3, 2, 1, 1)

        self.log_level_comboBox = QComboBox(self.groupBox_6)
        self.log_level_comboBox.addItem("CRITICAL")
        self.log_level_comboBox.addItem("ERROR")
        self.log_level_comboBox.addItem("WARNING")
        self.log_level_comboBox.addItem("INFO")
        self.log_level_comboBox.addItem("DEBUG")
        self.log_level_comboBox.addItem("NOTSET")
        self.log_level_comboBox.setObjectName("log_level_comboBox")

        self.gridLayout_2.addWidget(self.log_level_comboBox, 2, 2, 1, 1)

        self.open_log_dir_button = QPushButton(self.groupBox_6)
        self.open_log_dir_button.setObjectName("open_log_dir_button")

        self.gridLayout_2.addWidget(self.open_log_dir_button, 4, 2, 1, 1)

        self.language_comboBox = QComboBox(self.groupBox_6)
        self.language_comboBox.addItem("")
        self.language_comboBox.addItem("\u7b80\u4f53\u4e2d\u6587")
        self.language_comboBox.addItem("\u7e41\u9ad4\u4e2d\u6587")
        self.language_comboBox.addItem("English")
        self.language_comboBox.addItem("\u65e5\u672c\u8a9e")
        self.language_comboBox.setObjectName("language_comboBox")

        self.gridLayout_2.addWidget(self.language_comboBox, 0, 2, 1, 1)

        self.label_7 = QLabel(self.groupBox_6)
        self.label_7.setObjectName("label_7")
        sizePolicy3.setHeightForWidth(self.label_7.sizePolicy().hasHeightForWidth())
        self.label_7.setSizePolicy(sizePolicy3)

        self.gridLayout_2.addWidget(self.label_7, 0, 0, 1, 1)

        self.label_2 = QLabel(self.groupBox_6)
        self.label_2.setObjectName("label_2")

        self.gridLayout_2.addWidget(self.label_2, 1, 0, 1, 1)

        self.label_5 = QLabel(self.groupBox_6)
        self.label_5.setObjectName("label_5")
        sizePolicy1.setHeightForWidth(self.label_5.sizePolicy().hasHeightForWidth())
        self.label_5.setSizePolicy(sizePolicy1)

        self.gridLayout_2.addWidget(self.label_5, 2, 0, 1, 1)

        self.color_scheme_comboBox = QComboBox(self.groupBox_6)
        self.color_scheme_comboBox.addItem("")
        self.color_scheme_comboBox.addItem("")
        self.color_scheme_comboBox.addItem("")
        self.color_scheme_comboBox.setObjectName("color_scheme_comboBox")

        self.gridLayout_2.addWidget(self.color_scheme_comboBox, 1, 2, 1, 1)

        self.gridLayout_6.addWidget(self.groupBox_6, 4, 0, 1, 2)

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

        self.gridLayout_6.addWidget(self.groupBox_5, 5, 0, 1, 2)

        self.groupBox_2 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_2.setObjectName("groupBox_2")
        self.gridLayout = QGridLayout(self.groupBox_2)
        self.gridLayout.setObjectName("gridLayout")
        self.langs_order_listWidget = LyricOrderListWidget(self.groupBox_2)
        QListWidgetItem(self.langs_order_listWidget)
        QListWidgetItem(self.langs_order_listWidget)
        QListWidgetItem(self.langs_order_listWidget)
        self.langs_order_listWidget.setObjectName("langs_order_listWidget")
        sizePolicy3.setHeightForWidth(self.langs_order_listWidget.sizePolicy().hasHeightForWidth())
        self.langs_order_listWidget.setSizePolicy(sizePolicy3)
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

        self.gridLayout.addWidget(self.langs_order_listWidget, 1, 0, 6, 1)

        self.label_6 = QLabel(self.groupBox_2)
        self.label_6.setObjectName("label_6")
        sizePolicy1.setHeightForWidth(self.label_6.sizePolicy().hasHeightForWidth())
        self.label_6.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.label_6, 3, 1, 1, 1)

        self.label_8 = QLabel(self.groupBox_2)
        self.label_8.setObjectName("label_8")
        sizePolicy1.setHeightForWidth(self.label_8.sizePolicy().hasHeightForWidth())
        self.label_8.setSizePolicy(sizePolicy1)

        self.gridLayout.addWidget(self.label_8, 4, 1, 1, 1)

        self.skip_inst_lyrics_checkBox = QCheckBox(self.groupBox_2)
        self.skip_inst_lyrics_checkBox.setObjectName("skip_inst_lyrics_checkBox")
        sizePolicy4.setHeightForWidth(self.skip_inst_lyrics_checkBox.sizePolicy().hasHeightForWidth())
        self.skip_inst_lyrics_checkBox.setSizePolicy(sizePolicy4)

        self.gridLayout.addWidget(self.skip_inst_lyrics_checkBox, 0, 1, 1, 4)

        self.add_end_timestamp_line_checkBox = QCheckBox(self.groupBox_2)
        self.add_end_timestamp_line_checkBox.setObjectName("add_end_timestamp_line_checkBox")
        sizePolicy4.setHeightForWidth(self.add_end_timestamp_line_checkBox.sizePolicy().hasHeightForWidth())
        self.add_end_timestamp_line_checkBox.setSizePolicy(sizePolicy4)

        self.gridLayout.addWidget(self.add_end_timestamp_line_checkBox, 2, 1, 1, 4)

        self.label_4 = QLabel(self.groupBox_2)
        self.label_4.setObjectName("label_4")
        sizePolicy4.setHeightForWidth(self.label_4.sizePolicy().hasHeightForWidth())
        self.label_4.setSizePolicy(sizePolicy4)

        self.gridLayout.addWidget(self.label_4, 0, 0, 1, 1)

        self.auto_select_checkBox = QCheckBox(self.groupBox_2)
        self.auto_select_checkBox.setObjectName("auto_select_checkBox")
        sizePolicy4.setHeightForWidth(self.auto_select_checkBox.sizePolicy().hasHeightForWidth())
        self.auto_select_checkBox.setSizePolicy(sizePolicy4)

        self.gridLayout.addWidget(self.auto_select_checkBox, 1, 1, 1, 4)

        self.last_ref_line_time_sty_comboBox = QComboBox(self.groupBox_2)
        self.last_ref_line_time_sty_comboBox.addItem("")
        self.last_ref_line_time_sty_comboBox.addItem("")
        self.last_ref_line_time_sty_comboBox.setObjectName("last_ref_line_time_sty_comboBox")
        sizePolicy4.setHeightForWidth(self.last_ref_line_time_sty_comboBox.sizePolicy().hasHeightForWidth())
        self.last_ref_line_time_sty_comboBox.setSizePolicy(sizePolicy4)

        self.gridLayout.addWidget(self.last_ref_line_time_sty_comboBox, 4, 2, 1, 3)

        self.lrc_ms_digit_count_spinBox = QSpinBox(self.groupBox_2)
        self.lrc_ms_digit_count_spinBox.setObjectName("lrc_ms_digit_count_spinBox")
        sizePolicy4.setHeightForWidth(self.lrc_ms_digit_count_spinBox.sizePolicy().hasHeightForWidth())
        self.lrc_ms_digit_count_spinBox.setSizePolicy(sizePolicy4)
        self.lrc_ms_digit_count_spinBox.setMinimumSize(QSize(70, 0))
        self.lrc_ms_digit_count_spinBox.setMinimum(2)
        self.lrc_ms_digit_count_spinBox.setMaximum(3)
        self.lrc_ms_digit_count_spinBox.setValue(3)

        self.gridLayout.addWidget(self.lrc_ms_digit_count_spinBox, 3, 2, 1, 3)

        self.label_3 = QLabel(self.groupBox_2)
        self.label_3.setObjectName("label_3")

        self.gridLayout.addWidget(self.label_3, 5, 1, 1, 1)

        self.lrc_tag_info_src_comboBox = QComboBox(self.groupBox_2)
        self.lrc_tag_info_src_comboBox.addItem("")
        self.lrc_tag_info_src_comboBox.addItem("")
        self.lrc_tag_info_src_comboBox.setObjectName("lrc_tag_info_src_comboBox")

        self.gridLayout.addWidget(self.lrc_tag_info_src_comboBox, 5, 2, 1, 3)

        self.gridLayout_6.addWidget(self.groupBox_2, 2, 0, 1, 1)

        self.groupBox_7 = QGroupBox(self.scrollAreaWidgetContents)
        self.groupBox_7.setObjectName("groupBox_7")
        self.gridLayout_7 = QGridLayout(self.groupBox_7)
        self.gridLayout_7.setObjectName("gridLayout_7")
        self.translate_source_comboBox = QComboBox(self.groupBox_7)
        self.translate_source_comboBox.addItem("")
        self.translate_source_comboBox.addItem("")
        self.translate_source_comboBox.addItem("")
        self.translate_source_comboBox.setObjectName("translate_source_comboBox")

        self.gridLayout_7.addWidget(self.translate_source_comboBox, 0, 1, 1, 1)

        self.translate_cfg_stackedWidget = QStackedWidget(self.groupBox_7)
        self.translate_cfg_stackedWidget.setObjectName("translate_cfg_stackedWidget")
        self.page_3 = QWidget()
        self.page_3.setObjectName("page_3")
        self.translate_cfg_stackedWidget.addWidget(self.page_3)
        self.page_2 = QWidget()
        self.page_2.setObjectName("page_2")
        self.translate_cfg_stackedWidget.addWidget(self.page_2)
        self.page = QWidget()
        self.page.setObjectName("page")
        self.gridLayout_8 = QGridLayout(self.page)
        self.gridLayout_8.setObjectName("gridLayout_8")
        self.label_20 = QLabel(self.page)
        self.label_20.setObjectName("label_20")
        self.label_20.setText("API key:")

        self.gridLayout_8.addWidget(self.label_20, 1, 0, 1, 1)

        self.oai_model_lineEdit = QLineEdit(self.page)
        self.oai_model_lineEdit.setObjectName("oai_model_lineEdit")

        self.gridLayout_8.addWidget(self.oai_model_lineEdit, 2, 1, 1, 1)

        self.oai_key_lineEdit = QLineEdit(self.page)
        self.oai_key_lineEdit.setObjectName("oai_key_lineEdit")

        self.gridLayout_8.addWidget(self.oai_key_lineEdit, 1, 1, 1, 1)

        self.label_14 = QLabel(self.page)
        self.label_14.setObjectName("label_14")
        self.label_14.setText("Base URL:")

        self.gridLayout_8.addWidget(self.label_14, 0, 0, 1, 1)

        self.label_21 = QLabel(self.page)
        self.label_21.setObjectName("label_21")
        self.label_21.setText("Model:")

        self.gridLayout_8.addWidget(self.label_21, 2, 0, 1, 1)

        self.oai_base_url_lineEdit = QLineEdit(self.page)
        self.oai_base_url_lineEdit.setObjectName("oai_base_url_lineEdit")
        self.oai_base_url_lineEdit.setMinimumSize(QSize(256, 0))

        self.gridLayout_8.addWidget(self.oai_base_url_lineEdit, 0, 1, 1, 1)

        self.translate_cfg_stackedWidget.addWidget(self.page)

        self.gridLayout_7.addWidget(self.translate_cfg_stackedWidget, 2, 0, 1, 2)

        self.label_9 = QLabel(self.groupBox_7)
        self.label_9.setObjectName("label_9")

        self.gridLayout_7.addWidget(self.label_9, 0, 0, 1, 1)

        self.label_17 = QLabel(self.groupBox_7)
        self.label_17.setObjectName("label_17")

        self.gridLayout_7.addWidget(self.label_17, 1, 0, 1, 1)

        self.translate_target_lang_comboBox = QComboBox(self.groupBox_7)
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.addItem("")
        self.translate_target_lang_comboBox.setObjectName("translate_target_lang_comboBox")

        self.gridLayout_7.addWidget(self.translate_target_lang_comboBox, 1, 1, 1, 1)

        self.gridLayout_6.addWidget(self.groupBox_7, 2, 1, 1, 1)

        self.scrollArea.setWidget(self.scrollAreaWidgetContents)

        self.verticalLayout.addWidget(self.scrollArea)

        self.retranslateUi(settings)
        self.translate_source_comboBox.currentIndexChanged.connect(self.translate_cfg_stackedWidget.setCurrentIndex)

        self.log_level_comboBox.setCurrentIndex(0)
        self.translate_cfg_stackedWidget.setCurrentIndex(0)

        QMetaObject.connectSlotsByName(settings)

    # setupUi

    def retranslateUi(self, settings):
        self.groupBox.setTitle(QCoreApplication.translate("settings", "\u4fdd\u5b58\u8bbe\u7f6e", None))
        self.textBrowser_5.setHtml(
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
            ),
        )
        # if QT_CONFIG(whatsthis)
        self.label_26.setWhatsThis("")
        # endif // QT_CONFIG(whatsthis)
        # if QT_CONFIG(accessibility)
        self.label_26.setAccessibleDescription("")
        # endif // QT_CONFIG(accessibility)
        self.label_26.setText(QCoreApplication.translate("settings", "\u6b4c\u8bcd\u6587\u4ef6\u540d\u683c\u5f0f", None))
        self.label_27.setText(QCoreApplication.translate("settings", "\u9ed8\u8ba4\u4fdd\u5b58\u8def\u5f84", None))
        self.select_default_save_path_pushButton.setText(QCoreApplication.translate("settings", "\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.label_28.setText(QCoreApplication.translate("settings", "ID3\u7248\u672c", None))
        self.id3_ver_comboBox.setItemText(0, QCoreApplication.translate("settings", "v2.3", None))
        self.id3_ver_comboBox.setItemText(1, QCoreApplication.translate("settings", "v2.4", None))

        self.label.setText(QCoreApplication.translate("settings", "\u8bbe\u7f6e", None))
        self.groupBox_4.setTitle(QCoreApplication.translate("settings", "\u641c\u7d22", None))
        self.label_19.setText(QCoreApplication.translate("settings", "\u81ea\u52a8\u641c\u7d22\u6b4c\u8bcd\u6e90\uff1a", None))
        self.groupBox_3.setTitle(QCoreApplication.translate("settings", "\u684c\u9762\u6b4c\u8bcd\u8bbe\u7f6e", None))
        self.label_11.setText(QCoreApplication.translate("settings", "\u5df2\u64ad\u653e\u989c\u8272:", None))
        self.label_12.setText(QCoreApplication.translate("settings", "\u672a\u64ad\u653e\u989c\u8272:", None))
        self.label_13.setText(QCoreApplication.translate("settings", "\u9ed8\u8ba4\u8bed\u8a00\u7c7b\u578b\uff1a", None))
        self.label_16.setText(QCoreApplication.translate("settings", "\u81ea\u52a8\u641c\u7d22\u6b4c\u8bcd\u6e90\uff1a", None))
        self.label_10.setText(QCoreApplication.translate("settings", "\u5b57\u4f53:", None))
        self.played_add_color_button.setText(QCoreApplication.translate("settings", "\u6dfb\u52a0\u989c\u8272", None))
        self.unplayed_add_color_button.setText(QCoreApplication.translate("settings", "\u6dfb\u52a0\u989c\u8272", None))
        self.label_18.setText(
            QCoreApplication.translate("settings", "\u63d0\u793a\uff1a\u5b57\u4f53\u5927\u5c0f\u901a\u8fc7\u62c9\u4f38\u7a97\u53e3\u8c03\u8282", None),
        )
        self.label_15.setText(QCoreApplication.translate("settings", "\u5e27\u7387:", None))
        self.played_del_color_button.setText(QCoreApplication.translate("settings", "\u5220\u9664\u989c\u8272", None))
        self.unplayed_del_color_button.setText(QCoreApplication.translate("settings", "\u5220\u9664\u989c\u8272", None))
        self.auto_frame_rate_checkBox.setText(QCoreApplication.translate("settings", "\u81ea\u9002\u5e94\u5e27\u7387", None))
        self.show_local_song_lyrics_db_manager_button.setText(QCoreApplication.translate("settings", "\u6b4c\u8bcd\u5173\u8054\u7ba1\u7406", None))
        self.groupBox_6.setTitle(QCoreApplication.translate("settings", "\u5176\u4ed6", None))
        self.auto_check_update_checkBox.setText(QCoreApplication.translate("settings", "\u81ea\u52a8\u68c0\u67e5\u66f4\u65b0", None))
        self.restore2default_pushButton.setText(QCoreApplication.translate("settings", "\u6062\u590d\u9ed8\u8ba4\u8bbe\u7f6e", None))

        self.open_log_dir_button.setText(QCoreApplication.translate("settings", "\u6253\u5f00\u65e5\u5fd7\u6587\u4ef6\u5939", None))
        self.language_comboBox.setItemText(0, QCoreApplication.translate("settings", "\u81ea\u52a8", None))

        self.label_7.setText(QCoreApplication.translate("settings", "\u8bed\u8a00\uff1a", None))
        self.label_2.setText(QCoreApplication.translate("settings", "\u4e3b\u9898\u989c\u8272:", None))
        self.label_5.setText(QCoreApplication.translate("settings", "\u65e5\u5fd7\u7b49\u7ea7:", None))
        self.color_scheme_comboBox.setItemText(0, QCoreApplication.translate("settings", "\u8ddf\u968f\u7cfb\u7edf", None))
        self.color_scheme_comboBox.setItemText(1, QCoreApplication.translate("settings", "\u6d45\u8272", None))
        self.color_scheme_comboBox.setItemText(2, QCoreApplication.translate("settings", "\u6df1\u8272", None))

        self.groupBox_5.setTitle(QCoreApplication.translate("settings", "\u7f13\u5b58\u8bbe\u7f6e", None))
        self.clear_cache_pushButton.setText(QCoreApplication.translate("settings", "\u6e05\u9664\u7f13\u5b58", None))
        self.cache_size_label.setText(QCoreApplication.translate("settings", "\u7f13\u5b58\u5927\u5c0f\uff1a", None))
        self.groupBox_2.setTitle(QCoreApplication.translate("settings", "\u6b4c\u8bcd\u8bbe\u7f6e", None))

        __sortingEnabled = self.langs_order_listWidget.isSortingEnabled()
        self.langs_order_listWidget.setSortingEnabled(False)
        ___qlistwidgetitem = self.langs_order_listWidget.item(0)
        ___qlistwidgetitem.setText(QCoreApplication.translate("settings", "\u7f57\u9a6c\u97f3", None))
        ___qlistwidgetitem1 = self.langs_order_listWidget.item(1)
        ___qlistwidgetitem1.setText(QCoreApplication.translate("settings", "\u539f\u6587", None))
        ___qlistwidgetitem2 = self.langs_order_listWidget.item(2)
        ___qlistwidgetitem2.setText(QCoreApplication.translate("settings", "\u8bd1\u6587", None))
        self.langs_order_listWidget.setSortingEnabled(__sortingEnabled)

        self.label_6.setText(QCoreApplication.translate("settings", "LRC\u6b4c\u8bcd\u6beb\u79d2\u4f4d\u6570:", None))
        self.label_8.setText(QCoreApplication.translate("settings", "\u672b\u5c3e\u53c2\u7167\u884c\u65f6\u95f4\u6837\u5f0f(\u4ec5LRC):", None))
        self.skip_inst_lyrics_checkBox.setText(
            QCoreApplication.translate(
                "settings",
                "\u4fdd\u5b58\u4e13\u8f91/\u6b4c\u5355\u6b4c\u8bcd/\u672c\u5730\u5339\u914d\u65f6\u8df3\u8fc7\u7eaf\u97f3\u4e50",
                None,
            ),
        )
        self.add_end_timestamp_line_checkBox.setText(
            QCoreApplication.translate("settings", "\u4e3a\u9010\u884clrc\u6b4c\u8bcd\u6dfb\u52a0\u7ed3\u675f\u65f6\u95f4\u6233\u884c", None),
        )
        self.label_4.setText(QCoreApplication.translate("settings", "\u987a\u5e8f", None))
        self.auto_select_checkBox.setText(
            QCoreApplication.translate("settings", "\u6b4c\u66f2\u641c\u7d22\u6b4c\u8bcd\u65f6\u81ea\u52a8\u9009\u62e9(\u9177\u72d7\u97f3\u4e50)", None),
        )
        self.last_ref_line_time_sty_comboBox.setItemText(
            0,
            QCoreApplication.translate("settings", "\u4e0e\u5f53\u524d\u539f\u6587\u8d77\u59cb\u65f6\u95f4\u76f8\u540c", None),
        )
        self.last_ref_line_time_sty_comboBox.setItemText(
            1,
            QCoreApplication.translate("settings", "\u4e0e\u4e0b\u4e00\u884c\u539f\u6587\u8d77\u59cb\u65f6\u95f4\u63a5\u8fd1", None),
        )

        self.lrc_ms_digit_count_spinBox.setSpecialValueText("")
        self.lrc_ms_digit_count_spinBox.setPrefix("")
        self.label_3.setText(QCoreApplication.translate("settings", "\u6b4c\u8bcd\u6587\u4ef6\u6807\u7b7e\u4fe1\u606f\u6765\u6e90:", None))
        self.lrc_tag_info_src_comboBox.setItemText(0, QCoreApplication.translate("settings", "\u6b4c\u8bcd\u6e90", None))
        self.lrc_tag_info_src_comboBox.setItemText(1, QCoreApplication.translate("settings", "\u6b4c\u66f2\u4fe1\u606f", None))

        self.groupBox_7.setTitle(QCoreApplication.translate("settings", "\u7ffb\u8bd1", None))
        self.translate_source_comboBox.setItemText(0, QCoreApplication.translate("settings", "\u5fc5\u5e94\u7ffb\u8bd1", None))
        self.translate_source_comboBox.setItemText(1, QCoreApplication.translate("settings", "\u8c37\u6b4c\u7ffb\u8bd1", None))
        self.translate_source_comboBox.setItemText(2, QCoreApplication.translate("settings", "OpenAI\u517c\u5bb9API", None))

        self.label_9.setText(QCoreApplication.translate("settings", "\u7ffb\u8bd1\u6e90:", None))
        self.label_17.setText(QCoreApplication.translate("settings", "\u76ee\u6807\u8bed\u8a00:", None))
        self.translate_target_lang_comboBox.setItemText(0, QCoreApplication.translate("settings", "\u7b80\u4f53\u4e2d\u6587", None))
        self.translate_target_lang_comboBox.setItemText(1, QCoreApplication.translate("settings", "\u7e41\u4f53\u4e2d\u6587", None))
        self.translate_target_lang_comboBox.setItemText(2, QCoreApplication.translate("settings", "\u82f1\u8bed", None))
        self.translate_target_lang_comboBox.setItemText(3, QCoreApplication.translate("settings", "\u65e5\u8bed", None))
        self.translate_target_lang_comboBox.setItemText(4, QCoreApplication.translate("settings", "\u97e9\u8bed", None))
        self.translate_target_lang_comboBox.setItemText(5, QCoreApplication.translate("settings", "\u897f\u73ed\u7259\u8bed", None))
        self.translate_target_lang_comboBox.setItemText(6, QCoreApplication.translate("settings", "\u6cd5\u8bed", None))
        self.translate_target_lang_comboBox.setItemText(7, QCoreApplication.translate("settings", "\u8461\u8404\u7259\u8bed", None))
        self.translate_target_lang_comboBox.setItemText(8, QCoreApplication.translate("settings", "\u5fb7\u8bed", None))
        self.translate_target_lang_comboBox.setItemText(9, QCoreApplication.translate("settings", "\u4fc4\u8bed", None))

    # retranslateUi
