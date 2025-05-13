# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import contextlib
from abc import abstractmethod
from collections.abc import Callable, Iterable
from functools import partial, reduce
from threading import Lock, RLock
from typing import Any, Generic, final
from weakref import WeakKeyDictionary

from PySide6.QtCore import QObject, QRunnable, Qt, Signal, Slot

from .logger import logger
from .models import P, T
from .thread import in_other_thread, is_exited, threadpool


class TaskManager:
    def __init__(self, parent_childs: dict[str, list[str]], task_callback: dict[str, Callable[[], None]] | None = None) -> None:
        """任务管理器,用于管理任务.

        Args:
            parent_childs (dict[str, list[str]]): 任务类型和子任务类型的映射.
            task_callback (dict[str, Callable[[str, int], None]]): 任务完成时的回调函数.

        """
        for childs in parent_childs.values():
            for child in childs:
                if child not in parent_childs:
                    msg = f"{child} is not in parent_map"
                    raise ValueError(msg)

        self.tasks: dict[str, set[int]] = {task_type: set() for task_type in parent_childs}
        self.parent_childs: dict[str, list[str]] = parent_childs
        self.task_callback: dict[str, Callable[[], None]] = task_callback if task_callback is not None else {}

        self.main_id: int = 0  # 用来保证任务id唯一
        self.lock = RLock()

    def set_callback(self, task_type: str, callback: Callable[[], None]) -> None:
        """设置任务完成时的回调函数."""
        with self.lock:
            self.task_callback[task_type] = callback

    def set_task(self, task_type: str, childs: Iterable[str] = ()) -> None:
        """设置任务."""
        with self.lock:
            self.tasks[task_type] = set()
            self.parent_childs[task_type] = list(childs)

    def add_task(self, task_type: str) -> int:
        """添加一个任务,并返回任务ID."""
        with self.lock:
            task_id = self.main_id + 1
            self.tasks[task_type].add(task_id)
            self.main_id = task_id
            return task_id

    def cancel(self) -> None:
        """取消所有任务.不会callback,需要worker自己callback"""
        with self.lock:
            for task_type in self.tasks:
                self.tasks[task_type].clear()

    def clear_task(self, task_type: str) -> None:
        """清空指定类型的任务."""
        with self.lock:
            if self.tasks[task_type]:
                self.tasks[task_type].clear()
                if task_type in self.task_callback:
                    self.task_callback[task_type]()
            for child in self.parent_childs[task_type]:
                if self.tasks[child]:
                    self.tasks[child].clear()
                    if child in self.task_callback:
                        self.task_callback[child]()

    def is_finished(self, task_type: str | None = None, task_id: int | None = None) -> bool:
        """判断任务/任务类型是否完成/需要执行."""
        with self.lock:
            if task_type is None and task_id:
                msg = "task_id is not None, task_type is None"
                raise ValueError(msg)
            if task_type is None:
                return all(not tasks for tasks in self.tasks.values())

            if task_id is None:
                # 判断任务类型是否完成
                if self.tasks[task_type]:
                    return False
                return all(not self.tasks[child] for child in self.parent_childs[task_type])

            # 判断任务是否完成
            if task_id in self.tasks[task_type]:
                return False
            return all(task_id not in self.tasks[child] for child in self.parent_childs[task_type])

    def finished_task(self, task_type: str, task_id: int) -> None:
        """完成一个任务."""
        with self.lock:
            if task_id in self.tasks[task_type]:
                self.tasks[task_type].remove(task_id)
            else:
                for child in self.parent_childs[task_type]:
                    if task_id in self.tasks[child]:
                        self.tasks[child].remove(task_id)
                        return
            if task_type in self.task_callback and self.is_finished(task_type):
                self.task_callback[task_type]()

    def new_multithreaded_task(
        self,
        task_type: str,
        func: Callable[P, T],
        callback: Callable[[T], Any] | Iterable[Callable[[T], Any]],
        error_handling: Callable[[Exception], Any] | Iterable[Callable[[Exception], Any]],
        *args: P.args,
        **kwargs: P.kwargs,
    ) -> None:
        """在子线程运行函数(非堵塞、支持回调函数、检查任务id)

        Args:
            task_type (str): 任务类型
            func (Callable[P, T]): 需要在子线程运行的函数
            combined_callback (bool): 是否合并后回调
            callback (Callable[[T], Any]): 函数运行结束后的回调函数(在原线程运行)
            error_handling (Callable[[Exception], Any]): 错误处理函数(在原线程运行)
            *args: 传递给 func 的参数
            **kwargs: 传递给 func 的参数

        """
        task_id = self.add_task(task_type)
        callbacks = tuple(callback) if isinstance(callback, Iterable) else (callback,)
        error_handlings = tuple(error_handling) if isinstance(error_handling, Iterable) else (error_handling,)

        def _callback(param: T) -> None:
            if not self.is_finished(task_type, task_id):
                for _callback in callbacks:
                    try:
                        _callback(param)
                    except Exception:  # noqa: PERF203
                        logger.exception(f"调用回调函数时发生异常, 回调函数: {func.__name__}, 参数: {param}")
                self.finished_task(task_type, task_id)

        def _error_handling(e: Exception) -> None:
            if not self.is_finished(task_type, task_id):
                for _error_handling in error_handlings:
                    try:
                        _error_handling(e)
                    except Exception:  # noqa: PERF203
                        logger.exception(f"调用错误处理函数时发生异常, 错误处理函数: {func.__name__}, 错误: {e}")
                self.finished_task(task_type, task_id)

        in_other_thread(func, _callback, _error_handling, *args, **kwargs)

    def run_worker(self, task_type: str, worker: "TaskWorker") -> None:
        worker.taskmanager = self
        worker.taskid = self.add_task(task_type)
        worker.task_type = task_type
        threadpool.start(worker)


