################################################################################
## Form generated from reading UI file 'update.ui'
##
## Created by: Qt User Interface Compiler version 6.8.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, QSize, Qt
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QDialogButtonBox, QLabel, QTextBrowser, QVBoxLayout


class Ui_UpdateDialog:
    def setupUi(self, UpdateDialog):
        if not UpdateDialog.objectName():
            UpdateDialog.setObjectName("UpdateDialog")
        icon = QIcon()
        icon.addFile(":/LDDC/img/icon/logo.png", QSize(), QIcon.Mode.Normal, QIcon.State.Off)
        UpdateDialog.setWindowIcon(icon)
        self.verticalLayout = QVBoxLayout(UpdateDialog)
        self.verticalLayout.setObjectName("verticalLayout")
        self.label = QLabel(UpdateDialog)
        self.label.setObjectName("label")

        self.verticalLayout.addWidget(self.label)

        self.textBrowser = QTextBrowser(UpdateDialog)
        self.textBrowser.setObjectName("textBrowser")
        self.textBrowser.setOpenExternalLinks(True)

        self.verticalLayout.addWidget(self.textBrowser)

        self.buttonBox = QDialogButtonBox(UpdateDialog)
        self.buttonBox.setObjectName("buttonBox")
        self.buttonBox.setOrientation(Qt.Orientation.Horizontal)
        self.buttonBox.setStandardButtons(QDialogButtonBox.StandardButton.No | QDialogButtonBox.StandardButton.Yes)

        self.verticalLayout.addWidget(self.buttonBox)

        self.retranslateUi(UpdateDialog)
        self.buttonBox.accepted.connect(UpdateDialog.accept)
        self.buttonBox.rejected.connect(UpdateDialog.reject)

        QMetaObject.connectSlotsByName(UpdateDialog)

    # setupUi

    def retranslateUi(self, UpdateDialog):
        UpdateDialog.setWindowTitle(QCoreApplication.translate("UpdateDialog", "\u53d1\u73b0\u65b0\u7248\u672c", None))
        self.label.setText(
            QCoreApplication.translate(
                "UpdateDialog", "\u53d1\u73b0\u65b0\u7248\u672c\uff0c\u662f\u5426\u524d\u5f80GitHub\u4e0b\u8f7d\u66f4\u65b0\uff1f", None
            )
        )
        self.textBrowser.setMarkdown("")

    # retranslateUi
