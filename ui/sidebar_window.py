# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金

from PySide6.QtCore import Signal
from PySide6.QtWidgets import (
    QHBoxLayout,
    QMainWindow,
    QPushButton,
    QSizePolicy,
    QSpacerItem,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)


class Position:
    TOP = 0
    BOTTOM = 1


class SidebarWindow(QMainWindow):
    widget_changed = Signal(int)
    def __init__(self) -> None:
        super().__init__()
        self.setup_ui()
        self.Total_Widgets = 0
        self.Top_Widgets = 0
        self.Bottom_Widgets = 0

    def setup_ui(self) -> None:
        self.setObjectName("SidebarWindow")
        self.centralwidget = QWidget(self)
        self.centralwidget.setObjectName("centralwidget")
        self.setCentralWidget(self.centralwidget)
        self.horizontalLayout = QHBoxLayout(self.centralwidget)
        self.horizontalLayout.setObjectName("horizontalLayout")
        self.horizontalLayout.setContentsMargins(0, 0, 0, 0)  # 设置外边距为0
        self.horizontalLayout.setSpacing(0)

        self.sidebar = QVBoxLayout()
        self.Widgets = QTabWidget()
        self.horizontalLayout.addLayout(self.sidebar)
        self.horizontalLayout.addWidget(self.Widgets)
        self.sidebar.setContentsMargins(0, 10, 0, 10)
        self.Widgets.setStyleSheet("QTabBar::tab {height: 0px;}")

        sidebar_spacer = QSpacerItem(40, 20, QSizePolicy.Fixed, QSizePolicy.Expanding)
        self.sidebar.addItem(sidebar_spacer)

    def SidebarButtonClicked(self) -> None:
        sender = self.sender()
        index = sender.property("index")
        self.Widgets.setCurrentIndex(index)
        self.widget_changed.emit(index)
        sender.setChecked(True)
        for i in range(self.sidebar.count()):
            item = self.sidebar.itemAt(i).widget()
            if item != sender and isinstance(item, QPushButton):
                item.setChecked(False)

    def add_widget(self, name: str, widget: QWidget, position:Position = Position.TOP) -> None:
        '''
        添加一个新页面到侧边栏中
        :param name: 页面的名称
        :param widget: 页面的内容
        :param position: 标签页按钮的位置,默认为顶部
        :return: None
        '''
        button = QPushButton(name)
        button.setCheckable(True)
        if self.Total_Widgets == 0:
            button.setChecked(True)
        button.setProperty("index", self.Total_Widgets)
        button.clicked.connect(self.SidebarButtonClicked)
        button.setStyleSheet(
            """
            QPushButton {
                border: none;
                padding: 5px;
                font-size: 16px;
                border-radius: 10px;
            }
            QPushButton:checked {
                background-color: #d9d9d9;
            }
            """,
        )
        if position == Position.TOP:
            self.sidebar.insertWidget(self.Top_Widgets, button)
            self.Top_Widgets += 1
        elif position == Position.BOTTOM:
            self.sidebar.addWidget(button)
            self.Bottom_Widgets += 1
        self.Widgets.addTab(widget, "")
        self.Total_Widgets += 1
