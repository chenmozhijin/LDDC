# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import logging
import sys
import time

from PySide6.QtCore import QEvent, QPointF, QRectF, Qt, QTimer
from PySide6.QtGui import (
    QBrush,
    QColor,
    QFont,
    QFontMetricsF,
    QLinearGradient,
    QPainter,
    QPaintEvent,
    QPen,
)
from PySide6.QtWidgets import QApplication, QWidget

sys.path.append("D:\yy\project\lyric\LDDC")
__version__ = "0.0.1"

from backend.lyrics import LyricsWord, MultiLyricsData

desktop_lyrics_widgets = {}

class TransparentWindow(QWidget):
    def __init__(self):
        super().__init__()

        self.setWindowFlag(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)  # 将界面设置为无框
        self.setAttribute(Qt.WA_TranslucentBackground)  # 将界面属性设置为半透明

        self.setMouseTracking(True)  # 开启鼠标跟踪
        self.initDrag()  # 初始化各拖拽状态
        self.installEventFilter(self)  # 主窗口绑定事件过滤器

    # 初始化各拖拽状态
    def initDrag(self):
        self._drag_position = None
        self._resize_direction = None

    def eventFilter(self, obj, event):
        if event.type() == QEvent.Enter:
            self.setCursor(Qt.ArrowCursor)
        return super().eventFilter(obj, event)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._drag_position = event.globalPosition().toPoint() - self.pos()
            self._resize_direction = self.getResizeDirection(self._drag_position)
            event.accept()

    def mouseMoveEvent(self, event):
        if event.buttons() == Qt.LeftButton and self._drag_position:
            if self._resize_direction == 'move':
                self.move(event.globalPosition().toPoint() - self._drag_position)
            else:
                self.resizeWindow(event)
            event.accept()
        else:
            self.updateCursor(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.initDrag()

    def updateCursor(self, event):
        cursor_pos = event.globalPosition().toPoint() - self.pos()
        direction = self.getResizeDirection(cursor_pos)
        cursor_shape = {
            'bottom_right': Qt.SizeFDiagCursor,
            'bottom': Qt.SizeVerCursor,
            'right': Qt.SizeHorCursor,
            'move': Qt.ArrowCursor
        }.get(direction, Qt.ArrowCursor)
        self.setCursor(cursor_shape)

    def getResizeDirection(self, pos):
        margin = 5
        right = pos.x() > self.width() - margin
        bottom = pos.y() > self.height() - margin
        if right and bottom:
            return 'bottom_right'
        if bottom:
            return 'bottom'
        if right:
            return 'right'
        return 'move'

    def resizeWindow(self, event):
        if self._resize_direction == 'bottom_right':
            self.resize(event.globalPosition().x() - self.x(), event.globalPosition().y() - self.y())
        elif self._resize_direction == 'bottom':
            self.resize(self.width(), event.globalPosition().y() - self.y())
        elif self._resize_direction == 'right':
            self.resize(event.globalPosition().x() - self.x(), self.height())


class DesktopLyricsWidget(TransparentWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Karaoke Lyrics")  # 设置窗口标题
        self.setGeometry(100, 100, 1200, 0)   # 设置窗口尺寸和位置

        self.update_frequency: int = 1  # 更新频率,单位:毫秒
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_lyrics)

        self.played_colors = [(0, 255, 255), (0, 128, 255)]
        self.not_played_colors = [(255, 0, 0), (255, 128, 128)]

        self.text_font = QFont()
        self.reset()

    def reset(self) -> None:
        """
        重置歌词
        """
        self.start_time = 0  # 开始时间
        self.current_time = 0  # 当前播放时间,单位:毫秒
        self.lyrics: MultiLyricsData = {}
        self.order_lyrics = []
        self.lyrics_to_display: dict[str, list[tuple[str, tuple[str, float], str, int]]] = {"r": [], "l": []}  # 需要显示的歌词 {"左/右": [[已经播放过的歌词, (当前歌词字符, 显示比例), 未播放的歌词, 透明度]]}
        self.right: bool = False  # 当前播放歌词是否是右边的歌词
        self._reset_fort()
        if self.timer.isActive():
            self.timer.stop()

    def _reset_fort(self) -> None:
        self.text_font.setPointSizeF(24)
        self.font_metrics = QFontMetricsF(self.text_font)
        self.font_height = self.font_metrics.height()

    def pause(self) -> None:
        """
        暂停歌词
        """
        if self.timer.isActive():
            self.timer.stop()

    def proceed(self, current_time: int | None = None) -> None:
        """
        继续歌词
        """
        if not current_time:
            self.start_time = int(time.time() * 1000) - self.current_time
        else:
            self.start_time = int(time.time() * 1000) - current_time
        if not self.timer.isActive():
            self.timer.start(self.update_frequency)

    def set_lyrics(self, lyrics: MultiLyricsData, order_lyrics: list, current_time: int = 0, font: QFont = None) -> bool:
        """
        设置歌词
        :param lyrics: 歌词数据
        :param current_time: 当前播放时间,单位:毫秒
        :param order_lyrics: 歌词顺序
        """
        if not isinstance(order_lyrics, list) or not order_lyrics:
            logging.error("order_lyrics must be a list")
            return False
        self.lyrics = lyrics
        self.start_time = int(time.time() * 1000) - current_time
        self.order_lyrics = order_lyrics
        if not self.timer.isActive():
            self.timer.start(self.update_frequency)
        if font:
            self.text_font = font
            self._reset_fort()
        return True

    def set_font(self, font: QFont) -> None:
        """
        设置字体
        :param font: 字体
        """
        self.text_font = font
        self._reset_fort()

    def set_current_time(self, current_time: int = 0) -> None:
        """
        设置当前时间
        :param current_time: 当前播放时间,单位:毫秒
        """
        self.start_time = int(time.time() * 1000) - current_time

    def change_update_frequency(self, update_frequency: int = 1) -> None:
        """
        更改更新频率
        :param update_frequency: 更新频率,单位:毫秒
        """
        self.update_frequency = update_frequency
        self.timer.setInterval(update_frequency)

    def update_lyrics(self) -> None:
        """
        更新歌词
        """

        def add2lyrics_to_display(lyrics_lines: list[tuple[list[LyricsWord], str, int]]) -> None:
            for _lyrics_line, key, alpha in lyrics_lines:
                before = ""
                current: tuple[str, float] | None = ("", 0)
                after = ""

                all_chars = ""
                for start, end, chars in _lyrics_line:
                    all_chars += chars
                    if end <= self.current_time:
                        # 已经播放过的歌词字
                        before += chars
                    elif start <= self.current_time <= end:
                        # 正在播放的歌词字
                        kp = (self.current_time - start) / (end - start)
                        for c_index, char in enumerate(chars, start=1):
                            start_kp = (c_index - 1) / len(chars)
                            end_kp = c_index / len(chars)
                            if start_kp < kp < end_kp:
                                # 正在播放的歌词字
                                current = (char, (kp - start_kp) / (end_kp - start_kp))
                            elif end_kp <= kp:
                                # 已经播放过的歌词字
                                before += char
                            elif kp <= start_kp:
                                # 未播放的歌词字
                                after += char

                    elif self.current_time <= start:
                        # 未播放的歌词字
                        after += chars

                self.lyrics_to_display[key].append((before, current, after, alpha))

        self.current_time = int(time.time() * 1000) - self.start_time
        self.lyrics_to_display = {"l": [], "r": []}
        if not self.lyrics:
            return

        for lyrics_type in self.order_lyrics:
            if lyrics_type not in self.lyrics:
                continue

            lyrics_data = self.lyrics[lyrics_type]
            for index, lyrics_line in enumerate(lyrics_data):
                if lyrics_line[0] <= self.current_time <= lyrics_line[1]:
                    lyrics_lines = [(lyrics_line[2], "l" if (index % 2) == 0 else "r", 255)]
                    if 0 < index < len(lyrics_data) - 1:
                        if lyrics_data[index - 1][0] < self.current_time < lyrics_data[index + 1][1]:
                            # 计算透明度(淡入淡出)
                            kp = (lyrics_data[index + 1][0] - self.current_time) / (lyrics_data[index + 1][0] - lyrics_data[index - 1][1])
                            if kp > 0.5:
                                lyrics_lines.append((lyrics_data[index - 1][2], "l" if ((index - 1) % 2) == 0 else "r", 255 * (kp - 0.5) * 2))
                            else:
                                lyrics_lines.append((lyrics_data[index + 1][2], "l" if ((index + 1) % 2) == 0 else "r", 255 * (0.5 - kp) * 2))
                        else:
                            lyrics_lines.append((lyrics_data[index + 1][2], "l" if ((index + 1) % 2) == 0 else "r", 255))

                    elif index > 0:
                        # 最后一个
                        lyrics_lines.append((lyrics_data[index - 1][2], "l" if ((index - 1) % 2) == 0 else "r", 255))
                    elif index == 0:
                        # 第一个
                        lyrics_lines.append((lyrics_data[index + 1][2], "l" if ((index + 1) % 2) == 0 else "r", 255 * self.current_time / lyrics_data[index + 1][0]))

                    add2lyrics_to_display(lyrics_lines)
                    break
            else:
                before_lyrics_lines = None
                after_lyrics_lines = None
                lyrics_lines = []
                for index, lyrics_line in enumerate(lyrics_data):
                    if lyrics_line[1] < self.current_time:
                        before_lyrics_lines = (index, lyrics_line)
                    elif lyrics_line[0] > self.current_time:
                        after_lyrics_lines = (index, lyrics_line)
                        break

                if before_lyrics_lines and after_lyrics_lines:
                    if after_lyrics_lines[0] < len(lyrics_data) - 1 and after_lyrics_lines[0] - 2 >= 0:
                        next_before_index = before_lyrics_lines[0] + 2
                        next_before_lyrics_lines = lyrics_data[before_lyrics_lines[0] + 2]
                        previous_after_index = after_lyrics_lines[0] - 2
                        previous_after_lyrics_lines = lyrics_data[after_lyrics_lines[0] - 2]
                        after_lyrics_index = after_lyrics_lines[0]
                        after_lyrics_lines = after_lyrics_lines[1]
                        before_lyrics_index = before_lyrics_lines[0]
                        before_lyrics_lines = before_lyrics_lines[1]
                        kp = (next_before_lyrics_lines[0] - self.current_time) / (next_before_lyrics_lines[0] - before_lyrics_lines[1])
                        if kp > 0.5:
                            lyrics_lines.append((before_lyrics_lines[2], "l" if (before_lyrics_index % 2) == 0 else "r", 255 * (kp - 0.5) * 2))
                        else:
                            lyrics_lines.append((next_before_lyrics_lines[2], "l" if (next_before_index % 2) == 0 else "r", 255 * (0.5 - kp) * 2))

                        kp = (after_lyrics_lines[0] - self.current_time) / (after_lyrics_lines[0] - previous_after_lyrics_lines[0])
                        if kp > 0.5:
                            lyrics_lines.append((previous_after_lyrics_lines[2], "l" if (previous_after_index % 2) == 0 else "r", 255 * (kp - 0.5) * 2))
                        else:
                            lyrics_lines.append((after_lyrics_lines[2], "l" if (after_lyrics_index % 2) == 0 else "r", 255 * (0.5 - kp) * 2))
                        add2lyrics_to_display(lyrics_lines)
                    elif after_lyrics_lines[0] == len(lyrics_data) - 1 and after_lyrics_lines[0] - 2 >= 0:
                        previous_after_index = after_lyrics_lines[0] - 2
                        previous_after_lyrics_lines = lyrics_data[after_lyrics_lines[0] - 2]
                        after_lyrics_index = after_lyrics_lines[0]
                        after_lyrics_lines = after_lyrics_lines[1]

                        kp = (after_lyrics_lines[0] - self.current_time) / (after_lyrics_lines[0] - previous_after_lyrics_lines[0])
                        if kp > 0.5:
                            lyrics_lines.append((previous_after_lyrics_lines[2], "l" if (previous_after_index % 2) == 0 else "r", 255 * (kp - 0.5) * 2))
                        else:
                            lyrics_lines.append((after_lyrics_lines[2], "l" if (after_lyrics_index % 2) == 0 else "r", 255 * (0.5 - kp) * 2))
                        add2lyrics_to_display(lyrics_lines)

                elif not before_lyrics_lines and after_lyrics_lines:
                    # 开头
                    next_lyrics_index = after_lyrics_lines[0] + 1
                    next_lyrics_lines = lyrics_data[after_lyrics_lines[0] + 1]
                    after_lyrics_index = after_lyrics_lines[0]
                    after_lyrics_lines = after_lyrics_lines[1]
                    lyrics_lines.append((after_lyrics_lines[2], "l" if (after_lyrics_index % 2) == 0 else "r", 255 * self.current_time / after_lyrics_lines[0]))
                    lyrics_lines.append((next_lyrics_lines[2], "l" if (next_lyrics_index % 2) == 0 else "r", 255 * self.current_time / next_lyrics_lines[0]))

        self.update()

    def paintEvent(self, _event: QPaintEvent) -> None:
        super().paintEvent(_event)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setFont(self.text_font)

        current_chars: list[tuple[QPen, int, int, int, str]] = []  # x, y, played_width, char

        y = self.font_height
        for pos, lyrics_lines in self.lyrics_to_display.items():
            # pos: 方位(左/右)
            for played, (current_char, ratio), not_played, alpha in lyrics_lines:
                # played: 已经播放过的歌词字, current_char: 正在播放的歌词字, not_played: 未播放的歌词字

                # 计算字符串x坐标
                x_len = self.font_metrics.horizontalAdvance(played + current_char + not_played)  # 字符串长度
                if pos == "l":
                    x = self.font_metrics.horizontalAdvance(played) * -0.9 if x_len > self.width() else 0
                elif pos == "r":
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

        height = y
        # 绘制当前播放的部分的已播放部分
        painter.save()
        for played_pen, x, y, played_width, current_char in current_chars:
            painter.setPen(played_pen)
            painter.setClipRect(QRectF(x, y - self.font_height, played_width, self.font_height * 1.2))
            painter.drawText(QPointF(x, y), current_char)
        painter.restore()

        if self.height() < height:
            self.resize(self.width(), height - self.font_height)


if __name__ == "__main__":
    # test
    with open(r"test\test.krc", "rb") as f:
        data = f.read()
    from backend.decryptor import krc_decrypt
    krc_data = krc_decrypt(data)[0]

    from backend.lyrics import Lyrics, krc2dict
    from utils.enum import LyricsType, Source
    lyrics_order = ["roma", "orig", "ts"]
    lyrics = Lyrics({"source": Source.KG})
    lyrics.tags, lyric = krc2dict(krc_data)
    lyrics.update(lyric)
    lyrics.lrc_types["orig"] = LyricsType.KRC
    lyrics.lrc_types["ts"] = LyricsType.JSONLINE
    lyrics.lrc_types["roma"] = LyricsType.JSONVERBATIM

    app = QApplication(sys.argv)
    window = DesktopLyricsWidget()
    window.show()
    window.set_lyrics(lyrics, lyrics_order, 0)
    sys.exit(app.exec())
