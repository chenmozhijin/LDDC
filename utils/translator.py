# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from PySide6.QtCore import QLibraryInfo, QLocale, QObject, QTranslator, Signal
from PySide6.QtWidgets import QApplication

from utils.logger import logger

from .data import cfg

translator = QTranslator()
qt_translator = QTranslator()


class _SignalHelper(QObject):
    language_changed = Signal()


_signal_helper = _SignalHelper()
language_changed = _signal_helper.language_changed


def load_translation(emit: bool = True) -> None:
    global translator, qt_translator  # noqa: PLW0603
    app = QApplication.instance()
    if not app:
        return
    app.removeTranslator(translator)
    app.removeTranslator(qt_translator)
    translator = QTranslator()
    qt_translator = QTranslator()
    lang = cfg.get("language")
    match lang:
        case "auto":
            locale = QLocale.system()

            language = locale.language()
            logger.info("System language detected: %s", language)
            if language != QLocale.Language.Chinese:
                translator.load(":/i18n/LDDC_en.qm")
                qt_translator.load("qt_en.qm", QLibraryInfo.location(QLibraryInfo.LibraryPath.TranslationsPath))
            else:
                qt_translator.load("qt_zh_CN.qm", QLibraryInfo.location(QLibraryInfo.LibraryPath.TranslationsPath))
        case "en":
            translator.load(":/i18n/LDDC_en.qm")
            qt_translator.load("qt_en.qm", QLibraryInfo.location(QLibraryInfo.LibraryPath.TranslationsPath))
        case "zh-Hans":
            qt_translator.load("qt_zh_CN.qm", QLibraryInfo.location(QLibraryInfo.LibraryPath.TranslationsPath))
    app.installTranslator(translator)
    app.installTranslator(qt_translator)

    if emit:
        language_changed.emit()
