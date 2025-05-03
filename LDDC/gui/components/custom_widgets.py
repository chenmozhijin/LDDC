# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from typing import Any

from PySide6.QtCore import QEvent, QModelIndex, QObject, QPersistentModelIndex, Qt, Signal, Slot
from PySide6.QtGui import QColor, QCursor, QDropEvent, QHelpEvent, QMouseEvent, QPainter, QResizeEvent
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QColorDialog,
    QHeaderView,
    QListWidget,
    QListWidgetItem,
    QStyledItemDelegate,
    QTableWidget,
    QTableWidgetItem,
    QToolTip,
    QWidget,
)

from LDDC.common.models import Source
from LDDC.common.translator import language_changed


class HeaderViewResizeMode:
    ResizeToContents = 2


class LyricOrderListWidget(QListWidget):
    droped = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)

    def dropEvent(self, event: QDropEvent) -> None:
        super().dropEvent(event)
        self.droped.emit()


class ProportionallyStretchedTableWidget(QTableWidget):
    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.props = []

        self.setMouseTracking(True)

    def set_proportions(self, props: list) -> None:
        """设置表格宽度的比例

        ::param : 比例列表
        当比例大于等于0小于等于1时,为比例
        当比例等于2时,自适应内容
        """
        self.props = props
        self.adapt_size()

    def adapt_size(self) -> None:
        if not self.props or len(self.props) != self.columnCount():
            return
        width = self.viewport().size().width()
        for i, prop in enumerate(self.props):
            if prop == HeaderViewResizeMode.ResizeToContents:
                self.horizontalHeader().setSectionResizeMode(i, QHeaderView.ResizeMode.ResizeToContents)
                width -= self.columnWidth(i)
        for i in range(self.columnCount()):
            if 0 <= self.props[i] <= 1:
                self.horizontalHeader().setSectionResizeMode(i, QHeaderView.ResizeMode.Interactive)
                self.setColumnWidth(i, self.props[i] * width)

    def resizeEvent(self, event: QResizeEvent) -> None:
        super().resizeEvent(event)
        self.adapt_size()

    def event(self, event: QEvent) -> bool:
        if event.type() == QEvent.Type.ToolTip and isinstance(event, QHelpEvent):
            item = self.itemAt(event.x(), event.y() - self.horizontalHeader().height())
            if isinstance(item, QTableWidgetItem):
                if item.toolTip():
                    return super().event(event)
                text = item.text().strip()  # 考虑表头的高度
                if text:
                    QToolTip.showText(QCursor.pos(), text, self)
            return True
        return super().event(event)


class ColorDelegate(QStyledItemDelegate):
    def __init__(self, parent: "ColorsListWidget") -> None:
        super().__init__(parent)

    def paint(self, painter: QPainter, option: Any, index: QModelIndex | QPersistentModelIndex) -> None:
        widget: QListWidget = option.widget
        item = widget.item(index.row())
        if item:
            color = item.background().color()
            painter.fillRect(option.rect, color)
            if item.isSelected():
                painter.drawRect(option.rect)


