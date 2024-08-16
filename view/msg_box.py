# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

# 非堵塞的消息框
import contextlib
from collections.abc import Callable
from typing import Any

from PySide6.QtCore import QObject, Qt
from PySide6.QtGui import QIcon
from PySide6.QtWidgets import QAbstractButton, QMessageBox, QWidget

_msg_boxs: list[tuple[QMessageBox, QWidget | None, Callable | None]] = []


def button_clicked(button: QAbstractButton) -> None:
    """处理消息框的按钮点击事件的槽函数

    :param button: 按钮
    """
    msg_box = button.parent().parent()
    if not isinstance(msg_box, QMessageBox):
        return

    for index, (box, parent, func) in enumerate(_msg_boxs):  # noqa: B007
        if box == msg_box:
            break
    else:
        return
    if isinstance(parent, QWidget):
        parent.setFocus()
    if isinstance(func, Callable):
        with contextlib.suppress(Exception):
            func(msg_box.standardButton(button))

    msg_box.destroy()
    msg_box.deleteLater()
    _msg_boxs.pop(index)


class MsgBox(QObject):

    @staticmethod
    def init_msg_box(parent: QWidget | None, title: str, text: str) -> QMessageBox:
        """初始化消息框"""
        msg = QMessageBox(parent)
        msg.setWindowIcon(QIcon(":/LDDC/img/icon/logo.png"))
        if parent is not None:
            msg.setWindowModality(Qt.WindowModality.WindowModal)
        else:
            msg.setWindowModality(Qt.WindowModality.NonModal)
        msg.setWindowTitle(title)
        msg.setText(text)
        msg.setStandardButtons(QMessageBox.StandardButton.Ok)
        msg.setDefaultButton(QMessageBox.StandardButton.Ok)
        msg.buttonClicked.connect(button_clicked)
        return msg

    @staticmethod
    def information(parent: QWidget | None, title: str, text: str) -> None:
        """创建一个信息消息框

        :param parent: 父窗口
        :param title: 标题
        :param text: 内容
        """
        msg = MsgBox.init_msg_box(parent, title, text)
        msg.setIcon(QMessageBox.Icon.Information)
        msg.show()
        _msg_boxs.append((msg, parent, None))

    @staticmethod
    def warning(parent: QWidget | None, title: str, text: str) -> None:
        """创建一个警告消息框

        :param parent: 父窗口
        :param title: 标题
        :param text: 内容
        """
        msg = MsgBox.init_msg_box(parent, title, text)
        msg.setIcon(QMessageBox.Icon.Warning)
        msg.show()
        _msg_boxs.append((msg, parent, None))

    @staticmethod
    def critical(parent: QWidget | None, title: str, text: str) -> None:
        """创建一个错误消息框

        :param parent: 父窗口
        :param title: 标题
        :param text: 内容
        """
        msg = MsgBox.init_msg_box(parent, title, text)
        msg.setIcon(QMessageBox.Icon.Critical)
        msg.show()
        _msg_boxs.append((msg, parent, None))

    @staticmethod
    def question(parent: QWidget | None,
                 title: str,
                 text: str,
                 button0: QMessageBox.StandardButton,
                 button1: QMessageBox.StandardButton,
                 func: Callable[[QMessageBox.StandardButton], Any]) -> None:
        """创建一个询问消息框

        :param parent: 父窗口
        :param title: 标题
        :param text: 内容
        :param button0: 所有按键
        :param button1: 默认按键
        :param func: 按键回调函数,调用时会按键类型
        """
        msg = QMessageBox(parent)
        msg.setWindowIcon(QIcon(":/LDDC/img/icon/logo.png"))
        if parent is not None:
            msg.setWindowModality(Qt.WindowModality.WindowModal)
        msg.setIcon(QMessageBox.Icon.Question)
        msg.setWindowTitle(title)
        msg.setText(text)
        msg.setStandardButtons(button0)
        msg.setDefaultButton(button1)
        msg.buttonClicked.connect(lambda: None)
        msg.buttonClicked.connect(button_clicked)
        msg.show()
        _msg_boxs.append((msg, parent, func))
