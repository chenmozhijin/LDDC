# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

"""桌面歌词界面实现"""

import math
from dataclasses import dataclass
from pathlib import Path
from typing import NewType

from PySide6.QtCore import QEvent, QPoint, QPointF, QRect, QRectF, QSize, Qt, QTimer, Signal, Slot
from PySide6.QtGui import (
    QAction,
    QBrush,
    QCloseEvent,
    QColor,
    QContextMenuEvent,
    QEnterEvent,
    QFont,
    QFontDatabase,
    QFontMetricsF,
    QIcon,
    QLinearGradient,
    QMouseEvent,
    QPainter,
    QPainterPath,
    QPaintEvent,
    QPalette,
    QPen,
    QPixmap,
)
from PySide6.QtWidgets import QFileDialog, QLabel, QMenu, QPushButton, QSizePolicy, QSystemTrayIcon, QVBoxLayout, QWidget

from LDDC.common.data.config import cfg
from LDDC.common.logger import logger
from LDDC.common.models import Direction, Lyrics, LyricsType, Source
from LDDC.common.thread import cross_thread_func
from LDDC.common.utils import LimitedSizeDict
from LDDC.core.api.lyrics import get_lyrics
from LDDC.gui.components.msg_box import MsgBox
from LDDC.gui.ui.desktop_lyrics_control_bar_ui import Ui_DesktopLyricsControlBar

from .search import SearchWidgetBase

# 歌词内容: [(文本,当前文本引索(N) + 当前文本已播放比例(0-1), 透明度(0-255), [(起始引索, 结束引索, 注音文本)])]
DesktopLyric = NewType("DesktopLyric", list[tuple[str, float, int, list[tuple[int, int, str]]]])
DesktopLyrics = NewType("DesktopLyrics", list[DesktopLyric])
DRAW_TEXT_FLAGS = Qt.TextFlag.TextSingleLine | Qt.TextFlag.TextWordWrap


class DesktopLyricsSelectWidget(SearchWidgetBase):
    """选择歌词界面"""

    lyrics_selected = Signal(Lyrics, Path, list, int)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowFlags(Qt.WindowType.Window)
        self.setup_ui()
        self.resize(1050, 600)
        self.setWindowTitle(self.tr("选择歌词"))
        self.setWindowIcon(QIcon(":/LDDC/img/icon/logo.png"))

        self.last_keywords = ""  # 上次搜索的关键词
        self.lyrics_path = Path()
        self.select_lyrics_button.clicked.connect(self.select_lyrics)
        self.open_local_lyrics_button.clicked.connect(self.open_local_lyrics)

    def setup_ui(self) -> None:
        # 设置标题
        title_font = QFont()
        title_font.setPointSize(18)
        self.label_title = QLabel(self)
        self.label_sub_title = QLabel(self)
        self.label_title.setFont(title_font)

        self.verticalLayout.insertWidget(0, self.label_title)
        self.verticalLayout.insertWidget(1, self.label_sub_title)

        # 设置选定歌词按钮
        self.select_lyrics_button = QPushButton(self)
        self.open_local_lyrics_button = QPushButton(self)
        select_lyrics_button_size_policy = QSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        select_lyrics_button_size_policy.setHorizontalStretch(0)
        select_lyrics_button_size_policy.setVerticalStretch(0)
        select_lyrics_button_size_policy.setHeightForWidth(self.select_lyrics_button.sizePolicy().hasHeightForWidth())
        self.select_lyrics_button.setSizePolicy(select_lyrics_button_size_policy)
        self.open_local_lyrics_button.setSizePolicy(select_lyrics_button_size_policy)

        but_h = self.control_verticalLayout.sizeHint().height() - self.control_verticalSpacer.sizeHint().height() * 0.8

        self.select_lyrics_button.setMinimumSize(QSize(0, int(but_h)))
        self.open_local_lyrics_button.setMinimumSize(QSize(0, int(but_h)))

        self.bottom_horizontalLayout.addWidget(self.open_local_lyrics_button)
        self.bottom_horizontalLayout.addWidget(self.select_lyrics_button)

        self.retranslate_ui()

    def retranslate_ui(self, search_base: SearchWidgetBase | None = None) -> None:
        super().retranslateUi(self)
        if search_base:
            return
        self.label_title.setText(self.tr("选择歌词"))
        self.label_sub_title.setText(self.tr("为桌面歌词选择云端或本地歌词"))

        self.select_lyrics_button.setText(self.tr("选定歌词"))
        self.open_local_lyrics_button.setText(self.tr("打开本地歌词"))

    def set_lyrics(self, lyrics: Lyrics | None = None) -> None:
        super().set_lyrics(lyrics)
        if lyrics and lyrics.info.source != Source.Local:
            self.lyrics_path = Path()

    @Slot()
    def open_local_lyrics(self) -> None:
        @Slot(str)
        def file_selected(path: str) -> None:
            try:
                lyrics = get_lyrics(path=Path(path))
                if lyrics:
                    self.set_lyrics(lyrics)
                self.lyrics_path = Path(path)
            except Exception as e:
                logger.exception(f"open local lyrics failed: {e}")
                MsgBox.critical(self, self.tr("打开本地歌词失败"), str(e))

        dialog = QFileDialog(self)
        dialog.setWindowTitle(self.tr("打开本地歌词"))
        dialog.setFileMode(QFileDialog.FileMode.ExistingFile)
        dialog.setNameFilter(self.tr("歌词文件(*.qrc *.krc *.lrc)"))
        dialog.fileSelected.connect(file_selected)
        dialog.open()

    @Slot()
    def select_lyrics(self) -> None:
        if isinstance(self.lyrics, Lyrics):
            if self.lyrics.types.get("orig") != LyricsType.PlainText:
                langs = self.langs
                self.lyrics_selected.emit(
                    self.lyrics, self.lyrics_path, [lang for lang in cfg["desktop_lyrics_langs_order"] if lang in langs], self.offset_spinBox.value()
                )
                return
            MsgBox.warning(self, self.tr("提示"), self.tr("不支持纯文本歌词"))
            return
        MsgBox.warning(self, self.tr("提示"), self.tr("请先选择歌词"))

    @Slot()
    @Slot(dict)
    def show(self, infos: dict | None = None) -> None:
        if infos:
            keyword = infos.get("keyword")
            lyrics = infos.get("lyrics")
            langs = infos.get("langs")
            offset = infos.get("offset")
            if isinstance(offset, int):
                self.offset_spinBox.setValue(offset)
            if keyword and keyword != self.last_keywords:
                self.last_keywords = keyword
                self.source_comboBox.setCurrentIndex(0)
                self.search_type_comboBox.setCurrentIndex(0)
                self.search_keyword_lineEdit.setText(keyword)
                self.search()

            if isinstance(lyrics, Lyrics):
                self.set_lyrics(lyrics)
            else:
                self.preview_plainTextEdit.setPlainText("")

            if isinstance(langs, list):
                if "orig" in langs:
                    self.original_checkBox.setChecked(True)
                else:
                    self.original_checkBox.setChecked(False)
                if "ts" in langs:
                    self.translate_checkBox.setChecked(True)
                else:
                    self.translate_checkBox.setChecked(False)
                if "roma" in langs:
                    self.romanized_checkBox.setChecked(True)
                else:
                    self.romanized_checkBox.setChecked(False)
                self.kana_checkBox.setChecked(cfg["kana"])
                self.kana_checkBox.setEnabled(self.romanized_checkBox.isChecked())
        self.raise_()
        if self.isMinimized():
            self.showNormal()
        self.activateWindow()
        super().show()

    def closeEvent(self, event: QCloseEvent) -> None:
        self.hide()
        event.ignore()


