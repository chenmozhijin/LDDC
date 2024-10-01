# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'update.ui'
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
from PySide6.QtWidgets import (QAbstractButton, QApplication, QDialog, QDialogButtonBox,
    QLabel, QSizePolicy, QTextBrowser, QVBoxLayout,
    QWidget)
import res.resource_rc

class Ui_UpdateDialog(object):
    def setupUi(self, UpdateDialog):
        if not UpdateDialog.objectName():
            UpdateDialog.setObjectName(u"UpdateDialog")
        UpdateDialog.resize(538, 322)
        icon = QIcon()
        icon.addFile(u":/LDDC/img/icon/logo.png", QSize(), QIcon.Mode.Normal, QIcon.State.Off)
        UpdateDialog.setWindowIcon(icon)
        self.verticalLayout = QVBoxLayout(UpdateDialog)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.label = QLabel(UpdateDialog)
        self.label.setObjectName(u"label")

        self.verticalLayout.addWidget(self.label)

        self.textBrowser = QTextBrowser(UpdateDialog)
        self.textBrowser.setObjectName(u"textBrowser")
        self.textBrowser.setOpenExternalLinks(True)

        self.verticalLayout.addWidget(self.textBrowser)

        self.buttonBox = QDialogButtonBox(UpdateDialog)
        self.buttonBox.setObjectName(u"buttonBox")
        self.buttonBox.setOrientation(Qt.Orientation.Horizontal)
        self.buttonBox.setStandardButtons(QDialogButtonBox.StandardButton.No|QDialogButtonBox.StandardButton.Yes)

        self.verticalLayout.addWidget(self.buttonBox)


        self.retranslateUi(UpdateDialog)
        self.buttonBox.accepted.connect(UpdateDialog.accept)
        self.buttonBox.rejected.connect(UpdateDialog.reject)

        QMetaObject.connectSlotsByName(UpdateDialog)
    # setupUi

    def retranslateUi(self, UpdateDialog):
        UpdateDialog.setWindowTitle(QCoreApplication.translate("UpdateDialog", u"\u53d1\u73b0\u65b0\u7248\u672c", None))
        self.label.setText(QCoreApplication.translate("UpdateDialog", u"\u53d1\u73b0\u65b0\u7248\u672c\uff0c\u662f\u5426\u524d\u5f80GitHub\u4e0b\u8f7d\u66f4\u65b0\uff1f", None))
        self.textBrowser.setMarkdown("")
    # retranslateUi

