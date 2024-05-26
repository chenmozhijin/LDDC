from PySide6.QtCore import QThreadPool

threadpool = QThreadPool()
if threadpool.maxThreadCount() < 4:
    threadpool.setMaxThreadCount(4)