class DesktopLyricsMenu(QMenu):
    """桌面歌词菜单(桌面歌词与托盘图标)"""

    def __init__(self, parent: "DesktopLyricsWidget") -> None:
        super().__init__(parent)
        self._parent = parent

        self.action_select = QAction(self.tr("选择歌词"), self)
        self.action_set_inst = QAction(self.tr("标记为纯音乐"), self)
        self.actino_set_auto_search = QAction(self.tr("禁用自动搜索(仅本曲)"), self)
        self.action_unlink_lyrics = QAction(self.tr("取消歌词关联"), self)
        self.action_show_local_song_lyrics_db_manager = QAction(self.tr("歌词关联管理器"), self)
        self.action_show_hide = QAction(self.tr("显示/隐藏桌面歌词"), self)
        self.action_show_main_window = QAction(self.tr("显示主窗口"), self)
        self.action_set_mouse_penetration = QAction(self.tr("鼠标穿透"), self)

        self.actino_set_auto_search.setCheckable(True)
        self.action_set_mouse_penetration.setCheckable(True)

        # 添加菜单项的槽函数
        self.action_show_hide.triggered.connect(self.show_hide_triggered)
        self.action_select.triggered.connect(self._parent.to_select)
        self.action_set_mouse_penetration.triggered.connect(self._parent.set_mouse_penetration)
        self.action_show_local_song_lyrics_db_manager.triggered.connect(self.show_local_song_lyrics_db_manager)
        self.action_show_main_window.triggered.connect(self.show_main_window)

        # 将菜单项添加到托盘菜单
        self.addAction(self.action_select)
        self.addAction(self.action_unlink_lyrics)
        self.addAction(self.action_set_inst)
        self.addAction(self.actino_set_auto_search)
        self.addAction(self.action_set_mouse_penetration)
        self.addAction(self.action_show_hide)
        self.addAction(self.action_show_main_window)
        self.addAction(self.action_show_local_song_lyrics_db_manager)

    @Slot()
    def show_hide_triggered(self) -> None:
        if self._parent.isVisible():
            self._parent.hide()
        else:
            self._parent.set_transparency(True)
            self._parent.show()
            QTimer.singleShot(1000, self.windows_transparency)

    def windows_transparency(self) -> None:
        if not self._parent.mouse_inside and not self._parent.resizing:
            self._parent.set_transparency(False)

    @Slot()
    def show_local_song_lyrics_db_manager(self) -> None:
        from .local_song_lyrics_db_manager import local_song_lyrics_db_manager

        local_song_lyrics_db_manager.show()

    @Slot()
    def show_main_window(self) -> None:
        from .main_window import main_window

        main_window.show_window()


