################################################################################
## Form generated from reading UI file 'update.ui'
##
## Created by: Qt User Interface Compiler version 6.7.0
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import (
    QCoreApplication,
    QMetaObject,
    Qt,
)
from PySide6.QtWidgets import (
    QDialogButtonBox,
    QLabel,
    QTextBrowser,
    QVBoxLayout,
)


class Ui_UpdateDialog:
    def setupUi(self, UpdateDialog):
        if not UpdateDialog.objectName():
            UpdateDialog.setObjectName("UpdateDialog")
        UpdateDialog.resize(538, 322)
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
        self.buttonBox.setStandardButtons(
            QDialogButtonBox.StandardButton.No | QDialogButtonBox.StandardButton.Yes,
        )

        self.verticalLayout.addWidget(self.buttonBox)

        self.retranslateUi(UpdateDialog)
        self.buttonBox.accepted.connect(UpdateDialog.accept)
        self.buttonBox.rejected.connect(UpdateDialog.reject)

        QMetaObject.connectSlotsByName(UpdateDialog)

    # setupUi

    def retranslateUi(self, UpdateDialog):
        UpdateDialog.setWindowTitle(
            QCoreApplication.translate("UpdateDialog", "Dialog", None),
        )
        self.label.setText(
            QCoreApplication.translate(
                "UpdateDialog",
                "\u53d1\u73b0\u65b0\u7248\u672c\uff0c\u662f\u5426\u524d\u5f80GitHub\u4e0b\u8f7d\u66f4\u65b0\uff1f",
                None,
            ),
        )
        self.textBrowser.setMarkdown("")
        self.textBrowser.setHtml(
            QCoreApplication.translate(
                "UpdateDialog",
                '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN" "http://www.w3.org/TR/REC-html40/strict.dtd">\n'
                '<html><head><meta name="qrichtext" content="1" /><meta charset="utf-8" /><style type="text/css">\n'
                "p, li { white-space: pre-wrap; }\n"
                "hr { height: 1px; border-width: 0; }\n"
                'li.unchecked::marker { content: "\\2610"; }\n'
                'li.checked::marker { content: "\\2612"; }\n'
                "</style></head><body style=\" font-family:'Microsoft YaHei UI'; font-size:9pt; font-weight:400; font-style:normal;\">\n"
                '<p style="-qt-paragraph-type:empty; margin-top:0px; margin-bottom:0px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;"><br /></p></body></html>',
                None,
            ),
        )

    # retranslateUi
