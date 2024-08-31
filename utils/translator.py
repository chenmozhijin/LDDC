# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import platform

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


def get_system_language() -> QLocale.Language:
    if platform.system() == 'Darwin':
        try:
            from Foundation import NSUserDefaults  # type: ignore[reportMissingImports]
            if (languages := NSUserDefaults.standardUserDefaults().objectForKey_("AppleLanguages")):
                language = languages[0]
                if language.startswith("zh"):
                    return QLocale.Language.Chinese
        except ImportError:
            logger.warning("Failed to get system language on macOS")
    return QLocale.system().language()


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

            language = get_system_language()
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
