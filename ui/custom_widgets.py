from __future__ import annotations

from typing import TYPE_CHECKING

from PySide6.QtCore import Signal
from PySide6.QtWidgets import QHeaderView, QListWidget, QTableWidget, QWidget

if TYPE_CHECKING:
    from PySide6.QtGui import QDropEvent


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
        self.prop = []

    def set_proportion(self, prop: list) -> None:
        self.prop = prop

    def adapt_size(self) -> None:
        if not self.prop:
            return
        width = self.viewport().size().width()
        for i in range(self.columnCount()):
            self.horizontalHeader().setSectionResizeMode(i, QHeaderView.Interactive)
            self.setColumnWidth(i, self.prop[i] * width)

    def resizeEvent(self, event: QHeaderView.ResizeEvent) -> None:
        super().resizeEvent(event)
        self.adapt_size()
