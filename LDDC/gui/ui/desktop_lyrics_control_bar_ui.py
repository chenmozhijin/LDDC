################################################################################
## Form generated from reading UI file 'desktop_lyrics_control_bar.ui'
##
## Created by: Qt User Interface Compiler version 6.8.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, Qt
from PySide6.QtGui import QCursor, QIcon
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QSizePolicy, QSpacerItem


class Ui_DesktopLyricsControlBar:
    def setupUi(self, DesktopLyricsControlBar):
        if not DesktopLyricsControlBar.objectName():
            DesktopLyricsControlBar.setObjectName("DesktopLyricsControlBar")
        DesktopLyricsControlBar.setMouseTracking(True)
        self.horizontalLayout = QHBoxLayout(DesktopLyricsControlBar)
        self.horizontalLayout.setSpacing(0)
        self.horizontalLayout.setObjectName("horizontalLayout")
        self.horizontalLayout.setContentsMargins(0, 0, 0, 0)
        self.info_label = QLabel(DesktopLyricsControlBar)
        self.info_label.setObjectName("info_label")
        self.info_label.setLineWidth(0)
        self.info_label.setTextInteractionFlags(Qt.TextInteractionFlag.NoTextInteraction)

        self.horizontalLayout.addWidget(self.info_label)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)

        self.perv_button = QPushButton(DesktopLyricsControlBar)
        self.perv_button.setObjectName("perv_button")
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(self.perv_button.sizePolicy().hasHeightForWidth())
        self.perv_button.setSizePolicy(sizePolicy)
        self.perv_button.setCursor(QCursor(Qt.CursorShape.ArrowCursor))
        self.perv_button.setMouseTracking(True)
        icon = QIcon(QIcon.fromTheme(QIcon.ThemeIcon.GoPrevious))
        self.perv_button.setIcon(icon)

        self.horizontalLayout.addWidget(self.perv_button)

        self.play_pause_button = QPushButton(DesktopLyricsControlBar)
        self.play_pause_button.setObjectName("play_pause_button")
        sizePolicy.setHeightForWidth(self.play_pause_button.sizePolicy().hasHeightForWidth())
        self.play_pause_button.setSizePolicy(sizePolicy)
        self.play_pause_button.setCursor(QCursor(Qt.CursorShape.ArrowCursor))
        self.play_pause_button.setMouseTracking(True)
        self.play_pause_button.setText("")
        icon1 = QIcon(QIcon.fromTheme(QIcon.ThemeIcon.MediaPlaybackStart))
        self.play_pause_button.setIcon(icon1)

        self.horizontalLayout.addWidget(self.play_pause_button)

        self.next_button = QPushButton(DesktopLyricsControlBar)
        self.next_button.setObjectName("next_button")
        sizePolicy.setHeightForWidth(self.next_button.sizePolicy().hasHeightForWidth())
        self.next_button.setSizePolicy(sizePolicy)
        self.next_button.setCursor(QCursor(Qt.CursorShape.ArrowCursor))
        self.next_button.setMouseTracking(True)
        self.next_button.setText("")
        icon2 = QIcon(QIcon.fromTheme(QIcon.ThemeIcon.GoNext))
        self.next_button.setIcon(icon2)

        self.horizontalLayout.addWidget(self.next_button)

        self.select_button = QPushButton(DesktopLyricsControlBar)
        self.select_button.setObjectName("select_button")
        sizePolicy.setHeightForWidth(self.select_button.sizePolicy().hasHeightForWidth())
        self.select_button.setSizePolicy(sizePolicy)
        self.select_button.setCursor(QCursor(Qt.CursorShape.ArrowCursor))
        self.select_button.setMouseTracking(True)
        self.select_button.setText("")
        icon3 = QIcon(QIcon.fromTheme(QIcon.ThemeIcon.SystemSearch))
        self.select_button.setIcon(icon3)

        self.horizontalLayout.addWidget(self.select_button)

        self.close_button = QPushButton(DesktopLyricsControlBar)
        self.close_button.setObjectName("close_button")
        sizePolicy.setHeightForWidth(self.close_button.sizePolicy().hasHeightForWidth())
        self.close_button.setSizePolicy(sizePolicy)
        self.close_button.setCursor(QCursor(Qt.CursorShape.ArrowCursor))
        self.close_button.setMouseTracking(True)
        self.close_button.setText("")
        icon4 = QIcon(QIcon.fromTheme(QIcon.ThemeIcon.WindowClose))
        self.close_button.setIcon(icon4)

        self.horizontalLayout.addWidget(self.close_button)

        self.retranslateUi(DesktopLyricsControlBar)

        QMetaObject.connectSlotsByName(DesktopLyricsControlBar)

    # setupUi

    def retranslateUi(self, DesktopLyricsControlBar):
        self.info_label.setText("")
        # if QT_CONFIG(tooltip)
        self.perv_button.setToolTip(QCoreApplication.translate("DesktopLyricsControlBar", "\u4e0a\u4e00\u9996", None))
        # endif // QT_CONFIG(tooltip)
        # if QT_CONFIG(tooltip)
        self.play_pause_button.setToolTip(QCoreApplication.translate("DesktopLyricsControlBar", "\u64ad\u653e/\u505c\u6b62", None))
        # endif // QT_CONFIG(tooltip)
        # if QT_CONFIG(tooltip)
        self.next_button.setToolTip(QCoreApplication.translate("DesktopLyricsControlBar", "\u4e0b\u4e00\u9996", None))
        # endif // QT_CONFIG(tooltip)
        # if QT_CONFIG(tooltip)
        self.select_button.setToolTip(QCoreApplication.translate("DesktopLyricsControlBar", "\u9009\u62e9\u6b4c\u8bcd", None))
        # endif // QT_CONFIG(tooltip)
        # if QT_CONFIG(tooltip)
        self.close_button.setToolTip(QCoreApplication.translate("DesktopLyricsControlBar", "\u9690\u85cf\u7a97\u53e3", None))


# endif // QT_CONFIG(tooltip)
# retranslateUi