def create_collecting_callbacks(
    total_tasks: int,
    callback: Callable[[T], Any] | Callable[[T | list[Exception]], Any],
    error_callback: Callable[[Exception], Any] | None = None,
) -> tuple[Callable[[T], None], Callable[[Exception], None]]:
    """创建一对用于收集批量任务结果的回调函数。

    当所有任务完成(成功或失败)时,自动聚合结果并调用相应回调。
    注意: 当没有error_callback时, 所有任务失败时也会调用callback。

    Args:
        total_tasks: 需要等待的总任务数量
        callback: 当所有任务成功完成时的结果聚合回调
        error_callback: 单个任务失败时的错误处理回调

    Returns:
        Tuple[成功结果收集器, 错误处理器]

    """
    state = {"remaining": total_tasks, "results": [], "exceptions": []}

    def result_collector(data: T) -> None:
        """收集成功任务的结果并在全部完成时触发聚合"""
        state["results"].append(data)
        state["remaining"] -= 1
        if state["remaining"] == 0:
            callback(reduce(lambda a, b: a + b, state["results"]))

    def error_handler(exception: Exception) -> None:
        """处理任务错误并在全部任务完成时触发最终回调"""
        if error_callback is not None:
            error_callback(exception)
        else:
            state["exceptions"].append(exception)
        state["remaining"] -= 1
        if state["remaining"] == 0:
            if state["results"]:
                callback(reduce(lambda a, b: a + b, state["results"]))
            elif state["exceptions"]:
                callback(state["exceptions"])

    return result_collector, error_handler


class TaskrSignals(QObject):
    call_func = Signal(object)


class TaskSignalInstance(Generic[P]):
    def __init__(self, worker: "TaskWorker") -> None:
        self._lock = Lock()
        self.funcs = set()
        self.worker = worker

    def connect(self, func: Callable[P, Any]) -> None:
        with self._lock:
            self.funcs.add(func)

    def disconnect(self, func: Callable) -> None:
        with self._lock, contextlib.suppress(KeyError):
            self.funcs.remove(func)

    def emit(self, *args: P.args, **kwargs: P.kwargs) -> None:
        with self._lock:
            funcs = self.funcs.copy()
        for func in funcs:
            self.worker.worker_signals.call_func.emit(partial(func, *args, **kwargs))


class TaskSignal(Generic[P]):
    def __init__(self) -> None:
        self._lock = Lock()
        self._instances = WeakKeyDictionary()

    def __get__(self, instance: "TaskWorker", owner: type) -> "TaskSignalInstance[P]":
        with self._lock:
            return self._instances.setdefault(instance, TaskSignalInstance[P](instance))


class TaskWorker(QRunnable):
    """任务基类"""

    def __init__(self) -> None:
        super().__init__()
        self.worker_signals = TaskrSignals()
        self.worker_signals.call_func.connect(self.__signal_slot, Qt.ConnectionType.QueuedConnection)
        self.taskmanager: TaskManager  # 调用时赋值
        self.task_type: str  # 调用时赋值
        self.taskid: int  # 调用时赋值

    @property
    def is_stopped(self) -> bool:
        return self.taskmanager.is_finished(self.task_type, self.taskid) or is_exited()

    def finished_task(self) -> None:
        self.taskmanager.finished_task(self.task_type, self.taskid)

    @final
    def run(self) -> None:
        try:
            self.run_task()
        except Exception as e:
            self.error_handling(e)
        finally:
            self.finished_task()

    def error_handling(self, _e: Exception) -> None:
        logger.exception(f"任务 {self.task_type} {self.taskid} 运行时发生异常")

    @abstractmethod
    def run_task(self) -> None: ...

    @Slot(partial)
    def __signal_slot(self, func: partial) -> None:
        try:
            func()
        except Exception:
            logger.exception(f"调用信号槽函数时发生异常, 信号槽函数: {func.func.__name__}")
