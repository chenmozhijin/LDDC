# SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
# SPDX-License-Identifier: GPL-3.0-only
import argparse
import time

from LDDC.common.version import __version__, parse_version

parser = argparse.ArgumentParser()
parser.add_argument("--task", choices=["get_version", "get_year", "get_num_version", "get_qt_translations_path", "log_dir"], required=True)
arg = parser.parse_args()

num_version = ".".join(str(i) for i in parse_version(__version__)[:3])

year = time.strftime("%Y")
if year != "2024":
    year = "2024-" + year

match arg.task:
    case "get_version":
        print(__version__[1:])
    case "get_num_version":
        print(num_version)
    case "get_year":
        print(year)
    case "get_qt_translations_path":
        from PySide6.QtCore import QLibraryInfo

        print(QLibraryInfo.path(QLibraryInfo.LibraryPath.TranslationsPath))
    case "log_dir":
        from LDDC.common.paths import log_dir

        print(log_dir)
