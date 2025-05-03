################################################################################
## Form generated from reading UI file 'about.ui'
##
## Created by: Qt User Interface Compiler version 6.8.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, Qt
from PySide6.QtGui import QFont
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QSizePolicy, QSpacerItem, QVBoxLayout


class Ui_about:
    def setupUi(self, about):
        if not about.objectName():
            about.setObjectName("about")
        self.verticalLayout = QVBoxLayout(about)
        self.verticalLayout.setObjectName("verticalLayout")
        self.title_label = QLabel(about)
        self.title_label.setObjectName("title_label")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.title_label.sizePolicy().hasHeightForWidth())
        self.title_label.setSizePolicy(sizePolicy)
        font = QFont()
        font.setPointSize(18)
        self.title_label.setFont(font)

        self.verticalLayout.addWidget(self.title_label)

        self.verticalSpacer_2 = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Fixed)

        self.verticalLayout.addItem(self.verticalSpacer_2)

        self.label = QLabel(about)
        self.label.setObjectName("label")
        font1 = QFont()
        font1.setPointSize(16)
        self.label.setFont(font1)

        self.verticalLayout.addWidget(self.label, 0, Qt.AlignmentFlag.AlignHCenter)

        self.version_label = QLabel(about)
        self.version_label.setObjectName("version_label")

        self.verticalLayout.addWidget(self.version_label, 0, Qt.AlignmentFlag.AlignHCenter)

        self.horizontalLayout = QHBoxLayout()
        self.horizontalLayout.setObjectName("horizontalLayout")
        self.horizontalSpacer_2 = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer_2)

        self.github_pushButton = QPushButton(about)
        self.github_pushButton.setObjectName("github_pushButton")
        sizePolicy.setHeightForWidth(self.github_pushButton.sizePolicy().hasHeightForWidth())
        self.github_pushButton.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.github_pushButton)

        self.checkupdate_pushButton = QPushButton(about)
        self.checkupdate_pushButton.setObjectName("checkupdate_pushButton")
        sizePolicy.setHeightForWidth(self.checkupdate_pushButton.sizePolicy().hasHeightForWidth())
        self.checkupdate_pushButton.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.checkupdate_pushButton)

        self.githubissues_pushButton = QPushButton(about)
        self.githubissues_pushButton.setObjectName("githubissues_pushButton")
        sizePolicy.setHeightForWidth(self.githubissues_pushButton.sizePolicy().hasHeightForWidth())
        self.githubissues_pushButton.setSizePolicy(sizePolicy)

        self.horizontalLayout.addWidget(self.githubissues_pushButton)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)

        self.verticalLayout.addLayout(self.horizontalLayout)

        self.verticalSpacer = QSpacerItem(20, 40, QSizePolicy.Policy.Minimum, QSizePolicy.Policy.Expanding)

        self.verticalLayout.addItem(self.verticalSpacer)

        self.retranslateUi(about)

        QMetaObject.connectSlotsByName(about)

    # setupUi

    def retranslateUi(self, about):
        self.title_label.setText(QCoreApplication.translate("about", "\u5173\u4e8e", None))
        self.label.setText(
            QCoreApplication.translate(
                "about",
                '<html><head/><body><p align="center"><img src=":/LDDC/img/icon/logo.png" width="50" height="50" style="vertical-align: middle;"/><span style=" font-size:38pt;">LDDC</span></p><p align="right"><span style=" font-size:6pt;">\u00a9 {year} \u6c89\u9ed8\u306e\u91d1</span></p><p align="center"><span style=" font-size:12pt;">\u5b9e\u7528\u7684\u7cbe\u51c6\u6b4c\u8bcd\u4e0b\u8f7d\u5de5\u5177</span></p></body></html>',
                None,
            )
        )
        self.version_label.setText(QCoreApplication.translate("about", "\u7248\u672c | ", None))
        self.github_pushButton.setText(QCoreApplication.translate("about", "GitHub\u4ed3\u5e93", None))
        self.checkupdate_pushButton.setText(QCoreApplication.translate("about", "\u68c0\u67e5\u66f4\u65b0", None))
        self.githubissues_pushButton.setText(QCoreApplication.translate("about", "\u95ee\u9898\u53cd\u9988", None))

    # retranslateUi
