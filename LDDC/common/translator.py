# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import platform

from PySide6.QtCore import QLibraryInfo, QLocale, QObject, QTranslator, Signal
from PySide6.QtWidgets import QApplication

from .data.config import cfg
from .logger import logger

translator = QTranslator()
qt_translator = QTranslator()


class _SignalHelper(QObject):
    language_changed = Signal()


_signal_helper = _SignalHelper()
language_changed = _signal_helper.language_changed


def get_system_language() -> tuple[QLocale.Language, QLocale.Script]:
    if platform.system() == 'Darwin':
        try:
            from Foundation import NSUserDefaults  # type: ignore[reportMissingImports]
            if (languages := NSUserDefaults.standardUserDefaults().objectForKey_("AppleLanguages")):
                language = languages[0]
                if language.startswith("zh"):
                    if language.startswith("zh-Hant"):
                        return QLocale.Language.Chinese, QLocale.Script.TraditionalHanScript
                    return QLocale.Language.Chinese, QLocale.Script.SimplifiedHanScript
        except ImportError:
            logger.warning("Failed to get system language on macOS")
    return QLocale.system().language(), QLocale.system().script()


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
    if lang == "auto":
        language, script = get_system_language()
        match language:
            case QLocale.Language.Chinese:
                lang = 'zh-Hant' if script == QLocale.Script.TraditionalHanScript else 'zh-Hans'
            case QLocale.Language.Japanese:
                lang = 'ja'
            case _:
                lang = 'en'

    match lang:
        case "en":
            translator.load(":/i18n/LDDC_en.qm")
            if not qt_translator.load("qtbase_en.qm", QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath)):
                logger.warning("Failed to load qt_en.qm")
        case "zh-Hans":
            if not qt_translator.load("qtbase_zh_CN.qm", QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath)):
                logger.warning("Failed to load qt_zh_CN.qm")
        case "zh-Hant":
            translator.load(":/i18n/LDDC_zh-Hant.ts")
            if not qt_translator.load("qtbase_zh_TW.qm", QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath)):
                logger.warning("Failed to load qt_zh_TW.qm")
        case "ja":
            translator.load(":/i18n/LDDC_ja.qm")
            if not qt_translator.load("qtbase_ja.qm", QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath)):
                logger.warning("Failed to load qt_ja.qm")
    app.installTranslator(translator)
    app.installTranslator(qt_translator)

    if emit:
        language_changed.emit()
