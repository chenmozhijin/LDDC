# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from pathlib import Path
from typing import TYPE_CHECKING

import pytest
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QFileDialog
from pytestqt.qtbot import QtBot

from LDDC.common.models import LyricsFormat
from LDDC.gui.view.batch_convert import BatchConvertWidget, ConverStatusType

from .helper import close_msg_boxs, get_tmp_dir, grab, screenshot_path, select_file, test_artifacts_path, verify_lyrics

if TYPE_CHECKING:
    from LDDC.gui.view.main_window import MainWindow
# 测试文件定义
TEST_LYRICS = [
    {
        "name": "逐字LRC_复杂时间",
        "format": LyricsFormat.VERBATIMLRC,
        "content": "[00:00.00]测试\n[00:01.23]逐字LRC\n[01:30.45]带特殊符号!@#$%^&*()\n[02:00.00][02:01.00]重叠时间标签",
    },
    {
        "name": "逐行LRC_完整元数据",
        "format": LyricsFormat.LINEBYLINELRC,
        "content": "[ar:测试艺术家]\n[ti:逐行LRC]\n[al:测试专辑]\n[by:测试编辑器]\n\n[00:00.00]第一行\n[00:01.00]第二行\n[00:02.00]带[特殊]字符\n[00:03.00]",
    },
    {
        "name": "增强型LRC_多时间标签",
        "format": LyricsFormat.ENHANCEDLRC,
        "content": "[00:00.00][00:00.50]增强型\n[00:01.00][00:01.50]多时间标签\n[00:02.00][00:02.25][00:02.50][00:02.75]超密集时间标签",
    },
    {
        "name": "ASS_复杂样式",
        "format": LyricsFormat.ASS,
        "content": (
            "[Script Info]\n"
            "ScriptType: v4.00+\n"
            "Title: 测试ASS\n\n"
            # 样式定义部分
            "[V4+ Styles]\n"
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
            "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, "
            "ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
            "Alignment, MarginL, MarginR, MarginV, Encoding\n"
            "Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,"
            "&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1\n\n"
            # 事件部分
            "[Events]\n"
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, "
            "Effect, Text\n"
            "Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,测试\n"
            "Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,复杂样式"
        ),
    },
    {
        "name": "SRT_复杂结构",
        "format": LyricsFormat.SRT,
        "content": (
            "1\n00:00:00,000 --> 00:00:01,000\nSRT\n测试\n\n"
            "2\n00:00:01,000 --> 00:00:02,000\n多行\n带特殊符号!@#$%^&*()\n\n"
            "3\n00:01:00,000 --> 00:01:01,000\n带\\n换行符\\n测试"
        ),
    },
]


def verify_covered_lyrics(lyrics_text: str, lyrics_format: LyricsFormat) -> None:
    """验证歌词内容"""
    import re

    if not lyrics_text:
        msg = "空歌词文件"
        raise AssertionError(msg)

    # 定义各格式的正则表达式模式（ASS和SRT有单独处理）
    patterns = {
        LyricsFormat.VERBATIMLRC: r"^\[\d{2}:\d{2}\.\d{2,3}\].+$",
        LyricsFormat.LINEBYLINELRC: r"^(\[ar:.+\]|\[ti:.+\]|\[al:.+\]|\[by:.+\]|\[\d{2}:\d{2}\.\d{2,3}\].+)$",
        LyricsFormat.ENHANCEDLRC: r"^\[\d{2}:\d{2}\.\d{2,3}\]<\d{2}:\d{2}\.\d{2,3}>.+$",
        LyricsFormat.SRT: r"^\d+\n\d{2}:\d{2}:\d{2},\d{3}\s+-->\s+\d{2}:\d{2}:\d{2},\d{3}\n.*(?:\n.*)*\n?",
        LyricsFormat.ASS: r"\[Script Info\].*?\[V4\+\ Styles\].*?\[Events\].*?Dialogue:",
    }

    # 验证基本结构
    if lyrics_format not in patterns:
        msg = f"不支持的歌词格式: {lyrics_format}"
        raise AssertionError(msg)

    if lyrics_format == LyricsFormat.SRT:
        # SRT需要特殊处理，检查完整段落结构
        if not re.search(patterns[LyricsFormat.SRT], lyrics_text, re.MULTILINE):
            msg = f"{lyrics_format.name}格式错误: 未找到有效的SRT段落结构"
            raise AssertionError(msg)
    elif lyrics_format == LyricsFormat.ASS:
        # ASS需要检查完整文件结构
        if not re.search(patterns[LyricsFormat.ASS], lyrics_text, re.DOTALL):
            msg = f"{lyrics_format.name}格式错误: 未找到有效的ASS文件结构"
            raise AssertionError(msg)
    else:
        # 其他格式保持逐行验证
        lines = lyrics_text.splitlines()
        if not any(re.match(patterns[lyrics_format], line) for line in lines if line.strip()):
            msg = f"{lyrics_format.name}格式错误: 未找到匹配模式的内容"
            raise AssertionError(msg)

    verify_lyrics(lyrics_text)


