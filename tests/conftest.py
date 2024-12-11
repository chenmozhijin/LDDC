# SPDX-FileCopyrightText: Copyright (C) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import sys
import threading
from collections.abc import Callable
from functools import partial
from typing import Any

import pytest
from PySide6.QtCore import QRunnable, QThread

from LDDC.utils.cache import cache
from LDDC.utils.logger import logger
from LDDC.utils.thread import threadpool


@pytest.fixture(scope="session", autouse=True)
def init() -> None:
    cache.clear()


@pytest.fixture(autouse=True)
def cover_qthreadpool(monkeypatch: pytest.MonkeyPatch) -> None:

    def run_with_trace(self: QRunnable | QThread) -> None:
        if "coverage" in sys.modules:
            # https://github.com/nedbat/coveragepy/issues/686#issuecomment-634932753
            sys.settrace(threading._trace_hook)  # type: ignore[reportAttributeAccessIssue] # noqa: SLF001
        self._base_run()  # type: ignore[reportAttributeAccessIssue]

    def _start(worker: QRunnable | Callable, *args: Any, **kwargs: Any) -> None:

        if isinstance(worker, QRunnable):
            worker._base_run = worker.run   # type: ignore[reportAttributeAccessIssue] # noqa: SLF001
            worker.run = partial(run_with_trace, worker)
            threadpool.no_patch_start(worker, *args, **kwargs)  # type: ignore[reportAttributeAccessIssue]
        else:
            threadpool.no_patch_start(worker, *args, **kwargs)  # type: ignore[reportAttributeAccessIssue]
            logger.warning("No support coverage for start a function in QThreadPool")

    threadpool.no_patch_start = threadpool.start  # type: ignore[reportAttributeAccessIssue]
    monkeypatch.setattr(threadpool, "start", _start)

    def _init(self: QThread, *args: Any, **kwargs: Any) -> None:
        QThread.__init__(self, *args, **kwargs)
        self._base_run = self.run  # type: ignore[reportAttributeAccessIssue]
        self.run = partial(run_with_trace, self)

    monkeypatch.setattr(QThread, "__init__", _init)
