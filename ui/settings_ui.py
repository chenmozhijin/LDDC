# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'settings.ui'
##
## Created by: Qt User Interface Compiler version 6.6.2
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
    QBrush,
    QColor,
    QConicalGradient,
    QCursor,
    QFont,
    QFontDatabase,
    QGradient,
    QIcon,
    QImage,
    QKeySequence,
    QLinearGradient,
    QPainter,
    QPalette,
    QPixmap,
    QRadialGradient,
    QTransform,
)
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QCheckBox,
    QComboBox,
    QFrame,
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
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from ui.custom_widgets import LyricOrderListWidget


class Ui_settings(object):
    def setupUi(self, settings):
        if not settings.objectName():
            settings.setObjectName(u"settings")
        settings.resize(1050, 600)
        self.verticalLayout = QVBoxLayout(settings)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.label = QLabel(settings)
        self.label.setObjectName(u"label")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.label.sizePolicy().hasHeightForWidth())
        self.label.setSizePolicy(sizePolicy)
        font = QFont()
        font.setPointSize(18)
        self.label.setFont(font)

        self.verticalLayout.addWidget(self.label)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.verticalLayout_2 = QVBoxLayout()
        self.verticalLayout_2.setObjectName(u"verticalLayout_2")
        self.groupBox_2 = QGroupBox(settings)
        self.groupBox_2.setObjectName(u"groupBox_2")
        self.horizontalLayout_4 = QHBoxLayout(self.groupBox_2)
        self.horizontalLayout_4.setObjectName(u"horizontalLayout_4")
        self.verticalLayout_4 = QVBoxLayout()
        self.verticalLayout_4.setObjectName(u"verticalLayout_4")
        self.verticalLayout_4.setSizeConstraint(QLayout.SetDefaultConstraint)
        self.label_4 = QLabel(self.groupBox_2)
        self.label_4.setObjectName(u"label_4")
        sizePolicy.setHeightForWidth(self.label_4.sizePolicy().hasHeightForWidth())
        self.label_4.setSizePolicy(sizePolicy)

        self.verticalLayout_4.addWidget(self.label_4)

        self.lyrics_order_listWidget = LyricOrderListWidget(self.groupBox_2)
        QListWidgetItem(self.lyrics_order_listWidget)
        QListWidgetItem(self.lyrics_order_listWidget)
        QListWidgetItem(self.lyrics_order_listWidget)
        self.lyrics_order_listWidget.setObjectName(u"lyrics_order_listWidget")
        sizePolicy.setHeightForWidth(self.lyrics_order_listWidget.sizePolicy().hasHeightForWidth())
        self.lyrics_order_listWidget.setSizePolicy(sizePolicy)
        self.lyrics_order_listWidget.setMinimumSize(QSize(0, 0))
        self.lyrics_order_listWidget.setMaximumSize(QSize(118, 96))
        self.lyrics_order_listWidget.setFrameShape(QFrame.Box)
        self.lyrics_order_listWidget.setFrameShadow(QFrame.Sunken)
        self.lyrics_order_listWidget.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.lyrics_order_listWidget.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.lyrics_order_listWidget.setAutoScroll(True)
        self.lyrics_order_listWidget.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.lyrics_order_listWidget.setDragEnabled(True)
        self.lyrics_order_listWidget.setDragDropMode(QAbstractItemView.InternalMove)
        self.lyrics_order_listWidget.setDefaultDropAction(Qt.MoveAction)
        self.lyrics_order_listWidget.setSelectionMode(QAbstractItemView.SingleSelection)
        self.lyrics_order_listWidget.setMovement(QListView.Free)
        self.lyrics_order_listWidget.setSortingEnabled(False)

        self.verticalLayout_4.addWidget(self.lyrics_order_listWidget)


        self.horizontalLayout_4.addLayout(self.verticalLayout_4)

        self.verticalLayout_6 = QVBoxLayout()
        self.verticalLayout_6.setObjectName(u"verticalLayout_6")
        self.skip_inst_lyrics_checkBox = QCheckBox(self.groupBox_2)
        self.skip_inst_lyrics_checkBox.setObjectName(u"skip_inst_lyrics_checkBox")

        self.verticalLayout_6.addWidget(self.skip_inst_lyrics_checkBox)

        self.get_normal_lyrics_checkBox = QCheckBox(self.groupBox_2)
        self.get_normal_lyrics_checkBox.setObjectName(u"get_normal_lyrics_checkBox")

        self.verticalLayout_6.addWidget(self.get_normal_lyrics_checkBox)

        self.auto_select_checkBox = QCheckBox(self.groupBox_2)
        self.auto_select_checkBox.setObjectName(u"auto_select_checkBox")

        self.verticalLayout_6.addWidget(self.auto_select_checkBox)

        self.verticalSpacer_2 = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Expanding)

        self.verticalLayout_6.addItem(self.verticalSpacer_2)


        self.horizontalLayout_4.addLayout(self.verticalLayout_6)

        self.horizontalSpacer_2 = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout_4.addItem(self.horizontalSpacer_2)


        self.verticalLayout_2.addWidget(self.groupBox_2)

        self.groupBox = QGroupBox(settings)
        self.groupBox.setObjectName(u"groupBox")
        self.horizontalLayout_2 = QHBoxLayout(self.groupBox)
        self.horizontalLayout_2.setObjectName(u"horizontalLayout_2")
        self.textBrowser = QTextBrowser(self.groupBox)
        self.textBrowser.setObjectName(u"textBrowser")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Minimum)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.textBrowser.sizePolicy().hasHeightForWidth())
        self.textBrowser.setSizePolicy(sizePolicy1)
        self.textBrowser.setMinimumSize(QSize(192, 106))
        self.textBrowser.setMaximumSize(QSize(234, 78))
        self.textBrowser.setFrameShape(QFrame.Box)
        self.textBrowser.setFrameShadow(QFrame.Sunken)
        self.textBrowser.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.textBrowser.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.textBrowser.setOpenLinks(False)

        self.horizontalLayout_2.addWidget(self.textBrowser, 0, Qt.AlignTop)

        self.verticalLayout_3 = QVBoxLayout()
        self.verticalLayout_3.setObjectName(u"verticalLayout_3")
        self.horizontalLayout_3 = QHBoxLayout()
        self.horizontalLayout_3.setObjectName(u"horizontalLayout_3")
        self.horizontalLayout_3.setSizeConstraint(QLayout.SetDefaultConstraint)
        self.label_2 = QLabel(self.groupBox)
        self.label_2.setObjectName(u"label_2")
        sizePolicy.setHeightForWidth(self.label_2.sizePolicy().hasHeightForWidth())
        self.label_2.setSizePolicy(sizePolicy)
        self.label_2.setTextFormat(Qt.AutoText)

        self.horizontalLayout_3.addWidget(self.label_2)

        self.lyrics_file_name_format_lineEdit = QLineEdit(self.groupBox)
        self.lyrics_file_name_format_lineEdit.setObjectName(u"lyrics_file_name_format_lineEdit")
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.MinimumExpanding, QSizePolicy.Policy.Fixed)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.lyrics_file_name_format_lineEdit.sizePolicy().hasHeightForWidth())
        self.lyrics_file_name_format_lineEdit.setSizePolicy(sizePolicy2)

        self.horizontalLayout_3.addWidget(self.lyrics_file_name_format_lineEdit)


        self.verticalLayout_3.addLayout(self.horizontalLayout_3)

        self.horizontalLayout_5 = QHBoxLayout()
        self.horizontalLayout_5.setObjectName(u"horizontalLayout_5")
        self.label_3 = QLabel(self.groupBox)
        self.label_3.setObjectName(u"label_3")
        sizePolicy.setHeightForWidth(self.label_3.sizePolicy().hasHeightForWidth())
        self.label_3.setSizePolicy(sizePolicy)

        self.horizontalLayout_5.addWidget(self.label_3)

        self.default_save_path_lineEdit = QLineEdit(self.groupBox)
        self.default_save_path_lineEdit.setObjectName(u"default_save_path_lineEdit")

        self.horizontalLayout_5.addWidget(self.default_save_path_lineEdit)

        self.select_default_save_path_pushButton = QPushButton(self.groupBox)
        self.select_default_save_path_pushButton.setObjectName(u"select_default_save_path_pushButton")

        self.horizontalLayout_5.addWidget(self.select_default_save_path_pushButton)


        self.verticalLayout_3.addLayout(self.horizontalLayout_5)


        self.horizontalLayout_2.addLayout(self.verticalLayout_3)


        self.verticalLayout_2.addWidget(self.groupBox)

        self.groupBox_3 = QGroupBox(settings)
        self.groupBox_3.setObjectName(u"groupBox_3")
        self.verticalLayout_5 = QVBoxLayout(self.groupBox_3)
        self.verticalLayout_5.setObjectName(u"verticalLayout_5")
        self.horizontalLayout_6 = QHBoxLayout()
        self.horizontalLayout_6.setObjectName(u"horizontalLayout_6")
        self.label_5 = QLabel(self.groupBox_3)
        self.label_5.setObjectName(u"label_5")
        sizePolicy.setHeightForWidth(self.label_5.sizePolicy().hasHeightForWidth())
        self.label_5.setSizePolicy(sizePolicy)

        self.horizontalLayout_6.addWidget(self.label_5)

        self.log_level_comboBox = QComboBox(self.groupBox_3)
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.addItem("")
        self.log_level_comboBox.setObjectName(u"log_level_comboBox")

        self.horizontalLayout_6.addWidget(self.log_level_comboBox)


        self.verticalLayout_5.addLayout(self.horizontalLayout_6)


        self.verticalLayout_2.addWidget(self.groupBox_3)


        self.horizontalLayout.addLayout(self.verticalLayout_2)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)


        self.verticalLayout.addLayout(self.horizontalLayout)

        self.verticalSpacer = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Expanding)

        self.verticalLayout.addItem(self.verticalSpacer)


        self.retranslateUi(settings)

        self.log_level_comboBox.setCurrentIndex(1)


        QMetaObject.connectSlotsByName(settings)
    # setupUi

    def retranslateUi(self, settings):
        settings.setWindowTitle(QCoreApplication.translate("settings", u"Form", None))
        self.label.setText(QCoreApplication.translate("settings", u"\u8bbe\u7f6e", None))
        self.groupBox_2.setTitle(QCoreApplication.translate("settings", u"\u6b4c\u8bcd\u8bbe\u7f6e", None))
        self.label_4.setText(QCoreApplication.translate("settings", u"\u987a\u5e8f", None))

        __sortingEnabled = self.lyrics_order_listWidget.isSortingEnabled()
        self.lyrics_order_listWidget.setSortingEnabled(False)
        ___qlistwidgetitem = self.lyrics_order_listWidget.item(0)
        ___qlistwidgetitem.setText(QCoreApplication.translate("settings", u"\u7f57\u9a6c\u97f3", None));
        ___qlistwidgetitem1 = self.lyrics_order_listWidget.item(1)
        ___qlistwidgetitem1.setText(QCoreApplication.translate("settings", u"\u539f\u6587", None));
        ___qlistwidgetitem2 = self.lyrics_order_listWidget.item(2)
        ___qlistwidgetitem2.setText(QCoreApplication.translate("settings", u"\u8bd1\u6587", None));
        self.lyrics_order_listWidget.setSortingEnabled(__sortingEnabled)

        self.skip_inst_lyrics_checkBox.setText(QCoreApplication.translate("settings", u"\u4fdd\u5b58\u4e13\u8f91/\u6b4c\u5355\u6b4c\u8bcd\u65f6\u8df3\u8fc7\u7eaf\u97f3\u4e50", None))
        self.get_normal_lyrics_checkBox.setText(QCoreApplication.translate("settings", u"\u6ca1\u6709\u53ef\u7528\u7684\u52a0\u5bc6\u6b4c\u8bcd\u65f6\u5c1d\u8bd5\u83b7\u53d6\u666e\u901a\u6b4c\u8bcd", None))
        self.auto_select_checkBox.setText(QCoreApplication.translate("settings", u"\u6b4c\u66f2\u641c\u7d22\u6b4c\u8bcd\u65f6\u81ea\u52a8\u9009\u62e9(\u9177\u72d7\u97f3\u4e50)", None))
        self.groupBox.setTitle(QCoreApplication.translate("settings", u"\u4fdd\u5b58\u8bbe\u7f6e", None))
        self.textBrowser.setHtml(QCoreApplication.translate("settings", u"<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0//EN\" \"http://www.w3.org/TR/REC-html40/strict.dtd\">\n"
"<html><head><meta name=\"qrichtext\" content=\"1\" /><meta charset=\"utf-8\" /><style type=\"text/css\">\n"
"p, li { white-space: pre-wrap; }\n"
"hr { height: 1px; border-width: 0; }\n"
"li.unchecked::marker { content: \"\\2610\"; }\n"
"li.checked::marker { content: \"\\2612\"; }\n"
"</style></head><body style=\" font-family:'Microsoft YaHei UI'; font-size:9pt; font-weight:400; font-style:normal;\">\n"
"<p style=\" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;\">\u4ee5\u4e0b\u5360\u4f4d\u7b26\u53ef\u7528</p>\n"
"<p style=\" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;\"><span style=\" font-size:8pt;\">\u6b4c\u540d: %&lt;title&gt; \u827a\u672f\u5bb6: %&lt;artist&gt;</span></p>\n"
"<p style=\" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; te"
                        "xt-indent:0px;\"><span style=\" font-size:8pt;\">\u4e13\u8f91\u540d: %&lt;album&gt; \u6b4c\u66f2/\u6b4c\u8bcdid: %&lt;id&gt;</span></p>\n"
"<p style=\" margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;\"><span style=\" font-size:8pt;\">\u6b4c\u8bcd\u7c7b\u578b: %&lt;types&gt;</span></p></body></html>", None))
#if QT_CONFIG(whatsthis)
        self.label_2.setWhatsThis("")
