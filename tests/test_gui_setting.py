# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# ruff: noqa: S101
import os

from pytestqt.qtbot import QtBot

from .helper import grab, screenshot_path


def test_gui_setting(qtbot: QtBot) -> None:
    from LDDC.view.main_window import main_window

    main_window.show()
    main_window.set_current_widget(4)
    qtbot.wait(300)  # 等待窗口加载完成
    size = main_window.size()
    main_window.resize(size.width(), 980)
    qtbot.wait(300)  # 等待窗口加载完成
    grab(main_window, os.path.join(screenshot_path, "setting.png"))
    main_window.resize(size)
