# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from PySide6.QtCore import QThreadPool

threadpool = QThreadPool()
if threadpool.maxThreadCount() < 4:
    threadpool.setMaxThreadCount(4)