class DesktopLyricsTrayIcon(QSystemTrayIcon):
    """桌面歌词托盘图标"""

    def __init__(self, parent: "DesktopLyricsWidget") -> None:
        super().__init__(QIcon(":/LDDC/img/icon/logo.png"), parent)
        self._parent = parent
        self.setup_ui()

    def setup_ui(self) -> None:
        self.setToolTip(self.tr("LDDC桌面歌词"))

        # 将菜单设置为托盘图标的菜单
        self.setContextMenu(self._parent.menu)

        # 设置点击托盘图标时显示窗口
        self.activated.connect(self.self_activated)

        # 显示托盘图标
        self.show()

    @Slot(QSystemTrayIcon.ActivationReason)
    def self_activated(self, reason: QSystemTrayIcon.ActivationReason) -> None:
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self._parent.menu.show_hide_triggered()


class DesktopLyricsControlBar(Ui_DesktopLyricsControlBar, QWidget):
    """桌面歌词控制栏"""

    update_lyrics_info = Signal(dict)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setupUi(self)

        self.update_lyrics_info.connect(self.update_lyrics_info_slot)

        size_policy = self.sizePolicy()
        size_policy.setRetainSizeWhenHidden(True)  # 当控件隐藏时保留大小
        self.setSizePolicy(size_policy)

        color = self.palette().color(QPalette.ColorRole.Window)
        color.setAlpha(128)
        palette = self.info_label.palette()
        palette.setColor(self.info_label.backgroundRole(), color)
        self.info_label.setPalette(palette)

    @Slot(dict)
    def update_lyrics_info_slot(self, info: dict) -> None:
        if not info:
            self.info_label.setText("")
            return
        text = ""
        source = info.get("source")
        if source:
            text += f"{source}"
        lyrics_type = info.get("type")
        if lyrics_type:
            if text:
                text += " - "
            match lyrics_type:
                case LyricsType.VERBATIM:
                    text += self.tr("逐字")
                case LyricsType.LINEBYLINE:
                    text += self.tr("逐行")
                case LyricsType.PlainText:
                    text += self.tr("纯文本")
        inst = info.get("inst")
        if inst:
            text = "纯音乐"
        self.info_label.setText(text)