#endif // QT_CONFIG(whatsthis)
#if QT_CONFIG(accessibility)
        self.label_2.setAccessibleDescription("")
#endif // QT_CONFIG(accessibility)
        self.label_2.setText(QCoreApplication.translate("settings", u"\u6b4c\u8bcd\u6587\u4ef6\u540d\u683c\u5f0f", None))
        self.label_3.setText(QCoreApplication.translate("settings", u"\u9ed8\u8ba4\u4fdd\u5b58\u8def\u5f84", None))
        self.select_default_save_path_pushButton.setText(QCoreApplication.translate("settings", u"\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.groupBox_3.setTitle(QCoreApplication.translate("settings", u"\u65e5\u5fd7\u8bbe\u7f6e", None))
        self.label_5.setText(QCoreApplication.translate("settings", u"\u65e5\u5fd7\u7b49\u7ea7", None))
        self.log_level_comboBox.setItemText(0, QCoreApplication.translate("settings", u"CRITICAL", None))
        self.log_level_comboBox.setItemText(1, QCoreApplication.translate("settings", u"ERROR", None))
        self.log_level_comboBox.setItemText(2, QCoreApplication.translate("settings", u"WARNING", None))
        self.log_level_comboBox.setItemText(3, QCoreApplication.translate("settings", u"INFO", None))
        self.log_level_comboBox.setItemText(4, QCoreApplication.translate("settings", u"DEBUG", None))
        self.log_level_comboBox.setItemText(5, QCoreApplication.translate("settings", u"NOTSET", None))

    # retranslateUi

