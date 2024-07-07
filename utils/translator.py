# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
from PySide6.QtCore import QLocale, QTranslator
from PySide6.QtWidgets import QApplication, QWidget

from utils.logger import logger

from .data import cfg

translator = QTranslator()
_main_window = None


def load_translation() -> None:
    global translator  # noqa: PLW0603
    QApplication.instance().removeTranslator(translator)
    translator = QTranslator()
    lang = cfg.get("language")
    match lang:
        case "auto":
            locale = QLocale.system()

            language = locale.language()
            logger.info("System language detected: %s", language)
            if language != QLocale.Language.Chinese:
                translator.load(":/i18n/LDDC_en.qm")
        case "en":
            translator.load(":/i18n/LDDC_en.qm")
    QApplication.instance().installTranslator(translator)
    if _main_window is not None:
        _main_window.retranslateUi()


def apply_translation(main_window: QWidget) -> None:
    global _main_window  # noqa: PLW0603
    _main_window = main_window
    load_translation()
