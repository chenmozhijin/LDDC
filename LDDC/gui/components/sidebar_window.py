# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from PySide6.QtCore import QEvent, Qt, Signal, Slot
from PySide6.QtGui import QIcon
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

from LDDC.common.models import Direction


class SidebarWindow(QMainWindow):
    widget_changed = Signal(int)

    def __init__(self) -> None:
        super().__init__()
        self.__setup_ui()
        self.Total_Widgets = 0
        self.Top_Widgets = 0
        self.Bottom_Widgets = 0
        self.current_widget = 0

    def __setup_ui(self) -> None:
        self.setObjectName("SidebarWindow")
        self.centralwidget = QWidget(self)
        self.centralwidget.setObjectName("centralwidget")
        self.setCentralWidget(self.centralwidget)
        self.horizontalLayout = QHBoxLayout(self.centralwidget)
        self.horizontalLayout.setObjectName("horizontalLayout")
        self.horizontalLayout.setContentsMargins(0, 0, 0, 0)  # 设置外边距为0
        self.horizontalLayout.setSpacing(0)

        self.sidebar_widget = QWidget(self)
        self.sidebar = QVBoxLayout(self.sidebar_widget)
        self.Widgets = QTabWidget(self)
        self.horizontalLayout.addWidget(self.sidebar_widget)
        self.horizontalLayout.addWidget(self.Widgets)
        self.sidebar.setContentsMargins(0, 10, 0, 10)
        self.Widgets.tabBar().hide()

        self.__sidebar_spacer = QSpacerItem(40, 20, QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Expanding)
        self.sidebar.addItem(self.__sidebar_spacer)

    def set_current_widget(self, index: int) -> None:
        self.current_widget = index
        current_button = self.sidebar.itemAt(index + 1).widget() if index >= self.Top_Widgets else self.sidebar.itemAt(index).widget()
        if not isinstance(current_button, QPushButton):
            return
        self.Widgets.setCurrentIndex(index)
        self.widget_changed.emit(index)
        current_button.setChecked(True)
        for i in range(self.sidebar.count()):
            item = self.sidebar.itemAt(i).widget()
            if item != current_button and isinstance(item, QPushButton):
                item.setChecked(False)

    @Slot()
    def SidebarButtonClicked(self) -> None:
        sender = self.sender()
        index = sender.property("index")
        self.set_current_widget(index)

    def set_sidebar_width(self, width: int) -> None:
        self.sidebar_widget.setFixedWidth(width)

    def add_widget(self, name: str, widget: QWidget, position: Direction = Direction.TOP, icon: None | QIcon = None) -> None:
        """添加一个新页面到侧边栏中

        :param name: 页面的名称
        :param widget: 页面的内容
        :param position: 标签页按钮的位置,默认为顶部
        :return: None
        """
        button = QPushButton(name, self.sidebar_widget)
        button.setLayoutDirection(Qt.LayoutDirection.LeftToRight)
        if isinstance(icon, QIcon):
            button.setIcon(icon)
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
        if position == Direction.TOP:
            self.sidebar.insertWidget(self.Top_Widgets, button)
            self.Top_Widgets += 1
        elif position == Direction.BOTTOM:
            self.sidebar.addWidget(button)
            self.Bottom_Widgets += 1
        widget.setParent(self.Widgets)
        self.Widgets.addTab(widget, "")
        self.Total_Widgets += 1

    def changeEvent(self, event: QEvent) -> None:
        if event.type() == QEvent.Type.StyleChange:
            for i in range(self.Total_Widgets):
                item = self.sidebar.itemAt(i).widget()
                if isinstance(item, QPushButton):
                    item.setStyleSheet(
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
        return super().changeEvent(event)

    def clear_widgets(self) -> None:
        """清空所有页面"""
        self.Widgets.clear()
        while self.sidebar.count():
            item = self.sidebar.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        self.sidebar.addItem(self.__sidebar_spacer)
        self.Total_Widgets = 0
        self.Top_Widgets = 0
        self.Bottom_Widgets = 0
        self.current_widget = 0