class DesktopLyricsWidgetBase(QWidget):
    """桌面歌词窗口基类(处理窗口移动调整等)"""

    moved = Signal(QPoint)
    resized = Signal(QSize)

    def __init__(self) -> None:
        super().__init__(None, Qt.WindowType.Tool | Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setMouseTracking(True)
        self.resize_margin = 10  # 边缘用于调整大小的区域宽度
        self.start_pos: QPoint | None = None
        self.start_size = self.size()
        self.resizing: bool = False
        self.resize_direction = None

        self.transparency = 0.0
        self.mouse_inside = False
        self.show_timer = QTimer(self)  # 用于延迟显示半透明窗口的定时器
        self.show_timer.setInterval(500)
        self.hide_timer = QTimer(self)  # 用于延迟隐藏半透明窗口的定时器
        self.hide_timer.setInterval(500)
        self.show_timer.timeout.connect(lambda: self.set_transparency(True))
        self.hide_timer.timeout.connect(lambda: self.set_transparency(False))

    def enterEvent(self, event: QEnterEvent) -> None:
        self.mouse_inside = True
        self.show_timer.start()
        self.hide_timer.stop()
        super().enterEvent(event)

    def leaveEvent(self, event: QEvent) -> None:
        self.mouse_inside = False
        self.hide_timer.start()
        self.show_timer.stop()
        super().leaveEvent(event)

    def set_transparency(self, show: bool) -> None:
        if not show and self.resizing:
            self.hide_timer.start()

        if not show and self.mouse_inside:
            return

        if show:
            self.show_timer.stop()
        else:
            self.hide_timer.stop()

        self.transparency = 0.5 if show else 0.0
        self.update()

    def paintEvent(self, _event: QPaintEvent) -> None:
        painter = QPainter(self)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(self.palette().window())
        painter.setOpacity(self.transparency)
        painter.drawRect(self.rect())

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self.start_pos = event.globalPosition().toPoint()
            self.start_size = self.size()
            self.resizing = self.check_resize_direction(event)
            if not self.resizing:
                self.window_start_pos = self.pos()

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        if self.start_pos is not None:
            if self.resizing:
                self.resize_window(event)
            else:
                delta = event.globalPosition().toPoint() - self.start_pos
                self.setGeometry(QRect(self.window_start_pos + delta, self.start_size))
        if not self.resizing:  # 如果在调整大小,则不能调用self.check_resize_direction
            self.update_cursor(event)

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            if not self.resizing:
                self.moved.emit(self.pos())
            else:
                self.resized.emit(self.size())
            self.start_pos = None
            self.resizing = False
            self.resize_direction = None

    def check_resize_direction(self, event: QMouseEvent) -> bool:
        """检查鼠标是否在边缘区域,以确定是否需要调整大小"""
        rect = self.rect()
        pos = event.position().toPoint()
        margin = self.resize_margin
        if pos.x() <= rect.left() + margin:
            if pos.y() <= rect.top() + margin:
                self.resize_direction = Direction.TOP_LEFT
            elif pos.y() >= rect.bottom() - margin:
                self.resize_direction = Direction.BOTTOM_LEFT
            else:
                self.resize_direction = Direction.LEFT
        elif pos.x() >= rect.right() - margin:
            if pos.y() <= rect.top() + margin:
                self.resize_direction = Direction.TOP_RIGHT
            elif pos.y() >= rect.bottom() - margin:
                self.resize_direction = Direction.BOTTOM_RIGHT
            else:
                self.resize_direction = Direction.RIGHT
        elif pos.y() <= rect.top() + margin:
            self.resize_direction = Direction.TOP
        elif pos.y() >= rect.bottom() - margin:
            self.resize_direction = Direction.BOTTOM
        else:
            self.resize_direction = None
        return self.resize_direction is not None

    def resize_window(self, event: QMouseEvent) -> None:
        """调整窗口大小"""
        rect = self.geometry()
        pos = event.globalPosition().toPoint()
        new_rect = QRect(rect)

        match self.resize_direction:
            case Direction.LEFT:
                new_rect.setLeft(pos.x())
            case Direction.RIGHT:
                new_rect.setRight(pos.x())
            case Direction.TOP:
                new_rect.setTop(pos.y())
            case Direction.BOTTOM:
                new_rect.setBottom(pos.y())
            case Direction.TOP_LEFT:
                new_rect.setTopLeft(pos)
            case Direction.TOP_RIGHT:
                new_rect.setTopRight(pos)
            case Direction.BOTTOM_LEFT:
                new_rect.setBottomLeft(pos)
            case Direction.BOTTOM_RIGHT:
                new_rect.setBottomRight(pos)

        if new_rect.width() < self.minimumWidth():
            new_rect.setWidth(self.minimumWidth())
        if new_rect.height() < self.minimumHeight():
            new_rect.setHeight(self.minimumHeight())

        self.setGeometry(new_rect)

    def update_cursor(self, event: QMouseEvent) -> None:
        """根据鼠标位置更新光标形状"""
        cursors = {
            Direction.LEFT: Qt.CursorShape.SizeHorCursor,
            Direction.RIGHT: Qt.CursorShape.SizeHorCursor,
            Direction.TOP: Qt.CursorShape.SizeVerCursor,
            Direction.BOTTOM: Qt.CursorShape.SizeVerCursor,
            Direction.TOP_LEFT: Qt.CursorShape.SizeFDiagCursor,
            Direction.TOP_RIGHT: Qt.CursorShape.SizeBDiagCursor,
            Direction.BOTTOM_LEFT: Qt.CursorShape.SizeBDiagCursor,
            Direction.BOTTOM_RIGHT: Qt.CursorShape.SizeFDiagCursor,
            None: Qt.CursorShape.SizeAllCursor,
        }
        if self.check_resize_direction(event):
            self.setCursor(cursors[self.resize_direction])
        else:
            self.setCursor(Qt.CursorShape.SizeAllCursor)


class LyricsText(QWidget):
    """逐字歌词文本显示实现"""

    update_lyrics_signal = Signal(list)

    @dataclass
    class RubyLayoutInfo:
        """注音布局信息"""

        chars: str
        font: QFont
        metrics: QFontMetricsF
        x: float
        width: float
        base_start_x: float
        base_width: float
        scale_factor: float = 1.0
        gap_per_char: float = 0.0

    def __init__(self, parent: DesktopLyricsWidgetBase) -> None:
        super().__init__(parent)
        self._parent = parent
        self.update_lyrics_signal.connect(self.update_lyrics)

        size_policy = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.Expanding)
        size_policy.setHorizontalStretch(0)
        size_policy.setVerticalStretch(0)
        size_policy.setHeightForWidth(self.sizePolicy().hasHeightForWidth())
        self.setSizePolicy(size_policy)

        self.setMinimumHeight(18)

        self.setMouseTracking(True)

        self.perv_height = self.height()

        self.played_colors = tuple(tuple(color) for color in cfg["desktop_lyrics_played_colors"])
        self.unplayed_colors = tuple(tuple(color) for color in cfg["desktop_lyrics_unplayed_colors"])
        self.text_font = QFont()
        self.text_font.setBold(True)
        if cfg["desktop_lyrics_font_family"] in QFontDatabase.families():
            self.text_font.setFamily(cfg["desktop_lyrics_font_family"])
        if cfg["desktop_lyrics_font_size"]:
            self.text_font.setPointSizeF(cfg["desktop_lyrics_font_size"])

        # 缓存
        self.pens = LimitedSizeDict(12)
        self.played_chars_cache = LimitedSizeDict(4)
        self.unplayed_chars_cache = LimitedSizeDict(4)
        self.ruby_layouts_cache = LimitedSizeDict(16)

        self.lyrics = DesktopLyrics([])
        self.update_lyrics(DesktopLyrics([DesktopLyric([("欢迎使用LDDC桌面歌词", 12, 255, [(0, 12, "Welcome to LDDC Desktop Lyrics")])])]))

    def clear_chars_cache(self, font: QFont) -> None:
        for _i in range(2):
            if font in self.played_chars_cache:
                del self.played_chars_cache[font]
            if font in self.unplayed_chars_cache:
                del self.unplayed_chars_cache[font]
            font.setPointSizeF(font.pointSizeF() * 0.6)

    @Slot(list)
    def update_lyrics(self, lyrics: DesktopLyrics) -> None:
        if self.lyrics != lyrics:
            self.lyrics = lyrics
            self.update()

    def paintEvent(self, _event: QPaintEvent) -> None:  # noqa: C901, PLR0915
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        if self._parent.resizing:
            h = sum(1.8 if line[3] else 1.1 for lyrics_lines in self.lyrics for line in lyrics_lines)
            if math.ceil(painter.fontMetrics().height() * h) * 2 != self.height():
                self.clear_chars_cache(self.text_font)
                self.text_font.setPointSizeF((72 / painter.fontMetrics().fontDpi()) * (self.height() / h) * 0.8)
        painter.setFont(self.text_font)
        font_metrics = QFontMetricsF(self.text_font)
        font_height = font_metrics.height()

        rudy_font = QFont(self.text_font)
        rudy_font.setPointSizeF(self.text_font.pointSizeF() * 0.6)

        def _calculate_ruby_layouts(
            rubys: list[tuple[int, int, str]], text: str, font_metrics: QFontMetricsF, rudy_font: QFont
        ) -> list["LyricsText.RubyLayoutInfo"]:
            if not rubys:
                return []

            # --- 性能优化: 预计算累积宽度 ---
            cumulative_widths = [0.0] * (len(text) + 1)
            for i, char in enumerate(text):
                cumulative_widths[i + 1] = cumulative_widths[i] + font_metrics.horizontalAdvance(char)

            # 步骤 1: 为所有注音进行初始布局计算
            layouts: list[LyricsText.RubyLayoutInfo] = []
            rudy_metrics = QFontMetricsF(rudy_font)
            for start, end, chars in rubys:
                if not chars:
                    continue

                base_width = cumulative_widths[end] - cumulative_widths[start]
                start_x = cumulative_widths[start]
                font = QFont(rudy_font)
                ruby_width = rudy_metrics.horizontalAdvance(chars)

                layouts.append(
                    self.RubyLayoutInfo(
                        chars=chars,
                        font=font,
                        metrics=rudy_metrics,
                        x=0,
                        width=ruby_width,
                        base_start_x=start_x,
                        base_width=base_width,
                    )
                )

            if not layouts:
                return []

            # 步骤 2: 计算每个注音的可用空间和独立缩放因子
            text_total_width = cumulative_widths[-1]
            for i, layout in enumerate(layouts):
                prev_end_x = layouts[i - 1].base_start_x + layouts[i - 1].base_width if i > 0 else 0
                next_start_x = layouts[i + 1].base_start_x if i < len(layouts) - 1 else text_total_width

                left_space = (layout.base_start_x - prev_end_x) / 2
                right_space = (next_start_x - (layout.base_start_x + layout.base_width)) / 2
                available_width = left_space + layout.base_width + right_space

                if layout.width > available_width > 0:
                    layout.scale_factor = available_width / layout.width

            # 步骤 3: 决定全局缩放策略
            GLOBAL_SCALE_THRESHOLD = 0.7
            min_scale_factor = min((layout.scale_factor for layout in layouts), default=1.0)

            if min_scale_factor < 1.0:
                if min_scale_factor >= GLOBAL_SCALE_THRESHOLD:
                    for layout in layouts:
                        layout.scale_factor = min_scale_factor
                else:
                    for layout in layouts:
                        layout.scale_factor = min(GLOBAL_SCALE_THRESHOLD, layout.scale_factor)

            # 步骤 4: 应用缩放并重新计算布局
            for layout in layouts:
                if layout.scale_factor < 1.0:
                    layout.font.setPointSizeF(layout.font.pointSizeF() * layout.scale_factor)
                    layout.metrics = QFontMetricsF(layout.font)
                    layout.width = layout.metrics.horizontalAdvance(layout.chars)
                layout.x = layout.base_start_x + (layout.base_width - layout.width) / 2

            # 步骤 5: 碰撞检测与位置调整
            for i in range(1, len(layouts)):
                prev_layout = layouts[i - 1]
                current_layout = layouts[i]
                overlap = (prev_layout.x + prev_layout.width) - current_layout.x
                if overlap > 0:
                    current_layout.x += overlap

            # 步骤 6: 为比原文短的注音计算字符间距以实现两端对齐
            for layout in layouts:
                if layout.width < layout.base_width:
                    gap_width = layout.base_width - layout.width
                    if len(layout.chars) > 1:
                        layout.gap_per_char = gap_width / (len(layout.chars) - 1)
                        layout.x = layout.base_start_x

            return layouts

        def get_pen(colors: tuple, y: float, height: float) -> QPen:
            """创建渐变色的画笔"""
            query = (colors, y, height)
            if query not in self.pens:
                gradient = QLinearGradient(0, y, 0, y + height)
                for i, color in enumerate(colors):
                    gradient.setColorAt(i / (len(colors) - 1), QColor(*color))
                self.pens[query] = QPen(QBrush(gradient), 0)
            return self.pens[query]

        y = 0

        def draw_text(x: float, y: float, ratio: float, texts: str, alpha: int, ruby: bool = False) -> float:
            """绘制文本

            :param x: x坐标
            :param y: y坐标
            :param ratio: 已播放的比例
            :param texts: 文本
            :param alpha: 透明度
            """
            # 由于Qt算不准某些字符的宽度,所以只能一个个字符绘制
            if len(texts) <= 1:
                text_width = painter.fontMetrics().horizontalAdvance(texts) if ruby else font_metrics.horizontalAdvance(texts)
                text_height = painter.fontMetrics().height() if ruby else font_height
                font = painter.font()
                dpr = self.devicePixelRatioF()

                painter.setOpacity(alpha / 255)

                _chars_cache = self.played_chars_cache if ratio == 1.0 else self.unplayed_chars_cache
                if font not in _chars_cache:
                    _chars_cache[font] = LimitedSizeDict(1)
                if dpr not in _chars_cache[font]:
                    _chars_cache[font][dpr] = LimitedSizeDict(50)
                chars_cache = _chars_cache[font][dpr]

                if texts in chars_cache:
                    pixmap, width = chars_cache[texts]
                else:
                    pixmap = QPixmap(math.ceil(text_width * 1.2 * dpr), math.ceil(text_height * dpr))
                    pixmap.setDevicePixelRatio(dpr)
                    pixmap.fill(Qt.GlobalColor.transparent)
                    pixmap_painter = QPainter(pixmap)
                    pixmap_painter.setRenderHint(QPainter.RenderHint.Antialiasing)
                    pixmap_painter.setFont(font)

                    stroke_path = QPainterPath()
                    stroke_path.addText(0, painter.fontMetrics().ascent(), font, texts)
                    pixmap_painter.strokePath(stroke_path, QPen(QColor(0, 0, 0, 179), text_width * 0.04))
                    pixmap_painter.setPen(get_pen(self.played_colors if ratio == 1.0 else self.unplayed_colors, 0, text_height))
                    width = pixmap_painter.drawText(QRectF(0, 0, text_width * 1.2, text_height), DRAW_TEXT_FLAGS, texts).width()
                    pixmap_painter.end()
                    chars_cache[texts] = pixmap, width

                if 0.0 < ratio < 1.0:
                    pixmap = QPixmap(pixmap)
                    pixmap_painter = QPainter(pixmap)
                    pixmap_painter.setRenderHint(QPainter.RenderHint.Antialiasing)
                    pixmap_painter.setFont(font)
                    pixmap_painter.setPen(get_pen(self.played_colors, 0, text_height))
                    pixmap_painter.drawText(QRectF(0, 0, text_width * ratio, text_height), DRAW_TEXT_FLAGS, texts)
                    pixmap_painter.end()

                painter.drawPixmap(QPointF(x, y), pixmap)

                return width
            width = 0.0
            if 0.0 < ratio < 1.0:
                msg = "不支持多字符设置比例"
                raise NotImplementedError(msg)
            for text in texts:
                width += draw_text(x + width, y, ratio, text, alpha)
            return width

        for i, lyrics_lines in enumerate(self.lyrics):
            for text, current_index_ratio, alpha, rubys in lyrics_lines:
                # 步骤 1: 分解歌词文本
                current_index = int(current_index_ratio)
                ratio = current_index_ratio - current_index
                played = text[:current_index]
                current_char = text[current_index] if current_index < len(text) else ""
                unplayed = text[current_index + 1 :]
                texts = played + current_char + unplayed

                # 步骤 2: 预计算注音布局和整行歌词的边界框
                ruby_layouts = []
                keep_ruby_y = False
                if rubys == [(0, 0, "")]:
                    keep_ruby_y = True
                elif rubys:
                    cache_key = (text, tuple(map(tuple, rubys)), self.text_font.pointSizeF())
                    if cache_key in self.ruby_layouts_cache:
                        ruby_layouts = self.ruby_layouts_cache[cache_key]
                    else:
                        ruby_layouts: list[LyricsText.RubyLayoutInfo] = _calculate_ruby_layouts(rubys, texts, font_metrics, rudy_font)
                        self.ruby_layouts_cache[cache_key] = ruby_layouts

                text_width = font_metrics.horizontalAdvance(texts)
                line_rect = QRectF(0, 0, text_width, font_height)
                if ruby_layouts:
                    min_ruby_x = min(layout.x for layout in ruby_layouts) if ruby_layouts else 0
                    max_ruby_x = max(layout.x + layout.width for layout in ruby_layouts) if ruby_layouts else text_width
                    line_rect.setLeft(min(0, min_ruby_x))
                    line_rect.setRight(max(text_width, max_ruby_x))

                # 步骤 3: 计算最终的X坐标以防止边缘截断
                x = 0
                if self.width() < line_rect.width():
                    # 当歌词过长时，动态调整x坐标以使当前播放字符可见
                    played_width_in_rect = font_metrics.horizontalAdvance(played) - line_rect.left()
                    x = self.width() - line_rect.width() if self.width() > (line_rect.width() - played_width_in_rect) else -played_width_in_rect
                elif i % 2 == 0:
                    # 左对齐
                    x = -line_rect.left()
                else:
                    # 右对齐
                    x = self.width() - line_rect.width()

                # 步骤 4: 使用高亮逻辑绘制注音
                if keep_ruby_y:
                    y += font_height * 0.7
                elif ruby_layouts:
                    ruby_y = y
                    # 计算原文的绝对高亮分割点
                    played_split_x_abs = x + font_metrics.horizontalAdvance(played) + font_metrics.horizontalAdvance(current_char) * ratio

                    for layout in ruby_layouts:
                        painter.setFont(layout.font)
                        ruby_metrics = layout.metrics

                        # 计算每个注音对应原文片段的绝对起止位置
                        base_start_x_abs = x + layout.base_start_x
                        base_width_abs = layout.base_width

                        # 计算高亮分割点在当前原文片段中的比例
                        segment_ratio = max(0.0, min(1.0, (played_split_x_abs - base_start_x_abs) / base_width_abs if base_width_abs > 0 else 0.0))

                        current_ruby_x_abs = x + layout.x
                        gap_per_char = layout.gap_per_char

                        # 将原文片段的播放比例映射到注音的渲染宽度上，得到注音的绝对高亮分割点
                        ruby_render_width = layout.width + gap_per_char * (len(layout.chars) - 1)
                        split_x_for_ruby = current_ruby_x_abs + ruby_render_width * segment_ratio

                        # 逐字符绘制注音并应用高亮
                        for char in layout.chars:
                            char_width = ruby_metrics.horizontalAdvance(char)
                            r = 0.0
                            if split_x_for_ruby > current_ruby_x_abs:
                                if split_x_for_ruby >= current_ruby_x_abs + char_width:
                                    r = 1.0
                                elif char_width > 0:
                                    r = (split_x_for_ruby - current_ruby_x_abs) / char_width
                            actual_width = draw_text(current_ruby_x_abs, ruby_y, r, char, alpha, ruby=True)
                            current_ruby_x_abs += actual_width + gap_per_char

                    painter.setFont(self.text_font)
                    y += font_height * 0.7

                # 步骤 5: 绘制主歌词文本
                draw_x = x
                if played:
                    draw_x += draw_text(draw_x, y, 1.0, played, alpha)
                if current_char:
                    draw_x += draw_text(draw_x, y, ratio, current_char, alpha)
                if unplayed:
                    draw_text(draw_x, y, 0.0, unplayed, alpha)

                y += font_height * 1.1

        painter.end()

        if not self._parent.resizing:
            self.resize2adjust(y)

    def resize2adjust(self, height: float) -> None:
        height = math.ceil(height)
        if self.height() != height:
            self._parent.resize(self._parent.width(), self._parent.height() - self.height() + height)

    def clear_cache(self) -> None:
        self.pens.clear()
        self.played_chars_cache.clear()
        self.unplayed_chars_cache.clear()
        self.ruby_layouts_cache.clear()


