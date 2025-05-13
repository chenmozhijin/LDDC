# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from PySide6.QtCore import QObject, QThread, Signal, Slot
from PySide6.QtWidgets import QApplication, QWidget

from LDDC.common.logger import logger
from LDDC.common.thread import set_exited, threadpool
from LDDC.gui.service import check_any_instance_alive


class ExitManager(QObject):
    """程序退出管理器"""

    close_signal = Signal()

    def __init__(self) -> None:
        super().__init__()

        self.threads: list[QThread] = []
        self.windows: list[QWidget] = []

    def get_window_show_state(self) -> bool:
        try:
            from LDDC.gui.view.main_window import main_window

            return not main_window.isHidden()
        except Exception:
            return False

    def check_any_window_show(self, exclude: QWidget | None = None) -> bool:
        for window in self.windows:
            if window == exclude:
                continue
            try:
                if not window.isHidden():
                    return True
            except Exception:
                logger.exception("检查窗口状态时发生异常")
        return False

    def exit(self) -> None:
        logger.info("Exit...")
        self.close_signal.emit()
        for thread in self.threads:
            thread.quit()
            thread.wait()
        for window in self.windows:
            window.destroy()
            window.deleteLater()

        set_exited()

        # 设置超时等待线程退出
        logger.info("等待线程池清理完成...")
        threadpool.setMaxThreadCount(1)
        threadpool.clear()
        if not threadpool.waitForDone(3000):  # 3秒超时
            logger.warning("部分线程未能在超时时间内退出")

        logger.info("线程池清理完成")
        app = QApplication.instance()
        if app:
            app.quit()

    def window_close_event(self, window: QWidget) -> bool:
        """窗口关闭事件

        独立窗口关闭时调用

        :param window: 关闭的窗口
        """
        if not check_any_instance_alive() and not self.check_any_window_show(window):
            self.exit()
            return True
        return False

    @Slot()
    def close_event(self) -> bool:
        if not check_any_instance_alive() and not self.check_any_window_show():
            self.exit()
            return True
        return False


exit_manager = ExitManager()