def get_test_files_dir() -> Path:
    """生成包含多样测试文件的目录"""
    tmp_dir = get_tmp_dir()
    test_dir = tmp_dir / "batch_convert_test"
    test_dir.mkdir(parents=True, exist_ok=True)

    # 创建测试文件
    for lyric in TEST_LYRICS:
        path = test_dir / f"{lyric['name']}.{lyric['format'].ext[1:]}"
        with path.open("w", encoding="utf-8") as f:
            f.write(lyric["content"])

    return test_dir


def test_gui_batch_convert(qtbot: QtBot, monkeypatch: pytest.MonkeyPatch, main_window: "MainWindow") -> None:
    """测试批量转换功能 - 测试多个不同格式文件同时转换"""
    main_window.show()
    main_window.set_current_widget(3)  # 切换到批量转换标签页
    qtbot.wait(300)  # 等待窗口加载

    # 设置monkeypatch
    monkeypatch.setattr(QFileDialog, "open", lambda *_args, **_kwargs: None)

    # 准备测试数据
    test_dir = get_test_files_dir()

    # 获取batch转换组件
    batch_widget: BatchConvertWidget = main_window.batch_convert_widget

    # 测试所有转换组合
    for target_format in LyricsFormat:
        if target_format not in [LyricsFormat.VERBATIMLRC, LyricsFormat.LINEBYLINELRC, LyricsFormat.ENHANCEDLRC, LyricsFormat.ASS, LyricsFormat.SRT]:
            continue
        save_dir = test_artifacts_path / "converted" / target_format.name.lower()  # 根据目标格式创建保存目录
        save_dir.mkdir(exist_ok=True, parents=True)

        # 清空表格
        batch_widget.files_table.setRowCount(0)

        # 选择所有测试文件
        batch_widget.select_dirs_button.click()
        select_file(batch_widget, test_dir)

        assert batch_widget.files_table.rowCount() > 0  # 确保有文件被选中

        # 选择保存目录
        batch_widget.save_path_button.click()
        select_file(batch_widget, save_dir)

        assert batch_widget.files_table.rowCount() > 0  # 确保有文件被选中

        # 设置目标格式
        batch_widget.format_comboBox.setCurrentIndex(target_format.value)

        qtbot.wait(100)

        # 截图转换前状态
        grab(main_window, screenshot_path / f"batch_convert_before_{target_format.name}")

        # 开始转换
        batch_widget.start_button.click()

        qtbot.waitUntil(lambda: batch_widget.taskmanager.is_finished() and not batch_widget.status_label.text(), timeout=60000)  # 等待转换完成

        qtbot.wait(100)

        close_msg_boxs(batch_widget)  # 关闭可能弹出的消息框

        qtbot.wait(200)

        # 截图转换后状态
        grab(main_window, screenshot_path / f"batch_convert_after_{target_format.name}")

        # 验证转换结果
        verify_conversion(batch_widget, target_format)

        # 清理本次转换结果
        batch_widget.files_table.setRowCount(0)

        qtbot.wait(200)

    # 截图测试完成状态
    grab(main_window, screenshot_path / "batch_convert_complete")


def verify_conversion(widget: BatchConvertWidget, target_format: LyricsFormat) -> None:
    """验证转换结果"""
    # 检查表格状态
    for row in range(widget.files_table.rowCount()):
        status_item = widget.files_table.item(row, 2)
        assert status_item is not None, f"状态项不存在 (行 {row})"

        status_text = status_item.text()
        main_item = widget.files_table.item(row, 0)
        assert main_item is not None, f"主项不存在 (行 {row})"
        file_path: Path = main_item.data(Qt.ItemDataRole.UserRole)
        save_path: Path = main_item.data(Qt.ItemDataRole.UserRole + 1)
        assert status_item.data(Qt.ItemDataRole.UserRole).type == ConverStatusType.SUCCESS, f"转换失败: {file_path} - {status_text}"

        assert save_path.is_file(), f"文件未生成: {save_path}"

        with save_path.open(encoding="utf-8") as f:
            content = f.read()
            verify_covered_lyrics(content, target_format)
