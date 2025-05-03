# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only


from typing import TYPE_CHECKING

from pytestqt.qtbot import QtBot

from .helper import grab, screenshot_path

if TYPE_CHECKING:
    from LDDC.gui.view.main_window import MainWindow


def test_gui_about(qtbot: QtBot, main_window: "MainWindow") -> None:
    main_window.show()
    main_window.set_current_widget(4)
    qtbot.wait(300)  # 等待窗口加载完成
    grab(main_window, screenshot_path / "about")
