################################################################################
## Form generated from reading UI file 'local_song_lyrics_db_manager.ui'
##
## Created by: Qt User Interface Compiler version 6.8.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import QCoreApplication, QMetaObject, QSize
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QAbstractItemView, QGridLayout, QPushButton

from LDDC.gui.components.custom_widgets import ProportionallyStretchedTableWidget


class Ui_LocalSongLyricsDBManager:
    def setupUi(self, LocalSongLyricsDBManager):
        if not LocalSongLyricsDBManager.objectName():
            LocalSongLyricsDBManager.setObjectName("LocalSongLyricsDBManager")
        LocalSongLyricsDBManager.resize(640, 720)
        icon = QIcon()
        icon.addFile(":/LDDC/img/icon/logo.png", QSize(), QIcon.Mode.Normal, QIcon.State.Off)
        LocalSongLyricsDBManager.setWindowIcon(icon)
        self.gridLayout = QGridLayout(LocalSongLyricsDBManager)
        self.gridLayout.setObjectName("gridLayout")
        self.clear_button = QPushButton(LocalSongLyricsDBManager)
        self.clear_button.setObjectName("clear_button")

        self.gridLayout.addWidget(self.clear_button, 1, 1, 1, 1)

        self.change_dir_button = QPushButton(LocalSongLyricsDBManager)
        self.change_dir_button.setObjectName("change_dir_button")

        self.gridLayout.addWidget(self.change_dir_button, 1, 2, 1, 1)

        self.delete_all_button = QPushButton(LocalSongLyricsDBManager)
        self.delete_all_button.setObjectName("delete_all_button")

        self.gridLayout.addWidget(self.delete_all_button, 1, 3, 1, 1)

        self.backup_button = QPushButton(LocalSongLyricsDBManager)
        self.backup_button.setObjectName("backup_button")

        self.gridLayout.addWidget(self.backup_button, 1, 4, 1, 1)

        self.delete_button = QPushButton(LocalSongLyricsDBManager)
        self.delete_button.setObjectName("delete_button")

        self.gridLayout.addWidget(self.delete_button, 1, 0, 1, 1)

        self.export_lyrics_button = QPushButton(LocalSongLyricsDBManager)
        self.export_lyrics_button.setObjectName("export_lyrics_button")

        self.gridLayout.addWidget(self.export_lyrics_button, 1, 6, 1, 1)

        self.restore_button = QPushButton(LocalSongLyricsDBManager)
        self.restore_button.setObjectName("restore_button")

        self.gridLayout.addWidget(self.restore_button, 1, 5, 1, 1)

        self.data_table = ProportionallyStretchedTableWidget(LocalSongLyricsDBManager)
        self.data_table.setObjectName("data_table")
        self.data_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.data_table.setSelectionMode(QAbstractItemView.SelectionMode.MultiSelection)
        self.data_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)

        self.gridLayout.addWidget(self.data_table, 0, 0, 1, 7)

        self.retranslateUi(LocalSongLyricsDBManager)

        QMetaObject.connectSlotsByName(LocalSongLyricsDBManager)

    # setupUi

    def retranslateUi(self, LocalSongLyricsDBManager):
        LocalSongLyricsDBManager.setWindowTitle(QCoreApplication.translate("LocalSongLyricsDBManager", "\u6b4c\u8bcd\u5173\u8054\u7ba1\u7406\u5668", None))
        self.clear_button.setText(QCoreApplication.translate("LocalSongLyricsDBManager", "\u6e05\u7406\u65e0\u6548\u5173\u8054", None))
        self.change_dir_button.setText(QCoreApplication.translate("LocalSongLyricsDBManager", "\u6279\u91cf\u53d8\u66f4\u76ee\u5f55", None))
        self.delete_all_button.setText(QCoreApplication.translate("LocalSongLyricsDBManager", "\u6e05\u7a7a", None))
        self.backup_button.setText(QCoreApplication.translate("LocalSongLyricsDBManager", "\u5907\u4efd", None))
        self.delete_button.setText(QCoreApplication.translate("LocalSongLyricsDBManager", "\u5220\u9664", None))
        self.export_lyrics_button.setText(QCoreApplication.translate("LocalSongLyricsDBManager", "\u5bfc\u51fa\u6b4c\u8bcd", None))
        self.restore_button.setText(QCoreApplication.translate("LocalSongLyricsDBManager", "\u6062\u590d", None))

    # retranslateUi
