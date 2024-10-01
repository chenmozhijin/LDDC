# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'dir_selector.ui'
##
## Created by: Qt User Interface Compiler version 6.7.2
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
from PySide6.QtWidgets import (QAbstractButton, QApplication, QCheckBox, QDialog,
    QDialogButtonBox, QGridLayout, QLabel, QLineEdit,
    QPushButton, QSizePolicy, QWidget)
import res.resource_rc

class Ui_DirSelectorDialog(object):
    def setupUi(self, DirSelectorDialog):
        if not DirSelectorDialog.objectName():
            DirSelectorDialog.setObjectName(u"DirSelectorDialog")
        DirSelectorDialog.resize(406, 314)
        icon = QIcon()
        icon.addFile(u":/LDDC/img/icon/logo.png", QSize(), QIcon.Mode.Normal, QIcon.State.Off)
        DirSelectorDialog.setWindowIcon(icon)
        self.gridLayout = QGridLayout(DirSelectorDialog)
        self.gridLayout.setObjectName(u"gridLayout")
        self.new_lineEdit = QLineEdit(DirSelectorDialog)
        self.new_lineEdit.setObjectName(u"new_lineEdit")

        self.gridLayout.addWidget(self.new_lineEdit, 1, 1, 1, 1)

        self.label = QLabel(DirSelectorDialog)
        self.label.setObjectName(u"label")

        self.gridLayout.addWidget(self.label, 0, 0, 1, 1)

        self.old_pushButton = QPushButton(DirSelectorDialog)
        self.old_pushButton.setObjectName(u"old_pushButton")

        self.gridLayout.addWidget(self.old_pushButton, 0, 2, 1, 1)

        self.old_lineEdit = QLineEdit(DirSelectorDialog)
        self.old_lineEdit.setObjectName(u"old_lineEdit")

        self.gridLayout.addWidget(self.old_lineEdit, 0, 1, 1, 1)

        self.new_pushButton = QPushButton(DirSelectorDialog)
        self.new_pushButton.setObjectName(u"new_pushButton")

        self.gridLayout.addWidget(self.new_pushButton, 1, 2, 1, 1)

        self.label_2 = QLabel(DirSelectorDialog)
        self.label_2.setObjectName(u"label_2")

        self.gridLayout.addWidget(self.label_2, 1, 0, 1, 1)

        self.buttonBox = QDialogButtonBox(DirSelectorDialog)
        self.buttonBox.setObjectName(u"buttonBox")
        self.buttonBox.setOrientation(Qt.Orientation.Horizontal)
        self.buttonBox.setStandardButtons(QDialogButtonBox.StandardButton.Cancel|QDialogButtonBox.StandardButton.Ok)

        self.gridLayout.addWidget(self.buttonBox, 3, 0, 1, 3)

        self.del_old_checkBox = QCheckBox(DirSelectorDialog)
        self.del_old_checkBox.setObjectName(u"del_old_checkBox")

        self.gridLayout.addWidget(self.del_old_checkBox, 2, 0, 1, 1)


        self.retranslateUi(DirSelectorDialog)
        self.buttonBox.accepted.connect(DirSelectorDialog.accept)
        self.buttonBox.rejected.connect(DirSelectorDialog.reject)

        QMetaObject.connectSlotsByName(DirSelectorDialog)
    # setupUi

    def retranslateUi(self, DirSelectorDialog):
        DirSelectorDialog.setWindowTitle(QCoreApplication.translate("DirSelectorDialog", u"\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.label.setText(QCoreApplication.translate("DirSelectorDialog", u"\u65e7\u6587\u4ef6\u5939:", None))
        self.old_pushButton.setText(QCoreApplication.translate("DirSelectorDialog", u"\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.new_pushButton.setText(QCoreApplication.translate("DirSelectorDialog", u"\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.label_2.setText(QCoreApplication.translate("DirSelectorDialog", u"\u65b0\u6587\u4ef6\u5939:", None))
        self.del_old_checkBox.setText(QCoreApplication.translate("DirSelectorDialog", u"\u5220\u9664\u65e7\u5173\u8054", None))
    # retranslateUi

