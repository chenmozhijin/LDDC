# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'main.ui'
##
## Created by: Qt User Interface Compiler version 6.6.1
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import (QCoreApplication, QDate, QDateTime, QLocale,
    QMetaObject, QObject, QPoint, QRect,
    QSize, QTime, QUrl, Qt)
from PySide6.QtGui import (QBrush, QColor, QConicalGradient, QCursor,
    QFont, QFontDatabase, QGradient, QIcon,
    QImage, QKeySequence, QLinearGradient, QPainter,
    QPalette, QPixmap, QRadialGradient, QTransform)
from PySide6.QtWidgets import (QAbstractItemView, QAbstractScrollArea, QApplication, QCheckBox,
    QHBoxLayout, QHeaderView, QLabel, QLineEdit,
    QMainWindow, QMenuBar, QPlainTextEdit, QPushButton,
    QSizePolicy, QSpacerItem, QSplitter, QStatusBar,
    QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget)

class Ui_MainWindow(object):
    def setupUi(self, MainWindow):
        if not MainWindow.objectName():
            MainWindow.setObjectName(u"MainWindow")
        MainWindow.setWindowModality(Qt.NonModal)
        MainWindow.resize(1050, 600)
        self.centralwidget = QWidget(MainWindow)
        self.centralwidget.setObjectName(u"centralwidget")
        self.verticalLayout = QVBoxLayout(self.centralwidget)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.label = QLabel(self.centralwidget)
        self.label.setObjectName(u"label")
        sizePolicy = QSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.label.sizePolicy().hasHeightForWidth())
        self.label.setSizePolicy(sizePolicy)
        self.label.setMaximumSize(QSize(16777215, 16777215))
        font = QFont()
        font.setPointSize(18)
        self.label.setFont(font)

        self.verticalLayout.addWidget(self.label)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.label_3 = QLabel(self.centralwidget)
        self.label_3.setObjectName(u"label_3")
        sizePolicy.setHeightForWidth(self.label_3.sizePolicy().hasHeightForWidth())
        self.label_3.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.label_3)

        self.Songname_lineEdit = QLineEdit(self.centralwidget)
        self.Songname_lineEdit.setObjectName(u"Songname_lineEdit")
        sizePolicy.setHeightForWidth(self.Songname_lineEdit.sizePolicy().hasHeightForWidth())
        self.Songname_lineEdit.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.Songname_lineEdit)

        self.horizontalSpacer_2 = QSpacerItem(20, 20, QSizePolicy.Fixed, QSizePolicy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer_2)

        self.Search_pushButton = QPushButton(self.centralwidget)
        self.Search_pushButton.setObjectName(u"Search_pushButton")

        self.horizontalLayout.addWidget(self.Search_pushButton)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Expanding, QSizePolicy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)


        self.verticalLayout.addLayout(self.horizontalLayout)

        self.splitter = QSplitter(self.centralwidget)
        self.splitter.setObjectName(u"splitter")
        sizePolicy1 = QSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.splitter.sizePolicy().hasHeightForWidth())
        self.splitter.setSizePolicy(sizePolicy1)
        self.splitter.setOrientation(Qt.Horizontal)
        self.splitter.setOpaqueResize(True)
        self.splitter.setHandleWidth(5)
        self.splitter.setChildrenCollapsible(False)
        self.layoutWidget = QWidget(self.splitter)
        self.layoutWidget.setObjectName(u"layoutWidget")
        self.verticalLayout_3 = QVBoxLayout(self.layoutWidget)
        self.verticalLayout_3.setObjectName(u"verticalLayout_3")
        self.verticalLayout_3.setContentsMargins(0, 0, 0, 0)
        self.label_7 = QLabel(self.layoutWidget)
        self.label_7.setObjectName(u"label_7")
        sizePolicy.setHeightForWidth(self.label_7.sizePolicy().hasHeightForWidth())
        self.label_7.setSizePolicy(sizePolicy)
        font1 = QFont()
        font1.setPointSize(14)
        self.label_7.setFont(font1)

        self.verticalLayout_3.addWidget(self.label_7)

        self.Searchresults_tableWidget = QTableWidget(self.layoutWidget)
        if (self.Searchresults_tableWidget.columnCount() < 5):
            self.Searchresults_tableWidget.setColumnCount(5)
        __qtablewidgetitem = QTableWidgetItem()
        self.Searchresults_tableWidget.setHorizontalHeaderItem(0, __qtablewidgetitem)
        __qtablewidgetitem1 = QTableWidgetItem()
        self.Searchresults_tableWidget.setHorizontalHeaderItem(1, __qtablewidgetitem1)
        __qtablewidgetitem2 = QTableWidgetItem()
        self.Searchresults_tableWidget.setHorizontalHeaderItem(2, __qtablewidgetitem2)
        __qtablewidgetitem3 = QTableWidgetItem()
        self.Searchresults_tableWidget.setHorizontalHeaderItem(3, __qtablewidgetitem3)
        __qtablewidgetitem4 = QTableWidgetItem()
        self.Searchresults_tableWidget.setHorizontalHeaderItem(4, __qtablewidgetitem4)
        self.Searchresults_tableWidget.setObjectName(u"Searchresults_tableWidget")
        sizePolicy1.setHeightForWidth(self.Searchresults_tableWidget.sizePolicy().hasHeightForWidth())
        self.Searchresults_tableWidget.setSizePolicy(sizePolicy1)
        self.Searchresults_tableWidget.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOn)
        self.Searchresults_tableWidget.setSizeAdjustPolicy(QAbstractScrollArea.AdjustIgnored)
        self.Searchresults_tableWidget.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.Searchresults_tableWidget.setSelectionMode(QAbstractItemView.SingleSelection)
        self.Searchresults_tableWidget.setSelectionBehavior(QAbstractItemView.SelectRows)

        self.verticalLayout_3.addWidget(self.Searchresults_tableWidget)

        self.splitter.addWidget(self.layoutWidget)
        self.layoutWidget_2 = QWidget(self.splitter)
        self.layoutWidget_2.setObjectName(u"layoutWidget_2")
        self.verticalLayout_8 = QVBoxLayout(self.layoutWidget_2)
        self.verticalLayout_8.setObjectName(u"verticalLayout_8")
        self.verticalLayout_8.setContentsMargins(0, 0, 0, 0)
        self.label_8 = QLabel(self.layoutWidget_2)
        self.label_8.setObjectName(u"label_8")
        sizePolicy.setHeightForWidth(self.label_8.sizePolicy().hasHeightForWidth())
        self.label_8.setSizePolicy(sizePolicy)
        self.label_8.setFont(font1)

        self.verticalLayout_8.addWidget(self.label_8)

        self.preview_plainTextEdit = QPlainTextEdit(self.layoutWidget_2)
        self.preview_plainTextEdit.setObjectName(u"preview_plainTextEdit")
        sizePolicy2 = QSizePolicy(QSizePolicy.MinimumExpanding, QSizePolicy.Expanding)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.preview_plainTextEdit.sizePolicy().hasHeightForWidth())
        self.preview_plainTextEdit.setSizePolicy(sizePolicy2)
        self.preview_plainTextEdit.setLineWrapMode(QPlainTextEdit.NoWrap)
        self.preview_plainTextEdit.setReadOnly(True)

        self.verticalLayout_8.addWidget(self.preview_plainTextEdit)

        self.splitter.addWidget(self.layoutWidget_2)

        self.verticalLayout.addWidget(self.splitter)

        self.horizontalLayout_3 = QHBoxLayout()
        self.horizontalLayout_3.setObjectName(u"horizontalLayout_3")
        self.verticalLayout_7 = QVBoxLayout()
        self.verticalLayout_7.setObjectName(u"verticalLayout_7")
        self.horizontalLayout_4 = QHBoxLayout()
        self.horizontalLayout_4.setObjectName(u"horizontalLayout_4")
        self.label_6 = QLabel(self.centralwidget)
        self.label_6.setObjectName(u"label_6")
        sizePolicy3 = QSizePolicy(QSizePolicy.Fixed, QSizePolicy.Preferred)
        sizePolicy3.setHorizontalStretch(0)
        sizePolicy3.setVerticalStretch(0)
        sizePolicy3.setHeightForWidth(self.label_6.sizePolicy().hasHeightForWidth())
        self.label_6.setSizePolicy(sizePolicy3)

        self.horizontalLayout_4.addWidget(self.label_6)

        self.path_lineEdit = QLineEdit(self.centralwidget)
        self.path_lineEdit.setObjectName(u"path_lineEdit")
        sizePolicy4 = QSizePolicy(QSizePolicy.MinimumExpanding, QSizePolicy.Fixed)
        sizePolicy4.setHorizontalStretch(0)
        sizePolicy4.setVerticalStretch(0)
        sizePolicy4.setHeightForWidth(self.path_lineEdit.sizePolicy().hasHeightForWidth())
        self.path_lineEdit.setSizePolicy(sizePolicy4)

        self.horizontalLayout_4.addWidget(self.path_lineEdit)

        self.Selectpath_pushButton = QPushButton(self.centralwidget)
        self.Selectpath_pushButton.setObjectName(u"Selectpath_pushButton")
        sizePolicy.setHeightForWidth(self.Selectpath_pushButton.sizePolicy().hasHeightForWidth())
        self.Selectpath_pushButton.setSizePolicy(sizePolicy)

        self.horizontalLayout_4.addWidget(self.Selectpath_pushButton)


        self.verticalLayout_7.addLayout(self.horizontalLayout_4)

        self.horizontalLayout_2 = QHBoxLayout()
        self.horizontalLayout_2.setObjectName(u"horizontalLayout_2")
        self.Translate_checkBox = QCheckBox(self.centralwidget)
        self.Translate_checkBox.setObjectName(u"Translate_checkBox")
        sizePolicy.setHeightForWidth(self.Translate_checkBox.sizePolicy().hasHeightForWidth())
        self.Translate_checkBox.setSizePolicy(sizePolicy)

        self.horizontalLayout_2.addWidget(self.Translate_checkBox, 0, Qt.AlignLeft)

        self.Romanized_checkBox = QCheckBox(self.centralwidget)
        self.Romanized_checkBox.setObjectName(u"Romanized_checkBox")
        sizePolicy.setHeightForWidth(self.Romanized_checkBox.sizePolicy().hasHeightForWidth())
        self.Romanized_checkBox.setSizePolicy(sizePolicy)

        self.horizontalLayout_2.addWidget(self.Romanized_checkBox, 0, Qt.AlignLeft)


        self.verticalLayout_7.addLayout(self.horizontalLayout_2)

        self.lyric_info_label = QLabel(self.centralwidget)
        self.lyric_info_label.setObjectName(u"lyric_info_label")

        self.verticalLayout_7.addWidget(self.lyric_info_label)

        self.verticalSpacer = QSpacerItem(20, 40, QSizePolicy.Minimum, QSizePolicy.Preferred)

        self.verticalLayout_7.addItem(self.verticalSpacer)

        self.program_info_label = QLabel(self.centralwidget)
        self.program_info_label.setObjectName(u"program_info_label")

        self.verticalLayout_7.addWidget(self.program_info_label)


        self.horizontalLayout_3.addLayout(self.verticalLayout_7)

        self.horizontalSpacer_3 = QSpacerItem(97, 20, QSizePolicy.Maximum, QSizePolicy.Minimum)

        self.horizontalLayout_3.addItem(self.horizontalSpacer_3)

        self.Save_pushButton = QPushButton(self.centralwidget)
        self.Save_pushButton.setObjectName(u"Save_pushButton")
        sizePolicy5 = QSizePolicy(QSizePolicy.Expanding, QSizePolicy.Maximum)
        sizePolicy5.setHorizontalStretch(0)
        sizePolicy5.setVerticalStretch(0)
        sizePolicy5.setHeightForWidth(self.Save_pushButton.sizePolicy().hasHeightForWidth())
        self.Save_pushButton.setSizePolicy(sizePolicy5)
        self.Save_pushButton.setMinimumSize(QSize(92, 85))

        self.horizontalLayout_3.addWidget(self.Save_pushButton)


        self.verticalLayout.addLayout(self.horizontalLayout_3)

        MainWindow.setCentralWidget(self.centralwidget)
        self.menubar = QMenuBar(MainWindow)
        self.menubar.setObjectName(u"menubar")
        self.menubar.setGeometry(QRect(0, 0, 1050, 21))
        sizePolicy6 = QSizePolicy(QSizePolicy.Preferred, QSizePolicy.Minimum)
        sizePolicy6.setHorizontalStretch(0)
        sizePolicy6.setVerticalStretch(0)
        sizePolicy6.setHeightForWidth(self.menubar.sizePolicy().hasHeightForWidth())
        self.menubar.setSizePolicy(sizePolicy6)
        MainWindow.setMenuBar(self.menubar)
        self.statusbar = QStatusBar(MainWindow)
        self.statusbar.setObjectName(u"statusbar")
        MainWindow.setStatusBar(self.statusbar)

        self.retranslateUi(MainWindow)

        QMetaObject.connectSlotsByName(MainWindow)
    # setupUi

    def retranslateUi(self, MainWindow):
        MainWindow.setWindowTitle(QCoreApplication.translate("MainWindow", u"LDDC", None))
        self.label.setText(QCoreApplication.translate("MainWindow", u"LDDC", None))
        self.label_3.setText(QCoreApplication.translate("MainWindow", u"\u6b4c\u66f2\u540d\uff1a", None))
        self.Search_pushButton.setText(QCoreApplication.translate("MainWindow", u"\u641c\u7d22", None))
        self.label_7.setText(QCoreApplication.translate("MainWindow", u"\u641c\u7d22\u7ed3\u679c", None))
        ___qtablewidgetitem = self.Searchresults_tableWidget.horizontalHeaderItem(0)
        ___qtablewidgetitem.setText(QCoreApplication.translate("MainWindow", u"\u4e0b\u8f7d&\u9884\u89c8", None));
        ___qtablewidgetitem1 = self.Searchresults_tableWidget.horizontalHeaderItem(1)
        ___qtablewidgetitem1.setText(QCoreApplication.translate("MainWindow", u"\u6b4c\u66f2\u540d", None));
        ___qtablewidgetitem2 = self.Searchresults_tableWidget.horizontalHeaderItem(2)
        ___qtablewidgetitem2.setText(QCoreApplication.translate("MainWindow", u"\u827a\u672f\u5bb6", None));
        ___qtablewidgetitem3 = self.Searchresults_tableWidget.horizontalHeaderItem(3)
        ___qtablewidgetitem3.setText(QCoreApplication.translate("MainWindow", u"\u4e13\u8f91", None));
        ___qtablewidgetitem4 = self.Searchresults_tableWidget.horizontalHeaderItem(4)
        ___qtablewidgetitem4.setText(QCoreApplication.translate("MainWindow", u"\u6b4c\u66f2id", None));
        self.label_8.setText(QCoreApplication.translate("MainWindow", u"\u6b4c\u8bcd\u9884\u89c8", None))
        self.label_6.setText(QCoreApplication.translate("MainWindow", u"\u4fdd\u5b58\u5230:", None))
        self.Selectpath_pushButton.setText(QCoreApplication.translate("MainWindow", u"\u9009\u62e9\u4fdd\u5b58\u8def\u5f84", None))
        self.Translate_checkBox.setText(QCoreApplication.translate("MainWindow", u"\u8bd1\u6587", None))
        self.Romanized_checkBox.setText(QCoreApplication.translate("MainWindow", u"\u7f57\u9a6c\u97f3", None))
        self.lyric_info_label.setText(QCoreApplication.translate("MainWindow", u"\u6b4c\u8bcd\u4fe1\u606f\uff1a\u65e0", None))
        self.program_info_label.setText(QCoreApplication.translate("MainWindow", u"\u00a9 2024 \u6c89\u9ed8\u306e\u91d1 \u7248\u672c\uff1a", None))
        self.Save_pushButton.setText(QCoreApplication.translate("MainWindow", u"\u4fdd\u5b58", None))
    # retranslateUi