class DesktopLyricsWidget(DesktopLyricsWidgetBase):
    """桌面歌词窗口"""

    send_task = Signal(str)  # snder
    new_lyrics = Signal(dict)  # slot
    to_select = Signal()  # sender
    show_selector = Signal(dict)  # slot

    def __init__(self, available_tasks: list) -> None:
        super().__init__()

        self.menu = DesktopLyricsMenu(self)
        self.tray_icon = DesktopLyricsTrayIcon(self)

        self.setup_ui()
        self.update_lyrics = self.lyrics_text.update_lyrics_signal
        self.new_lyrics.connect(self.control_bar.update_lyrics_info)
        self.new_lyrics.connect(self.control_bar.show)
        self.new_lyrics.connect(lambda: QTimer.singleShot(3000, self.hide_control_bar))
        self.control_bar.select_button.clicked.connect(self.to_select)
        self.control_bar.close_button.clicked.connect(self.hide)
        self.show_selector.connect(self.selector.show)

        self.resized.connect(lambda: cfg.setitem("desktop_lyrics_font_size", self.lyrics_text.text_font.pointSizeF()))
        self.moved.connect(lambda: cfg.setitem("desktop_lyrics_rect", (self.x(), self.y(), self.rect().width(), self.rect().height())))

        cfg.desktop_lyrics_changed.connect(self.cfg_changed_slot)

        if not cfg["desktop_lyrics_rect"]:
            self.move_to_center()
            self.resize(1200, 150)
        else:
            self.setGeometry(QRect(*cfg["desktop_lyrics_rect"]))

        self.playing: bool = False

        if "prev" not in available_tasks:
            self.control_bar.perv_button.hide()
        else:
            self.control_bar.perv_button.clicked.connect(lambda: self.send_task.emit("prev"))

        if "next" not in available_tasks:
            self.control_bar.next_button.hide()
        else:
            self.control_bar.next_button.clicked.connect(lambda: self.send_task.emit("next"))

        if "pause" not in available_tasks or "play" not in available_tasks:
            self.control_bar.play_pause_button.hide()
        else:
            self.control_bar.play_pause_button.clicked.connect(self.play_pause_button_clicked)

    @Slot()
    def play_pause_button_clicked(self) -> None:
        self.send_task.emit("pause" if self.playing else "play")

    @cross_thread_func
    def set_playing(self, playing: bool) -> None:
        self.playing = playing
        if self.playing:
            self.control_bar.play_pause_button.setIcon(QIcon(QIcon.fromTheme(QIcon.ThemeIcon.MediaPlaybackPause)))
        else:
            self.control_bar.play_pause_button.setIcon(QIcon(QIcon.fromTheme(QIcon.ThemeIcon.MediaPlaybackStart)))

    def setup_ui(self) -> None:
        self.verticalLayout = QVBoxLayout(self)
        self.lyrics_text = LyricsText(self)
        self.control_bar = DesktopLyricsControlBar(self)

        self.verticalLayout.addWidget(self.control_bar)
        self.verticalLayout.addWidget(self.lyrics_text)

        self.selector = DesktopLyricsSelectWidget()

    def move_to_center(self) -> None:
        screen_geometry = self.screen().geometry()
        window_geometry = self.geometry()
        x = (screen_geometry.width() - window_geometry.width()) / 2
        y = (screen_geometry.height() - window_geometry.height()) / 1.3
        self.move(int(x), int(y))

    def close(self) -> bool:
        logger.info("DesktopLyricsWidget close")
        cfg["desktop_lyrics_rect"] = (self.x(), self.y(), self.rect().width(), self.rect().height())
        cfg["desktop_lyrics_font_size"] = self.lyrics_text.text_font.pointSizeF()
        self.tray_icon.hide()
        self.tray_icon.deleteLater()
        self.selector.destroy()
        self.selector.deleteLater()
        self.destroy()
        self.deleteLater()
        return True

    @Slot()
    def hide_control_bar(self) -> None:
        if not self.mouse_inside:
            self.control_bar.hide()

    def set_transparency(self, show: bool) -> None:
        if show:
            self.control_bar.show()
        else:
            self.control_bar.hide()
        super().set_transparency(show)

    def contextMenuEvent(self, event: QContextMenuEvent) -> None:
        self.menu.exec(event.globalPos())

    @Slot(tuple)
    def cfg_changed_slot(self, k_v: tuple) -> None:
        key, value = k_v
        match key:
            case "desktop_lyrics_font_family":
                if value:
                    self.lyrics_text.text_font.setFamily(value)
                else:
                    self.lyrics_text.text_font.setFamily(QFont().defaultFamily())
                self.lyrics_text.clear_cache()
                self.lyrics_text.update()
            case "desktop_lyrics_played_colors":
                self.lyrics_text.played_colors = tuple(tuple(color) for color in value)
                self.lyrics_text.clear_cache()
                self.lyrics_text.update()
            case "desktop_lyrics_unplayed_colors":
                self.lyrics_text.unplayed_colors = tuple(tuple(color) for color in value)
                self.lyrics_text.clear_cache()
                self.lyrics_text.update()

    @Slot(bool)
    def set_mouse_penetration(self, penetrate: bool) -> None:
        """设置鼠标穿透"""
        self.setWindowFlag(Qt.WindowType.WindowTransparentForInput, penetrate)
        self.show()
