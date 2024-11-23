# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from collections.abc import Callable
from typing import Any

from PySide6.QtCore import QCoreApplication, QEvent, QMutex, QObject, QThread, QThreadPool

threadpool = QThreadPool()
if threadpool.maxThreadCount() < 8:
    threadpool.setMaxThreadCount(8)


class RunEvent(QEvent):
    EVENT_TYPE = QEvent.Type(QEvent.registerEventType())

    def __init__(self, mutex: QMutex, func: Callable, ret: list, *args: Any, **kwargs: Any) -> None:
        super().__init__(self.EVENT_TYPE)
        self.mutex = mutex
        self.ret = ret
        self.func = func
        self.args = args
        self.kwargs = kwargs

    def run(self) -> None:
        self.func(*self.args, *self.kwargs)


class EventHandler(QObject):
    def __init__(self) -> None:
        super().__init__()

    def customEvent(self, event: QEvent) -> None:
        if isinstance(event, RunEvent):
            try:
                ret = event.func(*event.args, **event.kwargs)
                event.ret.append(True)
                event.ret.append(ret)
            except Exception as e:
                event.ret.append(False)
                event.ret.append(e)
            finally:
                event.mutex.unlock()


run_event_handler = EventHandler()


def in_main_thread(func: Callable, *args: Any, **kwargs: Any) -> Any:
    """在主线程运行函数(堵塞、支持返回值)"""
    if QThread.currentThread().isMainThread():
        return func(*args, **kwargs)
    ret = []
    mutex = QMutex()
    mutex.lock()
    try:
        QCoreApplication.postEvent(run_event_handler, RunEvent(mutex, func, ret, *args, **kwargs))
        mutex.lock()
    finally:
        mutex.unlock()
    if ret[0] is False:
        raise ret[1]
    return ret[1]
