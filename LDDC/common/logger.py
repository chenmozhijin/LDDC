# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only

"""日志记录器"""

import io
import logging
import os
import sys
import time
from logging import CRITICAL, DEBUG, ERROR, INFO, NOTSET, WARNING, Filter, LogRecord

from PySide6.QtCore import QLoggingCategory, QMessageLogContext, QtMsgType, qInstallMessageHandler

from .args import args
from .data.config import cfg
from .paths import log_dir

log_file = log_dir / f'{time.strftime("%Y.%m.%d", time.localtime())}.log'
log_file.parent.mkdir(parents=True, exist_ok=True)

LOGGING_TO_QT_RULES = {
    NOTSET: "*.debug=true\n*.info=true\n*.warning=true\n*.critical=true",
    DEBUG: "*.debug=true\n*.info=true\n*.warning=true\n*.critical=true",
    INFO: "*.debug=false\n*.info=true\n*.warning=true\n*.critical=true",
    WARNING: "*.debug=false\n*.info=false\n*.warning=true\n*.critical=true",
    ERROR: "*.debug=false\n*.info=false\n*.warning=false\n*.critical=true",
    CRITICAL: "*.debug=false\n*.info=false\n*.warning=false\n*.critical=true",
}


def str2log_level(level: str) -> int:
    match level:
        case "NOTSET":
            return NOTSET
        case "DEBUG":
            return DEBUG
        case "INFO":
            return INFO
        case "WARNING":
            return WARNING
        case "ERROR":
            return ERROR
        case "CRITICAL":
            return CRITICAL
        case _:
            msg = f"Invalid log level: {level}"
            raise ValueError(msg)


class QtMessageFilter(Filter):
    def filter(self, record: LogRecord) -> bool:
        if (qt := record.__dict__.get("qt")) and isinstance(qt, QMessageLogContext):
            record.filename = getattr(qt, "file", "?")
            record.module = getattr(qt, "category", "?")
            record.lineno = getattr(qt, "line", 0)
            record.funcName = getattr(qt, "function", "?")
        return True


class Logger:
    def __init__(self) -> None:
        self.name = 'LDDC'
        self.__logger = logging.getLogger(self.name)
        self.__logger.addFilter(QtMessageFilter())
        self.level = str2log_level(cfg["log_level"])

        formatter = logging.Formatter('[%(levelname)s]%(asctime)s- %(module)s(%(lineno)d) - %(funcName)s:%(message)s')
        # 创建一个处理器,用于将日志写入文件
        file_handler = logging.FileHandler(log_file, encoding='utf-8')
        file_handler.setFormatter(formatter)
        self.__logger.addHandler(file_handler)

        if __debug__ and (os.getenv("DEBUGPY_RUNNING") == "true" or sys.gettrace() is not None) and not args.get_service_port:
            # 调试时创建一个处理器,用于将日志输出到标准输出
            console_handler = logging.StreamHandler(sys.stdout)
            if isinstance(sys.stdout, io.TextIOWrapper):
                sys.stdout.reconfigure(encoding='utf-8')
            console_handler.setFormatter(formatter)
            self.__logger.addHandler(console_handler)

        self.set_level(self.level)

        self.debug = self.__logger.debug
        self.info = self.__logger.info
        self.warning = self.__logger.warning
        self.error = self.__logger.error
        self.critical = self.__logger.critical
        self.log = self.__logger.log
        self.exception = self.__logger.exception

    def set_level(self, level: int | str) -> None:
        if isinstance(level, str):
            level = str2log_level(level)
        self.level = level
        self.__logger.setLevel(level)
        for handler in self.__logger.handlers:
            handler.setLevel(level)

        if level >= WARNING:
            rules = LOGGING_TO_QT_RULES.get(level, "*.debug=true")
            if rules is not None:
                QLoggingCategory.setFilterRules(rules)
        else:
            QLoggingCategory.setFilterRules(LOGGING_TO_QT_RULES[WARNING])


logger = Logger()


def qt_message_handler(mode: QtMsgType, context: QMessageLogContext, message: str) -> None:
    match mode:
        case QtMsgType.QtDebugMsg:
            logger.debug(message, extra={"qt": context})
        case QtMsgType.QtInfoMsg:
            logger.info(message, extra={"qt": context})
        case QtMsgType.QtWarningMsg:
            logger.warning(message, extra={"qt": context})
        case QtMsgType.QtCriticalMsg:
            logger.error(message, extra={"qt": context})
        case QtMsgType.QtFatalMsg:
            logger.critical(message, extra={"qt": context})


qInstallMessageHandler(qt_message_handler)
