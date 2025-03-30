
################################################################################
## Form generated from reading UI file 'dir_selector.ui'
##
## Created by: Qt User Interface Compiler version 6.8.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, QSize, Qt
from PySide6.QtGui import (
    QIcon,
)
from PySide6.QtWidgets import (
    QCheckBox,
    QDialogButtonBox,
    QGridLayout,
    QLabel,
    QLineEdit,
    QPushButton,
)


class Ui_DirSelectorDialog:
    def setupUi(self, DirSelectorDialog):
        if not DirSelectorDialog.objectName():
            DirSelectorDialog.setObjectName("DirSelectorDialog")
        icon = QIcon()
        icon.addFile(":/LDDC/img/icon/logo.png", QSize(), QIcon.Mode.Normal, QIcon.State.Off)
        DirSelectorDialog.setWindowIcon(icon)
        self.gridLayout = QGridLayout(DirSelectorDialog)
        self.gridLayout.setObjectName("gridLayout")
        self.new_lineEdit = QLineEdit(DirSelectorDialog)
        self.new_lineEdit.setObjectName("new_lineEdit")

        self.gridLayout.addWidget(self.new_lineEdit, 1, 1, 1, 1)

        self.label = QLabel(DirSelectorDialog)
        self.label.setObjectName("label")

        self.gridLayout.addWidget(self.label, 0, 0, 1, 1)

        self.old_pushButton = QPushButton(DirSelectorDialog)
        self.old_pushButton.setObjectName("old_pushButton")

        self.gridLayout.addWidget(self.old_pushButton, 0, 2, 1, 1)

        self.old_lineEdit = QLineEdit(DirSelectorDialog)
        self.old_lineEdit.setObjectName("old_lineEdit")

        self.gridLayout.addWidget(self.old_lineEdit, 0, 1, 1, 1)

        self.new_pushButton = QPushButton(DirSelectorDialog)
        self.new_pushButton.setObjectName("new_pushButton")

        self.gridLayout.addWidget(self.new_pushButton, 1, 2, 1, 1)

        self.label_2 = QLabel(DirSelectorDialog)
        self.label_2.setObjectName("label_2")

        self.gridLayout.addWidget(self.label_2, 1, 0, 1, 1)

        self.buttonBox = QDialogButtonBox(DirSelectorDialog)
        self.buttonBox.setObjectName("buttonBox")
        self.buttonBox.setOrientation(Qt.Orientation.Horizontal)
        self.buttonBox.setStandardButtons(QDialogButtonBox.StandardButton.Cancel | QDialogButtonBox.StandardButton.Ok)

        self.gridLayout.addWidget(self.buttonBox, 3, 0, 1, 3)

        self.del_old_checkBox = QCheckBox(DirSelectorDialog)
        self.del_old_checkBox.setObjectName("del_old_checkBox")

        self.gridLayout.addWidget(self.del_old_checkBox, 2, 0, 1, 1)

        self.retranslateUi(DirSelectorDialog)
        self.buttonBox.accepted.connect(DirSelectorDialog.accept)
        self.buttonBox.rejected.connect(DirSelectorDialog.reject)

        QMetaObject.connectSlotsByName(DirSelectorDialog)

    # setupUi

    def retranslateUi(self, DirSelectorDialog):
        DirSelectorDialog.setWindowTitle(QCoreApplication.translate("DirSelectorDialog", "\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.label.setText(QCoreApplication.translate("DirSelectorDialog", "\u65e7\u6587\u4ef6\u5939:", None))
        self.old_pushButton.setText(QCoreApplication.translate("DirSelectorDialog", "\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.new_pushButton.setText(QCoreApplication.translate("DirSelectorDialog", "\u9009\u62e9\u6587\u4ef6\u5939", None))
        self.label_2.setText(QCoreApplication.translate("DirSelectorDialog", "\u65b0\u6587\u4ef6\u5939:", None))
        self.del_old_checkBox.setText(QCoreApplication.translate("DirSelectorDialog", "\u5220\u9664\u65e7\u5173\u8054", None))

    # retranslateUi
