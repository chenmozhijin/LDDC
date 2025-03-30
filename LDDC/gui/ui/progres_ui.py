################################################################################
## Form generated from reading UI file 'progres.ui'
##
## Created by: Qt User Interface Compiler version 6.8.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, QSize
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QLabel, QProgressBar, QVBoxLayout


class Ui_progressDialog:
    def setupUi(self, progressDialog):
        if not progressDialog.objectName():
            progressDialog.setObjectName("progressDialog")
        icon = QIcon()
        icon.addFile(":/LDDC/img/icon/logo.png", QSize(), QIcon.Mode.Normal, QIcon.State.Off)
        progressDialog.setWindowIcon(icon)
        progressDialog.setModal(False)
        self.verticalLayout = QVBoxLayout(progressDialog)
        self.verticalLayout.setObjectName("verticalLayout")
        self.label = QLabel(progressDialog)
        self.label.setObjectName("label")
        self.label.setText("")

        self.verticalLayout.addWidget(self.label)

        self.progressBar = QProgressBar(progressDialog)
        self.progressBar.setObjectName("progressBar")
        self.progressBar.setMaximum(0)
        self.progressBar.setFormat("%v/%m %p%")

        self.verticalLayout.addWidget(self.progressBar)

        self.retranslateUi(progressDialog)

        QMetaObject.connectSlotsByName(progressDialog)

    # setupUi

    def retranslateUi(self, progressDialog):
        progressDialog.setWindowTitle(QCoreApplication.translate("progressDialog", "\u8fdb\u5ea6", None))

    # retranslateUi
