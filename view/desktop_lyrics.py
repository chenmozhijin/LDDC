# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from typing import Literal

from PySide6.QtCore import QEvent, QMutex, QObject, QPoint, QPointF, QRectF, Qt
from PySide6.QtGui import (
    QBrush,
    QColor,
    QFont,
    QFontMetricsF,
    QLinearGradient,
    QMouseEvent,
    QPainter,
    QPaintEvent,
    QPen,
)
from PySide6.QtWidgets import QWidget

desktop_lyrics_widgets = {}


class TransparentWindow(QWidget):
    def __init__(self) -> None:
        super().__init__()

        self.setWindowFlag(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)  # 将界面设置为无框
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)  # 将界面属性设置为半透明

        self.setMouseTracking(True)  # 开启鼠标跟踪

        # 初始化各拖拽状态
        self._drag_position = None
        self._resize_direction = None

        self.installEventFilter(self)  # 主窗口绑定事件过滤器

    def eventFilter(self, obj: QObject, event: QEvent) -> bool:
        if event.type() == QEvent.Type.Enter:
            self.setCursor(Qt.CursorShape.ArrowCursor)
        return super().eventFilter(obj, event)

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_position = event.globalPosition().toPoint() - self.pos()
            self._resize_direction = self.get_resize_direction(self._drag_position)
            event.accept()

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        if event.buttons() == Qt.MouseButton.LeftButton and self._drag_position:
            if self._resize_direction == "move":
                self.move(event.globalPosition().toPoint() - self._drag_position)
            else:
                self.resize_window(event)
            event.accept()
        else:
            cursor_pos = event.globalPosition().toPoint() - self.pos()
            direction = self.get_resize_direction(cursor_pos)
            cursor_shape = {
                "bottom_right": Qt.CursorShape.SizeFDiagCursor,
                "bottom": Qt.CursorShape.SizeVerCursor,
                "right": Qt.CursorShape.SizeHorCursor,
                "move": Qt.CursorShape.ArrowCursor,
            }.get(direction, Qt.CursorShape.ArrowCursor)
            self.setCursor(cursor_shape)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_position = None
            self._resize_direction = None

    def get_resize_direction(self, pos: QPoint) -> str:
        margin = 5
        right = pos.x() > self.width() - margin
        bottom = pos.y() > self.height() - margin
        if right and bottom:
            return "bottom_right"
        if bottom:
            return "bottom"
        if right:
            return "right"
        return "move"

    def resize_window(self, event: QMouseEvent) -> None:
        if self._resize_direction == "bottom_right":
            self.resize(int(event.globalPosition().x()) - self.x(), int(event.globalPosition().y()) - self.y())
        elif self._resize_direction == "bottom":
            self.resize(self.width(), int(event.globalPosition().y() - self.y()))
        elif self._resize_direction == "right":
            self.resize(int(event.globalPosition().x() - self.x()), self.height())


class DesktopLyricsWidget(TransparentWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Karaoke Lyrics")  # 设置窗口标题
        self.setGeometry(100, 100, 1200, 0)  # 设置窗口尺寸和位置

        self.played_colors = [(0, 255, 255), (0, 128, 255)]
        self.not_played_colors = [(255, 0, 0), (255, 128, 128)]

        self.text_font = QFont()
        self.text_font.setPointSizeF(24)
        self.font_metrics = QFontMetricsF(self.text_font)
        self.font_height = self.font_metrics.height()

        # 需要显示的歌词 {"左/右": [[已经播放过的歌词, (当前歌词字符, 显示比例), 未播放的歌词, 透明度]]}
        self.lyrics_to_display: dict[Literal["r", "l"], list[tuple[str, tuple[str, float], str, int]]] = {"r": [], "l": []}
        self.lyrics_to_display_mutex = QMutex()

    def paintEvent(self, _event: QPaintEvent) -> None:
        super().paintEvent(_event)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setFont(self.text_font)

        current_chars: list[tuple[QPen, float, float, float, str]] = []  # x, y, played_width, char

        y = self.font_height
        self.lyrics_to_display_mutex.lock()

        for pos, lyrics_lines in self.lyrics_to_display.items():
            # pos: 方位(左/右)
            for played, (current_char, ratio), not_played, alpha in lyrics_lines:
                # played: 已经播放过的歌词字, current_char: 正在播放的歌词字, not_played: 未播放的歌词字

                # 计算字符串x坐标
                x_len = self.font_metrics.horizontalAdvance(played + current_char + not_played)  # 字符串长度
                if pos == "l":
                    x = self.font_metrics.horizontalAdvance(played) * -0.9 if x_len > self.width() else 0
                else:  # pos == "r"
                    x = self.width() - x_len * 1.1
                    if x_len > self.width():
                        x += self.font_metrics.horizontalAdvance(not_played)

                played_gradient = QLinearGradient(x, y - self.font_height * 0.5, x, y)
                for i, color in enumerate(self.played_colors):
                    played_gradient.setColorAt(i / (len(self.played_colors) - 1), QColor(*color, alpha))

                not_played_gradient = QLinearGradient(x, y - self.font_height * 0.5, x, y)
                for i, color in enumerate(self.not_played_colors):
                    not_played_gradient.setColorAt(i / (len(self.not_played_colors) - 1), QColor(*color, alpha))

                played_pen = QPen(QBrush(played_gradient), 0)
                not_played_pen = QPen(QBrush(not_played_gradient), 0)

                # 绘制已播放的部分
                if played:
                    painter.setPen(played_pen)
                    painter.drawText(QPointF(x, y), played)
                    x += self.font_metrics.horizontalAdvance(played)

                if current_char:
                    # 记录当前播放的部分的已播放部分
                    played_width = self.font_metrics.horizontalAdvance(current_char) * ratio
                    current_chars.append((played_pen, x, y, played_width, current_char))

                if current_char or not_played:
                    # 绘制未播放的部分
                    painter.setPen(not_played_pen)
                    painter.drawText(QPointF(x, y), current_char + not_played)

                y += self.font_height * 1.2  # 调整y坐标以容纳下一行

        self.lyrics_to_display_mutex.unlock()

        height = y
        # 绘制当前播放的部分的已播放部分
        painter.save()
        for played_pen, x, y, played_width, current_char in current_chars:
            painter.setPen(played_pen)
            painter.setClipRect(QRectF(x, y - self.font_height, played_width, self.font_height * 1.2))
            painter.drawText(QPointF(x, y), current_char)
        painter.restore()

        if self.height() < height:
            self.resize(self.width(), int(height - self.font_height))
