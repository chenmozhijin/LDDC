# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
from collections.abc import Callable, Iterable
from functools import partial, wraps
from threading import Event, Lock
from typing import Any

from PySide6.QtCore import QCoreApplication, QEvent, QObject, QRunnable, Qt, QThread, QThreadPool, Signal, Slot

from .logger import logger
from .models import P, T

exit_event = Event()


def is_exited() -> bool:
    return exit_event.is_set()


def set_exited() -> None:
    exit_event.set()


threadpool = QThreadPool(QCoreApplication.instance())
if threadpool.maxThreadCount() < 8:
    threadpool.setMaxThreadCount(8)


class RunEvent(QEvent):
    EVENT_TYPE = QEvent.Type(QEvent.registerEventType())

    def __init__(self, mutex: Lock, func: Callable, ret: list) -> None:
        super().__init__(self.EVENT_TYPE)
        self.mutex = mutex
        self.ret = ret
        self.func = func


class EventHandler(QObject):
    def __init__(self) -> None:
        super().__init__()

    def customEvent(self, event: QEvent) -> None:
        if isinstance(event, RunEvent):
            try:
                ret = event.func()
                event.ret.append(True)
                event.ret.append(ret)
            except Exception as e:
                event.ret.append(False)
                event.ret.append(e)
            finally:
                event.mutex.release()


run_event_handler = EventHandler()


def in_main_thread(func: Callable[P, T], *args: P.args, **kwargs: P.kwargs) -> T:
    """在主线程运行函数(堵塞、支持返回值)"""
    if QThread.currentThread().isMainThread():
        return func(*args, **kwargs)
    ret = []
    mutex = Lock()
    mutex.acquire()
    try:
        QCoreApplication.postEvent(run_event_handler, RunEvent(mutex, partial(func, *args, **kwargs), ret))
        mutex.acquire()
    finally:
        mutex.release()
    if ret[0] is False:
        raise ret[1]
    return ret[1]


# 信号发射器类，用于线程间通信
class SignalEmitter(QObject):
    success = Signal(object)  # 任务成功时发射，携带结果
    error = Signal(object)  # 任务失败时发射，携带异常


# 任务运行器类，在线程池中执行任务
class TaskRunnable(QRunnable):
    def __init__(self, func: Callable[..., T], emitter: SignalEmitter) -> None:
        super().__init__()
        self.func = func
        self.emitter = emitter

    def run(self) -> None:
        if is_exited():
            return
        try:
            result = self.func()
            if is_exited():
                return
            self.emitter.success.emit(result)  # 成功时发射信号
        except Exception as e:
            self.emitter.error.emit(e)  # 失败时发射信号
            logger.exception(e)


# 主函数，支持在其他线程中执行任务
def in_other_thread(
    func: Callable[..., T],  # 要执行的函数
    callback: Callable[[T], Any] | Iterable[Callable[[T], Any]] | None,  # 成功时的回调
    error_handling: Callable[[Exception], Any] | Iterable[Callable[[Exception], Any]] | None,  # 错误处理
    *args: Any,  # func 的位置参数
    **kwargs: Any,  # func 的关键字参数
) -> None:
    # 创建信号发射器
    emitter = SignalEmitter()

    # 将回调函数连接到 success 信号
    for cb in callback if isinstance(callback, Iterable) else ([] if callback is None else [callback]):
        emitter.success.connect(cb, Qt.ConnectionType.BlockingQueuedConnection)

    # 将错误处理函数连接到 error 信号
    for eh in error_handling if isinstance(error_handling, Iterable) else ([] if error_handling is None else [error_handling]):
        emitter.error.connect(eh, Qt.ConnectionType.BlockingQueuedConnection)

    # 创建并启动任务
    threadpool.start(TaskRunnable(partial(func, *args, **kwargs), emitter))


class CrossThreadSignalObject(QObject):
    signal = Signal(object, tuple, dict)


def cross_thread_func(func: Callable[P, T]) -> Callable[P, None | T]:
    orig_thread = QThread.currentThread()

    @Slot(object, tuple, dict)
    def _callback(func: Callable, args: tuple, kwargs: dict) -> None:
        func(*args, **kwargs)

    if not hasattr(orig_thread, "callback_signal_obj"):
        callback_signal_obj = CrossThreadSignalObject()  # 小心内存泄漏
        callback_signal = callback_signal_obj.signal
        callback_signal.connect(_callback, Qt.ConnectionType.QueuedConnection)
        orig_thread.callback_signal_obj = callback_signal_obj  # type: ignore[reportAttributeAccessIssue]
    else:
        callback_signal_obj = orig_thread.callback_signal_obj  # type: ignore[reportAttributeAccessIssue]
        callback_signal = callback_signal_obj.signal

    @wraps(func)
    def cross_thread_callback(*args: P.args, **kwargs: P.kwargs) -> None | T:
        if not orig_thread.isCurrentThread():
            callback_signal.emit(func, args, kwargs)
        else:
            return func(*args, **kwargs)
        return None

    return cross_thread_callback
