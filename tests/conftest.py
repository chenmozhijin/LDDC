# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

import os
import shutil
import sys
import threading
from collections.abc import Callable, Generator
from functools import partial
from typing import Any

import pytest
from PySide6.QtCore import QCoreApplication, QRunnable, QThread

from LDDC.res import resource_rc
from LDDC.utils.cache import cache
from LDDC.utils.logger import logger
from LDDC.utils.thread import threadpool

from .helper import screenshot_path, test_artifacts_path, tmp_dir_root, tmp_dirs


@pytest.fixture(scope="session", autouse=True)
def init(request: pytest.FixtureRequest) -> Generator[None, Any, None]:
    # 预处理
    if request.config.getoption("clear_cache"):
        cache.clear()

    if os.path.exists(test_artifacts_path):
        shutil.rmtree(test_artifacts_path)
    os.makedirs(test_artifacts_path)
    os.makedirs(screenshot_path)
    os.makedirs(tmp_dir_root)

    resource_rc.qInitResources()

    yield

    # 后处理
    app = QCoreApplication.instance()
    if app:
        app.quit()

    for tmp_dir in tmp_dirs:
        tmp_dir.cleanup()


def pytest_addoption(parser: pytest.Parser) -> None:
    group = parser.getgroup("LDDC tester")
    group.addoption(
        "--not-clear-cache",
        action="store_false",
        dest="clear_cache",
        default=True,
        help="Do not clear cache before and after testing",
    )


@pytest.fixture(autouse=True)
def apply_coverage_for_qthread(monkeypatch: pytest.MonkeyPatch) -> None:
    no_patch_start = threadpool.start

    def run_with_trace(self: QRunnable | QThread) -> None:
        if "coverage" in sys.modules:
            # https://github.com/nedbat/coveragepy/issues/686#issuecomment-634932753
            sys.settrace(threading._trace_hook)  # type: ignore[reportAttributeAccessIssue] # noqa: SLF001
        self._base_run()  # type: ignore[reportAttributeAccessIssue]

    def _start(worker: QRunnable | Callable, *args: Any, **kwargs: Any) -> None:

        if isinstance(worker, QRunnable):
            worker._base_run = worker.run   # type: ignore[reportAttributeAccessIssue] # noqa: SLF001
            worker.run = partial(run_with_trace, worker)
            no_patch_start(worker, *args, **kwargs)
        else:
            no_patch_start(worker, *args, **kwargs)
            logger.warning("No support coverage for start a function in QThreadPool")

    monkeypatch.setattr(threadpool, "start", _start)

    no_patch_init = QThread.__init__

    def _init(self: QThread, *args: Any, **kwargs: Any) -> None:
        no_patch_init(self, *args, **kwargs)
        self._base_run = self.run  # type: ignore[reportAttributeAccessIssue]
        self.run = partial(run_with_trace, self)

    monkeypatch.setattr(QThread, "__init__", _init)