class ColorsListWidget(QListWidget):
    color_changed = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setDragEnabled(True)
        self.setDragDropMode(QListWidget.DragDropMode.InternalMove)
        self.setSelectionMode(QListWidget.SelectionMode.SingleSelection)

        self.itemDoubleClicked.connect(self.open_color_dialog)

        self.setItemDelegate(ColorDelegate(self))

    def dropEvent(self, event: QDropEvent) -> None:
        super().dropEvent(event)
        self.color_changed.emit()

    def set_color(self, i: int, color: list | tuple[int, int, int] | QColor) -> None:
        if isinstance(color, tuple | list):
            color = QColor(*color)

        item = self.item(i)
        if item is None:
            item = QListWidgetItem()
            self.insertItem(i, item)
        item.setBackground(color)
        self.color_changed.emit()

    def set_colors(self, colors: list[tuple[int, int, int]]) -> None:
        self.clear()
        for i, color in enumerate(colors):
            self.set_color(i, color)

    def get_colors(self) -> list:
        return [self.item(i).background().color().toTuple() for i in range(self.count())]

    @Slot()
    @Slot(QListWidgetItem)
    def open_color_dialog(self, item: QListWidgetItem | None = None) -> None:
        i = self.row(item) if item is not None else self.count()
        self.dialog = QColorDialog(self)  # https://bugreports.qt.io/browse/QTBUG-124118
        if item:
            self.dialog.setCurrentColor(item.background().color())
        self.dialog.colorSelected.connect(lambda: self.set_color(i, self.dialog.currentColor()))
        self.dialog.setWindowModality(Qt.WindowModality.WindowModal)
        self.dialog.show()

    @Slot()
    def del_selected(self) -> None:
        selected_items = self.selectedItems()
        if selected_items:
            self.takeItem(self.row(selected_items[0]))
            self.color_changed.emit()


class CheckBoxListWidget(QListWidget):
    data_changed = Signal()

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setDragEnabled(True)
        self.setDragDropMode(QListWidget.DragDropMode.InternalMove)
        self.setSelectionMode(QListWidget.SelectionMode.SingleSelection)

        self.list_type = ""
        language_changed.connect(self.retranslate)

    def dropEvent(self, event: QDropEvent) -> None:
        super().dropEvent(event)
        self.data_changed.emit()

    def add_item(self, data: str, checked: bool) -> None:
        check_box = QCheckBox()
        item = QListWidgetItem()
        item.setData(Qt.ItemDataRole.UserRole, data)
        check_box.setChecked(checked)
        check_box.stateChanged.connect(self.data_changed)

        check_box.installEventFilter(self)

        match data:
            case "roma":
                check_box.setText(self.tr("罗马音"))
            case "orig":
                check_box.setText(self.tr("原文"))
            case "ts":
                check_box.setText(self.tr("译文"))

            case _:
                if data in Source.__members__:
                    check_box.setText(str(Source[data]))

        self.addItem(item)
        self.setItemWidget(item, check_box)

    def set_langs(self, langs: list[str], order: list[str]) -> None:
        self.list_type = "lang"
        self.clear()
        for lang in order:
            self.add_item(lang, lang in langs)

    def eventFilter(self, source: QObject, event: QEvent) -> bool:
        if isinstance(event, QMouseEvent) and event.type() == QEvent.Type.MouseButtonPress:
            self.viewport().setProperty("pressPosition", event.pos())
        elif isinstance(event, QMouseEvent) and event.type() == QEvent.Type.MouseMove:
            press_position = self.viewport().property("pressPosition")
            if press_position and (event.pos() - press_position).manhattanLength() > QApplication.startDragDistance():
                self.startDrag(Qt.DropAction.MoveAction)
                self.viewport().setProperty("pressPosition", None)
        return super().eventFilter(source, event)

    def set_soures(self, sources: list[str]) -> None:
        self.list_type = "source"
        self.clear()
        all_sources = [name for name in Source.__members__ if name not in ("MULTI", "Local")]
        for source in sources:
            self.add_item(source, True)
        for source in all_sources:
            if source not in sources:
                self.add_item(source, False)

    def get_data(self) -> list[str]:
        data = []
        for i in range(self.count()):
            item = self.item(i)
            check_box = self.itemWidget(item)
            if isinstance(check_box, QCheckBox) and check_box.isChecked():
                data.append(item.data(Qt.ItemDataRole.UserRole))
        return data

    def get_order(self) -> list[str]:
        return [self.item(i).data(Qt.ItemDataRole.UserRole) for i in range(self.count())]

    @Slot()
    def retranslate(self) -> None:
        match self.list_type:
            case "lang":
                self.set_langs(self.get_data(), self.get_order())
            case "source":
                self.set_soures(self.get_data())
