# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: Copyright (c) 2024 沉默の金
import sys

from PySide6.QtCore import (
    Qt,
    QThread,
)
from PySide6.QtWidgets import QApplication

import res.resource_rc
from backend.service import (
    LDDCService,
)
from utils.args import args
from utils.exit_manager import exit_manager
from utils.translator import load_translation
from utils.version import __version__

res.resource_rc.qInitResources()


if __name__ == "__main__":

    app = QApplication(sys.argv)
    if args.get_service_port:
        LDDCService()
        sys.exit()

    show = args.show
    service = LDDCService()
    service_thread = QThread(app)
    exit_manager.threads.append(service_thread)
    service.moveToThread(service_thread)
    service_thread.start()
    service.instance_del.connect(exit_manager.close_event)

    exit_manager.close_signal.connect(service.stop_service, Qt.ConnectionType.BlockingQueuedConnection)

    from view.main_window import main_window
    load_translation(False)
    if show:
        main_window.show()
    from utils.data import cfg
    if cfg["auto_check_update"]:
        from view.update import check_update
        check_update(True, QApplication.translate("CheckUpdate", "LDDC主程序"), "chenmozhijin/LDDC", __version__)
    sys.exit(app.exec())
